@echo off
setlocal EnableExtensions

rem ============================================================
rem ITINO FAKE DELL FULL TEST WITH FAKE DCU
rem ============================================================
rem
rem Sequence:
rem   1. 01-Gather-Hardware.ps1
rem   2. Set-FakeDellHardware.ps1
rem   3. Install-FakeDCU.ps1
rem   4. 02-Install-OEM-Update-Tool.ps1
rem   5. 03-Update-Drivers.ps1
rem   6. 04-Verify-Drivers.ps1
rem
rem The fake DCU never installs a driver or firmware package.
rem ============================================================

set "ROOT=%~dp0"

set "GATHER=%ROOT%Scripts\01-Gather-Hardware.ps1"
set "FAKEDELL=%ROOT%Set-FakeDellHardware.ps1"
set "FAKEDCU=%ROOT%Install-FakeDCU.ps1"
set "INSTALLTOOL=%ROOT%Scripts\02-Install-OEM-Update-Tool.ps1"
set "UPDATEDRIVERS=%ROOT%Scripts\03-Update-Drivers.ps1"
set "VERIFYDRIVERS=%ROOT%Scripts\04-Verify-Drivers.ps1"

set "HARDWAREJSON=C:\ProgramData\Itino\DriverDeployment\HardwareInformation.json"

rem ============================================================
rem FAKE DCU SCENARIO
rem ============================================================
rem
rem Recommended first test:
rem   UpdatesRequireReboot
rem
rem Other supported values:
rem   UpdatesSuccess
rem   NoUpdates
rem   ScanRestartRequired
rem   ScanFailure
rem   ScanRetryThenSuccess
rem   ApplyFailure
rem   ApplyRetryThenSuccess
rem ============================================================

set "FAKE_DCU_SCENARIO=UpdatesRequireReboot"


for /f %%I in (
    'powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"'
) do set "STAMP=%%I"

set "LOG=%ROOT%FakeDell-FakeDCU-FullTest-%STAMP%.log"


rem ============================================================
rem REQUIRE ADMINISTRATOR
rem ============================================================

net session >nul 2>&1

if not "%errorlevel%"=="0" (
    echo.
    echo Administrator rights are required.
    echo Requesting elevation...
    echo.

    powershell.exe ^
        -NoProfile ^
        -ExecutionPolicy Bypass ^
        -Command "Start-Process -FilePath '%~f0' -Verb RunAs"

    exit /b
)


rem ============================================================
rem VERIFY REQUIRED FILES
rem ============================================================

for %%F in (
    "%GATHER%"
    "%FAKEDELL%"
    "%FAKEDCU%"
    "%INSTALLTOOL%"
    "%UPDATEDRIVERS%"
    "%VERIFYDRIVERS%"
) do (
    if not exist "%%~F" (
        echo ERROR: Required file missing:
        echo   %%~F
        pause
        exit /b 1
    )
)


rem ============================================================
rem START LOG
rem ============================================================

(
    echo ============================================================
    echo ITINO FAKE DELL FULL TEST WITH FAKE DCU
    echo ============================================================
    echo Start Time        : %date% %time%
    echo Computer          : %COMPUTERNAME%
    echo USB Path          : %ROOT%
    echo Fake DCU Scenario : %FAKE_DCU_SCENARIO%
    echo ============================================================
    echo.
) > "%LOG%"


echo.
echo ============================================================
echo ITINO FAKE DELL FULL TEST WITH FAKE DCU
echo ============================================================
echo.
echo Scenario:
echo   %FAKE_DCU_SCENARIO%
echo.
echo Log:
echo   %LOG%
echo.


rem ============================================================
rem CONTROLLER ENVIRONMENT
rem ============================================================

set "ITINO_WRITE_LOG_FILES=1"
set "ITINO_UNATTENDED_MODE=1"
set "ITINO_REQUIRE_ADMINISTRATOR=1"
set "ITINO_WEB_TIMEOUT_SECONDS=15"
set "ITINO_MINIMUM_POWERSHELL_MAJOR_VERSION=5"

rem Safety: never permit BIOS/firmware in this fake Dell Lenovo test.
set "ITINO_ALLOW_FIRMWARE_UPDATES=0"

set "ITINO_DELL_COMMAND_UPDATE_OFFICIAL_PAGE_URL=https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update"
set "ITINO_DELL_COMMAND_UPDATE_FALLBACK_VERSION=5.7.1"
set "ITINO_DELL_COMMAND_UPDATE_FALLBACK_DOWNLOAD_URL=https://dl.dell.com/FOLDER14847331M/2/Dell-Command-Update-Windows-Universal-Application_P0P70_WIN64_5.7.1_A00.EXE"

set "ITINO_FAKE_DCU_SCENARIO=%FAKE_DCU_SCENARIO%"

set "RESTART_REQUIRED=0"


rem ============================================================
rem STEP 1
rem ============================================================

call :RunStage ^
    "STEP 1 OF 6 - GATHER REAL HARDWARE" ^
    "%GATHER%"

if errorlevel 1 goto :FAILED


rem ============================================================
rem STEP 2
rem ============================================================

echo.
echo ============================================================
echo STEP 2 OF 6 - APPLY FAKE DELL IDENTITY
echo ============================================================
echo.

(
    echo.
    echo ============================================================
    echo STEP 2 OF 6 - APPLY FAKE DELL IDENTITY
    echo ============================================================
) >> "%LOG%"

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%FAKEDELL%" ^
    -Manufacturer "Dell Inc." ^
    -Model "Latitude 5450" ^
    >> "%LOG%" 2>&1

set "RC=%errorlevel%"

echo Exit code: %RC%
echo Exit code: %RC% >> "%LOG%"

if "%RC%"=="3010" (
    set "RESTART_REQUIRED=1"
) else (
    if not "%RC%"=="0" (
        echo [FAILED] STEP 2 OF 6 - APPLY FAKE DELL IDENTITY
        echo [FAILED] STEP 2 OF 6 - APPLY FAKE DELL IDENTITY >> "%LOG%"
        goto :FAILED
    )
)


powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -Command ^
    "$h = Get-Content '%HARDWAREJSON%' -Raw | ConvertFrom-Json; Write-Host ('Manufacturer : ' + $h.Computer.Manufacturer); Write-Host ('Model        : ' + $h.Computer.Model); if ($h.Computer.Manufacturer -notmatch 'Dell') { exit 1 }" ^
    >> "%LOG%" 2>&1

if errorlevel 1 (
    echo Fake Dell identity verification failed.
    echo Fake Dell identity verification failed. >> "%LOG%"
    goto :FAILED
)


rem ============================================================
rem STEP 3
rem ============================================================

echo.
echo ============================================================
echo STEP 3 OF 6 - INSTALL SAFE FAKE DCU
echo ============================================================
echo.

(
    echo.
    echo ============================================================
    echo STEP 3 OF 6 - INSTALL SAFE FAKE DCU
    echo ============================================================
) >> "%LOG%"

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%FAKEDCU%" ^
    -Scenario "%FAKE_DCU_SCENARIO%" ^
    -ResetState ^
    >> "%LOG%" 2>&1

set "RC=%errorlevel%"

echo Exit code: %RC%
echo Exit code: %RC% >> "%LOG%"

if "%RC%"=="3010" (
    set "RESTART_REQUIRED=1"
) else (
    if not "%RC%"=="0" (
        echo [FAILED] STEP 3 OF 6 - INSTALL SAFE FAKE DCU
        echo [FAILED] STEP 3 OF 6 - INSTALL SAFE FAKE DCU >> "%LOG%"
        goto :FAILED
    )
)


rem ============================================================
rem STEP 4
rem ============================================================

call :RunStage ^
    "STEP 4 OF 6 - INSTALL OEM UPDATE TOOL" ^
    "%INSTALLTOOL%"

if errorlevel 1 goto :FAILED


rem ============================================================
rem STEP 5
rem ============================================================

call :RunStage ^
    "STEP 5 OF 6 - UPDATE DRIVERS" ^
    "%UPDATEDRIVERS%"

if errorlevel 1 goto :FAILED


rem ============================================================
rem STEP 6
rem ============================================================

call :RunStage ^
    "STEP 6 OF 6 - VERIFY DRIVERS" ^
    "%VERIFYDRIVERS%"

if errorlevel 1 goto :FAILED


rem ============================================================
rem SUCCESS
rem ============================================================

echo.
echo ============================================================
echo TEST COMPLETE
echo ============================================================
echo.

if "%RESTART_REQUIRED%"=="1" (
    echo Result: SUCCESS - RESTART REQUIRED
    echo Result: SUCCESS - RESTART REQUIRED >> "%LOG%"
) else (
    echo Result: SUCCESS
    echo Result: SUCCESS >> "%LOG%"
)

echo.
echo Log saved to:
echo   %LOG%
echo.

echo Fake DCU remains installed for post-reboot testing.
echo To remove it later, run:
echo   Remove-FakeDCU.ps1
echo.

pause

if "%RESTART_REQUIRED%"=="1" (
    exit /b 3010
)

exit /b 0


rem ============================================================
rem RUN STAGE WITHOUT EXTRA ARGUMENTS
rem ============================================================

:RunStage

set "STAGE_NAME=%~1"
set "STAGE_SCRIPT=%~2"

echo.
echo ============================================================
echo %STAGE_NAME%
echo ============================================================
echo.

(
    echo.
    echo ============================================================
    echo %STAGE_NAME%
    echo ============================================================
) >> "%LOG%"

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%STAGE_SCRIPT%" ^
    >> "%LOG%" 2>&1

set "RC=%errorlevel%"

echo Exit code: %RC%
echo Exit code: %RC% >> "%LOG%"

if "%RC%"=="3010" (
    set "RESTART_REQUIRED=1"
    exit /b 0
)

if not "%RC%"=="0" (
    echo [FAILED] %STAGE_NAME%
    echo [FAILED] %STAGE_NAME% >> "%LOG%"
    exit /b 1
)

exit /b 0


rem ============================================================
rem FAILURE
rem ============================================================

:FAILED

echo.
echo ============================================================
echo TEST FAILED
echo ============================================================
echo.
echo Check:
echo   %LOG%
echo.

echo. >> "%LOG%"
echo ============================================================ >> "%LOG%"
echo TEST FAILED >> "%LOG%"
echo ============================================================ >> "%LOG%"

pause
exit /b 1
