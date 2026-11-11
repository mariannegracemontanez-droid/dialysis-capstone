<#
.SYNOPSIS
  Builds the ENCRYPTED CureNurture data package from a LOCAL Supabase database.

.DESCRIPTION
  Runs only against a local Docker database container (never a hosted project)
  and only READS it: every query runs read-only, and a fingerprint of the
  source data is taken before and after the export and must match.

  Exported: every public table plus the account rows needed to keep
  relationships intact, WITHOUT any credentials:
    * auth.users      : identity columns only. No password hashes, no tokens.
    * auth.identities : email identities.
    * never exported  : auth sessions, refresh tokens, MFA, one-time tokens,
                        flow state, auth audit log, restore_meta.
    * donations.client_secret_hash is blanked (checkout secret hash).
    * tables whose name contains "backup" are skipped (their rows are old
      copies, not application data); the empty tables still come from the
      migrations. donation_payment_settings also comes from the migrations.

  Synthetic test data is excluded unless -IncludeSynthetic is given:
    * centres with ids 00000000-0000-4000-8000-0000000c1a0*
    * accounts with @example.invalid emails (their profiles and donor rows)
    * donations by those accounts or touching those centres (also through an
      allocation), patients of those centres/accounts, and every row whose
      foreign key points at any of the above.

  -ExcludeAccountId leaves one account out; rows that point at it keep their
  data but lose that link (donations.donor_id, name, email and
  donation_audit_logs.performed_by are set to NULL in the package copy only).

  Private files (-PrivateAssets, default: the two Donation payment QR images)
  travel only inside the encrypted package, never in Git.

  Before anything is encrypted, the plaintext files are scanned: the excluded
  account's id and email, synthetic centre ids, synthetic account ids and
  @example.invalid must not appear anywhere, or the export stops and deletes
  everything.

  Output: <OutputDir>\curenurture-handoff-<date>.zip.gpg (GnuPG AES-256,
  symmetric, integrity-protected). The package is decrypted again and compared
  byte-for-byte before ANY plaintext is deleted; on every outcome the plaintext
  working files are removed. A bad package is deleted, never left behind.

  GnuPG runs in its own temporary home (see handoff_gpg.ps1); your default
  GnuPG folder and any running gpg-agent are not used or stopped.

.PARAMETER Container
  Local database container (default: supabase_db_supabase-local-test).

.PARAMETER CentersOnlyMasked
  Test mode: exports only centre configuration (clinics, shifts, schedule
  settings) with contact numbers blanked. No patient, donor or account data,
  no private files.

.PARAMETER PassphraseFile
  Optional, for automated tests only. Without it you are prompted (masked,
  entered twice). Share the passphrase through a different channel from the file.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\handoff\export_handoff_data.ps1 -ExcludeAccountId <uuid>
#>
param(
  [string]$Container = 'supabase_db_supabase-local-test',
  [string]$OutputDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'handoff-data'),
  [string]$ExcludeAccountId = '',
  [switch]$CentersOnlyMasked,
  [switch]$IncludeSynthetic,
  [string[]]$PrivateAssets = @(
    (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Donation\lib\assets\image\gcash_qr.jpg'),
    (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Donation\lib\assets\image\bank_qr.jpg')),
  [string]$PassphraseFile = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'handoff_gpg.ps1')
# "powershell -File" passes a list as one comma-separated string
$PrivateAssets = @($PrivateAssets | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

# All SQL sent through -c must avoid double quotes (Windows PowerShell 5.1
# argument passing); identifiers are plain lower-case names.
function Invoke-Psql([string]$Sql) {
  $out = & docker exec -e PGOPTIONS='-c default_transaction_read_only=on' $Container psql -U supabase_admin -d postgres -At -F '|' -c $Sql
  if ($LASTEXITCODE -ne 0) { throw "psql failed: $Sql" }
  return $out
}

# Exact fingerprint of the source data: row count + md5 of every row, per table.
function Get-SourceFingerprint {
  $tbls = @(Invoke-Psql "select 'public.' || tablename from pg_tables where schemaname = 'public' order by 1") + @('auth.users', 'auth.identities')
  $parts = $tbls | ForEach-Object { "select '$_' || ':' || count(*) || ':' || md5(coalesce(string_agg(x::text, '|' order by x::text), '')) from $_ x" }
  (Invoke-Psql ("select md5(string_agg(v, ',' order by v)) from (" + ($parts -join ' union all ') + ") s(v)")) | Select-Object -First 1
}

# --- safety: local container only --------------------------------------------
$names = & docker ps --format '{{.Names}}'
if ($names -notcontains $Container) { throw "Container '$Container' is not a running local container." }
if ($ExcludeAccountId -and $ExcludeAccountId -notmatch '^[0-9a-fA-F-]{36}$') { throw 'ExcludeAccountId must be a UUID.' }

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$work = Join-Path $OutputDir "work-$stamp"
$zip = Join-Path $OutputDir "curenurture-handoff-$stamp.zip"
$package = "$zip.gpg"
$check = Join-Path $OutputDir "verify-$stamp.zip"
$remote = "/tmp/cn_export_$stamp"
$session = $null
$verified = $false

try {
  $session = New-GpgSession -PassphraseFile $PassphraseFile -Confirm
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  Protect-OwnerOnly $work
  $fingerprintBefore = Get-SourceFingerprint

  $x = if ($ExcludeAccountId) { "'$ExcludeAccountId'::uuid" } else { 'null::uuid' }
  $excludedEmail = if ($ExcludeAccountId) { (Invoke-Psql "select coalesce(email, '') from auth.users where id = $x") | Select-Object -First 1 } else { '' }

  # --- exclusion sets ---------------------------------------------------------
  $none = 'select null::uuid where false'
  if ($IncludeSynthetic) { $sc = $none; $su = $none }
  else {
    $sc = "select id from public.clinics where id::text like '00000000-0000-4000-8000-0000000c1a0%'"
    $su = "select id from auth.users where email ilike '%@example.invalid'"
  }
  $xd = "select d.id from public.donations d where d.donor_id in ($su) or d.clinic_id in ($sc) or exists (select 1 from public.donation_allocations a where a.donation_id = d.id and a.clinic_id in ($sc))"
  $xp = "select p.id from public.patients p where p.clinic_id in ($sc) or p.profile_id in ($su)"
  $sets = @{ 'public.clinics' = $sc; 'auth.users' = $su; 'public.profiles' = $su; 'public.donors' = $su; 'public.donations' = $xd; 'public.patients' = $xp }
  $syntheticIds = if ($IncludeSynthetic) { @() } else { @(Invoke-Psql "select id::text from ($sc union all $su) s(id)") | Where-Object { $_ } }

  function Get-ExclusionWhere([string]$Table) {
    $conds = @()
    if ($sets.ContainsKey("public.$Table")) { $conds += "not coalesce(id in ($($sets["public.$Table"])), false)" }
    $fks = Invoke-Psql "select a.attname || '|' || pn.nspname || '.' || pc.relname from pg_constraint k join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1] join pg_class pc on pc.oid = k.confrelid join pg_namespace pn on pn.oid = pc.relnamespace where k.contype = 'f' and k.conrelid = 'public.$Table'::regclass and array_length(k.conkey, 1) = 1"
    foreach ($fk in @($fks | Where-Object { $_ })) {
      $col, $parent = $fk -split '\|'
      if ($sets.ContainsKey($parent)) { $conds += "not coalesce($col in ($($sets[$parent])), false)" }
    }
    return $conds
  }

  # --- what to export -----------------------------------------------------------
  $centreTables = @('clinics', 'clinic_shifts', 'clinic_schedule_settings')
  $skipped = @()
  if ($CentersOnlyMasked) { $tables = $centreTables }
  else {
    $all = Invoke-Psql "select tablename from pg_tables where schemaname = 'public' and tablename <> 'donation_payment_settings' order by tablename"
    $skipped = @($all | Where-Object { $_ -like '*backup*' })
    $tables = @($all | Where-Object { $_ -notlike '*backup*' })
  }

  function Get-Columns([string]$Schema, [string]$Table) {
    (Invoke-Psql "select string_agg(quote_ident(attname), ',' order by attnum) from pg_attribute where attrelid = '$Schema.$Table'::regclass and attnum > 0 and not attisdropped and attgenerated = ''") | Select-Object -First 1
  }

  $script = New-Object System.Text.StringBuilder
  [void]$script.AppendLine('\set ON_ERROR_STOP on')
  [void]$script.AppendLine('begin transaction isolation level repeatable read read only;')
  $manifestTables = @()
  foreach ($t in $tables) {
    $cols = Get-Columns 'public' $t
    $conds = @(Get-ExclusionWhere $t)
    switch ($t) {
      'profiles' { $conds += "id is distinct from $x" }
      'donors'   { $conds += "id is distinct from $x" }
    }
    $list = $cols
    switch ($t) {
      'clinics'             { if ($CentersOnlyMasked) { $list = $cols -replace '\bcontact_number\b', 'null::text as contact_number' } }
      'donations'           { # The -join must be inside the parentheses: PowerShell evaluates '+' before
                              # the binary -join, so "select " + <array> would join with spaces.
                              $list = ((($cols -split ',') | ForEach-Object {
                                  switch ($_) {
                                    'donor_id'           { "case when donor_id = $x then null else donor_id end as donor_id" }
                                    'name'               { "case when donor_id = $x then null else name end as name" }
                                    'email'              { "case when donor_id = $x then null else email end as email" }
                                    'client_secret_hash' { 'null::text as client_secret_hash' }
                                    default              { $_ } } }) -join ',') }
      'donation_audit_logs' { $list = $cols -replace '\bperformed_by\b', "case when performed_by = $x then null else performed_by end as performed_by" }
    }
    $select = "select $list from public.$t"
    if ($conds.Count -gt 0) { $select += ' where ' + ($conds -join ' and ') }
    [void]$script.AppendLine("\copy ($select) to '$remote/public.$t.csv' with (format csv, header true)")
    $manifestTables += @{ schema = 'public'; table = $t; columns = $cols; rows = [int](Invoke-Psql "select count(*) from ($select) s") }
  }
  if (-not $CentersOnlyMasked) {
    $userWhere = "id is distinct from $x and not coalesce(id in ($su), false)"
    $userCols = 'id,instance_id,aud,role,email,email_confirmed_at,invited_at,last_sign_in_at,raw_app_meta_data,raw_user_meta_data,is_super_admin,created_at,updated_at,phone,phone_confirmed_at,banned_until,deleted_at,is_sso_user,is_anonymous'
    [void]$script.AppendLine("\copy (select $userCols from auth.users where $userWhere) to '$remote/auth.users.csv' with (format csv, header true)")
    $manifestTables += @{ schema = 'auth'; table = 'users'; columns = $userCols; rows = [int](Invoke-Psql "select count(*) from auth.users where $userWhere") }
    $idWhere = "user_id is distinct from $x and not coalesce(user_id in ($su), false)"
    $idCols = 'id,provider_id,user_id,identity_data,provider,last_sign_in_at,created_at,updated_at'
    [void]$script.AppendLine("\copy (select $idCols from auth.identities where $idWhere) to '$remote/auth.identities.csv' with (format csv, header true)")
    $manifestTables += @{ schema = 'auth'; table = 'identities'; columns = $idCols; rows = [int](Invoke-Psql "select count(*) from auth.identities where $idWhere") }
  }
  [void]$script.AppendLine('commit;')

  $sqlFile = Join-Path $work 'export.sql'
  [IO.File]::WriteAllText($sqlFile, $script.ToString(), (New-Object Text.UTF8Encoding $false))
  & docker exec $Container sh -c "rm -rf $remote && mkdir -p $remote && chmod 777 $remote" | Out-Null
  cmd /c "docker exec -i $Container psql -U supabase_admin -d postgres -q -f - < `"$sqlFile`""
  if ($LASTEXITCODE -ne 0) { throw 'Export query failed; nothing was packaged.' }
  & docker cp "${Container}:$remote/." $work | Out-Null
  Remove-Item $sqlFile

  # --- private files (encrypted package only) ------------------------------------
  $assetEntries = @()
  if (-not $CentersOnlyMasked) {
    $assetDir = Join-Path $work 'private_assets'
    New-Item -ItemType Directory -Path $assetDir | Out-Null
    foreach ($a in $PrivateAssets) {
      if (-not (Test-Path -LiteralPath $a)) { throw "Private asset not found: $a" }
      $dest = Join-Path $assetDir (Split-Path $a -Leaf)
      Copy-Item -LiteralPath $a -Destination $dest
      $assetEntries += [ordered]@{ name = (Split-Path $a -Leaf); sha256 = (Get-FileHash $dest -Algorithm SHA256).Hash }
    }
  }

  # --- pre-encryption checks on the plaintext ------------------------------------
  $needles = @()
  if ($ExcludeAccountId) { $needles += @{ what = 'excluded account id'; v = $ExcludeAccountId } }
  if ($excludedEmail) { $needles += @{ what = 'excluded account email'; v = $excludedEmail } }
  if (-not $IncludeSynthetic) {
    $needles += @{ what = 'synthetic centre id'; v = '00000000-0000-4000-8000-0000000c1a0' }
    $needles += @{ what = 'synthetic account email'; v = '@example.invalid' }
    foreach ($id in $syntheticIds) { $needles += @{ what = 'synthetic record id'; v = $id } }
  }
  $csvs = Get-ChildItem -LiteralPath $work -Filter '*.csv'
  foreach ($n in $needles) {
    $hit = $csvs | Select-String -SimpleMatch -Pattern $n.v -List | Select-Object -First 1
    if ($hit) { throw "Pre-encryption check failed: $($n.what) found in $($hit.Filename). Nothing was packaged." }
  }
  $fingerprintAfter = Get-SourceFingerprint
  if ($fingerprintAfter -ne $fingerprintBefore) { throw 'The source database changed during the export. Nothing was packaged.' }

  # --- manifest: row counts and checksums ----------------------------------------
  $entries = foreach ($m in $manifestTables) {
    $file = Join-Path $work ("{0}.{1}.csv" -f $m.schema, $m.table)
    [ordered]@{ schema = $m.schema; table = $m.table; columns = $m.columns; rows = $m.rows; sha256 = (Get-FileHash $file -Algorithm SHA256).Hash }
  }
  [ordered]@{
    created = (Get-Date).ToString('s'); source_container = $Container
    mode = $(if ($CentersOnlyMasked) { 'centres-only-masked' } else { 'full' })
    excluded_account = $ExcludeAccountId
    synthetic_excluded = (-not $IncludeSynthetic)
    skipped_tables = $skipped
    credentials_included = $false
    tables = $entries
    private_assets = $assetEntries
  } | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $work 'manifest.json')

  # --- encrypt, then prove the package decrypts to the same bytes ---------------
  Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zip -Force
  Invoke-Gpg $session @('--symmetric', '--cipher-algo', 'AES256', '--output', $package, $zip)
  Invoke-Gpg $session @('--output', $check, '--decrypt', $package)
  if ((Get-FileHash $check -Algorithm SHA256).Hash -ne (Get-FileHash $zip -Algorithm SHA256).Hash) {
    throw 'Verification failed: the decrypted package does not match the exported data.'
  }
  $verified = $true

  "Encrypted package: $package"
  "SHA-256 of the package (send with the passphrase): $((Get-FileHash $package -Algorithm SHA256).Hash)"
  "Verified: decrypts to the exported data byte-for-byte; manifest checksums recorded for $(@($entries).Count) tables and $(@($assetEntries).Count) private files."
  "Rows: $((@($entries) | ForEach-Object { $_.rows } | Measure-Object -Sum).Sum)  Centres: $((@($entries) | Where-Object { $_.table -eq 'clinics' }).rows)  Credentials included: no"
  "Skipped tables: $(if ($skipped) { $skipped -join ', ' } else { 'none' })  Synthetic data excluded: $(-not $IncludeSynthetic)  Source unchanged: yes"
  "Send the passphrase through a different channel from the file. Do not use a public download link."
}
finally {
  # Plaintext never outlives the run, whatever happened above.
  foreach ($p in @($check, $zip)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
  & docker exec $Container rm -rf $remote 2>$null | Out-Null
  if (-not $verified -and (Test-Path -LiteralPath $package)) { Remove-Item -LiteralPath $package -Force }
  Close-GpgSession $session
}
