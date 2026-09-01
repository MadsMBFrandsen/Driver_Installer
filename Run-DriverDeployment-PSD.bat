@echo off
setlocal EnableExtensions

cd /d "%~dp0"

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0Run-DriverDeployment.ps1"

set "DriverExitCode=%ERRORLEVEL%"

exit /b %DriverExitCode%