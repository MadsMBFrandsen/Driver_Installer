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
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$base=Join-Path $env:LOCALAPPDATA 'UniversalDriverInstaller'; $zip=Join-Path $env:TEMP 'UniversalDriverInstaller-main.zip'; New-Item -ItemType Directory -Path $base -Force | Out-Null; Invoke-WebRequest 'https://github.com/MadsMBFrandsen/Driver_Installer/archive/refs/heads/main.zip' -UseBasicParsing -OutFile $zip; Expand-Archive -LiteralPath $zip -DestinationPath $base -Force; & (Join-Path $base 'Driver_Installer-main\Run-DriverDeployment-AutoResume.bat')"
```

The command:

1. Downloads the latest version from the GitHub `main` branch.
2. Extracts the project into the current user's local application data folder.
3. Starts `Run-DriverDeployment-AutoResume.bat`.
4. Requests administrator rights through Windows UAC.
5. Creates a temporary scheduled task only when the deployment must continue
   after a restart.

The project is installed in:

```text
%LOCALAPPDATA%\UniversalDriverInstaller\Driver_Installer-main
```

## Start the application again

After the project has been downloaded, it can be started again with:

```cmd
call "%LOCALAPPDATA%\UniversalDriverInstaller\Driver_Installer-main\Run-DriverDeployment-AutoResume.bat"
```

Run the quick-start command again to download the latest version and overwrite
the local project files.

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

Working data may be removed automatically after a successful deployment. On a
failure, diagnostic information is normally preserved for troubleshooting.

## Private repositories

If the repository is made private later, the quick-start command will not work
without authentication. In that case, use GitHub CLI and run `gh auth login`
before cloning the repository.

## Public repository security

A public repository can be viewed and downloaded by anyone. Never commit
access tokens, passwords, private keys, or other secrets to the project files
or Git history.
