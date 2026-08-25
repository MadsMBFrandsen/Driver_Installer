<#
.SYNOPSIS
    ITINO manual driver rollback utility with post-rollback verification.

.DESCRIPTION
    Uses the before/after driver snapshots created by Phase 5
    together with the exported before-update driver packages
    created by Phase 7.

    SAFETY:
      - Preview mode is the default.
      - Nothing is changed unless -Execute is supplied.
      - Rollback is manual and targeted.
      - After rollback, Plug and Play is rescanned and the active
        driver version and device health are verified.
      - Verification is written to RollbackVerification.json.
      - Rollback blocks package removal when the current INF is
        shared by multiple devices.
      - Exact exported INF paths come from RollbackManifest.json;
        the script never guesses by taking the first INF file.
      - This script is NOT called by the normal deployment
        controller.

.EXAMPLE
    .\05-Rollback-Drivers.ps1

    Shows changed driver candidates only.

.EXAMPLE
    .\05-Rollback-Drivers.ps1 -DeviceID 'PCI\VEN_8086...' -Execute

    Attempts rollback for one specific device.

.EXAMPLE
    .\05-Rollback-Drivers.ps1 -AllChanged -Execute

    Attempts rollback for every changed driver. Use only when
    explicitly intended by a technician.
#>

[CmdletBinding(DefaultParameterSetName = 'Preview')]
param(
    [Parameter(ParameterSetName = 'Device')]
    [string]$DeviceID,

    [Parameter(ParameterSetName = 'All')]
    [switch]$AllChanged,

    [switch]$Execute,

    [switch]$ConfirmAllChanged
)

$ErrorActionPreference =
    'Stop'


$BasePath =
    'C:\ProgramData\Itino\DriverDeployment'


$BeforeSnapshotFile =
    Join-Path `
        $BasePath `
        'DriverSnapshot-Before.json'


$AfterSnapshotFile =
    Join-Path `
        $BasePath `
        'DriverSnapshot-After.json'


$RollbackRoot =
    'C:\ProgramData\Itino\DriverRollback'


$LatestPointerFile =
    Join-Path `
        $RollbackRoot `
        (
            "$($env:COMPUTERNAME)-Latest.txt"
        )


$RollbackBackupPath =
    $null


$RollbackManifestFile =
    $null


$RollbackLogFile =
    Join-Path `
        $BasePath `
        'DriverRollback.log'



$RollbackVerificationFile =
    Join-Path `
        $BasePath `
        'RollbackVerification.json'


function Write-RollbackLog {

    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet(
            'INFO',
            'WARNING',
            'ERROR',
            'SUCCESS'
        )]
        [string]$Level = 'INFO'
    )


    $Line =
        "[{0}] [{1}] {2}" -f `
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
            $Level,
            $Message


    Write-Host $Line


    try {

        Add-Content `
            -LiteralPath $RollbackLogFile `
            -Value $Line `
            -Encoding UTF8
    }
    catch {

    }
}


function Test-IsAdministrator {

    $Identity =
        [Security.Principal.WindowsIdentity]::GetCurrent()


    $Principal =
        New-Object `
            Security.Principal.WindowsPrincipal(
                $Identity
            )


    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}



function Resolve-RollbackArchive {

    if (-not (
        Test-Path -LiteralPath $LatestPointerFile
    )) {

        throw (
            "Latest rollback pointer was not found: $LatestPointerFile"
        )
    }


    $ArchivePath =
        (
            Get-Content `
                -LiteralPath $LatestPointerFile `
                -Raw `
                -ErrorAction Stop
        ).Trim()


    if (
        [string]::IsNullOrWhiteSpace(
            $ArchivePath
        ) -or
        -not (
            Test-Path -LiteralPath $ArchivePath
        )
    ) {

        throw (
            "Rollback archive referenced by '$LatestPointerFile' does not exist: $ArchivePath"
        )
    }


    return $ArchivePath
}


function Get-DevicesUsingPublishedInf {

    param(
        [Parameter(Mandatory)]
        [string]$PublishedInf
    )


    return @(
        Get-CimInstance `
            -ClassName Win32_PnPSignedDriver `
            -ErrorAction SilentlyContinue |
        Where-Object {

            [string]$_.InfName -eq
                [string]$PublishedInf
        } |
        ForEach-Object {

            [pscustomobject]@{

                DeviceID =
                    [string]$_.DeviceID

                DeviceName =
                    [string]$_.DeviceName

                DriverVersion =
                    [string]$_.DriverVersion

                InfName =
                    [string]$_.InfName
            }
        }
    )
}


function Read-JsonFile {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )


    if (-not (
        Test-Path -LiteralPath $Path
    )) {

        throw "Required file not found: $Path"
    }


    return (
        Get-Content `
            -LiteralPath $Path `
            -Raw |
        ConvertFrom-Json
    )
}


function Get-DriverChanges {

    param(
        [object[]]$Before,

        [object[]]$After
    )


    $BeforeByDeviceID =
        @{}

    $AfterByDeviceID =
        @{}


    foreach (
        $Driver in @($Before)
    ) {

        if (
            -not [string]::IsNullOrWhiteSpace(
                [string]$Driver.DeviceID
            )
        ) {

            $BeforeByDeviceID[
                ([string]$Driver.DeviceID).ToUpperInvariant()
            ] =
                $Driver
        }
    }


    foreach (
        $Driver in @($After)
    ) {

        if (
            -not [string]::IsNullOrWhiteSpace(
                [string]$Driver.DeviceID
            )
        ) {

            $AfterByDeviceID[
                ([string]$Driver.DeviceID).ToUpperInvariant()
            ] =
                $Driver
        }
    }


    $Changed =
        @()


    foreach (
        $Key in $AfterByDeviceID.Keys
    ) {

        if (-not $BeforeByDeviceID.ContainsKey($Key)) {

            continue
        }


        $BeforeDriver =
            $BeforeByDeviceID[$Key]


        $AfterDriver =
            $AfterByDeviceID[$Key]


        if (
            [string]$BeforeDriver.DriverVersion -ne
            [string]$AfterDriver.DriverVersion -or

            [string]$BeforeDriver.InfName -ne
            [string]$AfterDriver.InfName
        ) {

            $Changed +=
                [pscustomobject]@{

                    DeviceID =
                        $AfterDriver.DeviceID

                    DeviceName =
                        $AfterDriver.DeviceName

                    BeforeVersion =
                        [string]$BeforeDriver.DriverVersion

                    AfterVersion =
                        [string]$AfterDriver.DriverVersion

                    BeforeInf =
                        [string]$BeforeDriver.InfName

                    AfterInf =
                        [string]$AfterDriver.InfName

                    BeforeProvider =
                        [string]$BeforeDriver.DriverProviderName

                    AfterProvider =
                        [string]$AfterDriver.DriverProviderName
                }
        }
    }


    return @(
        $Changed
    )
}


function Find-BackupInfFile {

    param(
        [Parameter(Mandatory)]
        [string]$PublishedInfName,

        [Parameter(Mandatory)]
        $Manifest
    )


    $Package =
        @(
            $Manifest.Packages |
            Where-Object {

                [string]$_.PublishedInf -eq
                    [string]$PublishedInfName -and
                $_.Success
            }
        ) |
        Select-Object -First 1


    if (-not $Package) {

        return $null
    }


    $ExportedInf =
        [string]$Package.ExportedInf


    if (
        [string]::IsNullOrWhiteSpace(
            $ExportedInf
        ) -or
        -not (
            Test-Path -LiteralPath $ExportedInf
        )
    ) {

        return $null
    }


    return $ExportedInf
}


function Invoke-PnPRescan {

    Write-RollbackLog -Message (
        'Requesting Plug and Play rescan.'
    )


    $Output =
        & pnputil.exe `
            /scan-devices `
            2>&1


    $ExitCode =
        $LASTEXITCODE


    foreach (
        $Line in @($Output)
    ) {

        Write-RollbackLog -Message (
            "pnputil scan: $Line"
        )
    }


    return [pscustomobject]@{

        ExitCode =
            $ExitCode

        Success =
            ($ExitCode -eq 0)

        Output =
            @(
                $Output
            )
    }
}


function Get-CurrentDriverState {

    param(
        [Parameter(Mandatory)]
        [string]$DeviceID
    )


    $Driver =
        Get-CimInstance `
            -ClassName Win32_PnPSignedDriver `
            -ErrorAction SilentlyContinue |
        Where-Object {

            [string]$_.DeviceID -eq
                [string]$DeviceID
        } |
        Select-Object -First 1


    if (-not $Driver) {

        return $null
    }


    return [pscustomobject]@{

        DeviceID =
            [string]$Driver.DeviceID

        DeviceName =
            [string]$Driver.DeviceName

        DriverVersion =
            [string]$Driver.DriverVersion

        DriverProviderName =
            [string]$Driver.DriverProviderName

        InfName =
            [string]$Driver.InfName

        DriverDate =
            $Driver.DriverDate
    }
}


function Get-DeviceErrorState {

    param(
        [Parameter(Mandatory)]
        [string]$DeviceID
    )


    $Device =
        Get-CimInstance `
            -ClassName Win32_PnPEntity `
            -ErrorAction SilentlyContinue |
        Where-Object {

            [string]$_.PNPDeviceID -eq
                [string]$DeviceID
        } |
        Select-Object -First 1


    if (-not $Device) {

        return $null
    }


    return [pscustomobject]@{

        DeviceID =
            [string]$Device.PNPDeviceID

        Name =
            [string]$Device.Name

        ConfigManagerErrorCode =
            [int]$Device.ConfigManagerErrorCode

        Status =
            [string]$Device.Status

        HasError =
            ([int]$Device.ConfigManagerErrorCode -ne 0)
    }
}


function Test-RollbackResult {

    param(
        [Parameter(Mandatory)]
        $Change,

        [Parameter(Mandatory)]
        [bool]$RollbackCommandSucceeded
    )


    $RescanResult =
        Invoke-PnPRescan


    Start-Sleep `
        -Seconds 3


    $CurrentDriver =
        Get-CurrentDriverState `
            -DeviceID $Change.DeviceID


    $DeviceState =
        Get-DeviceErrorState `
            -DeviceID $Change.DeviceID


    $ExpectedVersion =
        [string]$Change.BeforeVersion


    $VersionMatches =
        $false


    if (
        $CurrentDriver -and
        -not [string]::IsNullOrWhiteSpace(
            $ExpectedVersion
        )
    ) {

        $VersionMatches =
            (
                [string]$CurrentDriver.DriverVersion -eq
                $ExpectedVersion
            )
    }


    $ProviderMatches =
        $false


    if (
        $CurrentDriver -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$Change.BeforeProvider
        )
    ) {

        $ProviderMatches =
            (
                [string]$CurrentDriver.DriverProviderName -eq
                [string]$Change.BeforeProvider
            )
    }


    $DeviceHealthy =
        $null


    if ($DeviceState) {

        $DeviceHealthy =
            (-not $DeviceState.HasError)
    }


    $VerificationStatus =
        'Unknown'


    if (-not $RollbackCommandSucceeded) {

        $VerificationStatus =
            'RollbackCommandFailed'
    }
    elseif (-not $CurrentDriver) {

        $VerificationStatus =
            'DriverNotDetected'
    }
    elseif (
        $VersionMatches -and
        $ProviderMatches -and
        $DeviceHealthy -eq $false
    ) {

        $VerificationStatus =
            'DriverRestoredButDeviceError'
    }
    elseif (
        $VersionMatches -and
        $ProviderMatches -and
        (
            $DeviceHealthy -eq $true -or
            $DeviceHealthy -eq $null
        )
    ) {

        $VerificationStatus =
            'Verified'
    }
    else {

        $VerificationStatus =
            'RestartOrFurtherActionRequired'
    }


    return [pscustomobject]@{

        DeviceID =
            $Change.DeviceID

        DeviceName =
            $Change.DeviceName

        ExpectedVersion =
            $ExpectedVersion

        ActualVersion =
            if ($CurrentDriver) {
                $CurrentDriver.DriverVersion
            }
            else {
                $null
            }

        ExpectedInf =
            $Change.BeforeInf

        ActualInf =
            if ($CurrentDriver) {
                $CurrentDriver.InfName
            }
            else {
                $null
            }

        VersionMatches =
            $VersionMatches

        ExpectedProvider =
            [string]$Change.BeforeProvider

        ActualProvider =
            if ($CurrentDriver) {
                $CurrentDriver.DriverProviderName
            }
            else {
                $null
            }

        ProviderMatches =
            $ProviderMatches

        DeviceHealthy =
            $DeviceHealthy

        DeviceErrorCode =
            if ($DeviceState) {
                $DeviceState.ConfigManagerErrorCode
            }
            else {
                $null
            }

        DeviceStatus =
            if ($DeviceState) {
                $DeviceState.Status
            }
            else {
                $null
            }

        RescanSuccess =
            $RescanResult.Success

        RescanExitCode =
            $RescanResult.ExitCode

        VerificationStatus =
            $VerificationStatus
    }
}


function Invoke-DriverRollback {

    param(
        [Parameter(Mandatory)]
        $Change,

        [Parameter(Mandatory)]
        $Manifest
    )


    Write-RollbackLog -Message (
        "Preparing rollback for '$($Change.DeviceName)'."
    )


    Write-RollbackLog -Message (
        "Device ID: $($Change.DeviceID)"
    )


    Write-RollbackLog -Message (
        "Version: $($Change.AfterVersion) -> $($Change.BeforeVersion)"
    )


    Write-RollbackLog -Message (
        "INF: $($Change.AfterInf) -> $($Change.BeforeInf)"
    )


    $BackupInfFile =
        Find-BackupInfFile `
            -PublishedInfName $Change.BeforeInf `
            -Manifest $Manifest


    if (-not $BackupInfFile) {

        Write-RollbackLog `
            -Message (
                "Rollback package was not found for $($Change.BeforeInf)."
            ) `
            -Level 'ERROR'


        return [pscustomobject]@{

            DeviceID =
                $Change.DeviceID

            DeviceName =
                $Change.DeviceName

            Success =
                $false

            RestartRequired =
                $false

            Reason =
                'Before-update driver package backup not found.'

            Verification =
                $null
        }
    }


    Write-RollbackLog -Message (
        "Backup INF: $BackupInfFile"
    )


    if (-not $Execute) {

        Write-RollbackLog `
            -Message (
                'Preview only. No driver changes were made.'
            ) `
            -Level 'INFO'


        return [pscustomobject]@{

            DeviceID =
                $Change.DeviceID

            DeviceName =
                $Change.DeviceName

            Success =
                $true

            RestartRequired =
                $false

            Reason =
                'Preview only.'

            Verification =
                $null
        }
    }


    # ========================================================
    # REMOVE CURRENT DRIVER PACKAGE FROM DEVICE
    # ========================================================
    #
    # /uninstall asks Windows to remove the package from devices
    # currently using it. /force is intentionally not used here.
    # If Windows refuses removal, rollback stops rather than
    # forcing a potentially critical driver off the system.
    # ========================================================

    if (
        -not [string]::IsNullOrWhiteSpace(
            [string]$Change.AfterInf
        ) -and
        $Change.AfterInf -match '^oem\d+\.inf$'
    ) {

        $DevicesUsingCurrentPackage =
            @(
                Get-DevicesUsingPublishedInf `
                    -PublishedInf $Change.AfterInf
            )


        $OtherDevicesUsingCurrentPackage =
            @(
                $DevicesUsingCurrentPackage |
                Where-Object {

                    [string]$_.DeviceID -ne
                        [string]$Change.DeviceID
                }
            )


        if (
            $OtherDevicesUsingCurrentPackage.Count -gt 0
        ) {

            Write-RollbackLog `
                -Message (
                    "Rollback blocked. Current package '$($Change.AfterInf)' is used by " +
                    "$($DevicesUsingCurrentPackage.Count) devices. Removing the package " +
                    'could affect devices other than the selected DeviceID.'
                ) `
                -Level 'ERROR'


            foreach (
                $SharedDevice in $DevicesUsingCurrentPackage
            ) {

                Write-RollbackLog `
                    -Message (
                        "Package user: $($SharedDevice.DeviceName) | $($SharedDevice.DeviceID)"
                    ) `
                    -Level 'WARNING'
            }


            return [pscustomobject]@{

                DeviceID =
                    $Change.DeviceID

                DeviceName =
                    $Change.DeviceName

                Success =
                    $false

                RestartRequired =
                    $false

                Reason =
                    'Rollback blocked because the current driver package is shared by multiple devices.'

                Verification =
                    $null
            }
        }


        Write-RollbackLog -Message (
            "Removing current package from selected device package: $($Change.AfterInf)"
        )


        $DeleteOutput =
            & pnputil.exe `
                /delete-driver `
                $Change.AfterInf `
                /uninstall `
                2>&1


        $DeleteExitCode =
            $LASTEXITCODE


        foreach (
            $Line in @($DeleteOutput)
        ) {

            Write-RollbackLog -Message (
                "pnputil delete: $Line"
            )
        }


        if (
            $DeleteExitCode -ne 0
        ) {

            Write-RollbackLog `
                -Message (
                    'Windows refused to uninstall the current driver package. ' +
                    "Exit code: $DeleteExitCode. No force removal was attempted."
                ) `
                -Level 'ERROR'


            return [pscustomobject]@{

                DeviceID =
                    $Change.DeviceID

                DeviceName =
                    $Change.DeviceName

                Success =
                    $false

                RestartRequired =
                    $false

                Reason =
                    "Current driver uninstall failed. Exit code: $DeleteExitCode"

                Verification =
                    $null
            }
        }
    }


    # ========================================================
    # INSTALL BEFORE-UPDATE PACKAGE
    # ========================================================

    Write-RollbackLog -Message (
        'Installing before-update driver package.'
    )


    $AddOutput =
        & pnputil.exe `
            /add-driver `
            $BackupInfFile `
            /install `
            2>&1


    $AddExitCode =
        $LASTEXITCODE


    foreach (
        $Line in @($AddOutput)
    ) {

        Write-RollbackLog -Message (
            "pnputil add: $Line"
        )
    }


    if (
        $AddExitCode -ne 0
    ) {

        Write-RollbackLog `
            -Message (
                'Rollback package installation failed. ' +
                "Exit code: $AddExitCode"
            ) `
            -Level 'ERROR'


        return [pscustomobject]@{

            DeviceID =
                $Change.DeviceID

            DeviceName =
                $Change.DeviceName

            Success =
                $false

            RestartRequired =
                $false

            Reason =
                "Rollback package install failed. Exit code: $AddExitCode"

            Verification =
                $null
        }
    }


    Write-RollbackLog `
        -Message (
            "Rollback package installed for '$($Change.DeviceName)'."
        ) `
        -Level 'SUCCESS'


    Write-RollbackLog -Message (
        'Verifying active driver state after rollback.'
    )


    $Verification =
        Test-RollbackResult `
            -Change $Change `
            -RollbackCommandSucceeded $true


    if (
        $Verification.VerificationStatus -eq 'Verified'
    ) {

        Write-RollbackLog `
            -Message (
                "Rollback verified. Active version: $($Verification.ActualVersion)"
            ) `
            -Level 'SUCCESS'
    }
    else {

        Write-RollbackLog `
            -Message (
                'Rollback package installation completed, but immediate verification ' +
                "status is '$($Verification.VerificationStatus)'. " +
                "Expected version: $($Verification.ExpectedVersion); " +
                "Active version: $($Verification.ActualVersion). " +
                'A restart may be required before Windows activates the restored driver.'
            ) `
            -Level 'WARNING'
    }


    return [pscustomobject]@{

        DeviceID =
            $Change.DeviceID

        DeviceName =
            $Change.DeviceName

        Success =
            $true

        RestartRequired =
            (
                $Verification.VerificationStatus -ne 'Verified'
            )

        Reason =
            if (
                $Verification.VerificationStatus -eq 'Verified'
            ) {
                'Before-update driver package installed and verified.'
            }
            else {
                'Before-update driver package installed; restart or further verification required.'
            }

        Verification =
            $Verification
    }
}


# ============================================================
# MAIN
# ============================================================

Write-Host ''
Write-Host '============================================================'
Write-Host 'ITINO DRIVER ROLLBACK - PHASE 8.1'
Write-Host '============================================================'
Write-Host ''


$RollbackBackupPath =
    Resolve-RollbackArchive


$RollbackManifestFile =
    Join-Path `
        $RollbackBackupPath `
        'RollbackManifest.json'


Write-RollbackLog -Message (
    "Using rollback archive: $RollbackBackupPath"
)


$RollbackManifest =
    Read-JsonFile `
        -Path $RollbackManifestFile


$BeforeSnapshot =
    @(
        Read-JsonFile `
            -Path $BeforeSnapshotFile
    )


$AfterSnapshot =
    @(
        Read-JsonFile `
            -Path $AfterSnapshotFile
    )


$Changes =
    @(
        Get-DriverChanges `
            -Before $BeforeSnapshot `
            -After $AfterSnapshot
    )


Write-Host "Changed driver candidates: $($Changes.Count)"
Write-Host ''


if (
    $Changes.Count -eq 0
) {

    Write-Host 'No changed driver candidates were found.'
    exit 0
}


$Index =
    1


foreach (
    $Change in $Changes
) {

    Write-Host (
        "[{0}] {1}" -f `
            $Index,
            $Change.DeviceName
    )

    Write-Host (
        "    Version : $($Change.BeforeVersion) -> $($Change.AfterVersion)"
    )

    Write-Host (
        "    INF     : $($Change.BeforeInf) -> $($Change.AfterInf)"
    )

    Write-Host (
        "    DeviceID: $($Change.DeviceID)"
    )

    Write-Host ''


    $Index++
}


if (-not $Execute) {

    Write-Host 'PREVIEW MODE'
    Write-Host 'No driver changes were made.'
    Write-Host ''
    Write-Host 'To execute one rollback:'
    Write-Host (
        '.\05-Rollback-Drivers.ps1 -DeviceID "<DeviceID>" -Execute'
    )
    Write-Host ''
    Write-Host 'To execute all changed drivers:'
    Write-Host (
        '.\05-Rollback-Drivers.ps1 -AllChanged -Execute'
    )

    exit 0
}


if (-not (
    Test-IsAdministrator
)) {

    throw (
        'Rollback execution requires administrator rights.'
    )
}


$SelectedChanges =
    @()


if (
    $AllChanged
) {

    if (-not $ConfirmAllChanged) {

        throw (
            'Using -AllChanged with -Execute also requires -ConfirmAllChanged.'
        )
    }


    $SelectedChanges =
        $Changes
}
elseif (
    -not [string]::IsNullOrWhiteSpace(
        $DeviceID
    )
) {

    $SelectedChanges =
        @(
            $Changes |
            Where-Object {

                [string]$_.DeviceID -eq
                [string]$DeviceID
            }
        )


    if (
        $SelectedChanges.Count -eq 0
    ) {

        throw (
            "No changed driver candidate matched DeviceID '$DeviceID'."
        )
    }
}
else {

    throw (
        'Execution mode requires either -DeviceID or -AllChanged.'
    )
}


$Results =
    @()


foreach (
    $SelectedChange in $SelectedChanges
) {

    $Results +=
        Invoke-DriverRollback `
            -Change $SelectedChange `
            -Manifest $RollbackManifest
}


$Failed =
    @(
        $Results |
        Where-Object {
            -not $_.Success
        }
    )


$RestartRequired =
    @(
        $Results |
        Where-Object {
            $_.RestartRequired
        }
    ).Count -gt 0


$VerificationResults =
    @(
        $Results |
        ForEach-Object {

            if ($_.Verification) {

                $_.Verification
            }
        }
    )


$RollbackVerification =
    [pscustomobject]@{

        VerificationTime =
            (Get-Date).ToString(
                'yyyy-MM-dd HH:mm:ss'
            )

        ComputerName =
            $env:COMPUTERNAME

        Attempted =
            $Results.Count

        Succeeded =
            @(
                $Results |
                Where-Object {
                    $_.Success
                }
            ).Count

        Failed =
            @(
                $Results |
                Where-Object {
                    -not $_.Success
                }
            ).Count

        Verified =
            @(
                $VerificationResults |
                Where-Object {
                    $_.VerificationStatus -eq 'Verified'
                }
            ).Count

        RestartOrFurtherActionRequired =
            @(
                $VerificationResults |
                Where-Object {
                    $_.VerificationStatus -ne 'Verified'
                }
            ).Count

        Results =
            @(
                $Results
            )
    }


$RollbackVerification |
    ConvertTo-Json `
        -Depth 10 |
    Set-Content `
        -LiteralPath $RollbackVerificationFile `
        -Encoding UTF8


Write-RollbackLog -Message (
    "Rollback verification report saved to '$RollbackVerificationFile'."
)


Write-Host ''
Write-Host '============================================================'
Write-Host 'ROLLBACK SUMMARY'
Write-Host '============================================================'
Write-Host "Attempted : $($Results.Count)"
Write-Host "Succeeded : $(@($Results | Where-Object { $_.Success }).Count)"
Write-Host "Failed    : $($Failed.Count)"
Write-Host (
    "Verified  : $($RollbackVerification.Verified)"
)
Write-Host (
    "Needs Recheck: $($RollbackVerification.RestartOrFurtherActionRequired)"
)
Write-Host "Restart   : $RestartRequired"
Write-Host '============================================================'
Write-Host ''


if (
    $RestartRequired
) {

    $RestartFile =
        Join-Path `
            $BasePath `
            'RestartRequired.txt'


    Add-Content `
        -LiteralPath $RestartFile `
        -Value (
            "Reason=Manual driver rollback completed; restart recommended."
        ) `
        -Encoding UTF8
}


if (
    $Failed.Count -gt 0
) {

    exit 1
}


if ($RestartRequired) {

    exit 3010
}


exit 0
