@echo off
:: OneClickInstall Launcher
echo ============================================
echo    OneClickInstall - Bulk Software Installer
echo ============================================
echo.

:: Check for admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Run the PowerShell script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OneClickInstall.ps1"
pause
