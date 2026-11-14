@echo off
setlocal

title Universal Driver Installer - Test PC

cls

echo ============================================================
echo Universal Driver Installer
echo Test PC - Full Driver Deployment
echo ============================================================
echo.

echo Script source:
echo %~dp0
echo.

REM ============================================================
REM Check Administrator rights
REM ============================================================

powershell.exe -NoLogo -NoProfile -Command ^
    "$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"

if "%ERRORLEVEL%"=="0" (
    echo [OK] Running as Administrator.
    echo.
    goto :AFTER_ADMIN_CHECK
)

REM ============================================================
REM Not elevated - ask for Administrator level
REM ============================================================


:REQUEST_ADMIN
echo.
echo [INFO] Administrator rights are required for this test.
echo [INFO] Opening Windows UAC prompt...
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
    "try { Start-Process -FilePath '%~f0' -WorkingDirectory '%~dp0' -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }"

if not "%ERRORLEVEL%"=="0" (
    echo.
    echo [ERROR] Administrator elevation was cancelled or failed.
    echo.
    pause
    exit /b 1
)

REM The elevated BAT starts as a new process.
REM Close this non-elevated instance.
exit /b 0


:AFTER_ADMIN_CHECK


REM ============================================================
REM Check Internet
REM ============================================================

echo Checking network connectivity...

powershell.exe -NoLogo -NoProfile -Command ^
    "if (Test-NetConnection -ComputerName 'www.microsoft.com' -Port 443 -InformationLevel Quiet) { exit 0 } else { exit 1 }"

if not "%ERRORLEVEL%"=="0" (
    echo.
    echo [ERROR] Internet connection test failed.
    echo.
    echo The driver deployment requires Internet access for:
    echo   OEM update tools
    echo   Windows Update
    echo   Driver downloads
    echo.
    pause
    exit /b 1
)

echo [OK] Internet connection available.
echo.


REM ============================================================
REM Check main controller
REM ============================================================

if not exist "%~dp0Run-DriverDeployment.ps1" (
    echo [ERROR] Main script not found:
    echo %~dp0Run-DriverDeployment.ps1
    echo.
    pause
    exit /b 1
)

echo [OK] Run-DriverDeployment.ps1 found.


REM ============================================================
REM Check Scripts folder
REM ============================================================

if not exist "%~dp0Scripts" (
    echo.
    echo [ERROR] Scripts folder not found:
    echo %~dp0Scripts
    echo.
    pause
    exit /b 1
)

echo [OK] Scripts folder found.


REM ============================================================
REM Check individual scripts
REM ============================================================

echo.
echo Checking required scripts...
echo.

set "MISSING=0"

if exist "%~dp0Scripts\00-Preflight.ps1" (
    echo [OK] 00-Preflight.ps1
) else (
    echo [ERROR] 00-Preflight.ps1 missing
    set "MISSING=1"
)

if exist "%~dp0Scripts\01-Gather-Hardware.ps1" (
    echo [OK] 01-Gather-Hardware.ps1
) else (
    echo [ERROR] 01-Gather-Hardware.ps1 missing
    set "MISSING=1"
)

if exist "%~dp0Scripts\02-Install-OEM-Update-Tool.ps1" (
    echo [OK] 02-Install-OEM-Update-Tool.ps1
) else (
    echo [ERROR] 02-Install-OEM-Update-Tool.ps1 missing
    set "MISSING=1"
)

if exist "%~dp0Scripts\03-Update-Drivers.ps1" (
    echo [OK] 03-Update-Drivers.ps1
) else (
    echo [ERROR] 03-Update-Drivers.ps1 missing
    set "MISSING=1"
)

if exist "%~dp0Scripts\04-Verify-Drivers.ps1" (
    echo [OK] 04-Verify-Drivers.ps1
) else (
    echo [ERROR] 04-Verify-Drivers.ps1 missing
    set "MISSING=1"
)

if "%MISSING%"=="1" (
    echo.
    echo [FAILED] Required scripts are missing.
    echo.
    pause
    exit /b 1
)


REM ============================================================
REM Show test information
REM ============================================================

echo.
echo ============================================================
echo Test PC Information
echo ============================================================
echo.

powershell.exe -NoLogo -NoProfile -Command ^
    "$c=Get-CimInstance Win32_ComputerSystem; $b=Get-CimInstance Win32_BIOS; Write-Host ('Manufacturer : ' + $c.Manufacturer); Write-Host ('Model        : ' + $c.Model); Write-Host ('Serial       : ' + $b.SerialNumber)"

echo.


REM ============================================================
REM Warning
REM ============================================================

echo ============================================================
echo WARNING
echo ============================================================
echo.
echo This is a REAL driver deployment test.
echo.
echo The scripts can:
echo.
echo   1. Detect the PC hardware
echo   2. Download OEM management tools
echo   3. Install or prepare OEM tools
echo   4. Search for newer drivers
echo   5. Download drivers
echo   6. Install drivers
echo   7. Verify Device Manager afterwards
echo.
echo The computer may require a restart.
echo.
echo The test will NOT automatically restart this computer.
echo.
echo Press CTRL+C to cancel.
echo.
echo Press any key to begin.
echo.

pause >nul


REM ============================================================
REM Start deployment
REM ============================================================

cls

echo ============================================================
echo Starting Driver Deployment
echo ============================================================
echo.

set "RUN_D_ROOT=%~dp0"

REM Explicitly start Run-DriverDeployment.ps1 with Administrator rights.
REM -Wait keeps this BAT paused until the deployment script finishes.
REM -PassThru lets us preserve the deployment script exit code.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
    "$script = Join-Path $env:RUN_D_ROOT 'Run-DriverDeployment.ps1'; try { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File', ('\"' + $script + '\"')) -WorkingDirectory $env:RUN_D_ROOT -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { Write-Host ('[ERROR] Could not start Run-DriverDeployment.ps1 as Administrator: ' + $_.Exception.Message); exit 1 }"

set "EXITCODE=%ERRORLEVEL%"


REM ============================================================
REM Result
REM ============================================================

echo.
echo ============================================================
echo Deployment Finished
echo ============================================================
echo.

echo Exit Code: %EXITCODE%
echo.


REM ============================================================
REM Read actual deployment summary
REM ============================================================

if exist "C:\ProgramData\UniversalDriverInstaller\DriverDeployment\DeploymentSummary.json" (

    echo Deployment result:
    echo.

    powershell.exe ^
        -NoLogo ^
        -NoProfile ^
        -Command ^
        "$r=Get-Content 'C:\ProgramData\UniversalDriverInstaller\DriverDeployment\DeploymentSummary.json' -Raw | ConvertFrom-Json; Write-Host ('Status           : ' + $r.Status); Write-Host ('Restart Required : ' + $r.RestartRequired); if ($r.FailedStage) { Write-Host ('Failed Stage     : ' + $r.FailedStage) }; Write-Host ''; Write-Host 'Stages:'; foreach ($s in $r.Stages) { Write-Host ('  ' + $s.Name + ' | Exit=' + $s.ExitCode + ' | ' + $s.DurationSeconds + ' sec') }"

) else (

    echo [WARNING] Deployment summary was not created.
)


REM ============================================================
REM Verification
REM ============================================================

echo.
echo ============================================================
echo Driver Verification
echo ============================================================
echo.

if exist "C:\ProgramData\UniversalDriverInstaller\DriverDeployment\DriverVerification.json" (

    powershell.exe ^
        -NoLogo ^
        -NoProfile ^
        -Command ^
        "$r=Get-Content 'C:\ProgramData\UniversalDriverInstaller\DriverDeployment\DriverVerification.json' -Raw | ConvertFrom-Json; Write-Host ('Status        : ' + $r.Results.Status); Write-Host ('Errors Before : ' + $r.Results.DeviceErrorsBefore); Write-Host ('Errors After  : ' + $r.Results.DeviceErrorsAfter); Write-Host ('Fixed         : ' + $r.Results.FixedDeviceErrors); Write-Host ('Remaining     : ' + $r.Results.RemainingDeviceErrors); Write-Host ('New Errors    : ' + $r.Results.NewDeviceErrors); Write-Host ('Restart       : ' + $r.Results.RestartRequired)"

) else (

    echo [WARNING] DriverVerification.json was not created.
)


REM ============================================================
REM Restart
REM ============================================================

echo.
echo ============================================================
echo Restart Status
echo ============================================================
echo.

if exist "C:\ProgramData\UniversalDriverInstaller\DriverDeployment\RestartRequired.txt" (

    echo [RESTART REQUIRED]
    echo.

    type "C:\ProgramData\UniversalDriverInstaller\DriverDeployment\RestartRequired.txt"

) else (

    echo [NO RESTART MARKER]
)


REM ============================================================
REM Log location
REM ============================================================

echo.
echo ============================================================
echo Test Finished
echo ============================================================
echo.

echo All logs and reports are stored on the TEST PC:
echo.
echo C:\ProgramData\UniversalDriverInstaller\DriverDeployment\
echo.

echo The USB can be removed after this test has completely finished.
echo.

echo Press any key to close.
pause >nul

exit /b %EXITCODE%