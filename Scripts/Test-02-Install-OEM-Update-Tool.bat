@echo off
setlocal

title Driver Deployment - Test OEM Update Tool

cls

echo ============================================================
echo Driver Deployment
echo Test: 02-Install-OEM-Update-Tool.ps1
echo ============================================================
echo.

echo Current directory:
echo %~dp0
echo.

echo Checking required files...
echo.

if not exist "%~dp002-Install-OEM-Update-Tool.ps1" (
    echo [ERROR] PowerShell script not found:
    echo %~dp002-Install-OEM-Update-Tool.ps1
    echo.
    pause
    exit /b 1
)

echo [OK] PowerShell script found.
echo.

echo Checking if HardwareInformation.json exists...

if not exist "C:\ProgramData\Itino\DriverDeployment\HardwareInformation.json" (
    echo.
    echo [ERROR] HardwareInformation.json was not found.
    echo.
    echo Script 01 must be run successfully first.
    echo.
    echo Expected file:
    echo C:\ProgramData\Itino\DriverDeployment\HardwareInformation.json
    echo.
    pause
    exit /b 1
)

echo [OK] HardwareInformation.json found.
echo.

echo ============================================================
echo Starting OEM Update Tool test
echo ============================================================
echo.

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp002-Install-OEM-Update-Tool.ps1"

set "EXITCODE=%ERRORLEVEL%"

echo.
echo ============================================================
echo OEM Update Tool test finished
echo ============================================================
echo.

echo Exit Code: %EXITCODE%
echo.

if "%EXITCODE%"=="0" (
    echo [SUCCESS] Script completed successfully.
) else (
    echo [FAILED] Script failed.
)

echo.
echo ------------------------------------------------------------
echo Log file:
echo C:\ProgramData\Itino\DriverDeployment\Logs\Install-OEM-Update-Tool.log
echo ------------------------------------------------------------
echo.

if exist "C:\ProgramData\Itino\DriverDeployment\Logs\Install-OEM-Update-Tool.log" (

    echo Last log entries:
    echo.
    
    powershell.exe -NoLogo -NoProfile -Command ^
        "Get-Content 'C:\ProgramData\Itino\DriverDeployment\Logs\Install-OEM-Update-Tool.log' -Tail 20"

) else (

    echo [WARNING] Log file was not found.
)

echo.
echo ============================================================
echo Press any key to close
echo ============================================================

pause >nul

exit /b %EXITCODE%