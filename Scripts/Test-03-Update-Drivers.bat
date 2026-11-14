@echo off
setlocal

title Driver Deployment - Test Update Drivers

cls

echo ============================================================
echo Driver Deployment
echo Test: 03-Update-Drivers.ps1
echo ============================================================
echo.

echo Current directory:
echo %~dp0
echo.

if not exist "%~dp003-Update-Drivers.ps1" (
    echo [ERROR] 03-Update-Drivers.ps1 not found.
    echo.
    pause
    exit /b 1
)

echo [OK] Script found.

if not exist "C:\ProgramData\UniversalDriverInstaller\DriverDeployment\HardwareInformation.json" (
    echo [ERROR] HardwareInformation.json not found.
    echo Run script 01 first.
    echo.
    pause
    exit /b 1
)

echo [OK] HardwareInformation.json found.
echo.

echo WARNING:
echo This test can actually download and install driver updates.
echo The computer may require a restart afterwards.
echo.
echo Press CTRL+C now to cancel.
echo.
pause

echo.
echo ============================================================
echo Starting driver update
echo ============================================================
echo.

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp003-Update-Drivers.ps1"

set "EXITCODE=%ERRORLEVEL%"

echo.
echo ============================================================
echo Driver update finished
echo ============================================================
echo.

echo Exit Code: %EXITCODE%
echo.

if "%EXITCODE%"=="0" (
    echo [SUCCESS] Driver update completed.
)

if "%EXITCODE%"=="3010" (
    echo [SUCCESS] Driver update completed.
    echo [RESTART REQUIRED]
)

if not "%EXITCODE%"=="0" if not "%EXITCODE%"=="3010" (
    echo [FAILED] Driver update failed.
)

echo.
echo Restart marker:
echo C:\ProgramData\UniversalDriverInstaller\DriverDeployment\RestartRequired.txt
echo.

if exist "C:\ProgramData\UniversalDriverInstaller\DriverDeployment\RestartRequired.txt" (
    echo [RESTART REQUIRED]
    echo.
    type "C:\ProgramData\UniversalDriverInstaller\DriverDeployment\RestartRequired.txt"
) else (
    echo [NO RESTART MARKER]
)

echo.
echo ============================================================
echo Last 40 log entries
echo ============================================================
echo.

if exist "C:\ProgramData\UniversalDriverInstaller\DriverDeployment\Logs\Update-Drivers.log" (
    powershell.exe -NoLogo -NoProfile -Command ^
        "Get-Content 'C:\ProgramData\UniversalDriverInstaller\DriverDeployment\Logs\Update-Drivers.log' -Tail 40"
) else (
    echo [WARNING] Update-Drivers.log was not found.
)

echo.
echo ============================================================
echo Press any key to close
echo ============================================================

pause >nul

exit /b %EXITCODE%