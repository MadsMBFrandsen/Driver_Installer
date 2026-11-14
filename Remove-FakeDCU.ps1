<#
.SYNOPSIS
    Removes the Universal Driver Installer fake Dell Command Update lab executable.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$FakeDCU =
    'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'

$StateDirectory =
    'C:\ProgramData\UniversalDriverInstaller\FakeDCU'

if (Test-Path -LiteralPath $FakeDCU) {
    $ProductName =
        $null

    try {
        $ProductName =
            (
                [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
                    $FakeDCU
                )
            ).ProductName
    }
    catch {
    }

    if (
        [string]::IsNullOrWhiteSpace(
            [string]$ProductName
        ) -or
        $ProductName -notmatch '^Universal Driver Installer Fake Dell Command Update'
    ) {
        throw (
            'The dcu-cli.exe at the normal Dell path does not identify ' +
            'itself as the Universal Driver Installer fake DCU. It will not be removed.'
        )
    }

    Remove-Item `
        -LiteralPath $FakeDCU `
        -Force

    Write-Host "Removed fake DCU: $FakeDCU"
}
else {
    Write-Host 'Fake DCU executable was not present.'
}

if (Test-Path -LiteralPath $StateDirectory) {
    Remove-Item `
        -LiteralPath $StateDirectory `
        -Recurse `
        -Force

    Write-Host "Removed fake DCU state: $StateDirectory"
}

[Environment]::SetEnvironmentVariable(
    'UNIVERSAL_DRIVER_INSTALLER_FAKE_DCU_SCENARIO',
    $null,
    'Machine'
)

Remove-Item `
    Env:\UNIVERSAL_DRIVER_INSTALLER_FAKE_DCU_SCENARIO `
    -ErrorAction SilentlyContinue

Write-Host 'Removed UNIVERSAL_DRIVER_INSTALLER_FAKE_DCU_SCENARIO machine environment variable.'
exit 0
