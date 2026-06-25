# uninstall-hooks.ps1 — Removes git hooks installed from scripts/hooks/
# Usage: pwsh scripts/uninstall-hooks.ps1  (from repository root)

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

Write-Host "🗑️  Removing hooks from: $GitHooksDir"
Write-Host ""

$removed = 0
Get-ChildItem -Path $HooksSourceDir -File | ForEach-Object {
    $dest = Join-Path $GitHooksDir $_.Name
    if (Test-Path $dest -PathType Leaf) {
        Remove-Item -Path $dest -Force
        Write-Host "🗑️  Removed: $($_.Name)"
        $removed++
    } else {
        Write-Host "⚠️  Not found (skipped): $($_.Name)"
    }
}

Write-Host ""
Write-Host "🎉 Done. $removed hook(s) removed."
