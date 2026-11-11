<#
  Shared GnuPG helpers for the CureNurture handoff scripts (dot-sourced).

  * Every run uses its OWN temporary GnuPG home (never your default
    %USERPROFILE%\.gnupg) and stops only that home's gpg-agent afterwards.
  * gpg runs through Start-Process with output redirected to files, so a
    background gpg-agent can never hold the calling PowerShell's output open.
  * The passphrase is read with a masked prompt (or from -PassphraseFile for
    automated tests), written to an owner-only file inside the temporary home
    for --passphrase-file, and that file is deleted with the home. It is never
    printed or logged.
#>

function Find-Gpg {
  $cmd = Get-Command gpg -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $git = 'C:\Program Files\Git\usr\bin\gpg.exe'
  if (Test-Path $git) { return $git }
  throw 'gpg not found. It ships with Git for Windows (C:\Program Files\Git\usr\bin\gpg.exe).'
}

function Protect-OwnerOnly([string]$Path) {
  try {
    $isDir = (Get-Item -LiteralPath $Path).PSIsContainer
    $acl = if ($isDir) { New-Object System.Security.AccessControl.DirectorySecurity } else { New-Object System.Security.AccessControl.FileSecurity }
    $acl.SetAccessRuleProtection($true, $false)
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($isDir) { $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow') }
    else { $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow') }
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
  } catch { Write-Warning "Could not restrict permissions on $Path" }
}

function New-GpgSession([string]$PassphraseFile, [switch]$Confirm) {
  $gpg = Find-Gpg
  $gHome = Join-Path ([IO.Path]::GetTempPath()) ('cn-gnupg-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $gHome | Out-Null
  Protect-OwnerOnly $gHome
  $pf = Join-Path $gHome 'passphrase'
  if ($PassphraseFile) {
    [IO.File]::WriteAllText($pf, ([IO.File]::ReadAllText($PassphraseFile)).Trim())
  } else {
    $s1 = Read-Host -AsSecureString 'Package passphrase'
    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
    if ($Confirm) {
      $s2 = Read-Host -AsSecureString 'Repeat passphrase'
      $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
      if ($p1 -cne $p2) { Remove-Item -LiteralPath $gHome -Recurse -Force; throw 'Passphrases do not match.' }
      if ($p1.Length -lt 16) { Remove-Item -LiteralPath $gHome -Recurse -Force; throw 'Use a passphrase of at least 16 characters.' }
      $p2 = $null
    }
    [IO.File]::WriteAllText($pf, $p1); $p1 = $null
  }
  Protect-OwnerOnly $pf
  # gpg (MSYS build) expects a POSIX-style home path
  $posixHome = '/' + $gHome.Substring(0, 1).ToLower() + $gHome.Substring(2).Replace('\', '/')
  return [pscustomobject]@{ Gpg = $gpg; Home = $gHome; PosixHome = $posixHome; PassFile = $pf; PosixPass = $posixHome + '/passphrase' }
}

function Invoke-Gpg($Session, [string[]]$Arguments) {
  $outLog = Join-Path $Session.Home 'gpg.out'; $errLog = Join-Path $Session.Home 'gpg.err'
  $all = @('--homedir', $Session.PosixHome, '--batch', '--yes', '--no-tty', '--pinentry-mode', 'loopback', '--passphrase-file', $Session.PosixPass) + $Arguments
  $quoted = $all | ForEach-Object { if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ } }
  # No -Wait: Start-Process -Wait also waits for every child process, and gpg
  # starts a background gpg-agent that keeps running. Wait for gpg itself only.
  $p = Start-Process -FilePath $Session.Gpg -ArgumentList ($quoted -join ' ') -NoNewWindow -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
  $null = $p.Handle   # keeps the exit code readable after exit (Windows PowerShell 5.1)
  if (-not $p.WaitForExit(300000)) { try { $p.Kill() } catch { }; throw 'gpg did not finish within 5 minutes.' }
  if ($p.ExitCode -ne 0) {
    $msg = (Get-Content $errLog -ErrorAction SilentlyContinue | Select-Object -Last 3) -join ' / '
    throw "gpg failed (exit $($p.ExitCode)): $msg"
  }
}

function Close-GpgSession($Session) {
  if (-not $Session) { return }
  # Stop ONLY the agent of this temporary home, then delete the home (passphrase file included).
  $gpgconf = Join-Path (Split-Path $Session.Gpg) 'gpgconf.exe'
  if (Test-Path $gpgconf) {
    $k = Start-Process -FilePath $gpgconf -ArgumentList @('--homedir', $Session.PosixHome, '--kill', 'gpg-agent') -NoNewWindow -PassThru `
      -RedirectStandardOutput (Join-Path ([IO.Path]::GetTempPath()) 'cn-gpgconf.out') -RedirectStandardError (Join-Path ([IO.Path]::GetTempPath()) 'cn-gpgconf.err')
    $null = $k.WaitForExit(30000)
  }
  Start-Sleep -Milliseconds 300
  Remove-Item -LiteralPath $Session.Home -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item (Join-Path ([IO.Path]::GetTempPath()) 'cn-gpgconf.out'), (Join-Path ([IO.Path]::GetTempPath()) 'cn-gpgconf.err') -ErrorAction SilentlyContinue
}
