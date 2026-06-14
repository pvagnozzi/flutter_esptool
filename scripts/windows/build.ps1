<#
.SYNOPSIS
  🏗️ Builds flutter_esptool example applications and writes a report.

.DESCRIPTION
  Builds all Flutter targets supported by the current host for each example app.
  Unsupported platform targets are skipped with a clear report entry. Reports
  are written to reports/builds/<timestamp> by default.

.PARAMETER ReportDir
  Base report directory. Default: reports/builds.

.PARAMETER Mode
  Flutter build mode: release, debug, or profile. Default: release.

.PARAMETER ContinueOnError
  Continue building remaining targets after a failure.

.EXAMPLE
  .\scripts\windows\build.ps1 -Mode release
#>
[CmdletBinding()]
param(
  [string]$ReportDir = 'reports/builds',
  [ValidateSet('release','debug','profile')][string]$Mode = 'release',
  [switch]$ContinueOnError
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$RunDir = Join-Path $Root (Join-Path $ReportDir $Stamp)
$Summary = Join-Path $RunDir 'summary.md'
$Failures = 0

$Examples = @(
  @{ Name = 'esptool_cli'; Path = 'example/esptool_cli' },
  @{ Name = 'esptool_ui'; Path = 'example/esptool_ui' }
)
$Targets = @(
  @{ Name = 'web'; Args = @('build','web'); Hosts = @('Windows','Linux','Darwin') },
  @{ Name = 'windows'; Args = @('build','windows'); Hosts = @('Windows') },
  @{ Name = 'linux'; Args = @('build','linux'); Hosts = @('Linux') },
  @{ Name = 'macos'; Args = @('build','macos'); Hosts = @('Darwin') },
  @{ Name = 'android-apk'; Args = @('build','apk'); Hosts = @('Windows','Linux','Darwin') },
  @{ Name = 'ios-no-codesign'; Args = @('build','ios','--no-codesign'); Hosts = @('Darwin') }
)

function Write-Step([string]$Message) { Write-Host "`n🔷 $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "⚠️  $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host "❌ $Message" -ForegroundColor Red }
function Add-Summary([string]$Line) { Add-Content -Path $Summary -Value $Line -Encoding UTF8 }
function Current-HostName { if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } elseif ($IsMacOS) { 'Darwin' } else { 'Unknown' } }

function Invoke-Logged {
  param([string]$Name, [string]$Cwd, [string[]]$Args)
  $log = Join-Path $RunDir ("$Name.log" -replace '[^A-Za-z0-9_.-]', '_')
  Write-Step $Name
  Write-Host "   📁 $Cwd" -ForegroundColor DarkGray
  Write-Host "   ▶ flutter $($Args -join ' ')" -ForegroundColor DarkCyan
  Push-Location $Cwd
  try {
    & flutter @Args *> $log
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  } catch {
    $_ | Out-File -FilePath $log -Append -Encoding UTF8
    $code = 1
  } finally { Pop-Location }
  if ($code -eq 0) {
    Write-Ok "$Name built"
    Add-Summary "| ✅ | $Name | [$([IO.Path]::GetFileName($log))]($([IO.Path]::GetFileName($log))) |"
  } else {
    Write-Err "$Name failed (exit $code)"
    Add-Summary "| ❌ | $Name | [$([IO.Path]::GetFileName($log))]($([IO.Path]::GetFileName($log))) |"
    $script:Failures++
    if (-not $ContinueOnError) { throw "$Name failed" }
  }
}

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
Set-Content -Path $Summary -Value "# 🏗️ Build report`n`nGenerated: $(Get-Date -Format o)`nMode: $Mode`n`n| Status | Step | Log |`n| --- | --- | --- |" -Encoding UTF8

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Magenta
Write-Host '║ 🏗️ flutter_esptool build runner                           ║' -ForegroundColor Magenta
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Magenta
Write-Host "📊 Report: $RunDir" -ForegroundColor Cyan

$hostName = Current-HostName
foreach ($example in $Examples) {
  foreach ($target in $Targets) {
    $name = "$($example.Name)-$($target.Name)-$Mode"
    if ($target.Hosts -notcontains $hostName) {
      Write-Warn "Skipping $name on $hostName host"
      Add-Summary "| ⚪ | $name | Skipped on $hostName host |"
      continue
    }
    $args = @($target.Args) + @("--$Mode")
    Invoke-Logged $name (Join-Path $Root $example.Path) $args
  }
}

Add-Summary "`nFailures: $Failures"
if ($Failures -eq 0) { Write-Ok "Build run completed. Report: $RunDir" } else { Write-Err "$Failures build step(s) failed. Report: $RunDir"; exit 1 }
