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

$LauncherPath =
    Join-Path `
        $ApplicationRoot `
        'Run-DriverDeployment-AutoResume.bat'

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
            -LiteralPath $LauncherPath `
            -PathType Leaf
    )) {
        throw "The launcher was not found after extraction: $LauncherPath"
    }

    # The auto-resume wrapper only removes installations carrying this marker.
    # A normal Git clone, USB copy, or manually extracted package is preserved.
    Set-Content `
        -LiteralPath $CleanupMarkerPath `
        -Value $InstallRoot `
        -Encoding UTF8 `
        -Force

    Write-Host 'Starting Universal Driver Installer...'

    & $LauncherPath
}
finally {

    Remove-Item `
        -LiteralPath $ArchivePath `
        -Force `
        -ErrorAction SilentlyContinue
}
