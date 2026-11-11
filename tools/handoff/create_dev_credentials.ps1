<#
.SYNOPSIS
  Gives selected accounts in YOUR local Supabase new, random, local-only passwords.

.DESCRIPTION
  The data package never contains passwords. This script sets fresh passwords on
  this machine only, through the LOCAL Auth admin API:
    * every superadmin,
    * every active centre admin linked to a centre (role admin, status active,
      is_active, clinic set) -- so you log in with the real centre assignment,
    * one donor account (if any).
  Passwords are written ONLY to handoff-data\dev_credentials.LOCAL-ONLY.txt
  (git-ignored, owner-only) and never printed. Refuses to run against anything
  that is not a local (127.0.0.1 / localhost) Supabase with the local demo key.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\handoff\create_dev_credentials.ps1
#>
param(
  [string]$Workdir = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
  [string]$Container = 'supabase_db_curenurture',
  [string]$SupabaseExe = 'supabase',
  [string]$OutFile = ''
)
$ErrorActionPreference = 'Stop'
if (-not $OutFile) { $OutFile = Join-Path $Workdir 'handoff-data\dev_credentials.LOCAL-ONLY.txt' }

# Local project only
$ErrorActionPreference = 'Continue'
$statusJson = (& $SupabaseExe status -o json --workdir $Workdir 2>$null) -join "`n"
$ErrorActionPreference = 'Stop'
$status = $statusJson | ConvertFrom-Json
$api = [string]$status.API_URL
if ($api -notmatch '^http://(127\.0\.0\.1|localhost):\d+$') { throw "Not a local Supabase API ($api). Stopping." }
$key = [string]$status.SERVICE_ROLE_KEY
$p = $key.Split('.')[1].Replace('-', '+').Replace('_', '/'); while ($p.Length % 4) { $p += '=' }
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
if ($claims.role -ne 'service_role' -or $claims.iss -ne 'supabase-demo' -or $claims.ref) { $key = $null; throw 'Not the local demo service key. Stopping.' }
$status = $null; $statusJson = $null

$query = @"
select u.id, u.email, p.role, coalesce(c.name, '') from auth.users u join public.profiles p on p.id = u.id
left join public.clinics c on c.id = p.clinic_id
where (lower(btrim(p.role)) = 'superadmin')
   or (lower(btrim(p.role)) = 'admin' and p.status = 'active' and p.is_active and p.clinic_id is not null)
union all
(select u.id, u.email, 'donor', '' from auth.users u join public.donors d on d.id = u.id order by u.created_at limit 1)
"@
$rows = & docker exec $Container psql -U supabase_admin -d postgres -At -F "`t" -c $query
if ($LASTEXITCODE -ne 0) { throw 'Could not read accounts.' }

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# CureNurture LOCAL development credentials -- this machine only. Never commit or share.")
$lines.Add("# email`tpassword`trole`tcentre")
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$h = @{ apikey = $key; Authorization = "Bearer $key" }
$ok = 0
foreach ($r in $rows) {
  $id, $email, $role, $centre = $r -split "`t", 4
  $b = New-Object byte[] 18; $rng.GetBytes($b)
  $pw = ([Convert]::ToBase64String($b)).TrimEnd('=').Replace('+', 'x').Replace('/', 'y')
  $body = @{ password = $pw; email_confirm = $true } | ConvertTo-Json
  Invoke-RestMethod -Method Put -Uri "$api/auth/v1/admin/users/$id" -Headers $h -ContentType 'application/json' -Body $body | Out-Null
  $lines.Add("$email`t$pw`t$role`t$centre")
  $pw = $null; $ok++
}
$rng.Dispose(); $key = $null; $h = $null
[IO.File]::WriteAllLines($OutFile, $lines)
try {
  $acl = New-Object System.Security.AccessControl.FileSecurity
  $acl.SetAccessRuleProtection($true, $false)
  $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule([Security.Principal.WindowsIdentity]::GetCurrent().Name, 'FullControl', 'Allow')))
  Set-Acl -LiteralPath $OutFile -AclObject $acl
} catch { Write-Warning "Could not restrict permissions on $OutFile; protect it manually." }
$lines = $null
"Local passwords set for $ok accounts. They are in $OutFile (not printed)."
