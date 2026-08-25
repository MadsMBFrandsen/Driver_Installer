@echo off
setlocal

title Driver Deployment - Test Verify Drivers

cls

echo ============================================================
echo Driver Deployment
echo Test: 04-Verify-Drivers.ps1
echo ============================================================
echo.

echo Current directory:
echo %~dp0
echo.

if not exist "%~dp004-Verify-Drivers.ps1" (
    echo [ERROR] 04-Verify-Drivers.ps1 not found.
    echo.
    pause
    exit /b 1
)

echo [OK] Script found.

if not exist "C:\ProgramData\Itino\DriverDeployment\HardwareInformation.json" (
    echo [ERROR] HardwareInformation.json not found.
    echo Run script 01 first.
    echo.
    pause
    exit /b 1
)

echo [OK] HardwareInformation.json found.

if not exist "C:\ProgramData\Itino\DriverDeployment\DeviceErrors-Before.json" (
    echo [WARNING] DeviceErrors-Before.json not found.
    echo Verification can still run, but before/after comparison will be limited.
)

echo.
echo ============================================================
echo Starting driver verification
echo ============================================================
echo.

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp004-Verify-Drivers.ps1"

set "EXITCODE=%ERRORLEVEL%"

echo.
echo ============================================================
echo Driver verification finished
echo ============================================================
echo.

echo Exit Code: %EXITCODE%
echo.

if "%EXITCODE%"=="0" (
    echo [SUCCESS] Verification completed.
) else (
    echo [FAILED] Verification script failed.
)

echo.
echo ============================================================
echo Verification report
echo ============================================================
echo.

if exist "C:\ProgramData\Itino\DriverDeployment\DriverVerification.json" (

    powershell.exe ^
        -NoLogo ^
        -NoProfile ^
        -Command ^
        "$r = Get-Content 'C:\ProgramData\Itino\DriverDeployment\DriverVerification.json' -Raw | ConvertFrom-Json; Write-Host ('Status        : ' + $r.Results.Status); Write-Host ('Errors Before : ' + $r.Results.DeviceErrorsBefore); Write-Host ('Errors After  : ' + $r.Results.DeviceErrorsAfter); Write-Host ('Fixed         : ' + $r.Results.FixedDeviceErrors); Write-Host ('Remaining     : ' + $r.Results.RemainingDeviceErrors); Write-Host ('New Errors    : ' + $r.Results.NewDeviceErrors); Write-Host ('Restart       : ' + $r.Results.RestartRequired)"

) else (

    echo [WARNING] DriverVerification.json was not created.
)

echo.
echo ============================================================
echo Restart status
echo ============================================================
echo.

if exist "C:\ProgramData\Itino\DriverDeployment\RestartRequired.txt" (

    echo [RESTART REQUIRED]
    echo.

    type "C:\ProgramData\Itino\DriverDeployment\RestartRequired.txt"

) else (

    echo [NO RESTART REQUIRED]
)

echo.
echo ============================================================
echo Last 40 log entries
echo ============================================================
echo.

if exist "C:\ProgramData\Itino\DriverDeployment\Logs\Verify-Drivers.log" (

    powershell.exe ^
        -NoLogo ^
        -NoProfile ^
        -Command ^
        "Get-Content 'C:\ProgramData\Itino\DriverDeployment\Logs\Verify-Drivers.log' -Tail 40"

) else (

    echo [WARNING] Verify-Drivers.log not found.
)

echo.
echo ============================================================
echo Files
echo ============================================================
echo.

echo Hardware:
echo C:\ProgramData\Itino\DriverDeployment\HardwareInformation.json
echo.

echo Before:
echo C:\ProgramData\Itino\DriverDeployment\DeviceErrors-Before.json
echo.

echo After:
echo C:\ProgramData\Itino\DriverDeployment\DeviceErrors-After.json
echo.

echo Final report:
echo C:\ProgramData\Itino\DriverDeployment\DriverVerification.json
echo.

echo Log:
echo C:\ProgramData\Itino\DriverDeployment\Logs\Verify-Drivers.log
echo.

echo ============================================================
echo Press any key to close
echo ============================================================

pause >nul

exit /b %EXITCODE%