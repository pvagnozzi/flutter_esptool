# install-hooks.ps1 — Installs git hooks from scripts/hooks/ into .git/hooks/
# Usage: pwsh scripts/install-hooks.ps1  (from repository root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$HooksSourceDir = Join-Path $ScriptDir 'hooks'
$RepoRoot       = Split-Path -Parent $ScriptDir
$GitHooksDir    = Join-Path $RepoRoot '.git\hooks'

# Check that .git\hooks\ exists
if (-not (Test-Path $GitHooksDir -PathType Container)) {
    Write-Error "❌ Directory not found: $GitHooksDir`n   Are you running this from the repository root?"
    exit 1
}

Write-Host "📂 Installing hooks from: $HooksSourceDir"
Write-Host "📂 Installing hooks into: $GitHooksDir"
Write-Host ""

$installed = 0
Get-ChildItem -Path $HooksSourceDir -File | ForEach-Object {
    $dest = Join-Path $GitHooksDir $_.Name
    Copy-Item -Path $_.FullName -Destination $dest -Force
    # Grant execute permission for the current user via icacls
    icacls $dest /grant "${env:USERNAME}:(RX)" | Out-Null
    Write-Host "✅ Installed: $($_.Name)"
    $installed++
}

Write-Host ""
Write-Host "🎉 Done. $installed hook(s) installed successfully."
