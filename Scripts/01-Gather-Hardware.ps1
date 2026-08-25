<#
.SYNOPSIS
    Collects hardware and Plug and Play device information.

.DESCRIPTION
    Stage 1 of Driver Check And Update.

    Collects:
        Computer information
        BIOS information
        Windows information
        CPU information
        Graphics adapters
        Network adapters
        Storage controllers
        Plug and Play device errors

    Creates:
        HardwareInformation.json
        DeviceErrors-Before.json

    Logging:
        Controlled by the ITINO_WRITE_LOG_FILES environment variable.

        1 / true
            Write Gather-Hardware.log

        0 / false
            Do not create persistent log files

    Console output is always produced so the main controller can
    capture it for the failure log if required.

.EXIT CODES
    0 = Success
    1 = Failure
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'


# ============================================================
# BOOLEAN ENVIRONMENT OPTION
# ============================================================

function Get-ItinoBooleanOption {

    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentVariable,

        [Parameter(Mandatory)]
        [bool]$DefaultValue
    )


    $Value =
        [Environment]::GetEnvironmentVariable(
            $EnvironmentVariable
        )


    if (
        [string]::IsNullOrWhiteSpace(
            $Value
        )
    ) {

        return $DefaultValue
    }


    switch -Regex (
        $Value.Trim()
    ) {

        '^(1|true|yes|on)$' {

            return $true
        }


        '^(0|false|no|off)$' {

            return $false
        }


        default {

            return $DefaultValue
        }
    }
}


# ============================================================
# OPTIONS FROM MAIN CONTROLLER
# ============================================================

$WriteLogFiles =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_WRITE_LOG_FILES' `
        -DefaultValue $true


$PreserveInitialDriverBaseline =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_PRESERVE_INITIAL_DRIVER_BASELINE' `
        -DefaultValue $false


$DeploymentCycle =
    [Environment]::GetEnvironmentVariable(
        'ITINO_DEPLOYMENT_CYCLE'
    )


# ============================================================
# PATHS
# ============================================================

$BasePath =
    'C:\ProgramData\Itino\DriverDeployment'


$LogPath =
    Join-Path `
        $BasePath `
        'Logs'


$HardwareFile =
    Join-Path `
        $BasePath `
        'HardwareInformation.json'


$DeviceErrorsBeforeFile =
    Join-Path `
        $BasePath `
        'DeviceErrors-Before.json'



$DriverSnapshotBeforeFile =
    Join-Path `
        $BasePath `
        'DriverSnapshot-Before.json'



$DriverRollbackRoot =
    'C:\ProgramData\Itino\DriverRollback'


$DriverRollbackBackupPath =
    Join-Path `
        $DriverRollbackRoot `
        (
            '{0}-{1}' -f `
                $env:COMPUTERNAME,
                (Get-Date -Format 'yyyyMMdd-HHmmss')
        )


$LogFile =
    Join-Path `
        $LogPath `
        'Gather-Hardware.log'


# ============================================================
# CREATE REQUIRED DIRECTORY
# ============================================================

if (-not (
    Test-Path -LiteralPath $BasePath
)) {

    New-Item `
        -Path $BasePath `
        -ItemType Directory `
        -Force |
        Out-Null
}


# Only create Logs when detailed logging is enabled.

if ($WriteLogFiles) {

    if (-not (
        Test-Path -LiteralPath $LogPath
    )) {

        New-Item `
            -Path $LogPath `
            -ItemType Directory `
            -Force |
            Out-Null
    }
}


# ============================================================
# LOGGING
# ============================================================

function Write-Log {

    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet(
            'INFO',
            'WARNING',
            'ERROR'
        )]
        [string]$Level = 'INFO'
    )


    $TimeStamp =
        Get-Date -Format 'yyyy-MM-dd HH:mm:ss'


    $LogEntry =
        "[$TimeStamp] [$Level] $Message"


    # Always output to console.
    #
    # The main controller captures this output even when
    # persistent logging is disabled.

    Write-Host $LogEntry


    if ($WriteLogFiles) {

        Add-Content `
            -LiteralPath $LogFile `
            -Value $LogEntry `
            -Encoding UTF8
    }
}


# ============================================================
# START LOG RUN
# ============================================================

function Start-LogRun {

    param(
        [Parameter(Mandatory)]
        [string]$ScriptName
    )


    $RunID =
        (Get-Date -Format 'yyyyMMdd-HHmmss') +
        '-' +
        (
            [guid]::NewGuid().
                ToString('N').
                Substring(0, 4).
                ToUpper()
        )


    $Separator =
        '=' * 75


    $Header = @(
        ''
        ''
        $Separator
        'NEW SCRIPT RUN'
        $Separator
        "Run ID       : $RunID"
        "Script       : $ScriptName"
        "Computer     : $env:COMPUTERNAME"
        "Start Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $Separator
        ''
    )


    if ($WriteLogFiles) {

        Add-Content `
            -LiteralPath $LogFile `
            -Value $Header `
            -Encoding UTF8
    }


    Write-Host ''
    Write-Host $Separator
    Write-Host 'NEW SCRIPT RUN'
    Write-Host $Separator
    Write-Host "Run ID       : $RunID"
    Write-Host "Script       : $ScriptName"
    Write-Host "Computer     : $env:COMPUTERNAME"
    Write-Host "Start Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host $Separator
    Write-Host ''


    return $RunID
}


# ============================================================
# STOP LOG RUN
# ============================================================

function Stop-LogRun {

    param(
        [Parameter(Mandatory)]
        [string]$RunID,

        [Parameter(Mandatory)]
        [string]$Result
    )


    $Separator =
        '=' * 75


    $Footer = @(
        ''
        $Separator
        'END SCRIPT RUN'
        $Separator
        "Run ID       : $RunID"
        "Result       : $Result"
        "End Time     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $Separator
        ''
    )


    if ($WriteLogFiles) {

        Add-Content `
            -LiteralPath $LogFile `
            -Value $Footer `
            -Encoding UTF8
    }


    Write-Host ''
    Write-Host $Separator
    Write-Host 'END SCRIPT RUN'
    Write-Host $Separator
    Write-Host "Run ID       : $RunID"
    Write-Host "Result       : $Result"
    Write-Host "End Time     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host $Separator
    Write-Host ''
}


# ============================================================
# MAIN
# ============================================================

$RunID =
    $null


try {

    # ========================================================
    # START
    # ========================================================

    $RunID =
        Start-LogRun `
            -ScriptName '01-Gather-Hardware.ps1'


    Write-Log -Message (
        'Starting hardware information collection.'
    )


    Write-Log -Message (
        "Write log files: $WriteLogFiles"
    )


    # ========================================================
    # COMPUTER SYSTEM
    # ========================================================

    Write-Log -Message (
        'Reading computer system information.'
    )


    $ComputerSystem =
        Get-CimInstance `
            -ClassName Win32_ComputerSystem


    $ComputerSystemProduct =
        Get-CimInstance `
            -ClassName Win32_ComputerSystemProduct


    # ========================================================
    # BIOS
    # ========================================================

    $BIOS =
        Get-CimInstance `
            -ClassName Win32_BIOS


    # ========================================================
    # OPERATING SYSTEM
    # ========================================================

    $OperatingSystem =
        Get-CimInstance `
            -ClassName Win32_OperatingSystem


    # ========================================================
    # PROCESSORS
    # ========================================================

    Write-Log -Message (
        'Reading processor information.'
    )


    $Processors =
        @(
            Get-CimInstance `
                -ClassName Win32_Processor |
            ForEach-Object {

                [pscustomobject]@{

                    Name =
                        $_.Name

                    Manufacturer =
                        $_.Manufacturer

                    NumberOfCores =
                        $_.NumberOfCores

                    NumberOfLogicalProcessors =
                        $_.NumberOfLogicalProcessors

                    MaxClockSpeed =
                        $_.MaxClockSpeed
                }
            }
        )


    # ========================================================
    # GRAPHICS
    # ========================================================

    Write-Log -Message (
        'Reading graphics adapter information.'
    )


    $GraphicsAdapters =
        @(
            Get-CimInstance `
                -ClassName Win32_VideoController |
            ForEach-Object {

                [pscustomobject]@{

                    Name =
                        $_.Name

                    AdapterCompatibility =
                        $_.AdapterCompatibility

                    DriverVersion =
                        $_.DriverVersion

                    VideoProcessor =
                        $_.VideoProcessor

                    AdapterRAM =
                        $_.AdapterRAM
                }
            }
        )


    # ========================================================
    # NETWORK
    # ========================================================

    Write-Log -Message (
        'Reading network adapter information.'
    )


    $NetworkAdapters =
        @(
            Get-CimInstance `
                -ClassName Win32_NetworkAdapter |
            Where-Object {

                $_.PhysicalAdapter -eq $true
            } |
            ForEach-Object {

                [pscustomobject]@{

                    Name =
                        $_.Name

                    Manufacturer =
                        $_.Manufacturer

                    MACAddress =
                        $_.MACAddress

                    NetConnectionID =
                        $_.NetConnectionID

                    NetEnabled =
                        $_.NetEnabled

                    Speed =
                        $_.Speed

                    PNPDeviceID =
                        $_.PNPDeviceID
                }
            }
        )


    # ========================================================
    # STORAGE CONTROLLERS
    # ========================================================

    Write-Log -Message (
        'Reading storage controller information.'
    )


    $StorageControllers =
        @(
            Get-CimInstance `
                -ClassName Win32_SCSIController |
            ForEach-Object {

                [pscustomobject]@{

                    Name =
                        $_.Name

                    Manufacturer =
                        $_.Manufacturer

                    DriverName =
                        $_.DriverName

                    PNPDeviceID =
                        $_.PNPDeviceID
                }
            }
        )


    # ========================================================
    # DEVICE ERRORS
    # ========================================================

    Write-Log -Message (
        'Checking Plug and Play devices for errors.'
    )


    $DeviceErrors =
        @(
            Get-CimInstance `
                -ClassName Win32_PnPEntity |
            Where-Object {

                $_.ConfigManagerErrorCode -ne 0
            } |
            ForEach-Object {

                [pscustomobject]@{

                    Name =
                        $_.Name

                    Manufacturer =
                        $_.Manufacturer

                    PNPDeviceID =
                        $_.PNPDeviceID

                    ConfigManagerErrorCode =
                        $_.ConfigManagerErrorCode

                    Status =
                        $_.Status
                }
            }
        )


    $DeviceErrorCount =
        @(
            $DeviceErrors
        ).Count


    # ========================================================
    # PHASE 9.2 - ORIGINAL DRIVER BASELINE
    # ========================================================

    $ReuseOriginalSnapshot =
        (
            $PreserveInitialDriverBaseline -and
            (Test-Path -LiteralPath $DriverSnapshotBeforeFile)
        )

    if ($ReuseOriginalSnapshot) {

        Write-Log -Message (
            'Reusing ORIGINAL before-update driver snapshot from ' +
            "deployment cycle 1: '$DriverSnapshotBeforeFile'."
        )

        $ParsedOriginalSnapshot =
            Get-Content `
                -LiteralPath $DriverSnapshotBeforeFile `
                -Raw `
                -ErrorAction Stop |
            ConvertFrom-Json `
                -ErrorAction Stop

        $DriverSnapshotBefore =
            @(
                $ParsedOriginalSnapshot |
                ForEach-Object {
                    $_
                }
            )

        if (
            $DriverSnapshotBefore.Count -eq 1 -and
            $DriverSnapshotBefore[0] -is [System.Array]
        ) {
            $DriverSnapshotBefore =
                @(
                    $DriverSnapshotBefore[0] |
                    ForEach-Object {
                        $_
                    }
                )
        }

        Write-Log -Message (
            "Original baseline contains $($DriverSnapshotBefore.Count) driver record(s)."
        )
    }
    else {

        Write-Log -Message (
            'Collecting ORIGINAL installed Plug and Play driver snapshot.'
        )

        $DriverSnapshotBefore =
            @(
                Get-CimInstance `
                    -ClassName Win32_PnPSignedDriver `
                    -ErrorAction Stop |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace(
                        [string]$_.DeviceID
                    )
                } |
                ForEach-Object {
                    [pscustomobject]@{
                        DeviceID = [string]$_.DeviceID
                        DeviceName = [string]$_.DeviceName
                        Manufacturer = [string]$_.Manufacturer
                        DriverProviderName = [string]$_.DriverProviderName
                        DriverVersion = [string]$_.DriverVersion
                        DriverDate = $_.DriverDate
                        InfName = [string]$_.InfName
                        IsSigned = $_.IsSigned
                        Signer = [string]$_.Signer
                    }
                } |
                Sort-Object -Property DeviceID
            )

        Write-Log -Message (
            "Original driver snapshot contains $($DriverSnapshotBefore.Count) driver record(s)."
        )

        ConvertTo-Json `
            -InputObject @($DriverSnapshotBefore) `
            -Depth 6 |
        Set-Content `
            -LiteralPath $DriverSnapshotBeforeFile `
            -Encoding UTF8

        Write-Log -Message (
            "Original driver snapshot saved to '$DriverSnapshotBeforeFile'."
        )
    }


    # ========================================================
    # PHASE 8.2 - ROLLBACK PACKAGE BACKUP
#
# PowerShell 5.1 compatibility fix:
# Export results now use a normal array rather than
# System.Collections.Generic.List[object]. This avoids
# the manifest-building "Argument types do not match"
# error seen on Windows PowerShell 5.1.
#
# Previous feature lineage: Phase 7 / 8.1
    # ========================================================
    #
    # Export the currently installed OEM INF packages before
    # any driver updates are applied. This is intentionally
    # independent of the normal deployment path: rollback is a
    # technician/manual action and is never performed
    # automatically.
    # ========================================================

    $LatestPointerFile =
        Join-Path `
            $DriverRollbackRoot `
            (
                "$($env:COMPUTERNAME)-Latest.txt"
            )

    $ReuseOriginalRollbackBackup =
        $false

    if (
        $PreserveInitialDriverBaseline -and
        (Test-Path -LiteralPath $LatestPointerFile)
    ) {

        try {

            $ExistingRollbackPath =
                (
                    Get-Content `
                        -LiteralPath $LatestPointerFile `
                        -Raw `
                        -ErrorAction Stop
                ).Trim()

            $ExistingRollbackManifest =
                Join-Path `
                    $ExistingRollbackPath `
                    'RollbackManifest.json'

            if (
                -not [string]::IsNullOrWhiteSpace(
                    $ExistingRollbackPath
                ) -and
                (Test-Path -LiteralPath $ExistingRollbackPath) -and
                (Test-Path -LiteralPath $ExistingRollbackManifest)
            ) {

                $DriverRollbackBackupPath =
                    $ExistingRollbackPath

                $RollbackManifestFile =
                    $ExistingRollbackManifest

                $RollbackManifest =
                    Get-Content `
                        -LiteralPath $RollbackManifestFile `
                        -Raw `
                        -ErrorAction Stop |
                    ConvertFrom-Json `
                        -ErrorAction Stop

                $ReuseOriginalRollbackBackup =
                    $true
            }
        }
        catch {

            Write-Log `
                -Message (
                    'Existing rollback baseline could not be reused. ' +
                    'A new baseline will be created. ' +
                    "Reason: $($_.Exception.Message)"
                ) `
                -Level 'WARNING'
        }
    }

    if ($ReuseOriginalRollbackBackup) {

        Write-Log -Message (
            'Reusing ORIGINAL driver rollback archive from deployment ' +
            "cycle 1: '$DriverRollbackBackupPath'."
        )

        Write-Log -Message (
            "Rollback baseline package count: $($RollbackManifest.PackageCount)."
        )
    }
    else {

        $RollbackBackupStartTime =
            Get-Date


        Write-Log -Message (
            'Preparing before-update driver package backup for manual rollback.'
        )



        if (-not (
            Test-Path -LiteralPath $DriverRollbackRoot
        )) {

            New-Item `
                -Path $DriverRollbackRoot `
                -ItemType Directory `
                -Force |
                Out-Null
        }


        if (
            Test-Path -LiteralPath $DriverRollbackBackupPath
        ) {

            Remove-Item `
                -LiteralPath $DriverRollbackBackupPath `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }


        New-Item `
            -Path $DriverRollbackBackupPath `
            -ItemType Directory `
            -Force |
            Out-Null


        $BeforeInfNames =
            @(
                $DriverSnapshotBefore |
                ForEach-Object {

                    [string]$_.InfName
                } |
                Where-Object {

                    -not [string]::IsNullOrWhiteSpace(
                        $_
                    ) -and
                    $_ -match '^oem\d+\.inf$'
                } |
                Sort-Object -Unique
            )


        # Use a normal PowerShell array here.
        #
        # Windows PowerShell 5.1 can throw:
        #   "Argument types do not match"
        #
        # when a generic List[object] is piped through Where-Object
        # inside an array subexpression while building the manifest.
        # The number of rollback packages is small enough that a
        # standard array is simpler and more reliable.

        $ExportResults =
            @()


        foreach (
            $InfName in $BeforeInfNames
        ) {

            $InfBackupPath =
                Join-Path `
                    $DriverRollbackBackupPath `
                    (
                        [System.IO.Path]::GetFileNameWithoutExtension(
                            $InfName
                        )
                    )


            New-Item `
                -Path $InfBackupPath `
                -ItemType Directory `
                -Force |
                Out-Null


            Write-Log -Message (
                "Exporting rollback driver package: $InfName"
            )


            $PnPUtilOutput =
                & pnputil.exe `
                    /export-driver `
                    $InfName `
                    $InfBackupPath `
                    2>&1


            $PnPUtilExitCode =
                $LASTEXITCODE


            $ExportSuccess =
                ($PnPUtilExitCode -eq 0)


            if ($ExportSuccess) {

                Write-Log -Message (
                    "Rollback package export succeeded: $InfName"
                )
            }
            else {

                Write-Log `
                    -Message (
                        "Rollback package export failed: $InfName. " +
                        "Exit code: $PnPUtilExitCode"
                    ) `
                    -Level 'WARNING'
            }


            $ExportedInfFile =
                $null


            if ($ExportSuccess) {

                $ExportedInfCandidates =
                    @(
                        Get-ChildItem `
                            -LiteralPath $InfBackupPath `
                            -Filter '*.inf' `
                            -File `
                            -Recurse `
                            -ErrorAction SilentlyContinue
                    )


                if ($ExportedInfCandidates.Count -eq 1) {

                    $ExportedInfFile =
                        $ExportedInfCandidates[0].FullName
                }
                elseif ($ExportedInfCandidates.Count -gt 1) {

                    # Prefer an INF whose catalog/package directory
                    # contains the original published INF basename.
                    $Preferred =
                        $ExportedInfCandidates |
                        Where-Object {

                            $_.DirectoryName -match (
                                [regex]::Escape(
                                    [System.IO.Path]::GetFileNameWithoutExtension(
                                        $InfName
                                    )
                                )
                            )
                        } |
                        Select-Object -First 1


                    if ($Preferred) {

                        $ExportedInfFile =
                            $Preferred.FullName
                    }
                }
            }


            $ExportResults +=
                [pscustomobject]@{

                    PublishedInf =
                        $InfName

                    BackupPath =
                        $InfBackupPath

                    ExportedInf =
                        $ExportedInfFile

                    ExitCode =
                        $PnPUtilExitCode

                    Success =
                        (
                            $ExportSuccess -and
                            -not [string]::IsNullOrWhiteSpace(
                                [string]$ExportedInfFile
                            )
                        )

                    Output =
                        @(
                            $PnPUtilOutput
                        )
                }
        }


        $RollbackBackupEndTime =
            Get-Date


        $RollbackBackupBytes =
            (
                Get-ChildItem `
                    -LiteralPath $DriverRollbackBackupPath `
                    -File `
                    -Recurse `
                    -ErrorAction SilentlyContinue |
                Measure-Object `
                    -Property Length `
                    -Sum
            ).Sum


        if ($null -eq $RollbackBackupBytes) {

            $RollbackBackupBytes =
                0
        }


        $RollbackManifest =
            [pscustomobject]@{

                Created =
                    (Get-Date).ToString(
                        'yyyy-MM-dd HH:mm:ss'
                    )

                DurationSeconds =
                    [math]::Round(
                        (
                            $RollbackBackupEndTime -
                            $RollbackBackupStartTime
                        ).TotalSeconds,
                        2
                    )

                BackupSizeBytes =
                    [int64]$RollbackBackupBytes

                ComputerName =
                    $env:COMPUTERNAME

                SnapshotFile =
                    $DriverSnapshotBeforeFile

                BackupRoot =
                    $DriverRollbackBackupPath

                PackageCount =
                    $ExportResults.Count

                SuccessfulExports =
                    @(
                        $ExportResults |
                        Where-Object {
                            $_.Success
                        }
                    ).Count

                FailedExports =
                    @(
                        $ExportResults |
                        Where-Object {
                            -not $_.Success
                        }
                    ).Count

                Packages =
                    @(
                        $ExportResults
                    )
            }


        $RollbackManifestFile =
            Join-Path `
                $DriverRollbackBackupPath `
                'RollbackManifest.json'


        $RollbackManifest |
            ConvertTo-Json `
                -Depth 8 |
            Set-Content `
                -LiteralPath $RollbackManifestFile `
                -Encoding UTF8


        Write-Log -Message (
            'Driver rollback package backup complete. ' +
            "Packages=$($ExportResults.Count), " +
            "Successful=$($RollbackManifest.SuccessfulExports), " +
            "Failed=$($RollbackManifest.FailedExports)."
        )


        Write-Log -Message (
            "Rollback manifest saved to '$RollbackManifestFile'."
        )



        # ========================================================
        # ROLLBACK ARCHIVE RETENTION
        # ========================================================
        #
        # Keep the five newest rollback archives for this computer.
        # This prevents persistent rollback data from growing
        # indefinitely while still preserving multiple recovery
        # points.
        # ========================================================

        $RetentionCount =
            5


        $ComputerArchives =
            @(
                Get-ChildItem `
                    -LiteralPath $DriverRollbackRoot `
                    -Directory `
                    -ErrorAction SilentlyContinue |
                Where-Object {

                    $_.Name -like (
                        "$($env:COMPUTERNAME)-*"
                    )
                } |
                Sort-Object `
                    -Property LastWriteTime `
                    -Descending
            )


        if (
            $ComputerArchives.Count -gt $RetentionCount
        ) {

            foreach (
                $OldArchive in (
                    $ComputerArchives |
                    Select-Object `
                        -Skip $RetentionCount
                )
            ) {

                Write-Log -Message (
                    "Removing old rollback archive: $($OldArchive.FullName)"
                )


                Remove-Item `
                    -LiteralPath $OldArchive.FullName `
                    -Recurse `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }


        $LatestPointerFile =
            Join-Path `
                $DriverRollbackRoot `
                (
                    "$($env:COMPUTERNAME)-Latest.txt"
                )


        Set-Content `
            -LiteralPath $LatestPointerFile `
            -Value $DriverRollbackBackupPath `
            -Encoding UTF8


    }


    # ========================================================
    # HARDWARE OBJECT
    # ========================================================

    $HardwareInformation =
        [pscustomobject]@{

            CollectionTime =
                Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

            DeploymentCycle =
                $DeploymentCycle

            OriginalDriverBaselineReused =
                $ReuseOriginalSnapshot

            OriginalRollbackBaselineReused =
                $ReuseOriginalRollbackBackup


            Computer =
                [pscustomobject]@{

                    ComputerName =
                        $env:COMPUTERNAME

                    Manufacturer =
                        $ComputerSystem.Manufacturer

                    Model =
                        $ComputerSystem.Model

                    UUID =
                        $ComputerSystemProduct.UUID

                    SystemType =
                        $ComputerSystem.SystemType

                    TotalPhysicalMemoryGB =
                        [math]::Round(
                            (
                                $ComputerSystem.TotalPhysicalMemory /
                                1GB
                            ),
                            2
                        )
                }


            BIOS =
                [pscustomobject]@{

                    Manufacturer =
                        $BIOS.Manufacturer

                    SerialNumber =
                        $BIOS.SerialNumber

                    SMBIOSBIOSVersion =
                        $BIOS.SMBIOSBIOSVersion

                    ReleaseDate =
                        $BIOS.ReleaseDate
                }


            Windows =
                [pscustomobject]@{

                    Caption =
                        $OperatingSystem.Caption

                    Version =
                        $OperatingSystem.Version

                    BuildNumber =
                        $OperatingSystem.BuildNumber

                    Architecture =
                        $OperatingSystem.OSArchitecture

                    InstallDate =
                        $OperatingSystem.InstallDate

                    LastBootUpTime =
                        $OperatingSystem.LastBootUpTime
                }


            Processors =
                $Processors


            GraphicsAdapters =
                $GraphicsAdapters


            NetworkAdapters =
                $NetworkAdapters


            StorageControllers =
                $StorageControllers


            DeviceErrorCount =
                $DeviceErrorCount


            DriverSnapshot =
                [pscustomobject]@{

                    File =
                        $DriverSnapshotBeforeFile

                    RecordCount =
                        $DriverSnapshotBefore.Count
                }


            DriverRollbackBackup =
                [pscustomobject]@{

                    Root =
                        $DriverRollbackRoot

                    Path =
                        $DriverRollbackBackupPath

                    Manifest =
                        $RollbackManifestFile

                    LatestPointer =
                        $LatestPointerFile

                    ExportedPackages =
                        $RollbackManifest.SuccessfulExports

                    FailedExports =
                        $RollbackManifest.FailedExports
                }
        }


    # ========================================================
    # SAVE HARDWARE INFORMATION
    # ========================================================

    Write-Log -Message (
        "Saving hardware information to '$HardwareFile'."
    )


    $HardwareInformation |
        ConvertTo-Json `
            -Depth 8 |
        Set-Content `
            -LiteralPath $HardwareFile `
            -Encoding UTF8


    # ========================================================
    # SAVE DEVICE ERRORS
    # ========================================================

    if (
        $DeviceErrorCount -gt 0
    ) {

        $DeviceErrors |
            ConvertTo-Json `
                -Depth 6 |
            Set-Content `
                -LiteralPath $DeviceErrorsBeforeFile `
                -Encoding UTF8
    }
    else {

        '[]' |
            Set-Content `
                -LiteralPath $DeviceErrorsBeforeFile `
                -Encoding UTF8
    }


    # ========================================================
    # SUMMARY
    # ========================================================

    if (
        $DeviceErrorCount -gt 0
    ) {

        Write-Log `
            -Message (
                "$DeviceErrorCount device error(s) detected."
            ) `
            -Level 'WARNING'
    }
    else {

        Write-Log -Message (
            'No Plug and Play device errors detected.'
        )
    }


    Write-Log -Message (
        "Manufacturer: $($ComputerSystem.Manufacturer)"
    )


    Write-Log -Message (
        "Model: $($ComputerSystem.Model)"
    )


    Write-Log -Message (
        "Serial number: $($BIOS.SerialNumber)"
    )


    Write-Log -Message (
        "Windows: $($OperatingSystem.Caption)"
    )


    Write-Log -Message (
        "Windows build: $($OperatingSystem.BuildNumber)"
    )


    Write-Log -Message (
        "Device errors: $DeviceErrorCount"
    )


    Write-Log -Message (
        'Hardware information collection completed successfully.'
    )


    Stop-LogRun `
        -RunID $RunID `
        -Result 'SUCCESS'


    exit 0
}
catch {

    $ErrorMessage =
        $_.Exception.Message


    try {

        Write-Log `
            -Message $ErrorMessage `
            -Level 'ERROR'


        if ($_.InvocationInfo.ScriptLineNumber) {

            Write-Log `
                -Message (
                    "Failure line: $($_.InvocationInfo.ScriptLineNumber)"
                ) `
                -Level 'ERROR'
        }


        if ($RunID) {

            Stop-LogRun `
                -RunID $RunID `
                -Result 'FAILED'
        }
    }
    catch {

        Write-Host (
            "ERROR: $ErrorMessage"
        )
    }


    exit 1
}