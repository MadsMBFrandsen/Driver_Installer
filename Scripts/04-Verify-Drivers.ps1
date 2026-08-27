<#
.SYNOPSIS
    Verifies device driver state after driver installation.

.DESCRIPTION
    Stage 4 of the ITINO Driver Check And Update workflow.

    This script:

        - Reads DeviceErrors-Before.json
        - Scans the current Plug and Play device state
        - Saves DeviceErrors-After.json
        - Determines which device errors were fixed
        - Determines which device errors remain
        - Determines whether new device errors appeared
        - Detects ConfigManagerErrorCode 14
        - Preserves or creates RestartRequired.txt when required
        - Saves DriverVerification.json
        - Inventories installed Dell, HP and Lenovo driver-management tools

    Logging is controlled by Run-DriverDeployment.ps1 through:

        ITINO_WRITE_LOG_FILES

    Console output is always produced so the main controller can
    capture it for DriverDeployment-Error.log if another stage fails.

.EXIT CODES
    0 = Verification completed
    1 = Verification script itself failed

.NOTES
    Remaining device errors do NOT automatically cause exit code 1.

    Exit code 1 is reserved for a real script failure such as:
        - Required files cannot be read
        - CIM query fails
        - Verification report cannot be created

    Driver state problems are recorded inside DriverVerification.json
    and in the verification status.
#>

[CmdletBinding()]
param()

$ErrorActionPreference =
    'Stop'


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


# ============================================================
# PATHS
# ============================================================

$BasePath =
    'C:\ProgramData\Itino\DriverDeployment'


$LogPath =
    Join-Path `
        $BasePath `
        'Logs'


# ============================================================
# PHASE 10.2 - OEM UPDATE RESULT VERIFICATION
# ============================================================

$OEMUpdateResultFile =
    Join-Path `
        (
            Join-Path `
                $BasePath `
                'DriverUpdates'
        ) `
        'OEMUpdateResult.json'


$HardwareFile =
    Join-Path `
        $BasePath `
        'HardwareInformation.json'


$DeviceErrorsBeforeFile =
    Join-Path `
        $BasePath `
        'DeviceErrors-Before.json'


$DeviceErrorsAfterFile =
    Join-Path `
        $BasePath `
        'DeviceErrors-After.json'


$VerificationFile =
    Join-Path `
        $BasePath `
        'DriverVerification.json'


$RestartFile =
    Join-Path `
        $BasePath `
        'RestartRequired.txt'



$DriverSnapshotBeforeFile =
    Join-Path `
        $BasePath `
        'DriverSnapshot-Before.json'


$DriverSnapshotAfterFile =
    Join-Path `
        $BasePath `
        'DriverSnapshot-After.json'


$LogFile =
    Join-Path `
        $LogPath `
        'Verify-Drivers.log'


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
    # The main controller captures this output.

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
# DEVICE DISPLAY NAME
# ============================================================
#
# Unknown devices often have Name = null before their driver
# is installed.
#
# Use the PNP device ID as a fallback so the log never contains
# an empty:
#
#     FIXED:
# ============================================================

function Get-DeviceDisplayName {

    param(
        [Parameter(Mandatory)]
        $Device
    )


    $DisplayName =
        [string]$Device.Name


    if (
        [string]::IsNullOrWhiteSpace(
            $DisplayName
        )
    ) {

        $DisplayName =
            [string]$Device.PNPDeviceID
    }


    if (
        [string]::IsNullOrWhiteSpace(
            $DisplayName
        )
    ) {

        $DisplayName =
            'Unknown device'
    }


    return $DisplayName
}


# ============================================================
# CREATE DEVICE OBJECT
# ============================================================

function ConvertTo-DeviceErrorObject {

    param(
        [Parameter(Mandatory)]
        $Device
    )


    return [PSCustomObject]@{

        Name =
            $Device.Name

        Manufacturer =
            $Device.Manufacturer

        PNPDeviceID =
            $Device.PNPDeviceID

        ConfigManagerErrorCode =
            $Device.ConfigManagerErrorCode

        Status =
            $Device.Status
    }
}


# ============================================================
# GET CURRENT DEVICE ERRORS
# ============================================================

function Get-CurrentDeviceErrors {

    $Devices =
        @(
            Get-CimInstance `
                -ClassName Win32_PnPEntity |
            Where-Object {

                $_.ConfigManagerErrorCode -ne 0
            } |
            ForEach-Object {

                ConvertTo-DeviceErrorObject `
                    -Device $_
            }
        )


    return @(
        $Devices
    )
}




# ============================================================
# PHASE 5.1 - DRIVER SNAPSHOT AND COMPARISON
#
# Windows PowerShell 5.1 compatibility fixes:
# - normal arrays instead of Generic.List[object]
# - explicit JSON array serialization
# - explicit top-level JSON array enumeration
# ============================================================

function Get-InstalledDriverSnapshot {

    return @(
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

                DeviceID =
                    [string]$_.DeviceID

                DeviceName =
                    [string]$_.DeviceName

                Manufacturer =
                    [string]$_.Manufacturer

                DriverProviderName =
                    [string]$_.DriverProviderName

                DriverVersion =
                    [string]$_.DriverVersion

                DriverDate =
                    $_.DriverDate

                InfName =
                    [string]$_.InfName

                IsSigned =
                    $_.IsSigned

                Signer =
                    [string]$_.Signer
            }
        } |
        Sort-Object `
            -Property DeviceID
    )
}


function Compare-DriverSnapshots {

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


    # Use normal PowerShell arrays for Windows PowerShell 5.1
    # compatibility. Generic List[object] can throw
    # "Argument types do not match" when wrapped in @() while
    # returning the comparison object.

    $Changed =
        @()


    $Added =
        @()


    $Removed =
        @()


    foreach (
        $Key in $AfterByDeviceID.Keys
    ) {

        $AfterDriver =
            $AfterByDeviceID[$Key]


        if (-not $BeforeByDeviceID.ContainsKey($Key)) {

            $Added +=
                [pscustomobject]@{

                    DeviceID =
                        $AfterDriver.DeviceID

                    DeviceName =
                        $AfterDriver.DeviceName

                    Manufacturer =
                        $AfterDriver.Manufacturer

                    DriverProviderName =
                        $AfterDriver.DriverProviderName

                    DriverVersion =
                        $AfterDriver.DriverVersion

                    DriverDate =
                        $AfterDriver.DriverDate

                    InfName =
                        $AfterDriver.InfName
                }


            continue
        }


        $BeforeDriver =
            $BeforeByDeviceID[$Key]


        $VersionChanged =
            ([string]$BeforeDriver.DriverVersion -ne [string]$AfterDriver.DriverVersion)


        $ProviderChanged =
            ([string]$BeforeDriver.DriverProviderName -ne [string]$AfterDriver.DriverProviderName)


        $InfChanged =
            ([string]$BeforeDriver.InfName -ne [string]$AfterDriver.InfName)


        if (
            $VersionChanged -or
            $ProviderChanged -or
            $InfChanged
        ) {

            $Changed +=
                [pscustomobject]@{

                    DeviceID =
                        $AfterDriver.DeviceID

                    DeviceName =
                        $AfterDriver.DeviceName

                    Manufacturer =
                        $AfterDriver.Manufacturer

                    BeforeVersion =
                        [string]$BeforeDriver.DriverVersion

                    AfterVersion =
                        [string]$AfterDriver.DriverVersion

                    BeforeProvider =
                        [string]$BeforeDriver.DriverProviderName

                    AfterProvider =
                        [string]$AfterDriver.DriverProviderName

                    BeforeInf =
                        [string]$BeforeDriver.InfName

                    AfterInf =
                        [string]$AfterDriver.InfName
                }
        }
    }


    foreach (
        $Key in $BeforeByDeviceID.Keys
    ) {

        if (-not $AfterByDeviceID.ContainsKey($Key)) {

            $BeforeDriver =
                $BeforeByDeviceID[$Key]


            $Removed +=
                [pscustomobject]@{

                    DeviceID =
                        $BeforeDriver.DeviceID

                    DeviceName =
                        $BeforeDriver.DeviceName

                    Manufacturer =
                        $BeforeDriver.Manufacturer

                    DriverProviderName =
                        $BeforeDriver.DriverProviderName

                    DriverVersion =
                        $BeforeDriver.DriverVersion

                    DriverDate =
                        $BeforeDriver.DriverDate

                    InfName =
                        $BeforeDriver.InfName
                }
        }
    }


    return [pscustomobject]@{

        Changed =
            @(
                $Changed
            )

        Added =
            @(
                $Added
            )

        Removed =
            @(
                $Removed
            )
    }
}


function Write-DriverChangeSummary {

    param(
        [Parameter(Mandatory)]
        $Comparison
    )


    Write-Host ''
    Write-Host '========================================'
    Write-Host 'Driver Changes'
    Write-Host '========================================'
    Write-Host "Changed : $(@($Comparison.Changed).Count)"
    Write-Host "Added   : $(@($Comparison.Added).Count)"
    Write-Host "Removed : $(@($Comparison.Removed).Count)"


    if (
        @($Comparison.Changed).Count -gt 0
    ) {

        Write-Host ''
        Write-Host 'Changed drivers:'


        foreach (
            $Driver in $Comparison.Changed
        ) {

            Write-Host (
                ' - ' +
                "$($Driver.DeviceName) | " +
                "$($Driver.BeforeVersion) -> $($Driver.AfterVersion)"
            )
        }
    }


    if (
        @($Comparison.Added).Count -gt 0
    ) {

        Write-Host ''
        Write-Host 'Newly detected drivers:'


        foreach (
            $Driver in $Comparison.Added
        ) {

            Write-Host (
                ' - ' +
                "$($Driver.DeviceName) | " +
                "$($Driver.DriverVersion)"
            )
        }
    }


    Write-Host '========================================'
    Write-Host ''
}


# ============================================================
# PHASE 4 - WINDOWS PENDING RESTART DETECTION
# ============================================================

function Get-WindowsPendingRestartInformation {

    # Normal array for reliable Windows PowerShell 5.1 JSON/
    # object handling.

    $Reasons =
        @()


    $CBSRebootPending =
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'


    if (
        Test-Path -LiteralPath $CBSRebootPending
    ) {

        $Reasons +=
            'CBS: RebootPending'
    }


    $WURebootRequired =
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'


    if (
        Test-Path -LiteralPath $WURebootRequired
    ) {

        $Reasons +=
            'Windows Update: RebootRequired'
    }


    try {

        $UpdateExeVolatile =
            Get-ItemProperty `
                -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Updates' `
                -Name 'UpdateExeVolatile' `
                -ErrorAction SilentlyContinue


        if (
            $UpdateExeVolatile -and
            [int]$UpdateExeVolatile.UpdateExeVolatile -ne 0
        ) {

            $Reasons +=
                "Windows Updates: UpdateExeVolatile=$($UpdateExeVolatile.UpdateExeVolatile)"
        }
    }
    catch {
    }


    try {

        $SessionManager =
            Get-ItemProperty `
                -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
                -ErrorAction SilentlyContinue


        if (
            $SessionManager.PendingFileRenameOperations
        ) {

            $Reasons +=
                'Session Manager: PendingFileRenameOperations'
        }


        if (
            $SessionManager.PendingFileRenameOperations2
        ) {

            $Reasons +=
                'Session Manager: PendingFileRenameOperations2'
        }
    }
    catch {
    }


    try {

        $ActiveComputerName =
            (
                Get-ItemProperty `
                    -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' `
                    -Name 'ComputerName' `
                    -ErrorAction Stop
            ).ComputerName


        $ConfiguredComputerName =
            (
                Get-ItemProperty `
                    -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' `
                    -Name 'ComputerName' `
                    -ErrorAction Stop
            ).ComputerName


        if (
            -not [string]::IsNullOrWhiteSpace(
                [string]$ActiveComputerName
            ) -and
            -not [string]::IsNullOrWhiteSpace(
                [string]$ConfiguredComputerName
            ) -and
            $ActiveComputerName -ne $ConfiguredComputerName
        ) {

            $Reasons +=
                "Computer rename pending: '$ActiveComputerName' -> '$ConfiguredComputerName'"
        }
    }
    catch {
    }


    return [PSCustomObject]@{

        Pending =
            ($Reasons.Count -gt 0)

        Reasons =
            @(
                $Reasons
            )
    }
}


# ============================================================
# SET RESTART REQUIRED
# ============================================================

function Set-RestartRequired {

    param(
        [Parameter(Mandatory)]
        [string]$Reason
    )


    $ExistingReasons =
        @()


    if (
        Test-Path -LiteralPath $RestartFile
    ) {

        try {

            $ExistingContent =
                Get-Content `
                    -LiteralPath $RestartFile `
                    -ErrorAction Stop


            $ExistingReasons =
                @(
                    $ExistingContent |
                    Where-Object {
                        $_ -like 'Reason=*'
                    } |
                    ForEach-Object {
                        $_.Substring(7)
                    }
                )
        }
        catch {

            Write-Log `
                -Message (
                    'Unable to read existing restart marker.'
                ) `
                -Level 'WARNING'
        }
    }


    $Reasons =
        @(
            $ExistingReasons
            $Reason
        ) |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        } |
        Select-Object -Unique


    $Content =
        @(
            'RestartRequired=True'
            "Date=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        )


    foreach (
        $RestartReason in $Reasons
    ) {

        $Content +=
            "Reason=$RestartReason"
    }


    # ASCII prevents BOM characters when CMD displays the file.

    $Content |
        Set-Content `
            -LiteralPath $RestartFile `
            -Encoding ASCII


    Write-Log `
        -Message (
            "Restart required: $Reason"
        ) `
        -Level 'WARNING'
}



# ============================================================
# PHASE 3 - OEM TOOL INVENTORY
# ============================================================

function Get-FileVersionSafe {

    param(
        [string]$Path
    )


    if (
        [string]::IsNullOrWhiteSpace(
            $Path
        ) -or
        -not (
            Test-Path -LiteralPath $Path
        )
    ) {

        return $null
    }


    try {

        $VersionInfo =
            [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
                $Path
            )


        if (
            -not [string]::IsNullOrWhiteSpace(
                [string]$VersionInfo.ProductVersion
            )
        ) {

            return [string]$VersionInfo.ProductVersion
        }


        if (
            -not [string]::IsNullOrWhiteSpace(
                [string]$VersionInfo.FileVersion
            )
        ) {

            return [string]$VersionInfo.FileVersion
        }
    }
    catch {

    }


    return $null
}


function Find-FirstExistingFile {

    param(
        [Parameter(Mandatory)]
        [string[]]$Paths
    )


    foreach (
        $Candidate in $Paths
    ) {

        if (
            -not [string]::IsNullOrWhiteSpace(
                $Candidate
            ) -and
            (
                Test-Path -LiteralPath $Candidate
            )
        ) {

            return $Candidate
        }
    }


    return $null
}


function Find-HPImageAssistant {

    # ========================================================
    # PHASE 10.1 - PERMANENT HPIA DETECTION
    # ========================================================

    $ExactCandidates =
        @(
            'C:\Program Files\HP\HP Image Assistant\HPImageAssistant.exe'

            'C:\Program Files\HP\HPIA\HPImageAssistant.exe'

            'C:\Program Files (x86)\HP\HP Image Assistant\HPImageAssistant.exe'

            'C:\Program Files (x86)\HP\HPIA\HPImageAssistant.exe'

            (
                Join-Path `
                    $BasePath `
                    'Tools\HPImageAssistant\HPImageAssistant.exe'
            )

            (
                Join-Path `
                    $BasePath `
                    'Tools\HP\HPIA\HPImageAssistant.exe'
            )

            'C:\ProgramData\HP\HPIA\HPImageAssistant.exe'
        )


    foreach (
        $Candidate in $ExactCandidates
    ) {

        if (
            -not [string]::IsNullOrWhiteSpace(
                [string]$Candidate
            ) -and
            (
                Test-Path `
                    -LiteralPath $Candidate `
                    -PathType Leaf
            )
        ) {

            return $Candidate
        }
    }


    $FallbackRoots =
        @(
            (
                Join-Path `
                    $BasePath `
                    'Tools\HPImageAssistant'
            )

            (
                Join-Path `
                    $BasePath `
                    'Tools\HP\HPIA'
            )

            'C:\Program Files\HP'

            'C:\Program Files (x86)\HP'

            'C:\ProgramData\HP\HPIA'
        )


    foreach (
        $Root in $FallbackRoots |
        Select-Object -Unique
    ) {

        if (
            [string]::IsNullOrWhiteSpace(
                [string]$Root
            ) -or
            -not (
                Test-Path `
                    -LiteralPath $Root `
                    -PathType Container
            )
        ) {

            continue
        }


        try {

            $Executable =
                Get-ChildItem `
                    -LiteralPath $Root `
                    -Filter 'HPImageAssistant.exe' `
                    -File `
                    -Recurse `
                    -ErrorAction SilentlyContinue |
                Select-Object -First 1


            if ($Executable) {

                return $Executable.FullName
            }
        }
        catch {

            # Best-effort inventory only.
        }
    }


    return $null
}



function Get-LSUClientInventory {

    $Modules =
        @(
            Get-Module `
                -Name 'LSUClient' `
                -ListAvailable `
                -ErrorAction SilentlyContinue |
            Sort-Object `
                -Property Version `
                -Descending
        )


    $Module =
        $Modules |
        Select-Object -First 1


    if (-not $Module) {

        return [PSCustomObject]@{
            Name =
                'LSUClient'

            Installed =
                $false

            Version =
                $null

            Path =
                $null

            Source =
                'PowerShell Module'
        }
    }


    return [PSCustomObject]@{
        Name =
            'LSUClient'

        Installed =
            $true

        Version =
            [string]$Module.Version

        Path =
            [string]$Module.Path

        Source =
            'PowerShell Module'
    }
}


function Get-OEMToolInventory {

    param(
        [Parameter(Mandatory)]
        [string]$Manufacturer
    )


    $Inventory =
        @()


    # ========================================================
    # DELL COMMAND UPDATE
    # ========================================================

    $DCUPath =
        Find-FirstExistingFile `
            -Paths @(
                'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
                'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe'
            )


    $Inventory +=
        [PSCustomObject]@{
            Name =
                'Dell Command Update'

            Installed =
                [bool]$DCUPath

            Version =
                Get-FileVersionSafe `
                    -Path $DCUPath

            Path =
                $DCUPath

            Source =
                'Executable'
        }


    # ========================================================
    # HP IMAGE ASSISTANT
    # ========================================================

    $HPIAPath =
        Find-HPImageAssistant


    $Inventory +=
        [PSCustomObject]@{
            Name =
                'HP Image Assistant'

            Installed =
                [bool]$HPIAPath

            Version =
                Get-FileVersionSafe `
                    -Path $HPIAPath

            Path =
                $HPIAPath

            Source =
                'Executable'
        }


    # ========================================================
    # LENOVO LSCLIENT
    # ========================================================

    $Inventory +=
        Get-LSUClientInventory


    # ========================================================
    # LENOVO SYSTEM UPDATE
    # ========================================================

    $TVSUPath =
        Find-FirstExistingFile `
            -Paths @(
                'C:\Program Files (x86)\Lenovo\System Update\tvsu.exe'
                'C:\Program Files\Lenovo\System Update\tvsu.exe'
            )


    $TVSUShimPath =
        Find-FirstExistingFile `
            -Paths @(
                'C:\Program Files (x86)\Lenovo\System Update\tvsuShim.exe'
                'C:\Program Files\Lenovo\System Update\tvsuShim.exe'
            )


    $LenovoVersion =
        Get-FileVersionSafe `
            -Path $TVSUPath


    if (
        [string]::IsNullOrWhiteSpace(
            $LenovoVersion
        )
    ) {

        $LenovoVersion =
            Get-FileVersionSafe `
                -Path $TVSUShimPath
    }


    $Inventory +=
        [PSCustomObject]@{
            Name =
                'Lenovo System Update'

            Installed =
                [bool](
                    $TVSUPath -or
                    $TVSUShimPath
                )

            Version =
                $LenovoVersion

            Path =
                $TVSUPath

            Source =
                'Executable'
        }


    $Inventory +=
        [PSCustomObject]@{
            Name =
                'Lenovo System Update Shim'

            Installed =
                [bool]$TVSUShimPath

            Version =
                Get-FileVersionSafe `
                    -Path $TVSUShimPath

            Path =
                $TVSUShimPath

            Source =
                'Executable'
        }


    # ========================================================
    # IDENTIFY TOOLS RELEVANT TO CURRENT OEM
    # ========================================================

    foreach (
        $Tool in $Inventory
    ) {

        $Relevant =
            $false


        if (
            $Manufacturer -match 'Dell' -and
            $Tool.Name -eq 'Dell Command Update'
        ) {

            $Relevant =
                $true
        }
        elseif (
            $Manufacturer -match 'HP|Hewlett' -and
            $Tool.Name -eq 'HP Image Assistant'
        ) {

            $Relevant =
                $true
        }
        elseif (
            $Manufacturer -match 'Lenovo' -and
            $Tool.Name -in @(
                'LSUClient'
                'Lenovo System Update'
                'Lenovo System Update Shim'
            )
        ) {

            $Relevant =
                $true
        }


        Add-Member `
            -InputObject $Tool `
            -MemberType NoteProperty `
            -Name 'RelevantToCurrentOEM' `
            -Value $Relevant `
            -Force
    }


    return @(
        $Inventory
    )
}


function Write-OEMToolInventorySummary {

    param(
        [Parameter(Mandatory)]
        [object[]]$Inventory
    )


    Write-Host ''
    Write-Host '========================================'
    Write-Host 'OEM Tool Inventory'
    Write-Host '========================================'


    foreach (
        $Tool in $Inventory |
        Where-Object {
            $_.RelevantToCurrentOEM -or
            $_.Installed
        }
    ) {

        Write-Host ''
        Write-Host $Tool.Name
        Write-Host (
            "Installed : $($Tool.Installed)"
        )


        $VersionText =
            if (
                [string]::IsNullOrWhiteSpace(
                    [string]$Tool.Version
                )
            ) {
                'Not detected'
            }
            else {
                [string]$Tool.Version
            }


        $PathText =
            if (
                [string]::IsNullOrWhiteSpace(
                    [string]$Tool.Path
                )
            ) {
                'Not detected'
            }
            else {
                [string]$Tool.Path
            }


        Write-Host (
            "Version   : $VersionText"
        )

        Write-Host (
            "Path      : $PathText"
        )
    }


    Write-Host '========================================'
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
            -ScriptName '04-Verify-Drivers.ps1'


    Write-Log -Message (
        'Driver verification stage started.'
    )


    Write-Log -Message (
        "Write log files: $WriteLogFiles"
    )


    # ========================================================
    # HARDWARE INFORMATION
    # ========================================================

    if (-not (
        Test-Path -LiteralPath $HardwareFile
    )) {

        throw (
            'HardwareInformation.json was not found.'
        )
    }


    $Hardware =
        Get-Content `
            -LiteralPath $HardwareFile `
            -Raw `
            -ErrorAction Stop |
        ConvertFrom-Json


    $Manufacturer =
        [string]$Hardware.Computer.Manufacturer


    $Model =
        [string]$Hardware.Computer.Model


    Write-Log -Message (
        "Manufacturer: $Manufacturer"
    )


    Write-Log -Message (
        "Model: $Model"
    )


    # ========================================================
    # PHASE 3 - OEM TOOL INVENTORY
    # ========================================================

    Write-Log -Message (
        'Collecting installed OEM driver-management tooling.'
    )


    $OEMToolInventory =
        @(
            Get-OEMToolInventory `
                -Manufacturer $Manufacturer
        )


    foreach (
        $Tool in $OEMToolInventory |
        Where-Object {
            $_.RelevantToCurrentOEM -or
            $_.Installed
        }
    ) {

        $VersionText =
            if (
                [string]::IsNullOrWhiteSpace(
                    [string]$Tool.Version
                )
            ) {
                'Not detected'
            }
            else {
                [string]$Tool.Version
            }


        $PathText =
            if (
                [string]::IsNullOrWhiteSpace(
                    [string]$Tool.Path
                )
            ) {
                'Not detected'
            }
            else {
                [string]$Tool.Path
            }


        Write-Log -Message (
            "OEM tool: $($Tool.Name) | " +
            "Installed=$($Tool.Installed) | " +
            "Version=$VersionText | " +
            "Path=$PathText"
        )
    }


    # ========================================================
    # PHASE 10.2 - READ NORMALIZED OEM UPDATE RESULT
    # ========================================================

    $OEMUpdateResult =
        $null


    if (
        Test-Path `
            -LiteralPath $OEMUpdateResultFile `
            -PathType Leaf
    ) {

        try {

            $OEMUpdateResult =
                Get-Content `
                    -LiteralPath $OEMUpdateResultFile `
                    -Raw `
                    -ErrorAction Stop |
                ConvertFrom-Json


            Write-Log -Message (
                'OEM update result loaded: ' +
                "Manufacturer=$($OEMUpdateResult.Manufacturer) | " +
                "Tool=$($OEMUpdateResult.Tool) | " +
                "Status=$($OEMUpdateResult.Status) | " +
                "RestartRequired=$($OEMUpdateResult.RestartRequired) | " +
                "ExitCode=$($OEMUpdateResult.ExitCode)"
            )
        }
        catch {

            Write-Log `
                -Message (
                    'Unable to read OEMUpdateResult.json. ' +
                    "Reason: $($_.Exception.Message)"
                ) `
                -Level 'WARNING'
        }
    }
    else {

        Write-Log `
            -Message (
                'OEMUpdateResult.json was not found. ' +
                'Verification will continue without normalized OEM result data.'
            ) `
            -Level 'WARNING'
    }


    # ========================================================
    # BEFORE STATE
    # ========================================================

    if (-not (
        Test-Path -LiteralPath $DeviceErrorsBeforeFile
    )) {

        throw (
            'DeviceErrors-Before.json was not found.'
        )
    }


    $BeforeRaw =
        Get-Content `
            -LiteralPath $DeviceErrorsBeforeFile `
            -Raw `
            -ErrorAction Stop


    if (
        [string]::IsNullOrWhiteSpace(
            $BeforeRaw
        )
    ) {

        $DeviceErrorsBefore =
            @()
    }
    else {

        $ParsedBefore =
            $BeforeRaw |
            ConvertFrom-Json


        $DeviceErrorsBefore =
            @(
                $ParsedBefore
            )
    }


    $BeforeCount =
        @(
            $DeviceErrorsBefore
        ).Count


    Write-Log -Message (
        "Device errors before update: $BeforeCount"
    )


    # ========================================================
    # CURRENT DEVICE STATE
    # ========================================================

    Write-Log -Message (
        'Scanning current Plug and Play device state.'
    )


    $DeviceErrorsAfter =
        @(
            Get-CurrentDeviceErrors
        )


    $AfterCount =
        @(
            $DeviceErrorsAfter
        ).Count


    # ========================================================
    # SAVE AFTER STATE
    # ========================================================

    if (
        $AfterCount -gt 0
    ) {

        $DeviceErrorsAfter |
            ConvertTo-Json `
                -Depth 6 |
            Set-Content `
                -LiteralPath $DeviceErrorsAfterFile `
                -Encoding UTF8
    }
    else {

        '[]' |
            Set-Content `
                -LiteralPath $DeviceErrorsAfterFile `
                -Encoding UTF8
    }


    # ========================================================
    # COMPARE BEFORE AND AFTER
    # ========================================================

    $BeforeIDs =
        @(
            $DeviceErrorsBefore |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace(
                    [string]$_.PNPDeviceID
                )
            } |
            ForEach-Object {
                [string]$_.PNPDeviceID
            }
        )


    $AfterIDs =
        @(
            $DeviceErrorsAfter |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace(
                    [string]$_.PNPDeviceID
                )
            } |
            ForEach-Object {
                [string]$_.PNPDeviceID
            }
        )


    # ========================================================
    # FIXED DEVICES
    # ========================================================

    $FixedDevices =
        @(
            $DeviceErrorsBefore |
            Where-Object {

                $PNPID =
                    [string]$_.PNPDeviceID


                if (
                    [string]::IsNullOrWhiteSpace(
                        $PNPID
                    )
                ) {

                    return $false
                }


                return (
                    $AfterIDs -notcontains
                    $PNPID
                )
            }
        )


    # ========================================================
    # REMAINING DEVICES
    # ========================================================

    $RemainingDevices =
        @(
            $DeviceErrorsAfter |
            Where-Object {

                $PNPID =
                    [string]$_.PNPDeviceID


                if (
                    [string]::IsNullOrWhiteSpace(
                        $PNPID
                    )
                ) {

                    return $false
                }


                return (
                    $BeforeIDs -contains
                    $PNPID
                )
            }
        )


    # ========================================================
    # NEW ERRORS
    # ========================================================

    $NewErrors =
        @(
            $DeviceErrorsAfter |
            Where-Object {

                $PNPID =
                    [string]$_.PNPDeviceID


                if (
                    [string]::IsNullOrWhiteSpace(
                        $PNPID
                    )
                ) {

                    return $false
                }


                return (
                    $BeforeIDs -notcontains
                    $PNPID
                )
            }
        )


    # ========================================================
    # RESTART DEVICES
    # ========================================================
    #
    # ConfigManagerErrorCode 14:
    #
    # CM_PROB_NEED_RESTART
    # ========================================================

    $RestartDevices =
        @(
            $DeviceErrorsAfter |
            Where-Object {

                $_.ConfigManagerErrorCode -eq 14
            }
        )


    # ========================================================
    # COUNTS
    # ========================================================

    $FixedCount =
        @(
            $FixedDevices
        ).Count


    $RemainingCount =
        @(
            $RemainingDevices
        ).Count


    $NewCount =
        @(
            $NewErrors
        ).Count


    $RestartDeviceCount =
        @(
            $RestartDevices
        ).Count


    # ========================================================
    # LOG COUNTS
    # ========================================================

    Write-Log -Message (
        "Device errors after update: $AfterCount"
    )


    Write-Log -Message (
        "Fixed device errors: $FixedCount"
    )


    Write-Log -Message (
        "Remaining device errors: $RemainingCount"
    )


    Write-Log -Message (
        "New device errors: $NewCount"
    )


    # ========================================================
    # LOG FIXED DEVICES
    # ========================================================

    foreach (
        $Device in $FixedDevices
    ) {

        $DisplayName =
            Get-DeviceDisplayName `
                -Device $Device


        Write-Log -Message (
            "FIXED: $DisplayName"
        )
    }


    # ========================================================
    # LOG REMAINING DEVICES
    # ========================================================

    foreach (
        $Device in $RemainingDevices
    ) {

        $DisplayName =
            Get-DeviceDisplayName `
                -Device $Device


        Write-Log `
            -Message (
                "REMAINING: $DisplayName | " +
                "Code=$($Device.ConfigManagerErrorCode)"
            ) `
            -Level 'WARNING'
    }


    # ========================================================
    # LOG NEW ERRORS
    # ========================================================

    foreach (
        $Device in $NewErrors
    ) {

        $DisplayName =
            Get-DeviceDisplayName `
                -Device $Device


        Write-Log `
            -Message (
                "NEW ERROR: $DisplayName | " +
                "Code=$($Device.ConfigManagerErrorCode)"
            ) `
            -Level 'WARNING'
    }


    # ========================================================
    # RESTART DEVICES
    # ========================================================

    Write-Log -Message (
        "Devices requiring restart: $RestartDeviceCount"
    )


    if (
        $RestartDeviceCount -gt 0
    ) {

        foreach (
            $Device in $RestartDevices
        ) {

            $DisplayName =
                Get-DeviceDisplayName `
                    -Device $Device


            Write-Log `
                -Message (
                    "RESTART DEVICE: $DisplayName"
                ) `
                -Level 'WARNING'
        }


        Set-RestartRequired `
            -Reason (
                "$RestartDeviceCount Plug and Play device(s) " +
                'report ConfigManagerErrorCode 14.'
            )
    }


    # ========================================================
    # PHASE 5 - DRIVER SNAPSHOT AFTER UPDATE
    # ========================================================

    Write-Log -Message (
        'Collecting installed Plug and Play driver snapshot after updates.'
    )


    $DriverSnapshotAfter =
        @(
            Get-InstalledDriverSnapshot
        )


    ConvertTo-Json `
        -InputObject @($DriverSnapshotAfter) `
        -Depth 6 |
    Set-Content `
        -LiteralPath $DriverSnapshotAfterFile `
        -Encoding UTF8


    Write-Log -Message (
        "Driver snapshot after update contains $($DriverSnapshotAfter.Count) driver record(s)."
    )


    Write-Log -Message (
        "Driver snapshot after update saved to '$DriverSnapshotAfterFile'."
    )


    $DriverSnapshotBefore =
        @()


    if (
        Test-Path -LiteralPath $DriverSnapshotBeforeFile
    ) {

        try {

            $ParsedBeforeSnapshot =
                Get-Content `
                    -LiteralPath $DriverSnapshotBeforeFile `
                    -Raw `
                    -ErrorAction Stop |
                ConvertFrom-Json `
                    -ErrorAction Stop


            # Windows PowerShell 5.1 may return a top-level JSON
            # array as one pipeline object. Explicitly enumerate
            # it so the comparison receives individual drivers.

            $DriverSnapshotBefore =
                @(
                    $ParsedBeforeSnapshot |
                    ForEach-Object {
                        $_
                    }
                )


            # If the parser still returned one nested array,
            # enumerate that array explicitly.
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
                "Loaded $($DriverSnapshotBefore.Count) before-update driver record(s)."
            )
        }
        catch {

            Write-Log `
                -Message (
                    'Unable to read DriverSnapshot-Before.json. ' +
                    "Driver comparison will continue with an empty baseline. " +
                    "Reason: $($_.Exception.Message)"
                ) `
                -Level 'WARNING'


            $DriverSnapshotBefore =
                @()
        }
    }
    else {

        Write-Log `
            -Message (
                'DriverSnapshot-Before.json was not found. ' +
                'Driver comparison will continue with an empty baseline.'
            ) `
            -Level 'WARNING'
    }


    $DriverComparison =
        Compare-DriverSnapshots `
            -Before $DriverSnapshotBefore `
            -After $DriverSnapshotAfter


    Write-Log -Message (
        'Driver comparison complete. ' +
        "Changed=$(@($DriverComparison.Changed).Count), " +
        "Added=$(@($DriverComparison.Added).Count), " +
        "Removed=$(@($DriverComparison.Removed).Count)."
    )


    foreach (
        $DriverChange in $DriverComparison.Changed
    ) {

        Write-Log -Message (
            'DRIVER CHANGED: ' +
            "$($DriverChange.DeviceName) | " +
            "$($DriverChange.BeforeVersion) -> $($DriverChange.AfterVersion) | " +
            "$($DriverChange.BeforeInf) -> $($DriverChange.AfterInf)"
        )
    }


    # ========================================================
    # WINDOWS PENDING RESTART STATE
    # ========================================================

    Write-Log -Message (
        'Checking Windows for pending restart conditions after driver updates.'
    )


    $WindowsPendingRestart =
        Get-WindowsPendingRestartInformation


    if (
        $WindowsPendingRestart.Pending
    ) {

        foreach (
            $PendingReason in $WindowsPendingRestart.Reasons
        ) {

            Write-Log `
                -Message (
                    "WINDOWS RESTART PENDING: $PendingReason"
                ) `
                -Level 'WARNING'


            Set-RestartRequired `
                -Reason (
                    "Windows pending restart detected after driver deployment: $PendingReason"
                )
        }
    }
    else {

        Write-Log -Message (
            'Windows does not currently report a pending restart.'
        )
    }


    # ========================================================
    # EXISTING RESTART MARKER
    # ========================================================

    $RestartRequired =
        Test-Path `
            -LiteralPath $RestartFile


    if ($RestartRequired) {

        Write-Log `
            -Message (
                'A restart marker exists. Device state may change ' +
                'after the deployment restart.'
            ) `
            -Level 'WARNING'
    }


    # ========================================================
    # STATUS
    # ========================================================

    if (
        $RemainingCount -eq 0 -and
        $NewCount -eq 0
    ) {

        if ($RestartRequired) {

            $Status =
                'SuccessRestartRequired'
        }
        else {

            $Status =
                'Success'
        }
    }
    elseif (
        $NewCount -gt 0
    ) {

        if ($RestartRequired) {

            $Status =
                'CompletedWithNewDeviceErrorsRestartRequired'
        }
        else {

            $Status =
                'CompletedWithNewDeviceErrors'
        }
    }
    else {

        if ($RestartRequired) {

            $Status =
                'CompletedWithDeviceErrorsRestartRequired'
        }
        else {

            $Status =
                'CompletedWithDeviceErrors'
        }
    }


    # ========================================================
    # PHASE 10.2 - ENRICH OEM RESULT WITH VERIFICATION
    # ========================================================

    if ($OEMUpdateResult) {

        try {

            $ChangedCount =
                @(
                    $DriverComparison.Changed
                ).Count


            $AddedCount =
                @(
                    $DriverComparison.Added
                ).Count


            $RemovedCount =
                @(
                    $DriverComparison.Removed
                ).Count


            $OEMUpdateResult.Verification =
                [PSCustomObject]@{

                    Status =
                        $Status

                    DeviceErrorsBefore =
                        $BeforeCount

                    DeviceErrorsAfter =
                        $AfterCount

                    FixedDeviceErrors =
                        $FixedCount

                    RemainingDeviceErrors =
                        $RemainingCount

                    NewDeviceErrors =
                        $NewCount

                    DriverChanged =
                        $ChangedCount

                    DriverAdded =
                        $AddedCount

                    DriverRemoved =
                        $RemovedCount

                    RestartRequired =
                        $RestartRequired
                }


            if (
                $OEMUpdateResult.Status -eq 'Success' -and
                -not $RestartRequired -and
                $ChangedCount -eq 0 -and
                $AddedCount -eq 0 -and
                $RemovedCount -eq 0 -and
                $RemainingCount -eq 0 -and
                $NewCount -eq 0
            ) {

                $OEMUpdateResult.Status =
                    'SuccessNoUpdates'
            }


            if ($RestartRequired) {

                $OEMUpdateResult.RestartRequired =
                    $true


                if (
                    $OEMUpdateResult.Status -match
                    '^Success'
                ) {

                    $OEMUpdateResult.Status =
                        'SuccessRestartRequired'
                }
            }


            $OEMUpdateResult |
                ConvertTo-Json `
                    -Depth 10 |
                Set-Content `
                    -LiteralPath $OEMUpdateResultFile `
                    -Encoding UTF8


            Write-Log -Message (
                'OEM update result enriched by verification. ' +
                "FinalStatus=$($OEMUpdateResult.Status); " +
                "Changed=$ChangedCount; " +
                "Added=$AddedCount; " +
                "Removed=$RemovedCount."
            )
        }
        catch {

            Write-Log `
                -Message (
                    'Unable to enrich OEMUpdateResult.json. ' +
                    "Reason: $($_.Exception.Message)"
                ) `
                -Level 'WARNING'
        }
    }


    # ========================================================
    # VERIFICATION REPORT
    # ========================================================

    $Verification =
        [PSCustomObject]@{

            VerificationTime =
                Get-Date -Format 'yyyy-MM-dd HH:mm:ss'


            Computer =
                [PSCustomObject]@{

                    ComputerName =
                        $env:COMPUTERNAME

                    Manufacturer =
                        $Manufacturer

                    Model =
                        $Model
                }


            Results =
                [PSCustomObject]@{

                    Status =
                        $Status

                    DeviceErrorsBefore =
                        $BeforeCount

                    DeviceErrorsAfter =
                        $AfterCount

                    FixedDeviceErrors =
                        $FixedCount

                    RemainingDeviceErrors =
                        $RemainingCount

                    NewDeviceErrors =
                        $NewCount

                    RestartDevices =
                        $RestartDeviceCount

                    RestartRequired =
                        $RestartRequired


                    WindowsPendingRestart =
                        [bool]$WindowsPendingRestart.Pending


                    WindowsPendingRestartReasons =
                        @(
                            $WindowsPendingRestart.Reasons
                        )
                }


            FixedDevices =
                @(
                    $FixedDevices
                )


            RemainingDevices =
                @(
                    $RemainingDevices
                )


            NewErrors =
                @(
                    $NewErrors
                )


            RestartDevices =
                @(
                    $RestartDevices
                )


            DriverSnapshots =
                [pscustomobject]@{

                    BeforeFile =
                        $DriverSnapshotBeforeFile

                    AfterFile =
                        $DriverSnapshotAfterFile

                    BeforeCount =
                        @($DriverSnapshotBefore).Count

                    AfterCount =
                        @($DriverSnapshotAfter).Count
                }


            DriverChanges =
                [pscustomobject]@{

                    ChangedCount =
                        @($DriverComparison.Changed).Count

                    AddedCount =
                        @($DriverComparison.Added).Count

                    RemovedCount =
                        @($DriverComparison.Removed).Count

                    Changed =
                        @(
                            $DriverComparison.Changed
                        )

                    Added =
                        @(
                            $DriverComparison.Added
                        )

                    Removed =
                        @(
                            $DriverComparison.Removed
                        )
                }


            OEMTools =
                @(
                    $OEMToolInventory
                )


            OEMUpdateResult =
                $OEMUpdateResult
        }


    # ========================================================
    # SAVE VERIFICATION REPORT
    # ========================================================

    $Verification |
        ConvertTo-Json `
            -Depth 8 |
        Set-Content `
            -LiteralPath $VerificationFile `
            -Encoding UTF8


    Write-Log -Message (
        "Verification report saved to '$VerificationFile'."
    )


    # ========================================================
    # CONSOLE SUMMARY
    # ========================================================

    Write-Host ''
    Write-Host '========================================'
    Write-Host 'Driver Verification Summary'
    Write-Host '========================================'
    Write-Host "Before errors   : $BeforeCount"
    Write-Host "After errors    : $AfterCount"
    Write-Host "Fixed           : $FixedCount"
    Write-Host "Remaining       : $RemainingCount"
    Write-Host "New errors      : $NewCount"
    Write-Host "Restart devices : $RestartDeviceCount"
    Write-Host "Restart         : $RestartRequired"
    Write-Host "Status          : $Status"
    Write-Host '========================================'
    Write-Host ''


    Write-OEMToolInventorySummary `
        -Inventory $OEMToolInventory


    Write-DriverChangeSummary `
        -Comparison $DriverComparison


    # ========================================================
    # FINAL LOGGING
    # ========================================================

    if (
        $RemainingCount -eq 0 -and
        $NewCount -eq 0
    ) {

        Write-Log -Message (
            'Driver verification completed successfully. ' +
            'No Plug and Play device errors detected.'
        )
    }
    else {

        Write-Log `
            -Message (
                'Driver verification completed with Plug and Play ' +
                'device errors still present.'
            ) `
            -Level 'WARNING'
    }


    if ($RestartRequired) {

        Write-Log `
            -Message (
                'Verification indicates that a restart is required.'
            ) `
            -Level 'WARNING'


        Stop-LogRun `
            -RunID $RunID `
            -Result 'SUCCESS - RESTART REQUIRED'
    }
    elseif (
        $RemainingCount -gt 0 -or
        $NewCount -gt 0
    ) {

        Stop-LogRun `
            -RunID $RunID `
            -Result 'COMPLETED WITH DEVICE ERRORS'
    }
    else {

        Stop-LogRun `
            -RunID $RunID `
            -Result 'SUCCESS'
    }


    # ========================================================
    # SUCCESSFUL SCRIPT EXECUTION
    # ========================================================
    #
    # Driver problems are represented in DriverVerification.json.
    #
    # Exit 1 is reserved for an actual script failure.
    # ========================================================

    exit 0
}
catch {

    $ErrorMessage =
        $_.Exception.Message


    try {

        Write-Log `
            -Message $ErrorMessage `
            -Level 'ERROR'


        if (
            $_.InvocationInfo.ScriptLineNumber
        ) {

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