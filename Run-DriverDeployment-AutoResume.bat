@echo off
setlocal EnableExtensions

title Universal Driver Installer Auto Resume

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Run-DriverDeployment-AutoResume.ps1"

echo.
echo ============================================================
echo Universal Driver Installer Auto Resume
echo ============================================================
echo.

if not exist "%PS_SCRIPT%" (
    echo ERROR: PowerShell launcher was not found:
    echo %PS_SCRIPT%
    echo.
    pause
    exit /b 1
)

rem ============================================================
rem CHECK ADMINISTRATOR
rem ============================================================

net session >nul 2>&1

if %errorlevel% neq 0 (
    echo Administrator rights are required.
    echo A UAC prompt will now appear.
    echo.

    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass ^
        -Command "$a='-NoLogo -NoProfile -ExecutionPolicy Bypass -File '+[char]34+$env:PS_SCRIPT+[char]34; $p=Start-Process -FilePath ($env:SystemRoot+'\System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $a -Verb RunAs -Wait -PassThru; exit $p.ExitCode"

    exit /b %errorlevel%
)

rem ============================================================
rem RUN POWERSHELL LAUNCHER
rem ============================================================

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass ^
    -File "%PS_SCRIPT%"

set "EXITCODE=%ERRORLEVEL%"

echo.
echo ============================================================
echo Universal Driver Installer Launcher Finished
echo ============================================================
echo.
echo Exit Code: %EXITCODE%
echo.

if "%EXITCODE%"=="3010" (
    echo Restart required.
    echo If automatic restart is enabled in the PowerShell launcher,
    echo Windows will restart automatically.
    echo.
)

if "%EXITCODE%"=="1618" (
    echo Another Universal Driver Installer is already running.
    echo.
)

exit /b %EXITCODE%
