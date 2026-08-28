@echo off
setlocal EnableExtensions

rem ============================================================
rem ITINO FAKE DELL FULL DEPLOYMENT TEST
rem ============================================================
rem
rem Runs:
rem   1. 01-Gather-Hardware.ps1
rem   2. Set-FakeDellHardware.ps1
rem   3. 02-Install-OEM-Update-Tool.ps1
rem   4. 03-Update-Drivers.ps1
rem   5. 04-Verify-Drivers.ps1
rem
rem The fake Dell identity exists only inside:
rem
rem C:\ProgramData\Itino\DriverDeployment\HardwareInformation.json
rem
rem Real Lenovo BIOS / WMI information is NOT modified.
rem ============================================================


rem ============================================================
rem PATHS
rem ============================================================

set "ROOT=%~dp0"

set "GATHER=%ROOT%Scripts\01-Gather-Hardware.ps1"
set "FAKEDELL=%ROOT%Set-FakeDellHardware.ps1"
set "INSTALLTOOL=%ROOT%Scripts\02-Install-OEM-Update-Tool.ps1"
set "UPDATEDRIVERS=%ROOT%Scripts\03-Update-Drivers.ps1"
set "VERIFYDRIVERS=%ROOT%Scripts\04-Verify-Drivers.ps1"

set "HARDWAREJSON=C:\ProgramData\Itino\DriverDeployment\HardwareInformation.json"


rem ============================================================
rem TIMESTAMP
rem ============================================================

for /f %%I in (
    'powershell.exe -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"'
) do set "STAMP=%%I"

set "LOG=%ROOT%FakeDell-FullTest-%STAMP%.log"


rem ============================================================
rem REQUIRE ADMINISTRATOR
rem ============================================================

net session >nul 2>&1

if not "%errorlevel%"=="0" (

    echo.
    echo ============================================================
    echo ADMINISTRATOR REQUIRED
    echo ============================================================
    echo.
    echo Requesting administrator rights...
    echo.

    powershell.exe ^
        -NoProfile ^
        -ExecutionPolicy Bypass ^
        -Command "Start-Process -FilePath '%~f0' -Verb RunAs"

    exit /b
)


rem ============================================================
rem START LOG
rem ============================================================

(
    echo ============================================================
    echo ITINO FAKE DELL FULL DEPLOYMENT TEST
    echo ============================================================
    echo.
    echo Start Time : %date% %time%
    echo Computer   : %COMPUTERNAME%
    echo USB Path   : %ROOT%
    echo.
    echo ============================================================
) > "%LOG%"


echo.
echo ============================================================
echo ITINO FAKE DELL FULL DEPLOYMENT TEST
echo ============================================================
echo.
echo Computer:
echo   %COMPUTERNAME%
echo.
echo USB:
echo   %ROOT%
echo.
echo Log:
echo   %LOG%
echo.


rem ============================================================
rem VERIFY REQUIRED FILES
rem ============================================================

echo Checking required files...
echo.


if not exist "%GATHER%" (

    echo [ERROR] Missing:
    echo %GATHER%

    echo [ERROR] Missing: %GATHER% >> "%LOG%"

    goto :FAILED
)


if not exist "%FAKEDELL%" (

    echo [ERROR] Missing:
    echo %FAKEDELL%

    echo [ERROR] Missing: %FAKEDELL% >> "%LOG%"

    goto :FAILED
)


if not exist "%INSTALLTOOL%" (

    echo [ERROR] Missing:
    echo %INSTALLTOOL%

    echo [ERROR] Missing: %INSTALLTOOL% >> "%LOG%"

    goto :FAILED
)


if not exist "%UPDATEDRIVERS%" (

    echo [ERROR] Missing:
    echo %UPDATEDRIVERS%

    echo [ERROR] Missing: %UPDATEDRIVERS% >> "%LOG%"

    goto :FAILED
)


if not exist "%VERIFYDRIVERS%" (

    echo [ERROR] Missing:
    echo %VERIFYDRIVERS%

    echo [ERROR] Missing: %VERIFYDRIVERS% >> "%LOG%"

    goto :FAILED
)


echo Required files found.
echo.

echo Required files found. >> "%LOG%"
echo. >> "%LOG%"


rem ============================================================
rem TRACK RESTART REQUIREMENT
rem ============================================================

set "RESTART_REQUIRED=0"


rem ============================================================
rem STEP 1
rem GATHER REAL HARDWARE
rem ============================================================

echo.
echo ============================================================
echo STEP 1 OF 5
echo GATHER REAL HARDWARE
echo ============================================================
echo.

(
    echo.
    echo ============================================================
    echo STEP 1 OF 5
    echo GATHER REAL HARDWARE
    echo ============================================================
) >> "%LOG%"


powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%GATHER%" ^
    >> "%LOG%" 2>&1


set "RC=%errorlevel%"


echo Exit code: %RC%
echo Exit code: %RC% >> "%LOG%"


if "%RC%"=="3010" (
    set "RESTART_REQUIRED=1"
    goto :STEP2
)


if not "%RC%"=="0" (

    echo.
    echo [FAILED] 01-Gather-Hardware.ps1
    echo.

    echo [FAILED] 01-Gather-Hardware.ps1 >> "%LOG%"

    goto :FAILED
)


:STEP2

rem ============================================================
rem STEP 2
rem FAKE DELL HARDWARE IDENTITY
rem ============================================================

echo.
echo ============================================================
echo STEP 2 OF 5
echo APPLY FAKE DELL IDENTITY
echo ============================================================
echo.

(
    echo.
    echo ============================================================
    echo STEP 2 OF 5
    echo APPLY FAKE DELL IDENTITY
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


if not "%RC%"=="0" (

    echo.
    echo [FAILED] Set-FakeDellHardware.ps1
    echo.

    echo [FAILED] Set-FakeDellHardware.ps1 >> "%LOG%"

    goto :FAILED
)


rem ============================================================
rem VERIFY FAKE IDENTITY BEFORE CONTINUING
rem ============================================================

echo.
echo Verifying simulated Dell identity...
echo.


powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -Command ^
    "$h = Get-Content '%HARDWAREJSON%' -Raw | ConvertFrom-Json; Write-Host ('Manufacturer : ' + $h.Computer.Manufacturer); Write-Host ('Model        : ' + $h.Computer.Model)" ^
    >> "%LOG%" 2>&1


powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -Command ^
    "$h = Get-Content '%HARDWAREJSON%' -Raw | ConvertFrom-Json; Write-Host ('Manufacturer : ' + $h.Computer.Manufacturer); Write-Host ('Model        : ' + $h.Computer.Model)"


rem ============================================================
rem SAFETY CHECK
rem ============================================================

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -Command ^
    "$h = Get-Content '%HARDWAREJSON%' -Raw | ConvertFrom-Json; if ($h.Computer.Manufacturer -notmatch 'Dell') { exit 1 } else { exit 0 }"


if not "%errorlevel%"=="0" (

    echo.
    echo [ERROR] Fake Dell identity verification failed.
    echo Stage 02 will NOT be started.
    echo.

    echo [ERROR] Fake Dell identity verification failed. >> "%LOG%"

    goto :FAILED
)


echo.
echo Fake Dell identity verified successfully.
echo.


rem ============================================================
rem STEP 3
rem INSTALL OEM UPDATE TOOL
rem ============================================================

echo.
echo ============================================================
echo STEP 3 OF 5
echo INSTALL OEM UPDATE TOOL
echo ============================================================
echo.

(
    echo.
    echo ============================================================
    echo STEP 3 OF 5
    echo INSTALL OEM UPDATE TOOL
    echo ============================================================
) >> "%LOG%"


powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%INSTALLTOOL%" ^
    >> "%LOG%" 2>&1


set "RC=%errorlevel%"


echo Exit code: %RC%
echo Exit code: %RC% >> "%LOG%"


if "%RC%"=="3010" (

    echo.
    echo [WARNING] Stage requested a restart.
    echo Deployment will continue to the next stage.
    echo.

    echo [WARNING] Restart requested. >> "%LOG%"

    set "RESTART_REQUIRED=1"

    goto :STEP4
)


if not "%RC%"=="0" (

    echo.
    echo [FAILED] 02-Install-OEM-Update-Tool.ps1
    echo.

    echo [FAILED] 02-Install-OEM-Update-Tool.ps1 >> "%LOG%"

    goto :FAILED
)


:STEP4

rem ============================================================
rem VERIFY FAKE IDENTITY AGAIN
rem ============================================================

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -Command ^
    "$h = Get-Content '%HARDWAREJSON%' -Raw | ConvertFrom-Json; if ($h.Computer.Manufacturer -notmatch 'Dell') { exit 1 } else { exit 0 }"


if not "%errorlevel%"=="0" (

    echo.
    echo [ERROR] Fake Dell identity disappeared before Stage 03.
    echo.

    echo [ERROR] Fake Dell identity disappeared before Stage 03. >> "%LOG%"

    goto :FAILED
)


rem ============================================================
rem STEP 4
rem UPDATE DRIVERS
rem ============================================================

echo.
echo ============================================================
echo STEP 4 OF 5
echo UPDATE DRIVERS
echo ============================================================
echo.

echo IMPORTANT:
echo This is now running the REAL Stage 03 script.
echo Dell Command Update may reject the physical Lenovo computer.
echo Your script may then use its configured fallback method.
echo.

(
    echo.
    echo ============================================================
    echo STEP 4 OF 5
    echo UPDATE DRIVERS
    echo ============================================================
) >> "%LOG%"


powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%UPDATEDRIVERS%" ^
    >> "%LOG%" 2>&1


set "RC=%errorlevel%"


echo Exit code: %RC%
echo Exit code: %RC% >> "%LOG%"


if "%RC%"=="3010" (

    echo.
    echo [WARNING] Driver update requested a restart.
    echo Verification will still run before reboot.
    echo.

    echo [WARNING] Driver update requested restart. >> "%LOG%"

    set "RESTART_REQUIRED=1"

    goto :STEP5
)


if not "%RC%"=="0" (

    echo.
    echo [FAILED] 03-Update-Drivers.ps1
    echo.

    echo [FAILED] 03-Update-Drivers.ps1 >> "%LOG%"

    goto :FAILED
)


:STEP5

rem ============================================================
rem STEP 5
rem VERIFY DRIVERS
rem ============================================================

echo.
echo ============================================================
echo STEP 5 OF 5
echo VERIFY DRIVERS
echo ============================================================
echo.

(
    echo.
    echo ============================================================
    echo STEP 5 OF 5
    echo VERIFY DRIVERS
    echo ============================================================
) >> "%LOG%"


powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%VERIFYDRIVERS%" ^
    >> "%LOG%" 2>&1


set "RC=%errorlevel%"


echo Exit code: %RC%
echo Exit code: %RC% >> "%LOG%"


if "%RC%"=="3010" (

    set "RESTART_REQUIRED=1"

    goto :SUCCESS
)


if not "%RC%"=="0" (

    echo.
    echo [FAILED] 04-Verify-Drivers.ps1
    echo.

    echo [FAILED] 04-Verify-Drivers.ps1 >> "%LOG%"

    goto :FAILED
)


rem ============================================================
rem SUCCESS
rem ============================================================

:SUCCESS

echo.
echo ============================================================
echo ITINO FAKE DELL TEST COMPLETE
echo ============================================================
echo.


(
    echo.
    echo ============================================================
    echo TEST COMPLETE
    echo ============================================================
    echo End Time : %date% %time%
) >> "%LOG%"


if "%RESTART_REQUIRED%"=="1" (

    echo Result:
    echo   SUCCESS - RESTART REQUIRED
    echo.
    echo One or more deployment stages requested a reboot.
    echo.
    echo Restart the computer before evaluating the final
    echo post-reboot driver state.
    echo.

    echo Result: SUCCESS - RESTART REQUIRED >> "%LOG%"

) else (

    echo Result:
    echo   SUCCESS
    echo.
    echo No deployment stage requested a restart.
    echo.

    echo Result: SUCCESS >> "%LOG%"
)


echo Log saved to:
echo   %LOG%
echo.

echo The physical Lenovo manufacturer information was NOT changed.
echo Only the ITINO HardwareInformation.json file was modified.
echo.

pause


if "%RESTART_REQUIRED%"=="1" (
    exit /b 3010
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
echo Check the log:
echo.
echo   %LOG%
echo.


(
    echo.
    echo ============================================================
    echo TEST FAILED
    echo ============================================================
    echo End Time : %date% %time%
) >> "%LOG%"


pause

exit /b 1