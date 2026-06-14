@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM SYNOPSIS
REM   🚀 Installs or updates the latest stable PowerShell on Windows.
REM
REM USAGE
REM   scripts\windows\install-powershell.cmd [/yes]
REM
REM BEHAVIOR
REM   Idempotent. Uses winget when available. Requests elevation when needed.

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo ⚠️  Requesting Administrator privileges...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs -Wait"
  exit /b %errorlevel%
)

echo ╔════════════════════════════════════════════════════════════╗
echo ║ 🚀 PowerShell installer/updater                           ║
echo ╚════════════════════════════════════════════════════════════╝

where winget >nul 2>&1
if not "%errorlevel%"=="0" (
  echo ❌ winget was not found. Install App Installer from Microsoft Store first.
  exit /b 1
)

winget list --id Microsoft.PowerShell --exact --accept-source-agreements >nul 2>&1
if "%errorlevel%"=="0" (
  echo 🔁 Updating PowerShell...
  winget upgrade --id Microsoft.PowerShell --exact --silent --accept-package-agreements --accept-source-agreements
) else (
  echo 📦 Installing PowerShell...
  winget install --id Microsoft.PowerShell --exact --silent --accept-package-agreements --accept-source-agreements
)

if not "%errorlevel%"=="0" (
  echo ❌ PowerShell install/update failed.
  exit /b %errorlevel%
)

echo ✅ PowerShell is installed or up to date.
exit /b 0
