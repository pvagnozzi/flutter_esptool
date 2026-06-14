<#
.SYNOPSIS
  🚀 Idempotently prepares a Windows machine for flutter_esptool development.

.DESCRIPTION
  Installs or updates the common project toolchain: Git, Visual Studio Code,
  Android Studio, Flutter, Java 17, Android platform tools, and Oh My Posh.
  The script is safe to run multiple times and self-elevates when administrative
  privileges are required.

.PARAMETER Yes
  Accept prompts and run non-interactively when supported.

.PARAMETER DryRun
  Print the actions without changing the machine.

.PARAMETER NoElevate
  Do not self-elevate. Package installation may fail without Administrator.

.EXAMPLE
  .\setup-dev.ps1 -Yes

.EXAMPLE
  .\setup-dev.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [switch]$Yes,
  [switch]$DryRun,
  [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Packages = @(
  @{ Id = 'Git.Git'; Name = 'Git' },
  @{ Id = 'Microsoft.VisualStudioCode'; Name = 'Visual Studio Code' },
  @{ Id = 'Google.AndroidStudio'; Name = 'Android Studio' },
  @{ Id = 'EclipseAdoptium.Temurin.17.JDK'; Name = 'Temurin Java 17 JDK' },
  @{ Id = 'Google.Flutter'; Name = 'Flutter SDK' },
  @{ Id = 'Google.PlatformTools'; Name = 'Android SDK Platform Tools' },
  @{ Id = 'JanDeDobbeleer.OhMyPosh'; Name = 'Oh My Posh' }
)

function Write-Step([string]$Message) { Write-Host "`n🔷 $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "⚠️  $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host "❌ $Message" -ForegroundColor Red }

function Test-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedIfNeeded {
  if ($NoElevate -or (Test-Admin)) { return }
  Write-Warn 'Administrative privileges are required for machine-wide package installation.'
  $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
  if ($Yes) { $arguments += '-Yes' }
  if ($DryRun) { $arguments += '-DryRun' }
  Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -Verb RunAs -Wait
  exit $LASTEXITCODE
}

function Invoke-CommandLine([string]$Exe, [string[]]$Args, [string]$Label) {
  $line = "$Exe $($Args -join ' ')"
  if ($DryRun) { Write-Warn "DRY-RUN: $line"; return }
  Write-Host "   ▶ $Label" -ForegroundColor DarkCyan
  & $Exe @Args
  if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" }
}

function Assert-Winget {
  if (Get-Command winget -ErrorAction SilentlyContinue) { Write-Ok 'winget available'; return }
  throw 'winget is required. Install App Installer from Microsoft Store, then re-run this script.'
}

function Install-Or-UpgradeWingetPackage([hashtable]$Package) {
  $id = $Package.Id
  $name = $Package.Name
  $list = & winget list --id $id --exact --accept-source-agreements 2>$null
  if ($LASTEXITCODE -eq 0 -and ($list -join "`n") -match [regex]::Escape($id)) {
    Write-Host "   🔁 Updating $name" -ForegroundColor DarkCyan
    Invoke-CommandLine 'winget' @('upgrade', '--id', $id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements') "Upgrade $name"
  } else {
    Write-Host "   📦 Installing $name" -ForegroundColor DarkCyan
    Invoke-CommandLine 'winget' @('install', '--id', $id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements') "Install $name"
  }
}

function Add-PathIfMissing([string]$PathToAdd, [string]$Scope) {
  if (-not (Test-Path $PathToAdd)) { return }
  $current = [Environment]::GetEnvironmentVariable('Path', $Scope)
  $items = $current -split ';' | Where-Object { $_ }
  if ($items -contains $PathToAdd) { return }
  if ($DryRun) { Write-Warn "DRY-RUN: add $PathToAdd to $Scope PATH"; return }
  [Environment]::SetEnvironmentVariable('Path', ($items + $PathToAdd -join ';'), $Scope)
  Write-Ok "Added $PathToAdd to $Scope PATH"
}

function Set-EnvIfPathExists([string]$Name, [string]$Value, [string]$Scope) {
  if (-not (Test-Path $Value)) { return }
  if ($DryRun) { Write-Warn "DRY-RUN: set $Name=$Value ($Scope)"; return }
  [Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
  Write-Ok "Configured $Name=$Value"
}

function Ensure-OhMyPoshProfile([string]$ProfilePath) {
  $markerStart = '# >>> flutter_esptool dev setup >>>'
  $markerEnd = '# <<< flutter_esptool dev setup <<<'
  $block = @"
$markerStart
`$theme = Join-Path `$env:POSH_THEMES_PATH 'M365Princess.omp.json'
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
  oh-my-posh init pwsh --config `$theme | Invoke-Expression
}
$markerEnd
"@
  if ($DryRun) { Write-Warn "DRY-RUN: update $ProfilePath"; return }
  $dir = Split-Path -Parent $ProfilePath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $content = if (Test-Path $ProfilePath) { Get-Content $ProfilePath -Raw } else { '' }
  $pattern = '(?s)' + [regex]::Escape($markerStart) + '.*?' + [regex]::Escape($markerEnd)
  $newContent = if ($content -match $pattern) { [regex]::Replace($content, $pattern, $block) } else { ($content.TrimEnd() + "`n`n" + $block) }
  Set-Content -Path $ProfilePath -Value $newContent -Encoding UTF8
  Write-Ok "Configured Oh My Posh in $ProfilePath"
}

function Main {
  Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Magenta
  Write-Host '║ 🚀 flutter_esptool Windows development setup               ║' -ForegroundColor Magenta
  Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Magenta

  Invoke-ElevatedIfNeeded
  Write-Step 'Checking package manager'
  Assert-Winget

  Write-Step 'Installing and updating development tools'
  foreach ($package in $Packages) { Install-Or-UpgradeWingetPackage $package }

  Write-Step 'Configuring Android and Flutter environment'
  $androidHomeCandidates = @(
    Join-Path $env:LOCALAPPDATA 'Android\Sdk',
    Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk'
  )
  foreach ($candidate in $androidHomeCandidates) {
    if (Test-Path $candidate) {
      Set-EnvIfPathExists 'ANDROID_HOME' $candidate 'User'
      Set-EnvIfPathExists 'ANDROID_SDK_ROOT' $candidate 'User'
      Add-PathIfMissing (Join-Path $candidate 'platform-tools') 'User'
      Add-PathIfMissing (Join-Path $candidate 'cmdline-tools\latest\bin') 'User'
      break
    }
  }

  Write-Step 'Configuring shell startup with Oh My Posh M365Princess'
  Ensure-OhMyPoshProfile $PROFILE.CurrentUserCurrentHost
  Ensure-OhMyPoshProfile (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')

  Write-Step 'Running Flutter doctor when available'
  if (Get-Command flutter -ErrorAction SilentlyContinue) {
    Invoke-CommandLine 'flutter' @('doctor') 'flutter doctor'
  } else {
    Write-Warn 'Flutter command not found in the current PATH yet. Restart the terminal and run flutter doctor.'
  }

  Write-Ok 'Windows development setup completed. Restart shells to load PATH/profile changes.'
}

Main
