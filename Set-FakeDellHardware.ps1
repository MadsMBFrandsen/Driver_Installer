<#
.SYNOPSIS
    Makes the Universal Driver Installer scripts treat the current PC
    as a Dell test machine.

.DESCRIPTION
    This DOES NOT modify BIOS, SMBIOS, WMI or the real manufacturer.

    It only modifies:

    C:\ProgramData\UniversalDriverInstaller\DriverDeployment\HardwareInformation.json

    The original JSON file is backed up automatically.

.EXAMPLE
    .\Set-FakeDellHardware.ps1

.EXAMPLE
    .\Set-FakeDellHardware.ps1 -Model "Latitude 5450"

.EXAMPLE
    .\Set-FakeDellHardware.ps1 -Restore
#>

[CmdletBinding()]
param (

    [string]$Manufacturer = 'Dell Inc.',

    [string]$Model = 'Latitude 5450',

    [switch]$Restore
)


$ErrorActionPreference = 'Stop'


# ============================================================
# PATHS
# ============================================================

$BasePath =
    'C:\ProgramData\UniversalDriverInstaller\DriverDeployment'


$HardwareFile =
    Join-Path `
        $BasePath `
        'HardwareInformation.json'


$BackupFile =
    Join-Path `
        $BasePath `
        'HardwareInformation.REAL.json'


# ============================================================
# RESTORE ORIGINAL HARDWARE INFORMATION
# ============================================================

if ($Restore) {

    Write-Host ''
    Write-Host '==============================================='
    Write-Host 'RESTORE REAL HARDWARE INFORMATION'
    Write-Host '==============================================='
    Write-Host ''

    if (-not (
        Test-Path `
            -LiteralPath $BackupFile `
            -PathType Leaf
    )) {

        throw (
            "Backup hardware file does not exist: $BackupFile"
        )
    }


    Copy-Item `
        -LiteralPath $BackupFile `
        -Destination $HardwareFile `
        -Force


    Write-Host 'Real hardware information restored.'
    Write-Host ''
    Write-Host "File:"
    Write-Host "  $HardwareFile"
    Write-Host ''

    exit 0
}


# ============================================================
# VERIFY HARDWARE FILE EXISTS
# ============================================================

if (-not (
    Test-Path `
        -LiteralPath $HardwareFile `
        -PathType Leaf
)) {

    throw @"
HardwareInformation.json was not found.

Run:

    01-Gather-Hardware.ps1

first.

Expected file:

    $HardwareFile
"@
}


# ============================================================
# READ REAL HARDWARE INFORMATION
# ============================================================

Write-Host ''
Write-Host '==============================================='
Write-Host 'Universal Driver Installer FAKE DELL HARDWARE TEST MODE'
Write-Host '==============================================='
Write-Host ''


$Hardware =
    Get-Content `
        -LiteralPath $HardwareFile `
        -Raw `
        -ErrorAction Stop |
    ConvertFrom-Json `
        -ErrorAction Stop


if (-not $Hardware.Computer) {

    throw (
        'Computer information was not found inside HardwareInformation.json.'
    )
}


$OriginalManufacturer =
    [string]$Hardware.Computer.Manufacturer


$OriginalModel =
    [string]$Hardware.Computer.Model


Write-Host 'Real hardware detected:'
Write-Host ''
Write-Host "  Manufacturer : $OriginalManufacturer"
Write-Host "  Model        : $OriginalModel"
Write-Host ''


# ============================================================
# BACKUP ORIGINAL FILE
# ============================================================

if (-not (
    Test-Path `
        -LiteralPath $BackupFile `
        -PathType Leaf
)) {

    Copy-Item `
        -LiteralPath $HardwareFile `
        -Destination $BackupFile `
        -Force


    Write-Host 'Original hardware information backed up:'
    Write-Host ''
    Write-Host "  $BackupFile"
    Write-Host ''
}
else {

    Write-Host 'Original backup already exists.'
    Write-Host 'Existing backup will NOT be overwritten.'
    Write-Host ''
}


# ============================================================
# FAKE DELL IDENTITY
# ============================================================

$Hardware.Computer.Manufacturer =
    $Manufacturer


$Hardware.Computer.Model =
    $Model


# BIOS manufacturer is changed only inside the JSON report.
# The actual Lenovo BIOS is NOT modified.

if ($Hardware.BIOS) {

    $Hardware.BIOS.Manufacturer =
        'Dell Inc.'
}


# ============================================================
# ADD TEST MODE INFORMATION
# ============================================================

$TestInformation =
    [PSCustomObject]@{

        Enabled =
            $true

        TestType =
            'Dell Hardware Simulation'

        GeneratedAt =
            Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

        OriginalManufacturer =
            $OriginalManufacturer

        OriginalModel =
            $OriginalModel

        SimulatedManufacturer =
            $Manufacturer

        SimulatedModel =
            $Model

        Warning =
            'Simulation only. Physical computer hardware is unchanged.'
    }


if (
    $Hardware.PSObject.Properties.Name -contains
    'LabSimulation'
) {

    $Hardware.LabSimulation =
        $TestInformation
}
else {

    $Hardware |
        Add-Member `
            -MemberType NoteProperty `
            -Name 'LabSimulation' `
            -Value $TestInformation
}


# ============================================================
# SAVE MODIFIED HARDWARE INFORMATION
# ============================================================

$Hardware |
    ConvertTo-Json `
        -Depth 10 |
    Set-Content `
        -LiteralPath $HardwareFile `
        -Encoding UTF8


# ============================================================
# VERIFY
# ============================================================

$Verify =
    Get-Content `
        -LiteralPath $HardwareFile `
        -Raw |
    ConvertFrom-Json


Write-Host '==============================================='
Write-Host 'FAKE DELL HARDWARE ENABLED'
Write-Host '==============================================='
Write-Host ''

Write-Host 'Universal Driver Installer will now see:'
Write-Host ''

Write-Host (
    "  Manufacturer : " +
    $Verify.Computer.Manufacturer
)

Write-Host (
    "  Model        : " +
    $Verify.Computer.Model
)

Write-Host ''

Write-Host 'Actual physical computer remains:'
Write-Host ''

Write-Host "  Manufacturer : $OriginalManufacturer"
Write-Host "  Model        : $OriginalModel"

Write-Host ''
Write-Host 'Hardware JSON:'
Write-Host "  $HardwareFile"

Write-Host ''
Write-Host 'Original backup:'
Write-Host "  $BackupFile"

Write-Host ''
Write-Host '==============================================='
Write-Host 'TEST MODE READY'
Write-Host '==============================================='
Write-Host ''

exit 0