@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Universal Driver Installer - Driver Rollback

rem ============================================================
rem Universal Driver Installer - Driver Rollback Launcher
rem
rem Place this BAT in the same folder as:
rem     05-Rollback-Drivers.ps1
rem
rem Options:
rem   1 = Preview changed drivers (safe / no changes)
rem   2 = Roll back one DeviceID
rem   3 = Roll back all changed drivers
rem   4 = Exit
rem ============================================================

set "SCRIPT=%~dp005-Rollback-Drivers.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo ============================================================
    echo ERROR
    echo ============================================================
    echo Could not find:
    echo "%SCRIPT%"
    echo.
    echo Put this BAT in the same folder as:
    echo 05-Rollback-Drivers.ps1
    echo.
    pause
    exit /b 1
)

rem ============================================================
rem ELEVATE THIS BAT IF NEEDED
rem ============================================================

net session >nul 2>&1

if not "%errorlevel%"=="0" (
    echo.
    echo ============================================================
    echo Administrator rights are required
    echo ============================================================
    echo.
    echo A UAC prompt will now appear.
    echo.

    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
        "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c """"%~f0"""" elevated' -Verb RunAs"

    exit /b
)

:MENU
cls
echo ============================================================
echo Universal Driver Installer - Driver Rollback
echo ============================================================
echo.
echo Script:
echo %SCRIPT%
echo.
echo [1] Preview changed drivers
echo     Safe - makes NO driver changes.
echo.
echo [2] Roll back ONE changed driver
echo     Uses the DeviceID shown by Preview.
echo.
echo [3] Roll back ALL changed drivers
echo     Requires explicit confirmation.
echo.
echo [4] Exit
echo.
echo ============================================================

set "CHOICE="
set /p "CHOICE=Choose 1-4: "

if "%CHOICE%"=="1" goto PREVIEW
if "%CHOICE%"=="2" goto SINGLE
if "%CHOICE%"=="3" goto ALL
if "%CHOICE%"=="4" goto END

echo.
echo Invalid selection.
timeout /t 2 /nobreak >nul
goto MENU


:PREVIEW
cls
echo ============================================================
echo DRIVER ROLLBACK - PREVIEW
echo ============================================================
echo.
echo No drivers will be changed.
echo.

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%SCRIPT%"

set "RC=%errorlevel%"

echo.
echo ============================================================
echo Preview Finished
echo ============================================================
echo Exit Code: %RC%
echo.
pause
goto MENU


:SINGLE
cls
echo ============================================================
echo ROLL BACK ONE DRIVER
echo ============================================================
echo.
echo First run Preview if you do not already have the DeviceID.
echo.
echo Example:
echo PCI\VEN_8086^&DEV_1234^&SUBSYS_...
echo.

set "UNIVERSAL_DRIVER_INSTALLER_ROLLBACK_DEVICE_ID="
set /p "UNIVERSAL_DRIVER_INSTALLER_ROLLBACK_DEVICE_ID=Paste the exact DeviceID: "

if not defined UNIVERSAL_DRIVER_INSTALLER_ROLLBACK_DEVICE_ID (
    echo.
    echo No DeviceID entered.
    pause
    goto MENU
)

echo.
echo Selected DeviceID:
echo %UNIVERSAL_DRIVER_INSTALLER_ROLLBACK_DEVICE_ID%
echo.
echo WARNING:
echo This will attempt to replace the current driver with the
echo backed-up before-update driver.
echo.
set "CONFIRM="
set /p "CONFIRM=Type YES to continue: "

if /I not "%CONFIRM%"=="YES" (
    echo.
    echo Rollback cancelled.
    pause
    goto MENU
)

echo.
echo Starting rollback...
echo.

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -Command ^
    "& '%SCRIPT%' -DeviceID $env:UNIVERSAL_DRIVER_INSTALLER_ROLLBACK_DEVICE_ID -Execute; exit $LASTEXITCODE"

set "RC=%errorlevel%"

echo.
echo ============================================================
echo Rollback Finished
echo ============================================================
echo Exit Code: %RC%
echo.

if "%RC%"=="0" (
    echo Result: Rollback completed successfully.
) else if "%RC%"=="194" (
    echo Result: Restart required.
    echo NOTE: Windows CMD may display PowerShell exit 3010 as 194.
) else if "%RC%"=="3010" (
    echo Result: Restart required.
) else (
    echo Result: Rollback reported an error.
)

echo.
pause
goto MENU


:ALL
cls
echo ============================================================
echo ROLL BACK ALL CHANGED DRIVERS
echo ============================================================
echo.
echo WARNING:
echo This attempts rollback for every changed driver detected by
echo the before/after snapshots.
echo.
echo Use Preview first and only use this when you deliberately
echo want to undo the whole driver deployment.
echo.
set "CONFIRMALL="
set /p "CONFIRMALL=Type ROLLBACK ALL to continue: "

if /I not "%CONFIRMALL%"=="ROLLBACK ALL" (
    echo.
    echo Rollback cancelled.
    pause
    goto MENU
)

echo.
echo Starting rollback of all changed drivers...
echo.

powershell.exe ^
    -NoLogo ^
    -NoProfile ^
    -ExecutionPolicy Bypass ^
    -Command ^
    "& '%SCRIPT%' -AllChanged -Execute -ConfirmAllChanged; exit $LASTEXITCODE"

set "RC=%errorlevel%"

echo.
echo ============================================================
echo Rollback Finished
echo ============================================================
echo Exit Code: %RC%
echo.

if "%RC%"=="0" (
    echo Result: Rollback completed successfully.
) else if "%RC%"=="194" (
    echo Result: Restart required.
    echo NOTE: Windows CMD may display PowerShell exit 3010 as 194.
) else if "%RC%"=="3010" (
    echo Result: Restart required.
) else (
    echo Result: One or more rollbacks failed.
)

echo.
pause
goto MENU


:END
endlocal
exit /b 0
