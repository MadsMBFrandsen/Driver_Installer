# Universal Driver Installer

Universal Driver Installer automates driver detection and installation on
supported Dell, HP, and Lenovo computers.

The application detects the computer manufacturer, uses the manufacturer's
official update tools, and can automatically continue after a restart.

## Important information

- Save and close any open work before starting.
- The computer must have an internet connection.
- Administrator rights are required. Windows will display a UAC prompt.
- If a driver requires a restart, the computer may restart automatically after
  a 30-second warning.
- Only run this application on Windows computers where you are authorized to
  install or update drivers.

## Quick start from CMD

The repository must be public for this command to download it without a GitHub
login.

Open **Command Prompt (CMD)**, paste the complete command below, and press
Enter:

```cmd
powershell -c "irm https://raw.githubusercontent.com/MadsMBFrandsen/Driver_Installer/main/Install.ps1|iex"
```

The command:

1. Downloads and runs the repository's public `Install.ps1` bootstrap script.
2. Downloads the latest project version from the GitHub `main` branch.
3. Extracts the project into the current user's local application data folder.
4. Starts `Run-DriverDeployment-AutoResume.bat` and requests administrator
   rights through Windows UAC.
5. Creates a temporary scheduled task only when the deployment must continue
   after a restart.
6. Removes the downloaded bootstrap installation after the deployment finishes
   successfully.

Review [`Install.ps1`](Install.ps1) before running the command if you want to
inspect exactly what it downloads and executes.

The project is installed in:

```text
%LOCALAPPDATA%\UniversalDriverInstaller\Driver_Installer-main
```

## Start an incomplete or failed deployment again

While the downloaded package is still present, it can be started again with:

```cmd
call "%LOCALAPPDATA%\UniversalDriverInstaller\Driver_Installer-main\Run-DriverDeployment-AutoResume.bat"
```

After a successful deployment, the bootstrap installation is removed
automatically. Run the quick-start command again whenever you want to download
and start the latest version.

After a required restart, the scheduled task runs as `SYSTEM` in the
background. No console window is displayed. By default, the resumed deployment
starts 60 seconds after Windows startup.

## Deployment process

The application performs the following main steps:

1. Checks Windows, administrator rights, available disk space, and other
   prerequisites.
2. Detects the computer manufacturer and hardware.
3. Installs or prepares the appropriate manufacturer update tool.
4. Searches for and installs applicable driver updates.
5. Verifies the result and saves reports and log files.
6. Restarts and continues automatically when an update requires it.

## Logs and troubleshooting

Copied log files can be found in the project's `Logs` folder. During a
deployment, working data and failure reports may also be available under:

```text
C:\ProgramData\UniversalDriverInstaller
```

Logs published before final cleanup remain available under:

```text
C:\Windows\Temp\UniversalDriverInstaller-Deployment\Driver
```

Bootstrap cleanup activity is recorded in:

```text
C:\Windows\Temp\UniversalDriverInstaller-Cleanup.log
```

Working data may be removed automatically after a successful deployment. On a
failure, diagnostic information is normally preserved for troubleshooting.


