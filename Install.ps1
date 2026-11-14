$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw 'Universal Driver Installer requires Windows PowerShell 5.1 or later.'
}

$RepositoryArchiveUrl =
    'https://github.com/MadsMBFrandsen/Driver_Installer/archive/refs/heads/main.zip'

$InstallRoot =
    Join-Path `
        $env:LOCALAPPDATA `
        'UniversalDriverInstaller'

$ArchivePath =
    Join-Path `
        $env:TEMP `
        'UniversalDriverInstaller-main.zip'

$ApplicationRoot =
    Join-Path `
        $InstallRoot `
        'Driver_Installer-main'

$AutoResumePath =
    Join-Path `
        $ApplicationRoot `
        'Run-DriverDeployment-AutoResume.ps1'

$CleanupMarkerPath =
    Join-Path `
        $ApplicationRoot `
        '.universal-driver-installer-install-root'

try {

    New-Item `
        -ItemType Directory `
        -Path $InstallRoot `
        -Force |
        Out-Null

    Write-Host 'Downloading Universal Driver Installer...'

    Invoke-WebRequest `
        -Uri $RepositoryArchiveUrl `
        -UseBasicParsing `
        -OutFile $ArchivePath

    Write-Host 'Extracting Universal Driver Installer...'

    Expand-Archive `
        -LiteralPath $ArchivePath `
        -DestinationPath $InstallRoot `
        -Force

    if (-not (
        Test-Path `
            -LiteralPath $AutoResumePath `
            -PathType Leaf
    )) {
        throw "The auto-resume script was not found after extraction: $AutoResumePath"
    }

    # The auto-resume wrapper only removes installations carrying this marker.
    # A normal Git clone, USB copy, or manually extracted package is preserved.
    Set-Content `
        -LiteralPath $CleanupMarkerPath `
        -Value $InstallRoot `
        -Encoding UTF8 `
        -Force

    $WindowsPowerShellPath =
        Join-Path `
            $env:SystemRoot `
            'System32\WindowsPowerShell\v1.0\powershell.exe'

    $PowerShellArguments =
        (
            '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' +
            $AutoResumePath +
            '"'
        )

    Write-Host 'Requesting administrator rights...'

    $DeploymentProcess =
        Start-Process `
            -FilePath $WindowsPowerShellPath `
            -ArgumentList $PowerShellArguments `
            -Verb RunAs `
            -Wait `
            -PassThru `
            -ErrorAction Stop

    $DeploymentExitCode =
        [int]$DeploymentProcess.ExitCode

    switch ($DeploymentExitCode) {

        0 {
            Write-Host 'Universal Driver Installer completed successfully.'
        }

        3010 {
            Write-Host 'Universal Driver Installer scheduled a restart.'
        }

        1618 {
            throw 'Another Universal Driver Installer deployment is already running.'
        }

        default {
            throw "Universal Driver Installer failed with exit code $DeploymentExitCode."
        }
    }
}
finally {

    Remove-Item `
        -LiteralPath $ArchivePath `
        -Force `
        -ErrorAction SilentlyContinue
}
