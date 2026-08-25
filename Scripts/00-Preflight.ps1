<#
.SYNOPSIS
    Performs prerequisite checks for the ITINO Driver Deployment workflow.

.DESCRIPTION
    Stage 0 of Driver Check And Update.

    The script verifies that the machine is ready before scripts 01-04 run.

    Default mode:
        Full

    Optional modes:
        Full
        BeforeOEM
        BeforeDrivers
        BeforeVerify

    Creates:
        C:\ProgramData\Itino\DriverDeployment\Preflight.json

    Logging:
        Controlled by ITINO_WRITE_LOG_FILES.

    Administrator requirement:
        Controlled by ITINO_REQUIRE_ADMINISTRATOR.

    Preflight requirements are controlled by Run-DriverDeployment.ps1 through:
        ITINO_MINIMUM_SYSTEM_DRIVE_FREE_GB
        ITINO_WEB_TIMEOUT_SECONDS
        ITINO_MINIMUM_POWERSHELL_MAJOR_VERSION

.EXIT CODES
    0 = Preflight passed
    1 = One or more blocking checks failed

.NOTES
    This script does not restart Windows and does not install or modify drivers.
#>

[CmdletBinding()]
param(
    [ValidateSet(
        'Full',
        'BeforeOEM',
        'BeforeDrivers',
        'BeforeVerify'
    )]
    [string]$Mode = 'Full'
)

$ErrorActionPreference = 'Stop'


# ============================================================
# ENVIRONMENT OPTION HELPERS
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


function Get-ItinoIntegerOption {

    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentVariable,

        [Parameter(Mandatory)]
        [int]$DefaultValue,

        [int]$MinimumValue = 0
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

    $ParsedValue = 0

    if (
        -not (
            [int]::TryParse(
                $Value,
                [ref]$ParsedValue
            )
        )
    ) {

        return $DefaultValue
    }

    if (
        $ParsedValue -lt $MinimumValue
    ) {

        return $DefaultValue
    }

    return $ParsedValue
}


# ============================================================
# OPTIONS FROM MAIN CONTROLLER
# ============================================================

$WriteLogFiles =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_WRITE_LOG_FILES' `
        -DefaultValue $true


$RequireAdministrator =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_REQUIRE_ADMINISTRATOR' `
        -DefaultValue $true


$MinimumSystemDriveFreeGB =
    Get-ItinoIntegerOption `
        -EnvironmentVariable 'ITINO_MINIMUM_SYSTEM_DRIVE_FREE_GB' `
        -DefaultValue 10 `
        -MinimumValue 1


$WebTimeoutSeconds =
    Get-ItinoIntegerOption `
        -EnvironmentVariable 'ITINO_WEB_TIMEOUT_SECONDS' `
        -DefaultValue 15 `
        -MinimumValue 1


$MinimumPowerShellMajorVersion =
    Get-ItinoIntegerOption `
        -EnvironmentVariable 'ITINO_MINIMUM_POWERSHELL_MAJOR_VERSION' `
        -DefaultValue 5 `
        -MinimumValue 1


# ============================================================
# PATHS
# ============================================================

$BasePath =
    'C:\ProgramData\Itino\DriverDeployment'


$LogsPath =
    Join-Path `
        $BasePath `
        'Logs'


$LogFile =
    Join-Path `
        $LogsPath `
        'Preflight.log'


$PreflightFile =
    Join-Path `
        $BasePath `
        'Preflight.json'


$RequiredScripts =
    @(
        '01-Gather-Hardware.ps1'
        '02-Install-OEM-Update-Tool.ps1'
        '03-Update-Drivers.ps1'
        '04-Verify-Drivers.ps1'
    )


# ============================================================
# CREATE WORKING DIRECTORIES
# ============================================================

if (
    -not (
        Test-Path -LiteralPath $BasePath
    )
) {

    New-Item `
        -Path $BasePath `
        -ItemType Directory `
        -Force |
    Out-Null
}


if ($WriteLogFiles) {

    if (
        -not (
            Test-Path -LiteralPath $LogsPath
        )
    ) {

        New-Item `
            -Path $LogsPath `
            -ItemType Directory `
            -Force |
        Out-Null
    }
}


# ============================================================
# RUN INFORMATION
# ============================================================

$RunId =
    (
        Get-Date -Format 'yyyyMMdd-HHmmss'
    ) +
    '-' +
    (
        [guid]::NewGuid().
            ToString('N').
            Substring(0, 4).
            ToUpper()
    )


$StartTime =
    Get-Date


$CheckResults =
    New-Object `
        'System.Collections.Generic.List[object]'


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

    $Entry =
        "[$TimeStamp] [$Level] $Message"

    Write-Host $Entry

    if ($WriteLogFiles) {

        Add-Content `
            -LiteralPath $LogFile `
            -Value $Entry `
            -Encoding UTF8
    }
}


function Write-RunHeader {

    $Lines =
        @(
            '==========================================================================='
            'NEW SCRIPT RUN'
            '==========================================================================='
            "Run ID       : $RunId"
            "Script       : $([System.IO.Path]::GetFileName($PSCommandPath))"
            "Computer     : $env:COMPUTERNAME"
            "Mode         : $Mode"
            "Start Time   : $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
            '==========================================================================='
            ''
        )

    foreach ($Line in $Lines) {

        Write-Host $Line

        if ($WriteLogFiles) {

            Add-Content `
                -LiteralPath $LogFile `
                -Value $Line `
                -Encoding UTF8
        }
    }
}


function Write-RunFooter {

    param(
        [Parameter(Mandatory)]
        [string]$Result
    )

    $EndTime =
        Get-Date

    $Lines =
        @(
            ''
            '==========================================================================='
            'END SCRIPT RUN'
            '==========================================================================='
            "Run ID       : $RunId"
            "Result       : $Result"
            "End Time     : $($EndTime.ToString('yyyy-MM-dd HH:mm:ss'))"
            '==========================================================================='
        )

    foreach ($Line in $Lines) {

        Write-Host $Line

        if ($WriteLogFiles) {

            Add-Content `
                -LiteralPath $LogFile `
                -Value $Line `
                -Encoding UTF8
        }
    }
}


# ============================================================
# RESULT HANDLING
# ============================================================

function Add-PreflightResult {

    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Passed,

        [Parameter(Mandatory)]
        [ValidateSet(
            'BLOCKING',
            'WARNING',
            'INFO'
        )]
        [string]$Severity,

        [Parameter(Mandatory)]
        [string]$Message,

        [AllowNull()]
        [object]$Value = $null
    )

    $Result =
        [PSCustomObject]@{
            Name = $Name
            Passed = $Passed
            Severity = $Severity
            Message = $Message
            Value = $Value
        }

    [void]$CheckResults.Add(
        $Result
    )

    if ($Passed) {

        Write-Log -Message (
            "PASS: $Name - $Message"
        )
    }
    elseif ($Severity -eq 'BLOCKING') {

        Write-Log `
            -Message (
                "FAIL: $Name - $Message"
            ) `
            -Level 'ERROR'
    }
    else {

        Write-Log `
            -Message (
                "WARN: $Name - $Message"
            ) `
            -Level 'WARNING'
    }
}


# ============================================================
# ADMINISTRATOR CHECK
# ============================================================

function Test-IsAdministrator {

    try {

        $Identity =
            [Security.Principal.WindowsIdentity]::GetCurrent()

        $Principal =
            New-Object `
                Security.Principal.WindowsPrincipal(
                    $Identity
                )

        return (
            $Principal.IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator
            )
        )
    }
    catch {

        return $false
    }
}


# ============================================================
# WRITABLE DIRECTORY TEST
# ============================================================

function Test-DirectoryWritable {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {

        if (
            -not (
                Test-Path -LiteralPath $Path
            )
        ) {

            New-Item `
                -Path $Path `
                -ItemType Directory `
                -Force |
            Out-Null
        }

        $TestFile =
            Join-Path `
                $Path `
                (
                    '.itino-write-test-' +
                    [guid]::NewGuid().ToString('N') +
                    '.tmp'
                )

        'ITINO' |
            Set-Content `
                -LiteralPath $TestFile `
                -Encoding ASCII `
                -ErrorAction Stop

        Remove-Item `
            -LiteralPath $TestFile `
            -Force `
            -ErrorAction Stop

        return $true
    }
    catch {

        return $false
    }
}


# ============================================================
# HTTPS CONNECTIVITY TEST
# ============================================================

function Test-WebConnectivity {

    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [int]$TimeoutSeconds = 15
    )


    try {

        $Response =
            Invoke-WebRequest `
                -Uri $Url `
                -UseBasicParsing `
                -Method Get `
                -TimeoutSec $TimeoutSeconds `
                -ErrorAction Stop


        if (
            $Response.StatusCode -ge 200 -and
            $Response.StatusCode -lt 400
        ) {

            return $true
        }


        return $false
    }
    catch {

        return $false
    }
}


# ============================================================
# PENDING RESTART DETECTION
# ============================================================

function Get-PendingRestartInformation {

    $Reasons =
        New-Object `
            'System.Collections.Generic.List[string]'


    # ========================================================
    # COMPONENT BASED SERVICING
    # ========================================================

    $CBSRebootPending =
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'


    if (
        Test-Path -LiteralPath $CBSRebootPending
    ) {

        [void]$Reasons.Add(
            'CBS: RebootPending'
        )
    }


    # ========================================================
    # WINDOWS UPDATE
    # ========================================================

    $WURebootRequired =
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'


    if (
        Test-Path -LiteralPath $WURebootRequired
    ) {

        [void]$Reasons.Add(
            'Windows Update: RebootRequired'
        )
    }


    # ========================================================
    # UPDATE.EXE VOLATILE STATE
    # ========================================================

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

            [void]$Reasons.Add(
                "Windows Updates: UpdateExeVolatile=$($UpdateExeVolatile.UpdateExeVolatile)"
            )
        }
    }
    catch {
    }


    # ========================================================
    # PENDING FILE RENAME OPERATIONS
    # ========================================================

    try {

        $SessionManager =
            Get-ItemProperty `
                -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
                -ErrorAction SilentlyContinue


        if (
            $SessionManager.PendingFileRenameOperations
        ) {

            [void]$Reasons.Add(
                'Session Manager: PendingFileRenameOperations'
            )
        }


        if (
            $SessionManager.PendingFileRenameOperations2
        ) {

            [void]$Reasons.Add(
                'Session Manager: PendingFileRenameOperations2'
            )
        }
    }
    catch {
    }


    # ========================================================
    # PENDING COMPUTER RENAME
    # ========================================================

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

            [void]$Reasons.Add(
                "Computer rename pending: '$ActiveComputerName' -> '$ConfiguredComputerName'"
            )
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
# SERVICE CHECK
# ============================================================

function Get-ServiceReadiness {

    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    try {

        $Service =
            Get-CimInstance `
                -ClassName Win32_Service `
                -Filter "Name='$Name'" `
                -ErrorAction Stop

        if (-not $Service) {

            return [PSCustomObject]@{
                Exists = $false
                Disabled = $false
                State = $null
                StartMode = $null
            }
        }

        return [PSCustomObject]@{
            Exists = $true
            Disabled = ($Service.StartMode -eq 'Disabled')
            State = $Service.State
            StartMode = $Service.StartMode
        }
    }
    catch {

        return [PSCustomObject]@{
            Exists = $false
            Disabled = $false
            State = $null
            StartMode = $null
        }
    }
}


# ============================================================
# SAVE REPORT
# ============================================================

function Save-PreflightReport {

    param(
        [Parameter(Mandatory)]
        [bool]$Ready,

        [AllowNull()]
        [object]$ComputerInformation,

        [AllowNull()]
        [object]$OperatingSystemInformation,

        [AllowNull()]
        [object]$PendingRestartInformation
    )

    $EndTime =
        Get-Date

    $BlockingFailures =
        @(
            $CheckResults |
            Where-Object {
                -not $_.Passed -and
                $_.Severity -eq 'BLOCKING'
            }
        )

    $Warnings =
        @(
            $CheckResults |
            Where-Object {
                -not $_.Passed -and
                $_.Severity -eq 'WARNING'
            }
        )

    $CheckResultsArray =
        @(
            foreach (
                $CheckResult in $CheckResults
            ) {

                $CheckResult
            }
        )

    $Manufacturer = $null
    $Model = $null
    $WindowsCaption = $null
    $WindowsVersion = $null
    $WindowsBuild = $null
    $PendingRestartValue = $false
    $PendingRestartReasons = @()

    if ($ComputerInformation) {
        $Manufacturer = [string]$ComputerInformation.Manufacturer
        $Model = [string]$ComputerInformation.Model
    }

    if ($OperatingSystemInformation) {
        $WindowsCaption = [string]$OperatingSystemInformation.Caption
        $WindowsVersion = [string]$OperatingSystemInformation.Version
        $WindowsBuild = [string]$OperatingSystemInformation.BuildNumber
    }

    if ($PendingRestartInformation) {
        $PendingRestartValue = [bool]$PendingRestartInformation.Pending
        $PendingRestartReasons =
            @(
                foreach (
                    $Reason in $PendingRestartInformation.Reasons
                ) {

                    [string]$Reason
                }
            )
    }

    $Report =
        [PSCustomObject]@{
            RunId = $RunId
            Mode = $Mode
            ComputerName = $env:COMPUTERNAME
            StartTime = $StartTime.ToString('yyyy-MM-dd HH:mm:ss')
            EndTime = $EndTime.ToString('yyyy-MM-dd HH:mm:ss')
            DurationSeconds = [math]::Round(
                ($EndTime - $StartTime).TotalSeconds,
                1
            )
            Ready = $Ready
            BlockingFailureCount = $BlockingFailures.Count
            WarningCount = $Warnings.Count
            Manufacturer = $Manufacturer
            Model = $Model
            WindowsCaption = $WindowsCaption
            WindowsVersion = $WindowsVersion
            WindowsBuild = $WindowsBuild
            PendingRestart = $PendingRestartValue
            PendingRestartReasons = $PendingRestartReasons
            Requirements = [PSCustomObject]@{
                MinimumSystemDriveFreeGB = $MinimumSystemDriveFreeGB
                WebTimeoutSeconds = $WebTimeoutSeconds
                MinimumPowerShellMajorVersion = $MinimumPowerShellMajorVersion
                RequireAdministrator = $RequireAdministrator
            }
            Checks = $CheckResultsArray
        }

    $Report |
        ConvertTo-Json `
            -Depth 8 |
        Set-Content `
            -LiteralPath $PreflightFile `
            -Encoding UTF8
}


# ============================================================
# MAIN
# ============================================================

Write-RunHeader

$ComputerSystem =
    $null

$OperatingSystem =
    $null

$PendingRestart =
    $null


try {

    Write-Log -Message (
        "Starting preflight checks in mode '$Mode'."
    )

    Write-Log -Message (
        "Require administrator: $RequireAdministrator"
    )

    Write-Log -Message (
        "Minimum system drive free space: $MinimumSystemDriveFreeGB GB"
    )

    Write-Log -Message (
        "Web connectivity timeout: $WebTimeoutSeconds seconds"
    )

    Write-Log -Message (
        "Minimum PowerShell major version: $MinimumPowerShellMajorVersion"
    )


    # ========================================================
    # POWERSHELL VERSION
    # ========================================================

    $CurrentPowerShellMajorVersion =
        [int]$PSVersionTable.PSVersion.Major

    $PowerShellVersionPassed =
        $CurrentPowerShellMajorVersion -ge
        $MinimumPowerShellMajorVersion

    $PowerShellVersionMessage =
        (
            "PowerShell version is $($PSVersionTable.PSVersion). " +
            "Minimum required major version: " +
            "$MinimumPowerShellMajorVersion."
        )

    Add-PreflightResult `
        -Name 'PowerShellVersion' `
        -Passed $PowerShellVersionPassed `
        -Severity 'BLOCKING' `
        -Message $PowerShellVersionMessage `
        -Value $PSVersionTable.PSVersion.ToString()


    # ========================================================
    # ADMINISTRATOR
    # ========================================================

    $IsAdministrator =
        Test-IsAdministrator

    if ($RequireAdministrator) {

        if ($IsAdministrator) {
            $AdministratorMessage =
                'Process is running elevated as administrator.'
        }
        else {
            $AdministratorMessage =
                'Production mode requires an elevated administrator token.'
        }

        Add-PreflightResult `
            -Name 'Administrator' `
            -Passed $IsAdministrator `
            -Severity 'BLOCKING' `
            -Message $AdministratorMessage `
            -Value $IsAdministrator
    }
    else {

        if ($IsAdministrator) {
            $AdministratorMessage =
                'Process is running elevated as administrator.'
        }
        else {
            $AdministratorMessage =
                'Non-elevated development mode is enabled.'
        }

        Add-PreflightResult `
            -Name 'Administrator' `
            -Passed $IsAdministrator `
            -Severity 'WARNING' `
            -Message $AdministratorMessage `
            -Value $IsAdministrator
    }


    # ========================================================
    # REQUIRED SCRIPTS
    # ========================================================

    if ($Mode -eq 'Full') {

        foreach ($RequiredScript in $RequiredScripts) {

            $RequiredScriptPath =
                Join-Path `
                    $PSScriptRoot `
                    $RequiredScript

            $Exists =
                Test-Path -LiteralPath $RequiredScriptPath

            if ($Exists) {
                $RequiredScriptMessage =
                    "Required script found: $RequiredScript"
            }
            else {
                $RequiredScriptMessage =
                    "Required script missing: $RequiredScriptPath"
            }

            Add-PreflightResult `
                -Name "RequiredScript:$RequiredScript" `
                -Passed $Exists `
                -Severity 'BLOCKING' `
                -Message $RequiredScriptMessage `
                -Value $RequiredScriptPath
        }
    }


    # ========================================================
    # WORKING DIRECTORY WRITE ACCESS
    # ========================================================

    if (
        $Mode -in @(
            'Full',
            'BeforeOEM',
            'BeforeDrivers',
            'BeforeVerify'
        )
    ) {

        $Writable =
            Test-DirectoryWritable `
                -Path $BasePath

        if ($Writable) {
            $WritableMessage =
                "$BasePath is writable."
        }
        else {
            $WritableMessage =
                "$BasePath is not writable."
        }

        Add-PreflightResult `
            -Name 'DriverDeploymentPathWritable' `
            -Passed $Writable `
            -Severity 'BLOCKING' `
            -Message $WritableMessage `
            -Value $BasePath
    }


    # ========================================================
    # CIM / HARDWARE / WINDOWS
    # ========================================================

    try {

        $ComputerSystem =
            Get-CimInstance `
                -ClassName Win32_ComputerSystem `
                -ErrorAction Stop

        $OperatingSystem =
            Get-CimInstance `
                -ClassName Win32_OperatingSystem `
                -ErrorAction Stop

        Add-PreflightResult `
            -Name 'CIM' `
            -Passed $true `
            -Severity 'BLOCKING' `
            -Message 'CIM hardware and operating system queries succeeded.' `
            -Value (
                "$($ComputerSystem.Manufacturer) $($ComputerSystem.Model)"
            )
    }
    catch {

        Add-PreflightResult `
            -Name 'CIM' `
            -Passed $false `
            -Severity 'BLOCKING' `
            -Message (
                "CIM query failed: $($_.Exception.Message)"
            )
    }


    # ========================================================
    # WINDOWS VERSION
    # ========================================================

    if ($OperatingSystem) {

        $WindowsVersionObject =
            $null

        try {
            $WindowsVersionObject =
                [version]$OperatingSystem.Version
        }
        catch {
        }

        $SupportedWindows =
            $false

        if ($WindowsVersionObject) {
            $SupportedWindows =
                $WindowsVersionObject.Major -ge 10
        }

        $WindowsMessage =
            (
                "$($OperatingSystem.Caption), version " +
                "$($OperatingSystem.Version), build " +
                "$($OperatingSystem.BuildNumber)."
            )

        Add-PreflightResult `
            -Name 'WindowsVersion' `
            -Passed $SupportedWindows `
            -Severity 'BLOCKING' `
            -Message $WindowsMessage `
            -Value $OperatingSystem.Version
    }


    # ========================================================
    # SYSTEM DRIVE FREE SPACE
    # ========================================================

    if (
        $Mode -in @(
            'Full',
            'BeforeOEM',
            'BeforeDrivers'
        )
    ) {

        try {

            $Disk =
                Get-CimInstance `
                    -ClassName Win32_LogicalDisk `
                    -Filter "DeviceID='$($env:SystemDrive)'" `
                    -ErrorAction Stop

            if (-not $Disk) {
                throw (
                    "System drive $($env:SystemDrive) could not be found."
                )
            }

            $FreeGB =
                [math]::Round(
                    $Disk.FreeSpace / 1GB,
                    2
                )

            $DiskPassed =
                $FreeGB -ge $MinimumSystemDriveFreeGB

            $DiskMessage =
                (
                    "$($env:SystemDrive) has $FreeGB GB free. " +
                    "Minimum required: $MinimumSystemDriveFreeGB GB."
                )

            Add-PreflightResult `
                -Name 'SystemDriveFreeSpace' `
                -Passed $DiskPassed `
                -Severity 'BLOCKING' `
                -Message $DiskMessage `
                -Value $FreeGB
        }
        catch {

            Add-PreflightResult `
                -Name 'SystemDriveFreeSpace' `
                -Passed $false `
                -Severity 'BLOCKING' `
                -Message (
                    'Unable to determine system drive free space. ' +
                    "Reason: $($_.Exception.Message)"
                )
        }
    }


    # ========================================================
    # TLS 1.2 SUPPORT
    # ========================================================

    if (
        $Mode -in @(
            'Full',
            'BeforeOEM',
            'BeforeDrivers'
        )
    ) {

        $Tls12Available =
            $false

        try {
            $Tls12Value =
                [Net.SecurityProtocolType]::Tls12

            $Tls12Available =
                $true
        }
        catch {
            $Tls12Available =
                $false
        }

        if ($Tls12Available) {
            $TlsMessage =
                'TLS 1.2 is available to Windows PowerShell.'
        }
        else {
            $TlsMessage =
                'TLS 1.2 is not available.'
        }

        Add-PreflightResult `
            -Name 'TLS12' `
            -Passed $Tls12Available `
            -Severity 'BLOCKING' `
            -Message $TlsMessage `
            -Value $Tls12Available

        if ($Tls12Available) {

            [Net.ServicePointManager]::SecurityProtocol =
                [Net.ServicePointManager]::SecurityProtocol -bor
                [Net.SecurityProtocolType]::Tls12
        }
    }


    # ========================================================
    # INTERNET / HTTPS CONNECTIVITY
    # ========================================================

    if (
        $Mode -in @(
            'Full',
            'BeforeOEM',
            'BeforeDrivers'
        )
    ) {

        $InternetTestUrls =
            @(
                'https://www.msftconnecttest.com/connecttest.txt'
                'https://www.microsoft.com'
            )


        $InternetAvailable =
            $false


        $SuccessfulInternetUrl =
            $null


        foreach (
            $TestUrl in $InternetTestUrls
        ) {

            if (
                Test-WebConnectivity `
                    -Url $TestUrl `
                    -TimeoutSeconds $WebTimeoutSeconds
            ) {

                $InternetAvailable =
                    $true


                $SuccessfulInternetUrl =
                    $TestUrl


                break
            }
        }


        if ($InternetAvailable) {

            $InternetMessage =
                (
                    'HTTPS internet connectivity is available. ' +
                    "Successful endpoint: $SuccessfulInternetUrl"
                )
        }
        else {

            $InternetMessage =
                (
                    'Unable to establish HTTPS internet connectivity. ' +
                    'All configured connectivity endpoints failed.'
                )
        }


        Add-PreflightResult `
            -Name 'InternetHTTPS' `
            -Passed $InternetAvailable `
            -Severity 'BLOCKING' `
            -Message $InternetMessage `
            -Value ($InternetTestUrls -join '; ')
    }


    # ========================================================
    # OEM DOWNLOAD ENDPOINT
    # ========================================================

    if (
        $Mode -in @(
            'Full',
            'BeforeOEM',
            'BeforeDrivers'
        ) -and
        $ComputerSystem
    ) {

        $Manufacturer =
            [string]$ComputerSystem.Manufacturer

        $OEMUrl =
            $null

        $OEMName =
            $null

        switch -Regex ($Manufacturer) {

            'Dell' {
                $OEMName = 'Dell'
                $OEMUrl = 'https://dl.dell.com'
                break
            }

            'HP|Hewlett-Packard|Hewlett Packard' {
                $OEMName = 'HP'
                $OEMUrl = 'https://hpia.hpcloud.hp.com'
                break
            }

            'Lenovo' {
                $OEMName = 'Lenovo'
                $OEMUrl = 'https://download.lenovo.com'
                break
            }

            default {
                $OEMName = 'Other'
            }
        }

        if ($OEMUrl) {

            $OEMReachable =
                Test-WebConnectivity `
                    -Url $OEMUrl `
                    -TimeoutSeconds $WebTimeoutSeconds

            if ($OEMReachable) {
                $OEMMessage =
                    "$OEMName download endpoint is reachable."
            }
            else {
                $OEMMessage =
                    (
                        "$OEMName download endpoint could not be reached. " +
                        'Script 02 may still try its configured fallback.'
                    )
            }

            Add-PreflightResult `
                -Name 'OEMEndpoint' `
                -Passed $OEMReachable `
                -Severity 'WARNING' `
                -Message $OEMMessage `
                -Value $OEMUrl
        }
        else {

            Add-PreflightResult `
                -Name 'OEMEndpoint' `
                -Passed $true `
                -Severity 'INFO' `
                -Message (
                    "Manufacturer '$Manufacturer' does not use a configured " +
                    'OEM utility. Windows Update will be used.'
                ) `
                -Value $Manufacturer
        }
    }


    # ========================================================
    # WINDOWS UPDATE SERVICE
    # ========================================================

    if (
        $Mode -in @(
            'Full',
            'BeforeDrivers'
        )
    ) {

        $WindowsUpdateService =
            Get-ServiceReadiness `
                -Name 'wuauserv'

        $WUPassed =
            $WindowsUpdateService.Exists -and
            -not $WindowsUpdateService.Disabled

        if (-not $WindowsUpdateService.Exists) {
            $WUMessage =
                'Windows Update service was not found.'
        }
        elseif ($WindowsUpdateService.Disabled) {
            $WUMessage =
                'Windows Update service is disabled.'
        }
        else {
            $WUMessage =
                (
                    'Windows Update service exists. State: ' +
                    "$($WindowsUpdateService.State), StartMode: " +
                    "$($WindowsUpdateService.StartMode)."
                )
        }

        Add-PreflightResult `
            -Name 'WindowsUpdateService' `
            -Passed $WUPassed `
            -Severity 'BLOCKING' `
            -Message $WUMessage `
            -Value $WindowsUpdateService


        $BITSService =
            Get-ServiceReadiness `
                -Name 'BITS'

        $BITSPassed =
            $BITSService.Exists -and
            -not $BITSService.Disabled

        if (-not $BITSService.Exists) {
            $BITSMessage =
                'BITS service was not found.'
        }
        elseif ($BITSService.Disabled) {
            $BITSMessage =
                'BITS service is disabled.'
        }
        else {
            $BITSMessage =
                (
                    "BITS service exists. State: $($BITSService.State), " +
                    "StartMode: $($BITSService.StartMode)."
                )
        }

        Add-PreflightResult `
            -Name 'BITSService' `
            -Passed $BITSPassed `
            -Severity 'BLOCKING' `
            -Message $BITSMessage `
            -Value $BITSService
    }


    # ========================================================
    # PENDING RESTART
    # ========================================================

    if ($Mode -eq 'Full') {

        $PendingRestart =
            Get-PendingRestartInformation

        if ($PendingRestart.Pending) {
            $PendingRestartMessage =
                (
                    'Windows already reports a pending restart before the ' +
                    'driver workflow starts. The workflow will continue, ' +
                    'but this is recorded for diagnostics.'
                )
        }
        else {
            $PendingRestartMessage =
                'No existing Windows pending restart was detected.'
        }

        Add-PreflightResult `
            -Name 'PendingRestartBeforeDeployment' `
            -Passed (-not $PendingRestart.Pending) `
            -Severity 'WARNING' `
            -Message $PendingRestartMessage `
            -Value @($PendingRestart.Reasons)
    }


    # ========================================================
    # SYSTEM CLOCK SANITY
    # ========================================================

    if (
        $Mode -in @(
            'Full',
            'BeforeOEM',
            'BeforeDrivers'
        )
    ) {

        $CurrentDate =
            Get-Date

        $CurrentYear =
            $CurrentDate.Year

        $ClockLooksSane =
            $CurrentYear -ge 2024 -and
            $CurrentYear -le 2100

        if ($ClockLooksSane) {
            $ClockMessage =
                (
                    'System date is ' +
                    $CurrentDate.ToString('yyyy-MM-dd HH:mm:ss') +
                    '.'
                )
        }
        else {
            $ClockMessage =
                (
                    'System clock appears invalid. HTTPS and digital ' +
                    'signature checks may fail.'
                )
        }

        Add-PreflightResult `
            -Name 'SystemClock' `
            -Passed $ClockLooksSane `
            -Severity 'WARNING' `
            -Message $ClockMessage `
            -Value $CurrentDate.ToString('yyyy-MM-dd HH:mm:ss')
    }


    # ========================================================
    # FINAL RESULT
    # ========================================================

    $BlockingFailures =
        @(
            $CheckResults |
            Where-Object {
                -not $_.Passed -and
                $_.Severity -eq 'BLOCKING'
            }
        )

    $Warnings =
        @(
            $CheckResults |
            Where-Object {
                -not $_.Passed -and
                $_.Severity -eq 'WARNING'
            }
        )

    $Ready =
        $BlockingFailures.Count -eq 0

    Save-PreflightReport `
        -Ready $Ready `
        -ComputerInformation $ComputerSystem `
        -OperatingSystemInformation $OperatingSystem `
        -PendingRestartInformation $PendingRestart

    Write-Log -Message (
        "Preflight report saved to '$PreflightFile'."
    )

    Write-Host ''
    Write-Host '============================================================'
    Write-Host 'Preflight Summary'
    Write-Host '============================================================'
    Write-Host ''
    Write-Host "Mode              : $Mode"
    Write-Host "Checks            : $($CheckResults.Count)"
    Write-Host "Blocking failures : $($BlockingFailures.Count)"
    Write-Host "Warnings          : $($Warnings.Count)"
    Write-Host "Ready             : $Ready"
    Write-Host ''
    Write-Host '============================================================'

    if ($Ready) {

        Write-RunFooter `
            -Result 'SUCCESS'

        exit 0
    }

    Write-RunFooter `
        -Result 'FAILED'

    exit 1
}
catch {

    $FailureMessage =
        $_.Exception.Message

    try {

        Add-PreflightResult `
            -Name 'UnhandledPreflightError' `
            -Passed $false `
            -Severity 'BLOCKING' `
            -Message $FailureMessage

        Save-PreflightReport `
            -Ready $false `
            -ComputerInformation $ComputerSystem `
            -OperatingSystemInformation $OperatingSystem `
            -PendingRestartInformation $PendingRestart
    }
    catch {
    }

    Write-Log `
        -Message (
            "Preflight failed unexpectedly: $FailureMessage"
        ) `
        -Level 'ERROR'

    Write-RunFooter `
        -Result 'FAILED'

    exit 1
}