@echo off
title Driver Deployment - Gather Hardware Test

echo ==========================================
echo Driver Deployment - Hardware Test
echo ==========================================
echo.

echo Running:
echo 01-Gather-Hardware.ps1
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp001-Gather-Hardware.ps1"

set EXITCODE=%ERRORLEVEL%

echo.
echo ==========================================
echo Script finished
echo ==========================================
echo Exit Code: %EXITCODE%
echo.

if "%EXITCODE%"=="0" (
    echo RESULT: SUCCESS
) else (
    echo RESULT: FAILED
)

echo.
echo Output location:
echo C:\ProgramData\UniversalDriverInstaller\DriverDeployment\
echo.

echo Press any key to close...
pause >nul

exit /b %EXITCODE%