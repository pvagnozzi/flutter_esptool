<#
.SYNOPSIS
  🧪 Runs flutter_esptool tests and writes a timestamped report.

.DESCRIPTION
  Runs root package tests with coverage plus non-hardware tests for all example
  applications. Reports are written to reports/tests/<timestamp> by default.
  The report directory is ignored by git.

.PARAMETER ReportDir
  Base report directory. Default: reports/tests.

.PARAMETER SkipCoverage
  Run root tests without --coverage.

.PARAMETER IncludeHardware
  Also run opt-in hardware integration tests when available.

.PARAMETER Port
  Serial port for hardware tests. Default: COM22.

.EXAMPLE
  .\scripts\windows\run-tests.ps1

.EXAMPLE
  .\scripts\windows\run-tests.ps1 -IncludeHardware -Port COM22
#>
[CmdletBinding()]
param(
  [string]$ReportDir = 'reports/tests',
  [switch]$SkipCoverage,
  [switch]$IncludeHardware,
  [string]$Port = 'COM22'
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$RunDir = Join-Path $Root (Join-Path $ReportDir $Stamp)
$Summary = Join-Path $RunDir 'summary.md'
$Failures = 0

function Write-Step([string]$Message) { Write-Host "`n🔷 $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "✅ $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "⚠️  $Message" -ForegroundColor Yellow }
function Write-Err([string]$Message) { Write-Host "❌ $Message" -ForegroundColor Red }

function Add-Summary([string]$Line) { Add-Content -Path $Summary -Value $Line -Encoding UTF8 }

function Invoke-Logged {
  param(
    [string]$Name,
    [string]$Cwd,
    [string]$Exe,
    [string[]]$Args
  )
  $log = Join-Path $RunDir ("$Name.log" -replace '[^A-Za-z0-9_.-]', '_')
  Write-Step "$Name"
  Write-Host "   📁 $Cwd" -ForegroundColor DarkGray
  Write-Host "   ▶ $Exe $($Args -join ' ')" -ForegroundColor DarkCyan
  Push-Location $Cwd
  try {
    & $Exe @Args *> $log
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
  } catch {
    $_ | Out-File -FilePath $log -Append -Encoding UTF8
    $code = 1
  } finally {
    Pop-Location
  }
  if ($code -eq 0) {
    Write-Ok "$Name passed"
    Add-Summary "| ✅ | $Name | [$([IO.Path]::GetFileName($log))]($([IO.Path]::GetFileName($log))) |"
  } else {
    Write-Err "$Name failed (exit $code)"
    Add-Summary "| ❌ | $Name | [$([IO.Path]::GetFileName($log))]($([IO.Path]::GetFileName($log))) |"
    $script:Failures++
  }
}

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
Set-Content -Path $Summary -Value "# 🧪 Test report`n`nGenerated: $(Get-Date -Format o)`n`n| Status | Step | Log |`n| --- | --- | --- |" -Encoding UTF8

Write-Host '╔════════════════════════════════════════════════════════════╗' -ForegroundColor Magenta
Write-Host '║ 🧪 flutter_esptool test runner                            ║' -ForegroundColor Magenta
Write-Host '╚════════════════════════════════════════════════════════════╝' -ForegroundColor Magenta
Write-Host "📊 Report: $RunDir" -ForegroundColor Cyan

$rootArgs = if ($SkipCoverage) { @('test') } else { @('test', '--coverage') }
Invoke-Logged 'root-flutter-test' $Root 'flutter' $rootArgs
if (-not $SkipCoverage) {
  $lcov = Join-Path $Root 'coverage/lcov.info'
  if (Test-Path $lcov) {
    Copy-Item $lcov (Join-Path $RunDir 'lcov.info') -Force
    Add-Summary "`nCoverage file: [lcov.info](lcov.info)"
  }
}

Invoke-Logged 'example-cli-flutter-test' (Join-Path $Root 'example/esptool_cli') 'flutter' @('test')
Invoke-Logged 'example-ui-flutter-test' (Join-Path $Root 'example/esptool_ui') 'flutter' @('test')

if ($IncludeHardware) {
  Invoke-Logged 'example-ui-hardware-test' (Join-Path $Root 'example/esptool_ui') 'flutter' @('test', '-d', 'windows', 'integration_test/esp32_hardware_test.dart', "--dart-define=RUN_ESP_HARDWARE_TESTS=true", "--dart-define=ESP_PORT=$Port")
} else {
  Write-Warn 'Hardware tests skipped. Use -IncludeHardware to run them.'
  Add-Summary "`nHardware tests skipped."
}

Add-Summary "`nFailures: $Failures"
if ($Failures -eq 0) { Write-Ok "All tests passed. Report: $RunDir" } else { Write-Err "$Failures test step(s) failed. Report: $RunDir"; exit 1 }
