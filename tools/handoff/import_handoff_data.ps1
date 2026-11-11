<#
.SYNOPSIS
  Loads the encrypted CureNurture data package into YOUR OWN local Supabase.

.DESCRIPTION
  * Local Docker database only (default container: supabase_db_curenurture,
    created by `supabase start` in the repository root).
  * Refuses to run if the target already has centre data (fresh import only).
  * Decrypts with gpg, checks every file against the package manifest, then
    loads everything in ONE transaction with triggers paused (historical rows
    must not create new audit entries or notifications). Foreign keys are
    checked explicitly afterwards; any problem rolls the whole import back.
  * Sequences are moved past the imported ids. No passwords are imported:
    run create_dev_credentials.ps1 next.
  * The decrypted files are deleted when the import finishes or fails.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\handoff\import_handoff_data.ps1 -Package C:\path\curenurture-handoff-20261110-1500.zip.gpg
#>
param(
  [Parameter(Mandatory = $true)][string]$Package,
  [string]$Container = 'supabase_db_curenurture',
  [string]$PassphraseFile = '',
  [string]$PrivateAssetsDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'handoff-data\private-assets')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'handoff_gpg.ps1')

$names = & docker ps --format '{{.Names}}'
if ($names -notcontains $Container) { throw "Container '$Container' is not running. Run 'supabase start' in the repository root first." }
if (-not (Test-Path $Package)) { throw "Package not found: $Package" }
$Package = (Resolve-Path -LiteralPath $Package).Path

$existing = & docker exec $Container psql -U supabase_admin -d postgres -At -c "select count(*) from public.clinics"
if ([int]$existing -ne 0) { throw "The target database already has $existing centre rows. The import only runs on a fresh database (supabase db reset)." }

$work = Join-Path ([IO.Path]::GetTempPath()) ("cn-import-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Protect-OwnerOnly $work
$remote = "/tmp/cn_import_" + [guid]::NewGuid().ToString('N')
$session = $null
try {
  $session = New-GpgSession -PassphraseFile $PassphraseFile
  $zip = Join-Path $work 'package.zip'
  try { Invoke-Gpg $session @('--output', $zip, '--decrypt', $Package) }
  catch { throw 'Decryption failed (wrong passphrase or damaged file).' }
  Expand-Archive -Path $zip -DestinationPath (Join-Path $work 'data')
  Remove-Item $zip -Force
  $data = Join-Path $work 'data'
  $manifest = Get-Content (Join-Path $data 'manifest.json') -Raw | ConvertFrom-Json
  if ($manifest.credentials_included -ne $false) { throw 'Refusing a package that is not marked credential-free.' }

  foreach ($t in $manifest.tables) {
    $f = Join-Path $data ("{0}.{1}.csv" -f $t.schema, $t.table)
    if ((Get-FileHash $f -Algorithm SHA256).Hash -ne $t.sha256) { throw "Checksum mismatch: $($t.schema).$($t.table)" }
  }
  foreach ($a in @($manifest.private_assets | Where-Object { $_ })) {
    $f = Join-Path $data ('private_assets\' + $a.name)
    if (-not (Test-Path -LiteralPath $f) -or (Get-FileHash $f -Algorithm SHA256).Hash -ne $a.sha256) { throw "Checksum mismatch: private file $($a.name)" }
  }

  # Load order: accounts first, then everything else (triggers paused; FKs checked after).
  $ordered = @($manifest.tables | Where-Object { $_.schema -eq 'auth' -and $_.table -eq 'users' }) +
             @($manifest.tables | Where-Object { $_.schema -eq 'auth' -and $_.table -eq 'identities' }) +
             @($manifest.tables | Where-Object { $_.schema -eq 'public' -and $_.table -ne 'donation_payment_settings' })
  # (payment settings always come from the migrations: sandbox-only)

  $sql = New-Object System.Text.StringBuilder
  [void]$sql.AppendLine('\set ON_ERROR_STOP on')
  [void]$sql.AppendLine('begin;')
  [void]$sql.AppendLine('set local session_replication_role = replica;')
  [void]$sql.AppendLine('create temp table _expected (tbl text, expected_rows bigint);')
  foreach ($t in $ordered) {
    [void]$sql.AppendLine(("\copy {0}.{1} ({2}) from '{3}/{0}.{1}.csv' with (format csv, header true)" -f $t.schema, $t.table, $t.columns, $remote))
    [void]$sql.AppendLine(("insert into _expected values ('{0}.{1}', {2});" -f $t.schema, $t.table, [int64]$t.rows))
  }
  # The package carries no tokens. Supabase Auth stores "no token" as an empty
  # string and cannot read NULL in these columns, so set them to '' (no secret).
  [void]$sql.AppendLine(@'
do $$
declare c text;
begin
  foreach c in array array['confirmation_token', 'recovery_token', 'email_change_token_new', 'email_change',
                           'email_change_token_current', 'phone_change', 'phone_change_token', 'reauthentication_token'] loop
    if exists (select 1 from information_schema.columns where table_schema = 'auth' and table_name = 'users' and column_name = c) then
      execute format('update auth.users set %I = '''' where %I is null', c, c);
    end if;
  end loop;
end $$;
'@)
  [void]$sql.AppendLine('set local session_replication_role = origin;')
  [void]$sql.AppendLine(@'
do $$
declare r record; n bigint; cond text; nn text; bad int := 0;
begin
  for r in select tbl, expected_rows as expected from _expected loop
    execute format('select count(*) from %s', r.tbl) into n;
    if n <> r.expected then raise exception 'COUNT MISMATCH %: expected %, loaded %', r.tbl, r.expected, n; end if;
  end loop;
  for r in select k.conname, k.conrelid::regclass child, k.confrelid::regclass parent, k.conkey, k.confkey
           from pg_constraint k join pg_class c on c.oid = k.conrelid
           where k.contype = 'f' and c.relnamespace::regnamespace::text in ('public', 'auth')
  loop
    select string_agg(format('p.%I = c.%I', pa.attname, ca.attname), ' and '),
           string_agg(format('c.%I is not null', ca.attname), ' and ') into cond, nn
    from unnest(r.conkey, r.confkey) as u(ck, pk)
    join pg_attribute ca on ca.attrelid = r.child and ca.attnum = u.ck
    join pg_attribute pa on pa.attrelid = r.parent and pa.attnum = u.pk;
    execute format('select count(*) from %s c where %s and not exists (select 1 from %s p where %s)', r.child, nn, r.parent, cond) into n;
    if n > 0 then bad := bad + 1; raise warning 'FK % on %: % orphan rows', r.conname, r.child, n; end if;
  end loop;
  if bad > 0 then raise exception 'IMPORT ROLLED BACK: % foreign keys have orphan rows', bad; end if;
  -- keep sequences ahead of the imported ids
  for r in select s.oid::regclass seq, d.refobjid::regclass tbl, a.attname col
           from pg_class s join pg_depend d on d.objid = s.oid and d.deptype in ('a', 'i')
           join pg_attribute a on a.attrelid = d.refobjid and a.attnum = d.refobjsubid
           join pg_class t on t.oid = d.refobjid
           where s.relkind = 'S' and t.relnamespace::regnamespace::text = 'public'
  loop
    execute format('select max(%I) from %s', r.col, r.tbl) into n;
    if n is not null then perform setval(r.seq, n, true); end if;
  end loop;
  raise notice 'IMPORT CHECKS PASSED';
end $$;
'@)
  [void]$sql.AppendLine('commit;')
  $sqlFile = Join-Path $work 'import.sql'
  [IO.File]::WriteAllText($sqlFile, $sql.ToString(), (New-Object Text.UTF8Encoding $false))

  & docker exec $Container sh -c "mkdir -p $remote" | Out-Null
  & docker cp "$data\." "${Container}:$remote" | Out-Null
  cmd /c "docker exec -i $Container psql -U supabase_admin -d postgres -q -f - < `"$sqlFile`" 2>&1"
  if ($LASTEXITCODE -ne 0) { throw 'Import failed and was rolled back. Nothing was kept.' }
  # Private files (e.g. the payment QR images) go to the git-ignored handoff-data
  # folder only -- never into the app source or a public build.
  $assets = @($manifest.private_assets | Where-Object { $_ })
  if ($assets.Count -gt 0) {
    $assetDir = $PrivateAssetsDir
    New-Item -ItemType Directory -Force -Path $assetDir | Out-Null
    Protect-OwnerOnly $assetDir
    foreach ($a in $assets) { Copy-Item -LiteralPath (Join-Path $data ('private_assets\' + $a.name)) -Destination (Join-Path $assetDir $a.name) -Force }
    "Private files ($($assets.Count)) saved to $assetDir (git-ignored; do not commit or publish)."
  }
  "Imported $(@($ordered).Count) tables, $((@($ordered) | ForEach-Object { [int64]$_.rows } | Measure-Object -Sum).Sum) rows (mode: $($manifest.mode)). Next: create_dev_credentials.ps1"
}
finally {
  # Decrypted data never outlives the run, whatever happened above.
  & docker exec $Container rm -rf $remote 2>$null | Out-Null
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
  Close-GpgSession $session
}
