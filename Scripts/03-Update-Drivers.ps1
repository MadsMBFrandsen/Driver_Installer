<#
.SYNOPSIS
    Updates device drivers.

.DESCRIPTION
    Stage 3 of the ITINO Driver Check And Update workflow.

    Dell:
        Dell Command Update
        Windows Update fallback if OEM update fails

    HP:
        HP Image Assistant
        Windows Update fallback if OEM update fails

    Lenovo:
        1. Initial Windows Update
        2. Lenovo System Update using tvsuShim.exe
        3. Final Windows Update

    Other:
        Windows Update

    Windows Update:
        - Fresh scan
        - Download driver updates
        - Install driver updates
        - Repeat until 0 remain
        - Maximum 5 passes
        - Maximum 3 download attempts per pass

    Lenovo Hotkey Installer:
        - A watcher starts before Windows Update installs drivers
        - New visible setup.exe dialogs are detected
        - The completion window is closed gracefully
        - No forceful process termination is used

.EXIT CODES
    0    Success
    1    Failure
    3010 Success, restart required

.NOTES
    This script never restarts Windows.
#>

[CmdletBinding()]
param()

# ============================================================
# ITINO DRIVER UPDATE SCRIPT
# ============================================================

$ScriptName =
    '03-Update-Drivers.ps1'


# ============================================================
# VERSION HISTORY
# ============================================================

# ------------------------------------------------------------
# Title   : OEM-Specific Startup Logging
# Version : 1.4.0
# Reason  : Generic firmware safety status is shown on all OEMs.
#           Lenovo-only options are logged only on Lenovo PCs.
# Date    : 2026-08-26
# ------------------------------------------------------------


# ------------------------------------------------------------
# Title   : Deployment Sequence Firmware Safety
# Version : 1.3.8
# Reason  : Adds controller-driven BIOS/Firmware power safety.
#           Normal driver updates continue even when firmware
#           updates are blocked by the safety gate.
# Date    : 2026-08-25
# ------------------------------------------------------------


# ------------------------------------------------------------
# Title   : Dell Phase 1/2 Merge
# Version : 1.3.7
# Reason  : Merged Dell Command Update scan-before-apply,
#           stale scan protection, documented exit-code
#           interpretation and retry handling into the newer
#           Lenovo/Windows Update branch. Preserves LSUClient
#           reboot-pending suppression, repaired catalog cache
#           reuse and Windows Update download activity monitor.
# Date    : 2026-08-24
# ------------------------------------------------------------

# ------------------------------------------------------------
# Title   : Windows Update Download Activity Monitor
# Version : 1.3.6
# Reason  : Adds a native download-cache activity monitor while
#           the existing Windows Update batch Download() call is
#           running. This shows whether download data is still
#           changing without changing the known-good 5-pass
#           Windows Update or batch download/install behavior.
# Date    : 2026-08-21
# ------------------------------------------------------------

# ------------------------------------------------------------
# Title   : LSUClient Reliability and Recovery Cache
# Version : 1.3.5
# Reason  : Treats LSUClient Success=False install results as
#           real update failures so the existing Lenovo System
#           Update fallback can take over. Also builds the
#           repaired Lenovo catalog once and reuses it across
#           later LSUClient rounds during the same script run.
# Date    : 2026-08-21
# ------------------------------------------------------------

# ------------------------------------------------------------
# Title   : Skip Repeated LSUClient Reboot-Pending Updates
# Version : 1.3.4
# Reason  : Tracks Lenovo updates successfully installed during
#           the current run when they request a restart. If the
#           same package and version is still reported in a
#           later LSUClient round, it is skipped instead of
#           being installed repeatedly before the restart.
# Date    : 2026-08-20
# ------------------------------------------------------------

# ------------------------------------------------------------
# Title   : Clear Lenovo Recovery Logging
# Version : 1.3.3
# Reason  : Changed successful Lenovo catalog-recovery messages
#           so expected recovery actions are shown as recovery
#           information instead of repeated warnings. No update
#           engine behavior was changed.
# Date    : 2026-08-20
# ------------------------------------------------------------

# ------------------------------------------------------------
# Title   : LSU Internal Reference Recovery
# Version : 1.3.2
# Reason  : Added validation of internal Lenovo package file
#           references. Packages with broken referenced files
#           are removed before LSUClient retries.
# Date    : 2026-08-20
# ------------------------------------------------------------

# ------------------------------------------------------------
# Title   : Lenovo Fallback Fix
# Version : 1.3.1
# Reason  : Fixed tvsuShim exit-code capture and improved
#           LSUClient mirrored repository recovery.
# Date    : 2026-08-20
# ------------------------------------------------------------

# ------------------------------------------------------------
# Title   : Known-Good Windows Update Base
# Version : 1.3.0
# Reason  : Rebuilt the script using the Windows Update flow
#           confirmed working with up to 5 update passes.
#           Added heartbeat and countdown output without
#           changing the known-good Windows Update sequence.
# Date    : 2026-08-20
# ------------------------------------------------------------


$ScriptVersion =
    '1.4.0'

$ScriptUpdated =
    '2026-08-26'



$ErrorActionPreference =
    'Stop'


# Reused only during the current script run. If Lenovo's normal
# catalog is broken, the cleaned local recovery repository is
# created once and reused by later LSUClient rounds.
$script:LenovoLSURecoveryRepository =
    $null


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



function Get-ItinoIntegerOption {

    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentVariable,

        [Parameter(Mandatory)]
        [int]$DefaultValue,

        [int]$MinimumValue = 1
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

    $ParsedValue =
        0

    if (
        [int]::TryParse(
            $Value.Trim(),
            [ref]$ParsedValue
        ) -and
        $ParsedValue -ge $MinimumValue
    ) {
        return $ParsedValue
    }

    return $DefaultValue
}


function Get-ItinoStringOption {

    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentVariable,

        [Parameter(Mandatory)]
        [string]$DefaultValue
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

    return $Value.Trim()
}


function Get-ItinoListOption {

    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentVariable,

        [Parameter(Mandatory)]
        [string[]]$DefaultValue
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

    $Items =
        @(
            $Value.Split(',') |
            ForEach-Object {
                $_.Trim()
            } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            }
        )

    if (
        $Items.Count -eq 0
    ) {
        return $DefaultValue
    }

    return $Items
}


# ============================================================
# OPTIONS FROM MAIN CONTROLLER
# ============================================================

$WriteLogFiles =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_WRITE_LOG_FILES' `
        -DefaultValue $true


$UnattendedMode =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_UNATTENDED_MODE' `
        -DefaultValue $true


$CloseLenovoHotkeyPopup =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_CLOSE_LENOVO_HOTKEY_POPUP' `
        -DefaultValue $true


$RequireAdministrator =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_REQUIRE_ADMINISTRATOR' `
        -DefaultValue $true

# ============================================================
# SCRIPT SETTINGS
# ============================================================

$ForceWindowsUpdate =
    $false


$TriggerWindowsUpdateScan =
    $true


$MaximumWindowsUpdatePasses =
    5


$MaximumDownloadAttempts =
    3


$WindowsUpdateScanWaitSeconds =
    20


$WindowsUpdateRetryWaitSeconds =
    20


$WindowsUpdatePassDelaySeconds =
    15


$LenovoPopupWatcherMaximumSeconds =
    300


$LenovoPopupWatcherGraceSeconds =
    5


# Maximum time an OEM update process may run before it is
# treated as hung. 900 seconds = 15 minutes.

$OEMProcessTimeoutSeconds =
    900


$LenovoLSUClientModuleName =
    Get-ItinoStringOption `
        -EnvironmentVariable 'ITINO_LENOVO_LSUCLIENT_MODULE_NAME' `
        -DefaultValue 'LSUClient'


$LenovoLSUClientRepository =
    Get-ItinoStringOption `
        -EnvironmentVariable 'ITINO_LENOVO_LSUCLIENT_REPOSITORY' `
        -DefaultValue 'PSGallery'


$MaximumLenovoLSURounds =
    Get-ItinoIntegerOption `
        -EnvironmentVariable 'ITINO_LENOVO_LSUCLIENT_MAXIMUM_ROUNDS' `
        -DefaultValue 3 `
        -MinimumValue 1


$LenovoLSUUpdateTypes =
    Get-ItinoListOption `
        -EnvironmentVariable 'ITINO_LENOVO_LSUCLIENT_UPDATE_TYPES' `
        -DefaultValue @(
            'Driver'
            'BIOS'
            'Firmware'
        )


$LenovoLSUSeverities =
    Get-ItinoListOption `
        -EnvironmentVariable 'ITINO_LENOVO_LSUCLIENT_SEVERITIES' `
        -DefaultValue @(
            'Critical'
            'Recommended'
        )


$AllowFirmwareUpdates =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_ALLOW_FIRMWARE_UPDATES' `
        -DefaultValue $false


# ============================================================
# PATHS
# ============================================================

$BasePath =
    'C:\ProgramData\Itino\DriverDeployment'


$LogPath =
    Join-Path `
        $BasePath `
        'Logs'


$ToolsPath =
    Join-Path `
        $BasePath `
        'Tools'


$WorkingPath =
    Join-Path `
        $BasePath `
        'DriverUpdates'


$LenovoLSUPackagePath =
    Join-Path `
        $WorkingPath `
        'LenovoLSUClient'


$HardwareFile =
    Join-Path `
        $BasePath `
        'HardwareInformation.json'


$LogFile =
    Join-Path `
        $LogPath `
        'Update-Drivers.log'


$RestartFile =
    Join-Path `
        $BasePath `
        'RestartRequired.txt'


# ============================================================
# CREATE REQUIRED DIRECTORIES
# ============================================================

foreach (
    $Directory in @(
        $BasePath,
        $ToolsPath,
        $WorkingPath
    )
) {

    if (-not (
        Test-Path -LiteralPath $Directory
    )) {

        New-Item `
            -Path $Directory `
            -ItemType Directory `
            -Force |
            Out-Null
    }
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
# ADMINISTRATOR CHECK
# ============================================================

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


# ============================================================
# RUN PROCESS WITH TIMEOUT
# ============================================================

function Invoke-ProcessWithTimeout {

    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [int]$TimeoutSeconds = 3600,

        [string]$ProcessName = 'OEM update process'
    )


    Write-Log -Message (
        "Starting $ProcessName. Timeout: $TimeoutSeconds seconds."
    )


    $Process =
        Start-Process `
            -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -PassThru `
            -NoNewWindow


    try {

        $Completed =
            $Process.WaitForExit(
                $TimeoutSeconds * 1000
            )


        if (-not $Completed) {

            Write-Log `
                -Message (
                    "$ProcessName exceeded the timeout of " +
                    "$TimeoutSeconds seconds. Stopping process."
                ) `
                -Level 'ERROR'


            try {

                Stop-Process `
                    -Id $Process.Id `
                    -Force `
                    -ErrorAction Stop
            }
            catch {

                Write-Log `
                    -Message (
                        "Unable to stop timed-out process $($Process.Id). " +
                        "Reason: $($_.Exception.Message)"
                    ) `
                    -Level 'WARNING'
            }


            throw (
                "$ProcessName timed out after $TimeoutSeconds seconds."
            )
        }


        $Process.Refresh()


        return [PSCustomObject]@{

            ExitCode =
                $Process.ExitCode

            ProcessId =
                $Process.Id
        }
    }
    finally {

        if ($Process) {

            $Process.Dispose()
        }
    }
}


# ============================================================
# RESTART MARKER
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
# COM CLEANUP
# ============================================================

function Remove-ComObject {

    param(
        $Object
    )


    if (
        $null -ne $Object
    ) {

        try {

            [void][System.Runtime.InteropServices.Marshal]::
                FinalReleaseComObject(
                    $Object
                )
        }
        catch {

            # Ignore COM cleanup errors.
        }
    }
}


# ============================================================
# LENOVO HOTKEY POPUP WATCHER
# ============================================================

function Start-LenovoHotkeyPopupWatcher {

    if (-not $CloseLenovoHotkeyPopup) {

        Write-Log -Message (
            'Lenovo Hotkey popup watcher is disabled.'
        )

        return $null
    }


    if (-not $UnattendedMode) {

        Write-Log -Message (
            'Unattended mode is disabled. ' +
            'Lenovo popup will not be automatically closed.'
        )

        return $null
    }


    Write-Log -Message (
        'Starting Lenovo Hotkey Installer popup watcher.'
    )


    $WatcherJob =
        Start-Job `
            -ScriptBlock {

                param(
                    [int]$MaximumSeconds
                )


                # ----------------------------------------------------
                # REMEMBER setup.exe PROCESSES THAT ALREADY EXIST
                # ----------------------------------------------------

                $ExistingSetupIDs =
                    @(
                        Get-CimInstance `
                            -ClassName Win32_Process `
                            -Filter "Name='setup.exe'" `
                            -ErrorAction SilentlyContinue |
                        Select-Object `
                            -ExpandProperty ProcessId
                    )


                $StartTime =
                    Get-Date


                while (
                    (
                        (Get-Date) - $StartTime
                    ).TotalSeconds -lt $MaximumSeconds
                ) {

                    $SetupProcesses =
                        Get-CimInstance `
                            -ClassName Win32_Process `
                            -Filter "Name='setup.exe'" `
                            -ErrorAction SilentlyContinue


                    foreach (
                        $SetupProcess in $SetupProcesses
                    ) {

                        try {

                            if (
                                $ExistingSetupIDs -contains
                                $SetupProcess.ProcessId
                            ) {

                                continue
                            }


                            $Process =
                                Get-Process `
                                    -Id $SetupProcess.ProcessId `
                                    -ErrorAction Stop


                            if (
                                $Process.MainWindowHandle -eq 0
                            ) {

                                continue
                            }


                            $ExecutablePath =
                                $SetupProcess.ExecutablePath


                            $CompanyName =
                                $null

                            $ProductName =
                                $null

                            $FileDescription =
                                $null

                            $ParentName =
                                $null


                            if (
                                -not [string]::IsNullOrWhiteSpace(
                                    $ExecutablePath
                                )
                            ) {

                                try {

                                    if (
                                        Test-Path `
                                            -LiteralPath $ExecutablePath
                                    ) {

                                        $FileInfo =
                                            Get-Item `
                                                -LiteralPath $ExecutablePath `
                                                -ErrorAction Stop


                                        $CompanyName =
                                            $FileInfo.VersionInfo.CompanyName


                                        $ProductName =
                                            $FileInfo.VersionInfo.ProductName


                                        $FileDescription =
                                            $FileInfo.VersionInfo.FileDescription
                                    }
                                }
                                catch {

                                    # Metadata is optional.
                                }
                            }


                            try {

                                $Parent =
                                    Get-CimInstance `
                                        -ClassName Win32_Process `
                                        -Filter (
                                            "ProcessId=$($SetupProcess.ParentProcessId)"
                                        ) `
                                        -ErrorAction SilentlyContinue


                                if ($Parent) {

                                    $ParentName =
                                        $Parent.Name
                                }
                            }
                            catch {

                                # Parent lookup is optional.
                            }


                            $IdentificationText =
                                @(
                                    $CompanyName
                                    $ProductName
                                    $FileDescription
                                    $ParentName
                                    $Process.MainWindowTitle
                                    $ExecutablePath
                                    $SetupProcess.CommandLine
                                ) -join ' '


                            $LooksLikeLenovoHotkey =
                                (
                                    $IdentificationText -match 'Lenovo'
                                ) -or
                                (
                                    $IdentificationText -match 'Hotkey'
                                ) -or
                                (
                                    $IdentificationText -match 'Fn'
                                )


                            # ------------------------------------------------
                            # The completion dialog we observed had only
                            # "setup.exe" as the title.
                            #
                            # Therefore a NEW visible setup.exe appearing
                            # during Lenovo driver installation is treated
                            # as a candidate even if metadata is poor.
                            # ------------------------------------------------

                            $IsNewVisibleSetup =
                                $true


                            if (
                                $LooksLikeLenovoHotkey -or
                                $IsNewVisibleSetup
                            ) {

                                Write-Output (
                                    'Detected Lenovo installer completion window. ' +
                                    "PID=$($Process.Id); " +
                                    "Title='$($Process.MainWindowTitle)'; " +
                                    "Company='$CompanyName'; " +
                                    "Product='$ProductName'; " +
                                    "Description='$FileDescription'; " +
                                    "Parent='$ParentName'; " +
                                    "Path='$ExecutablePath'"
                                )


                                $Closed =
                                    $Process.CloseMainWindow()


                                if ($Closed) {

                                    Write-Output (
                                        'Lenovo installer completion window ' +
                                        'closed automatically.'
                                    )


                                    Start-Sleep `
                                        -Seconds 2


                                    return
                                }
                            }
                        }
                        catch {

                            # Process may disappear while inspected.
                        }
                    }


                    Start-Sleep `
                        -Milliseconds 500
                }


                Write-Output (
                    'Lenovo popup watcher reached timeout without ' +
                    'closing a matching window.'
                )
            } `
            -ArgumentList $LenovoPopupWatcherMaximumSeconds


    return $WatcherJob
}


# ============================================================
# STOP LENOVO HOTKEY POPUP WATCHER
# ============================================================

function Stop-LenovoHotkeyPopupWatcher {

    param(
        $WatcherJob
    )


    if (
        $null -eq $WatcherJob
    ) {

        return
    }


    try {

        if (
            $WatcherJob.State -eq 'Running' -and
            $LenovoPopupWatcherGraceSeconds -gt 0
        ) {

            Start-Sleep `
                -Seconds $LenovoPopupWatcherGraceSeconds
        }


        $Output =
            Receive-Job `
                -Job $WatcherJob `
                -ErrorAction SilentlyContinue


        foreach (
            $Line in @($Output)
        ) {

            if (
                -not [string]::IsNullOrWhiteSpace(
                    [string]$Line
                )
            ) {

                Write-Log -Message (
                    "Popup watcher: $Line"
                )
            }
        }


        if (
            $WatcherJob.State -eq 'Running'
        ) {

            Stop-Job `
                -Job $WatcherJob `
                -ErrorAction SilentlyContinue
        }


        $Output =
            Receive-Job `
                -Job $WatcherJob `
                -ErrorAction SilentlyContinue


        foreach (
            $Line in @($Output)
        ) {

            if (
                -not [string]::IsNullOrWhiteSpace(
                    [string]$Line
                )
            ) {

                Write-Log -Message (
                    "Popup watcher: $Line"
                )
            }
        }


        Remove-Job `
            -Job $WatcherJob `
            -Force `
            -ErrorAction SilentlyContinue
    }
    catch {

        Write-Log `
            -Message (
                'Unable to clean up Lenovo popup watcher. ' +
                "Error: $($_.Exception.Message)"
            ) `
            -Level 'WARNING'
    }
}


# ============================================================
# WINDOWS UPDATE SCAN
# ============================================================

function Request-WindowsUpdateScan {

    if (-not $TriggerWindowsUpdateScan) {

        Write-Log -Message (
            'Fresh Windows Update scan trigger is disabled.'
        )

        return
    }


    $UsoClient =
        Join-Path `
            $env:SystemRoot `
            'System32\UsoClient.exe'


    if (-not (
        Test-Path -LiteralPath $UsoClient
    )) {

        Write-Log `
            -Message (
                'UsoClient.exe was not found. ' +
                'Continuing with Windows Update COM search.'
            ) `
            -Level 'WARNING'

        return
    }


    Write-Log -Message (
        'Requesting fresh Windows Update scan.'
    )


    try {

        $Process =
            Start-Process `
                -FilePath $UsoClient `
                -ArgumentList 'StartScan' `
                -WindowStyle Hidden `
                -Wait `
                -PassThru `
                -ErrorAction Stop


        Write-Log -Message (
            "Windows Update scan request exit code: $($Process.ExitCode)"
        )
    }
    catch {

        Write-Log `
            -Message (
                'Unable to explicitly trigger Windows Update scan. ' +
                "Error: $($_.Exception.Message)"
            ) `
            -Level 'WARNING'
    }


    Write-Log -Message (
        "Waiting $WindowsUpdateScanWaitSeconds seconds " +
        'for Windows Update scan state to refresh.'
    )


    Invoke-ItinoCountdown `
        -Seconds $WindowsUpdateScanWaitSeconds `
        -Message 'Windows Update scan refresh countdown.'
}


# ============================================================
# WINDOWS UPDATE FIRMWARE CLASSIFICATION
# ============================================================

function Test-ItinoWindowsUpdateFirmware {

    param(
        [Parameter(Mandatory)]
        $Update
    )


    $Title =
        [string]$Update.Title


    if (
        $Title -match '(?i)\bfirmware\b' -or
        $Title -match '(?i)\bBIOS\b' -or
        $Title -match '(?i)\bUEFI\b'
    ) {

        return $true
    }


    try {

        for (
            $CategoryIndex = 0;
            $CategoryIndex -lt $Update.Categories.Count;
            $CategoryIndex++
        ) {

            $Category =
                $Update.Categories.Item(
                    $CategoryIndex
                )


            $CategoryName =
                [string]$Category.Name


            if (
                $CategoryName -match '(?i)\bfirmware\b' -or
                $CategoryName -match '(?i)\bBIOS\b' -or
                $CategoryName -match '(?i)\bUEFI\b'
            ) {

                return $true
            }
        }
    }
    catch {

        # Title-based detection above still protects known
        # Firmware / BIOS / UEFI update naming.
    }


    return $false
}


function Test-ItinoWindowsUpdateAllowed {

    param(
        [Parameter(Mandatory)]
        $Update
    )


    if ($AllowFirmwareUpdates) {
        return $true
    }


    return -not (
        Test-ItinoWindowsUpdateFirmware `
            -Update $Update
    )
}


# ============================================================
# WINDOWS UPDATE FINAL CONFIRMATION
# ============================================================

function Get-PendingWindowsUpdateDriverCount {

    param(
        [Parameter(Mandatory)]
        [string]$PhaseName
    )


    $UpdateSession =
        $null

    $UpdateSearcher =
        $null


    try {

        Write-Log -Message (
            "$PhaseName final confirmation: creating fresh Windows Update session."
        )


        $UpdateSession =
            New-Object `
                -ComObject 'Microsoft.Update.Session'


        $UpdateSession.ClientApplicationID =
            'ITINO Driver Deployment'


        $UpdateSearcher =
            $UpdateSession.CreateUpdateSearcher()


        Write-Log -Message (
            "$PhaseName final confirmation: searching for remaining drivers."
        )


        $SearchResult =
            $UpdateSearcher.Search(
                "IsInstalled=0 and IsHidden=0 and Type='Driver'"
            )


        $EligibleCount =
            0


        for (
            $Index = 0;
            $Index -lt $SearchResult.Updates.Count;
            $Index++
        ) {

            $PendingUpdate =
                $SearchResult.Updates.Item(
                    $Index
                )


            if (
                Test-ItinoWindowsUpdateAllowed `
                    -Update $PendingUpdate
            ) {

                $EligibleCount++
            }
            else {

                Write-Log `
                    -Message (
                        '[FIRMWARE-SAFETY] Ignoring pending Windows Update ' +
                        "firmware item during final confirmation: $($PendingUpdate.Title)"
                    ) `
                    -Level 'WARNING'
            }
        }


        return [int]$EligibleCount
    }
    finally {

        Remove-ComObject `
            -Object $UpdateSearcher


        Remove-ComObject `
            -Object $UpdateSession


        $UpdateSearcher =
            $null

        $UpdateSession =
            $null


        [GC]::Collect()

        [GC]::WaitForPendingFinalizers()
    }
}



# ============================================================
# COUNTDOWN
# ============================================================

function Invoke-ItinoCountdown {

    param(
        [Parameter(Mandatory)]
        [int]$Seconds,

        [Parameter(Mandatory)]
        [string]$Message
    )

    for (
        $Remaining = $Seconds;
        $Remaining -gt 0;
        $Remaining--
    ) {

        Write-Host (
            "`r[{0}] [INFO] {1} {2} second(s) remaining...   " -f
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
            $Message,
            $Remaining
        ) -NoNewline

        Start-Sleep -Seconds 1
    }

    Write-Host (
        "`r[{0}] [INFO] {1} Complete.                          " -f
        (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
        $Message
    )
}


# ============================================================
# NATIVE CONSOLE HEARTBEAT
# ============================================================

function Initialize-ItinoNativeConsoleHeartbeat {

    if (
        'ItinoConsoleHeartbeat' -as [type]
    ) {
        return
    }

    $TypeDefinition =
@"
using System;
using System.Threading;

public sealed class ItinoConsoleHeartbeat : IDisposable
{
    private readonly string _message;
    private readonly Timer _timer;
    private readonly DateTime _started;

    public ItinoConsoleHeartbeat(string message, int intervalSeconds)
    {
        _message = message;
        _started = DateTime.Now;

        int milliseconds = intervalSeconds * 1000;

        _timer = new Timer(
            WriteHeartbeat,
            null,
            milliseconds,
            milliseconds
        );
    }

    private void WriteHeartbeat(object state)
    {
        try
        {
            TimeSpan elapsed = DateTime.Now - _started;

            Console.WriteLine(
                "[{0}] [INFO] {1} Elapsed: {2:00}:{3:00}:{4:00}",
                DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                _message,
                (int)elapsed.TotalHours,
                elapsed.Minutes,
                elapsed.Seconds
            );

            Console.Out.Flush();
        }
        catch
        {
        }
    }

    public void Dispose()
    {
        try
        {
            _timer.Dispose();
        }
        catch
        {
        }
    }
}
"@

    Add-Type `
        -TypeDefinition $TypeDefinition `
        -Language CSharp `
        -ErrorAction Stop
}


function Start-ItinoNativeConsoleHeartbeat {

    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [int]$IntervalSeconds = 15
    )

    Initialize-ItinoNativeConsoleHeartbeat

    return New-Object `
        -TypeName ItinoConsoleHeartbeat `
        -ArgumentList @(
            $Message,
            $IntervalSeconds
        )
}


function Stop-ItinoNativeConsoleHeartbeat {

    param(
        $Heartbeat
    )

    if (-not $Heartbeat) {
        return
    }

    try {
        $Heartbeat.Dispose()
    }
    catch {
    }
}



function Initialize-ItinoDownloadActivityMonitor {

    if (
        'ItinoDownloadActivityMonitor' -as [type]
    ) {

        return
    }


    $TypeDefinition =
@"
using System;
using System.IO;
using System.Threading;

public sealed class ItinoDownloadActivityMonitor : IDisposable
{
    private readonly Timer _timer;
    private readonly string[] _paths;
    private readonly string _message;
    private long _previousBytes;
    private readonly DateTime _started;

    public ItinoDownloadActivityMonitor(
        string message,
        string[] paths,
        int intervalSeconds)
    {
        _message = message;
        _paths = paths ?? new string[0];
        _previousBytes = GetTotalBytes();
        _started = DateTime.Now;

        _timer = new Timer(
            Tick,
            null,
            intervalSeconds * 1000,
            intervalSeconds * 1000
        );
    }

    private long GetDirectoryBytes(string path)
    {
        long total = 0;

        try
        {
            if (!Directory.Exists(path))
            {
                return 0;
            }

            foreach (string file in Directory.EnumerateFiles(
                path,
                "*",
                SearchOption.AllDirectories))
            {
                try
                {
                    total += new FileInfo(file).Length;
                }
                catch
                {
                }
            }
        }
        catch
        {
        }

        return total;
    }

    private long GetTotalBytes()
    {
        long total = 0;

        foreach (string path in _paths)
        {
            total += GetDirectoryBytes(path);
        }

        return total;
    }

    private static string FormatBytes(long bytes)
    {
        double value = Math.Abs((double)bytes);

        if (value >= 1024d * 1024d * 1024d)
        {
            return (bytes / (1024d * 1024d * 1024d)).ToString("0.00") + " GB";
        }

        if (value >= 1024d * 1024d)
        {
            return (bytes / (1024d * 1024d)).ToString("0.0") + " MB";
        }

        if (value >= 1024d)
        {
            return (bytes / 1024d).ToString("0.0") + " KB";
        }

        return bytes.ToString() + " bytes";
    }

    private void Tick(object state)
    {
        try
        {
            long currentBytes = GetTotalBytes();
            long changeBytes = currentBytes - _previousBytes;
            TimeSpan elapsed = DateTime.Now - _started;

            string changeText;

            if (changeBytes > 0)
            {
                changeText = "+" + FormatBytes(changeBytes);
            }
            else
            {
                changeText = FormatBytes(changeBytes);
            }

            Console.WriteLine(
                "[{0}] [INFO] {1} Elapsed: {2:00}:{3:00}:{4:00}; Cache={5}; ChangeLast30s={6}",
                DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"),
                _message,
                (int)elapsed.TotalHours,
                elapsed.Minutes,
                elapsed.Seconds,
                FormatBytes(currentBytes),
                changeText
            );

            Console.Out.Flush();

            _previousBytes = currentBytes;
        }
        catch
        {
        }
    }

    public void Dispose()
    {
        try
        {
            _timer.Dispose();
        }
        catch
        {
        }
    }
}
"@


    Add-Type `
        -TypeDefinition $TypeDefinition `
        -Language CSharp `
        -ErrorAction Stop
}


function Start-ItinoDownloadActivityMonitor {

    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [int]$IntervalSeconds = 30
    )


    Initialize-ItinoDownloadActivityMonitor


    $ActivityPaths =
        @(
            (Join-Path $env:SystemRoot 'SoftwareDistribution\Download'),
            (Join-Path $env:ProgramData 'Microsoft\Network\Downloader')
        )


    return New-Object `
        -TypeName ItinoDownloadActivityMonitor `
        -ArgumentList @(
            $Message,
            [string[]]$ActivityPaths,
            $IntervalSeconds
        )
}


function Stop-ItinoDownloadActivityMonitor {

    param(
        $Monitor
    )


    if (-not $Monitor) {

        return
    }


    try {

        $Monitor.Dispose()
    }
    catch {
    }
}


# ============================================================
# WINDOWS UPDATE DRIVER UPDATE
# ============================================================

function Invoke-WindowsUpdateDriverUpdate {

    param(
        [string]$PhaseName = 'Windows Update',

        [int]$MaximumPasses = 5,

        [int]$MaximumDownloadRetries = 3,

        [int]$PassDelaySeconds = 15,

        [int]$RetryWaitSeconds = 20
    )


    Write-Log -Message (
        "$PhaseName processing started."
    )


    Write-Log -Message (
        "$PhaseName maximum passes: $MaximumPasses"
    )


    Write-Log -Message (
        "$PhaseName maximum download attempts per pass: " +
        "$MaximumDownloadRetries"
    )


    $TotalInstalled =
        0


    for (
        $Pass = 1;
        $Pass -le $MaximumPasses;
        $Pass++
    ) {

        Write-Log -Message (
            "$PhaseName pass $Pass of $MaximumPasses started."
        )


        Request-WindowsUpdateScan


        $PassCompleted =
            $false


        for (
            $DownloadAttempt = 1;
            $DownloadAttempt -le $MaximumDownloadRetries;
            $DownloadAttempt++
        ) {

            Write-Log -Message (
                "$PhaseName pass $Pass download attempt " +
                "$DownloadAttempt of $MaximumDownloadRetries."
            )


            $UpdateSession =
                $null

            $UpdateSearcher =
                $null

            $SearchResult =
                $null

            $UpdatesToDownload =
                $null

            $UpdatesToInstall =
                $null

            $Downloader =
                $null

            $DownloadResult =
                $null

            $Installer =
                $null

            $InstallResult =
                $null

            $PopupWatcher =
                $null


            try {

                # ============================================
                # SESSION
                # ============================================

                Write-Log -Message (
                    "$PhaseName pass ${Pass}: " +
                    'Creating fresh Windows Update session.'
                )


                $UpdateSession =
                    New-Object `
                        -ComObject 'Microsoft.Update.Session'


                $UpdateSession.ClientApplicationID =
                    'ITINO Driver Deployment'


                $UpdateSearcher =
                    $UpdateSession.CreateUpdateSearcher()


                # ============================================
                # SEARCH
                # ============================================

                Write-Log -Message (
                    "$PhaseName pass ${Pass}: " +
                    'Searching for applicable drivers.'
                )


                $SearchStopwatch =
                    [System.Diagnostics.Stopwatch]::StartNew()


                $SearchHeartbeat =
                    Start-ItinoNativeConsoleHeartbeat `
                        -Message (
                            "$PhaseName pass ${Pass}: Windows Update is still searching for applicable drivers..."
                        ) `
                        -IntervalSeconds 15


                try {

                    $SearchResult =
                        $UpdateSearcher.Search(
                            "IsInstalled=0 and IsHidden=0 and Type='Driver'"
                        )
                }
                finally {

                    $SearchStopwatch.Stop()


                    Stop-ItinoNativeConsoleHeartbeat `
                        -Heartbeat $SearchHeartbeat


                    Write-Log -Message (
                        "$PhaseName pass ${Pass}: Windows Update search returned. Duration: " +
                        "$($SearchStopwatch.Elapsed.ToString('hh\:mm\:ss'))."
                    )
                }


                $UpdateCount =
                    $SearchResult.Updates.Count


                Write-Log -Message (
                    "$PhaseName pass ${Pass}: Found " +
                    "$UpdateCount driver update(s)."
                )


                # ============================================
                # STOP AT ZERO
                # ============================================

                if (
                    $UpdateCount -eq 0
                ) {

                    Write-Log -Message (
                        "$PhaseName pass ${Pass}: " +
                        'No additional driver updates found.'
                    )


                    Write-Log -Message (
                        "$PhaseName processing complete. " +
                        "Total installed: $TotalInstalled."
                    )


                    return
                }


                # ============================================
                # COLLECTIONS
                # ============================================

                $UpdatesToDownload =
                    New-Object `
                        -ComObject 'Microsoft.Update.UpdateColl'


                $UpdatesToInstall =
                    New-Object `
                        -ComObject 'Microsoft.Update.UpdateColl'


                # ============================================
                # PROCESS FOUND UPDATES
                # ============================================

                for (
                    $Index = 0;
                    $Index -lt $UpdateCount;
                    $Index++
                ) {

                    $Update =
                        $SearchResult.Updates.Item(
                            $Index
                        )


                    Write-Log -Message (
                        "$PhaseName pass $Pass found: " +
                        "$($Update.Title)"
                    )


                    if (
                        -not (
                            Test-ItinoWindowsUpdateAllowed `
                                -Update $Update
                        )
                    ) {

                        Write-Log `
                            -Message (
                                '[FIRMWARE-SAFETY] Skipping Windows Update ' +
                                "firmware/BIOS item because controller power " +
                                "safety requirements were not met: $($Update.Title)"
                            ) `
                            -Level 'WARNING'

                        continue
                    }


                    if (-not $Update.EulaAccepted) {

                        try {

                            $Update.AcceptEula()
                        }
                        catch {

                            Write-Log `
                                -Message (
                                    "$PhaseName pass ${Pass}: " +
                                    'Unable to accept EULA for ' +
                                    "'$($Update.Title)'."
                                ) `
                                -Level 'WARNING'

                            continue
                        }
                    }


                    if ($Update.IsDownloaded) {

                        Write-Log -Message (
                            "$PhaseName pass $Pass already downloaded: " +
                            "$($Update.Title)"
                        )


                        [void]$UpdatesToInstall.Add(
                            $Update
                        )
                    }
                    else {

                        [void]$UpdatesToDownload.Add(
                            $Update
                        )
                    }
                }


                # ============================================
                # STOP IF ONLY BLOCKED FIRMWARE WAS FOUND
                # ============================================

                if (
                    $UpdatesToDownload.Count -eq 0 -and
                    $UpdatesToInstall.Count -eq 0
                ) {

                    Write-Log -Message (
                        "$PhaseName pass ${Pass}: No eligible driver updates remain " +
                        'after firmware safety filtering.'
                    )


                    Write-Log -Message (
                        "$PhaseName processing complete. " +
                        "Total installed: $TotalInstalled."
                    )


                    return
                }


                # ============================================
                # DOWNLOAD
                # ============================================

                if (
                    $UpdatesToDownload.Count -gt 0
                ) {

                    Write-Log -Message (
                        "$PhaseName pass ${Pass}: Downloading " +
                        "$($UpdatesToDownload.Count) driver update(s)."
                    )


                    $Downloader =
                        $UpdateSession.CreateUpdateDownloader()


                    $Downloader.Updates =
                        $UpdatesToDownload


                    $DownloadStopwatch =
                        [System.Diagnostics.Stopwatch]::StartNew()


                    $DownloadHeartbeat =
                        Start-ItinoNativeConsoleHeartbeat `
                            -Message (
                                "$PhaseName pass ${Pass}: Windows Update is still downloading " +
                                "$($UpdatesToDownload.Count) driver update(s) as one batch..."
                            ) `
                            -IntervalSeconds 15


                    $DownloadActivityMonitor =
                        Start-ItinoDownloadActivityMonitor `
                            -Message (
                                "$PhaseName pass ${Pass}: Windows Update download cache activity."
                            ) `
                            -IntervalSeconds 30


                    try {

                        $DownloadResult =
                            $Downloader.Download()
                    }
                    finally {

                        $DownloadStopwatch.Stop()


                        Stop-ItinoDownloadActivityMonitor `
                            -Monitor $DownloadActivityMonitor


                        Stop-ItinoNativeConsoleHeartbeat `
                            -Heartbeat $DownloadHeartbeat


                        Write-Log -Message (
                            "$PhaseName pass ${Pass}: Windows Update download returned. Duration: " +
                            "$($DownloadStopwatch.Elapsed.ToString('hh\:mm\:ss'))."
                        )
                    }


                    Write-Log -Message (
                        "$PhaseName pass ${Pass}: Download result code: " +
                        "$($DownloadResult.ResultCode)"
                    )


                    for (
                        $Index = 0;
                        $Index -lt $UpdatesToDownload.Count;
                        $Index++
                    ) {

                        $Update =
                            $UpdatesToDownload.Item(
                                $Index
                            )


                        try {

                            $UpdateDownloadResult =
                                $DownloadResult.GetUpdateResult(
                                    $Index
                                )


                            $HResultHex =
                                '0x{0:X8}' -f (
                                    $UpdateDownloadResult.HResult `
                                    -band 0xFFFFFFFF
                                )


                            Write-Log -Message (
                                "$PhaseName pass $Pass download result for " +
                                "'$($Update.Title)': " +
                                "Result=$($UpdateDownloadResult.ResultCode), " +
                                "HRESULT=$HResultHex"
                            )
                        }
                        catch {

                            Write-Log `
                                -Message (
                                    "$PhaseName pass $Pass could not read " +
                                    "download result for '$($Update.Title)'."
                                ) `
                                -Level 'WARNING'
                        }


                        if ($Update.IsDownloaded) {

                            Write-Log -Message (
                                "$PhaseName pass $Pass downloaded: " +
                                "$($Update.Title)"
                            )


                            [void]$UpdatesToInstall.Add(
                                $Update
                            )
                        }
                        else {

                            Write-Log `
                                -Message (
                                    "$PhaseName pass $Pass download not ready: " +
                                    "$($Update.Title)"
                                ) `
                                -Level 'WARNING'
                        }
                    }
                }
                else {

                    Write-Log -Message (
                        "$PhaseName pass ${Pass}: " +
                        'All discovered updates are already downloaded.'
                    )
                }


                # ============================================
                # NOTHING READY
                # ============================================

                if (
                    $UpdatesToInstall.Count -eq 0
                ) {

                    Write-Log `
                        -Message (
                            "$PhaseName pass ${Pass}: " +
                            'Updates were found but none are ready ' +
                            'for installation.'
                        ) `
                        -Level 'WARNING'


                    if (
                        $DownloadAttempt -lt $MaximumDownloadRetries
                    ) {

                        Write-Log `
                            -Message (
                                "$PhaseName pass ${Pass}: Waiting " +
                                "$RetryWaitSeconds seconds before retry."
                            ) `
                            -Level 'WARNING'


                        Start-Sleep `
                            -Seconds $RetryWaitSeconds


                        continue
                    }


                    throw (
                        "$PhaseName pass $Pass failed after " +
                        "$MaximumDownloadRetries download attempts."
                    )
                }


                # ============================================
                # INSTALL
                # ============================================

                Write-Log -Message (
                    "$PhaseName pass ${Pass}: Installing " +
                    "$($UpdatesToInstall.Count) driver update(s)."
                )


                $Installer =
                    $UpdateSession.CreateUpdateInstaller()


                $Installer.Updates =
                    $UpdatesToInstall


                $Installer.ForceQuiet =
                    $true


                # ============================================
                # LENOVO POPUP WATCHER
                # ============================================

                if (
                    $Manufacturer -match 'Lenovo' -and
                    $CloseLenovoHotkeyPopup -and
                    $UnattendedMode
                ) {

                    $PopupWatcher =
                        Start-LenovoHotkeyPopupWatcher
                }


                $InstallStopwatch =
                    [System.Diagnostics.Stopwatch]::StartNew()


                $InstallHeartbeat =
                    Start-ItinoNativeConsoleHeartbeat `
                        -Message (
                            "$PhaseName pass ${Pass}: Windows Update is still installing " +
                            "$($UpdatesToInstall.Count) driver update(s) as one batch..."
                        ) `
                        -IntervalSeconds 15


                Write-Log -Message (
                    "$PhaseName pass ${Pass}: Entering Windows Update batch installer. " +
                    'This can take several minutes.'
                )


                try {

                    $InstallResult =
                        $Installer.Install()
                }
                finally {

                    $InstallStopwatch.Stop()


                    Stop-ItinoNativeConsoleHeartbeat `
                        -Heartbeat $InstallHeartbeat


                    if ($PopupWatcher) {

                        Stop-LenovoHotkeyPopupWatcher `
                            -WatcherJob $PopupWatcher


                        $PopupWatcher =
                            $null
                    }


                    Write-Log -Message (
                        "$PhaseName pass ${Pass}: Windows Update batch installer returned. Duration: " +
                        "$($InstallStopwatch.Elapsed.ToString('hh\:mm\:ss'))."
                    )
                }


                Write-Log -Message (
                    "$PhaseName pass ${Pass}: Installation result code: " +
                    "$($InstallResult.ResultCode)"
                )


                # ============================================
                # PER UPDATE RESULTS
                # ============================================

                $InstalledThisPass =
                    0


                for (
                    $Index = 0;
                    $Index -lt $UpdatesToInstall.Count;
                    $Index++
                ) {

                    $Update =
                        $UpdatesToInstall.Item(
                            $Index
                        )


                    $UpdateResult =
                        $InstallResult.GetUpdateResult(
                            $Index
                        )


                    $HResultHex =
                        '0x{0:X8}' -f (
                            $UpdateResult.HResult `
                            -band 0xFFFFFFFF
                        )


                    Write-Log -Message (
                        "$PhaseName pass $Pass install result for " +
                        "'$($Update.Title)': " +
                        "Result=$($UpdateResult.ResultCode), " +
                        "HRESULT=$HResultHex"
                    )


                    if (
                        $UpdateResult.ResultCode -eq 2
                    ) {

                        $InstalledThisPass++
                    }
                }


                $TotalInstalled +=
                    $InstalledThisPass


                Write-Log -Message (
                    "$PhaseName pass $Pass successfully installed " +
                    "$InstalledThisPass driver update(s)."
                )


                # ============================================
                # RESTART REQUIRED
                # ============================================

                if (
                    $InstallResult.RebootRequired
                ) {

                    Set-RestartRequired `
                        -Reason (
                            "$PhaseName requested a restart " +
                            "during pass $Pass."
                        )
                }


                # ============================================
                # OVERALL INSTALL RESULT
                # ============================================

                switch (
                    $InstallResult.ResultCode
                ) {

                    2 {

                        Write-Log -Message (
                            "$PhaseName pass $Pass completed successfully."
                        )
                    }


                    3 {

                        Write-Log `
                            -Message (
                                "$PhaseName pass $Pass completed with " +
                                'one or more installation errors.'
                            ) `
                            -Level 'WARNING'
                    }


                    default {

                        throw (
                            "$PhaseName installation failed during " +
                            "pass $Pass. Result code: " +
                            "$($InstallResult.ResultCode)"
                        )
                    }
                }


                if (
                    $InstalledThisPass -eq 0
                ) {

                    throw (
                        "$PhaseName pass $Pass installed zero updates."
                    )
                }


                $PassCompleted =
                    $true


                break
            }
            finally {

                if ($PopupWatcher) {

                    Stop-LenovoHotkeyPopupWatcher `
                        -WatcherJob $PopupWatcher
                }


                Remove-ComObject `
                    -Object $Installer


                Remove-ComObject `
                    -Object $Downloader


                Remove-ComObject `
                    -Object $UpdatesToInstall


                Remove-ComObject `
                    -Object $UpdatesToDownload


                Remove-ComObject `
                    -Object $UpdateSearcher


                Remove-ComObject `
                    -Object $UpdateSession


                $Installer =
                    $null

                $Downloader =
                    $null

                $UpdatesToInstall =
                    $null

                $UpdatesToDownload =
                    $null

                $UpdateSearcher =
                    $null

                $UpdateSession =
                    $null


                [GC]::Collect()

                [GC]::WaitForPendingFinalizers()
            }
        }


        if (-not $PassCompleted) {

            throw (
                "$PhaseName pass $Pass did not complete."
            )
        }


        if (
            $Pass -lt $MaximumPasses
        ) {

            Write-Log -Message (
                "$PhaseName waiting $PassDelaySeconds seconds " +
                'before the next pass.'
            )


            Invoke-ItinoCountdown `
                -Seconds $PassDelaySeconds `
                -Message "$PhaseName countdown before pass $($Pass + 1)."
        }
    }


    Write-Log `
        -Message (
            "$PhaseName reached maximum pass limit of " +
            "$MaximumPasses. Total installed: $TotalInstalled."
        ) `
        -Level 'WARNING'


    # ========================================================
    # FINAL SEARCH-ONLY CONFIRMATION
    # ========================================================

    Request-WindowsUpdateScan


    $RemainingDriverUpdates =
        Get-PendingWindowsUpdateDriverCount `
            -PhaseName $PhaseName


    Write-Log -Message (
        "$PhaseName final confirmation found " +
        "$RemainingDriverUpdates remaining driver update(s)."
    )


    if (
        $RemainingDriverUpdates -eq 0
    ) {

        Write-Log -Message (
            "$PhaseName processing complete after final confirmation. " +
            "Total installed: $TotalInstalled."
        )


        return
    }


    throw (
        "$PhaseName reached the maximum pass limit of $MaximumPasses " +
        "and $RemainingDriverUpdates driver update(s) are still pending."
    )
}


# ============================================================
# WINDOWS UPDATE FALLBACK
# ============================================================

function Invoke-WindowsUpdateFallback {

    param(
        [Parameter(Mandatory)]
        [string]$OEMName,

        [Parameter(Mandatory)]
        [string]$Reason
    )


    Write-Log `
        -Message (
            "$OEMName OEM update method could not be used. " +
            'Falling back to Windows Update. ' +
            "Reason: $Reason"
        ) `
        -Level 'WARNING'


    Invoke-WindowsUpdateDriverUpdate `
        -PhaseName "$OEMName Windows Update fallback" `
        -MaximumPasses $MaximumWindowsUpdatePasses `
        -MaximumDownloadRetries $MaximumDownloadAttempts `
        -PassDelaySeconds $WindowsUpdatePassDelaySeconds `
        -RetryWaitSeconds $WindowsUpdateRetryWaitSeconds
}


# ============================================================
# DELL COMMAND UPDATE
# ============================================================

function Get-DellCommandUpdatePath {

    $PossiblePaths =
        @(
            'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
            'C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe'
        )


    foreach (
        $Path in $PossiblePaths
    ) {

        if (
            Test-Path -LiteralPath $Path
        ) {

            return $Path
        }
    }


    return $null
}


function Get-DellDCUExitInfo {

    param(
        [Parameter(Mandatory)]
        [int]$ExitCode,

        [ValidateSet(
            'Generic',
            'Scan',
            'Apply'
        )]
        [string]$Operation = 'Generic'
    )


    $Description =
        'Unknown Dell Command Update exit code.'


    $Resolution =
        'Review the Dell Command Update log for additional details.'


    $Category =
        'Error'


    $Retryable =
        $false


    $RestartRequired =
        $false


    $NoUpdates =
        $false


    # ========================================================
    # GENERIC DCU CODES
    # ========================================================

    switch ($ExitCode) {

        0 {

            $Description =
                'Command execution was successful.'

            $Resolution =
                'No action required.'

            $Category =
                'Success'
        }


        1 {

            $Description =
                'A restart is required to complete the Dell operation.'

            $Resolution =
                'Restart Windows to complete the operation.'

            $Category =
                'RestartRequired'

            $RestartRequired =
                $true
        }


        2 {

            $Description =
                'An unknown Dell Command Update application error occurred.'

            $Resolution =
                'Review the DCU log and retry if appropriate.'
        }


        3 {

            $Description =
                'The current system manufacturer is not Dell.'

            $Resolution =
                'Dell Command Update can only run on supported Dell systems.'
        }


        4 {

            $Description =
                'Dell Command Update was not launched with administrator privileges.'

            $Resolution =
                'Run the deployment elevated as administrator.'
        }


        5 {

            $Description =
                'A restart is pending from a previous Dell Command Update operation.'

            $Resolution =
                'Restart Windows before running Dell Command Update again.'

            $Category =
                'RestartRequired'

            $RestartRequired =
                $true
        }


        6 {

            $Description =
                'Another Dell Command Update UI or CLI instance is already running.'

            $Resolution =
                'Wait for or close the existing DCU process, then retry.'

            $Category =
                'Retryable'

            $Retryable =
                $true
        }


        7 {

            $Description =
                'Dell Command Update does not support the current system model.'

            $Resolution =
                'Confirm that the model is supported by the current Dell catalog.'
        }


        8 {

            $Description =
                'No Dell Command Update update filters were applied or configured.'

            $Resolution =
                'Specify at least one valid update filter.'
        }


        100 {

            $Description =
                'No command-line parameters were recognized.'

            $Resolution =
                'Verify the DCU command line.'
        }


        101 {

            $Description =
                'No valid DCU command was recognized.'

            $Resolution =
                'Verify the DCU command line.'
        }


        102 {

            $Description =
                'An invalid DCU command was supplied.'

            $Resolution =
                'Verify the DCU command and supported options.'
        }


        103 {

            $Description =
                'Duplicate DCU commands were supplied.'

            $Resolution =
                'Remove duplicate commands.'
        }


        104 {

            $Description =
                'The DCU command syntax is invalid.'

            $Resolution =
                'Verify the command syntax.'
        }


        105 {

            $Description =
                'The DCU option syntax is invalid.'

            $Resolution =
                'Verify the option syntax.'
        }


        106 {

            $Description =
                'One or more invalid DCU options were supplied.'

            $Resolution =
                'Verify that all options are supported by the installed DCU version.'
        }


        107 {

            $Description =
                'One or more invalid values were supplied to a DCU option.'

            $Resolution =
                'Verify the option values.'
        }


        108 {

            $Description =
                'One or more required DCU options are missing.'

            $Resolution =
                'Add the required options.'
        }


        109 {

            $Description =
                'An invalid combination of DCU options was supplied.'

            $Resolution =
                'Remove mutually exclusive options.'
        }


        110 {

            $Description =
                'Multiple DCU commands were supplied.'

            $Resolution =
                'Run only one DCU command at a time.'
        }


        111 {

            $Description =
                'Duplicate DCU options were supplied.'

            $Resolution =
                'Remove duplicate options.'
        }


        112 {

            $Description =
                'An invalid Dell catalog was supplied.'

            $Resolution =
                'Verify the catalog path, URL and permissions.'
        }


        113 {

            $Description =
                'One or more DCU option values exceeded their supported length.'

            $Resolution =
                'Shorten the supplied option value.'
        }


        3000 {

            $Description =
                'Dell Client Management Service is not running.'

            $Resolution =
                'Start the Dell Client Management Service and retry.'
        }


        3001 {

            $Description =
                'Dell Client Management Service is not installed.'

            $Resolution =
                'Repair or reinstall Dell Command Update.'
        }


        3002 {

            $Description =
                'Dell Client Management Service is disabled.'

            $Resolution =
                'Enable the Dell Client Management Service and retry.'
        }


        3003 {

            $Description =
                'Dell Client Management Service is busy.'

            $Resolution =
                'Wait for the service to become available, then retry.'

            $Category =
                'Retryable'

            $Retryable =
                $true
        }


        3004 {

            $Description =
                'Dell Client Management Service is performing a DCU self-update.'

            $Resolution =
                'Wait for the self-update to finish, then retry.'

            $Category =
                'Retryable'

            $Retryable =
                $true
        }


        3005 {

            $Description =
                'Dell Client Management Service is installing pending updates.'

            $Resolution =
                'Wait for the current operation to finish, then retry.'

            $Category =
                'Retryable'

            $Retryable =
                $true
        }
    }


    # ========================================================
    # SCAN-SPECIFIC CODES
    # ========================================================

    if (
        $Operation -eq 'Scan'
    ) {

        switch ($ExitCode) {

            500 {

                $Description =
                    'No updates were found for the system using the requested scan filters.'

                $Resolution =
                    'The system is up to date for the requested Dell driver filter.'

                $Category =
                    'NoUpdates'

                $NoUpdates =
                    $true
            }


            501 {

                $Description =
                    'Dell Command Update encountered an error while determining available updates.'

                $Resolution =
                    'Retry the scan.'

                $Category =
                    'Retryable'

                $Retryable =
                    $true
            }


            502 {

                $Description =
                    'The Dell Command Update scan was cancelled.'

                $Resolution =
                    'Retry the scan if the cancellation was not intentional.'
            }


            503 {

                $Description =
                    'Dell Command Update encountered a download/network error during scan.'

                $Resolution =
                    'Verify internet connectivity and retry.'

                $Category =
                    'Retryable'

                $Retryable =
                    $true
            }
        }
    }


    # ========================================================
    # APPLY-SPECIFIC CODES
    # ========================================================

    if (
        $Operation -eq 'Apply'
    ) {

        switch ($ExitCode) {

            1000 {

                $Description =
                    'Dell Command Update could not retrieve the apply-updates result.'

                $Resolution =
                    'Retry the apply operation.'

                $Category =
                    'Retryable'

                $Retryable =
                    $true
            }


            1001 {

                $Description =
                    'The Dell Command Update apply operation was cancelled.'

                $Resolution =
                    'Retry if the cancellation was not intentional.'
            }


            1002 {

                $Description =
                    'Dell Command Update encountered a download/network error while applying updates.'

                $Resolution =
                    'Verify internet connectivity and retry.'

                $Category =
                    'Retryable'

                $Retryable =
                    $true
            }
        }
    }


    # Compatibility with tools/installers that may bubble up
    # MSI-style reboot-required code 3010.

    if (
        $ExitCode -eq 3010
    ) {

        $Description =
            'The Dell update operation completed and requested a restart.'

        $Resolution =
            'Restart Windows to complete the operation.'

        $Category =
            'RestartRequired'

        $RestartRequired =
            $true
    }


    return [PSCustomObject]@{

        ExitCode =
            $ExitCode

        Operation =
            $Operation

        Category =
            $Category

        Description =
            $Description

        Resolution =
            $Resolution

        Retryable =
            $Retryable

        RestartRequired =
            $RestartRequired

        NoUpdates =
            $NoUpdates
    }
}

function Write-DellDCUExitInfo {

    param(
        [Parameter(Mandatory)]
        $ExitInfo,

        [Parameter(Mandatory)]
        [string]$Prefix
    )


    $Level =
        'INFO'


    if (
        $ExitInfo.Category -eq 'Error'
    ) {

        $Level =
            'ERROR'
    }
    elseif (
        $ExitInfo.Category -in @(
            'Retryable'
            'RestartRequired'
        )
    ) {

        $Level =
            'WARNING'
    }


    Write-Log `
        -Message (
            "$Prefix exit code $($ExitInfo.ExitCode): " +
            "$($ExitInfo.Description) " +
            "Resolution: $($ExitInfo.Resolution)"
        ) `
        -Level $Level
}

function Invoke-DellDCUWithRetry {

    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [Parameter(Mandatory)]
        [ValidateSet(
            'Scan',
            'Apply'
        )]
        [string]$Operation,

        [Parameter(Mandatory)]
        [string]$ProcessName,

        [int]$MaximumAttempts = 3,

        [int]$RetryDelaySeconds = 30
    )


    for (
        $Attempt = 1;
        $Attempt -le $MaximumAttempts;
        $Attempt++
    ) {

        Write-Log -Message (
            "$ProcessName attempt $Attempt of $MaximumAttempts."
        )


        $ProcessResult =
            Invoke-ProcessWithTimeout `
                -FilePath $FilePath `
                -ArgumentList $ArgumentList `
                -TimeoutSeconds $OEMProcessTimeoutSeconds `
                -ProcessName $ProcessName


        $ExitInfo =
            Get-DellDCUExitInfo `
                -ExitCode $ProcessResult.ExitCode `
                -Operation $Operation


        Write-DellDCUExitInfo `
            -ExitInfo $ExitInfo `
            -Prefix $ProcessName


        if (
            -not $ExitInfo.Retryable
        ) {

            return [PSCustomObject]@{

                ProcessResult =
                    $ProcessResult

                ExitInfo =
                    $ExitInfo

                Attempts =
                    $Attempt
            }
        }


        if (
            $Attempt -lt $MaximumAttempts
        ) {

            Write-Log `
                -Message (
                    "$ProcessName returned a retryable Dell code. " +
                    "Waiting $RetryDelaySeconds seconds before retry."
                ) `
                -Level 'WARNING'


            Start-Sleep `
                -Seconds $RetryDelaySeconds
        }
    }


    return [PSCustomObject]@{

        ProcessResult =
            $ProcessResult

        ExitInfo =
            $ExitInfo

        Attempts =
            $MaximumAttempts
    }
}

function Invoke-DellDriverUpdate {

    Write-Log -Message (
        'Starting Dell Command Update driver update.'
    )


    $DCU =
        Get-DellCommandUpdatePath


    if (-not $DCU) {

        throw (
            'Dell Command Update CLI was not found.'
        )
    }


    Write-Log -Message (
        "Dell Command Update executable: $DCU"
    )


    $DellWorkingPath =
        Join-Path `
            $WorkingPath `
            'Dell'


    if (-not (
        Test-Path -LiteralPath $DellWorkingPath
    )) {

        New-Item `
            -Path $DellWorkingPath `
            -ItemType Directory `
            -Force |
            Out-Null
    }


    $ScanLog =
        Join-Path `
            $DellWorkingPath `
            'Dell-Scan.log'


    $ApplyLog =
        Join-Path `
            $DellWorkingPath `
            'Dell-Apply.log'


    $DellScanReportPath =
        Join-Path `
            $DellWorkingPath `
            'ScanReport'


    if (-not (
        Test-Path -LiteralPath $DellScanReportPath
    )) {

        New-Item `
            -Path $DellScanReportPath `
            -ItemType Directory `
            -Force |
            Out-Null
    }


    $ApplicableUpdatesXml =
        Join-Path `
            $DellScanReportPath `
            'DCUApplicableUpdates.xml'


    # ========================================================
    # PHASE 1 + 2
    # ========================================================
    #
    # Phase 1:
    #   - Remove stale scan XML.
    #   - Scan before apply.
    #   - Apply only when a fresh report contains updates.
    #
    # Phase 2:
    #   - Interpret documented DCU exit codes.
    #   - Correctly treat scan code 500 as "no updates".
    #   - Correctly treat code 6 as "another DCU instance".
    #   - Retry transient scan/apply/service-busy failures.
    #   - Translate restart-required results into ITINO 3010
    #     restart-marker behavior.
    # ========================================================


    # ========================================================
    # REMOVE STALE REPORT
    # ========================================================

    if (
        Test-Path -LiteralPath $ApplicableUpdatesXml
    ) {

        Write-Log -Message (
            'Removing stale Dell DCU applicable-updates report before scan: ' +
            $ApplicableUpdatesXml
        )


        Remove-Item `
            -LiteralPath $ApplicableUpdatesXml `
            -Force `
            -ErrorAction Stop
    }
    else {

        Write-Log -Message (
            'No stale Dell DCU applicable-updates report was present.'
        )
    }


    # ========================================================
    # SCAN WITH RETRY + EXIT-CODE INTERPRETATION
    # ========================================================

    Write-Log -Message (
        'Scanning Dell system for applicable driver updates before apply.'
    )


    $ScanResult =
        Invoke-DellDCUWithRetry `
            -FilePath $DCU `
            -ArgumentList @(
                '/scan'
                '-silent'
                '-updateType=driver'
                "-report=`"$DellScanReportPath`""
                "-outputLog=`"$ScanLog`""
            ) `
            -Operation 'Scan' `
            -ProcessName 'Dell Command Update scan' `
            -MaximumAttempts 3 `
            -RetryDelaySeconds 30


    $ScanInfo =
        $ScanResult.ExitInfo


    if (
        $ScanInfo.NoUpdates
    ) {

        Write-Log -Message (
            'Dell Command Update confirmed that no applicable driver updates exist. ' +
            '/applyUpdates will be skipped.'
        )


        return
    }


    if (
        $ScanInfo.RestartRequired
    ) {

        Set-RestartRequired `
            -Reason (
                'Dell Command Update scan indicates that Windows must be restarted ' +
                'before Dell updates can continue.'
            )


        Write-Log `
            -Message (
                'Dell scan cannot continue until a restart is completed. ' +
                'Skipping Dell apply for this deployment run.'
            ) `
            -Level 'WARNING'


        return
    }


    if (
        $ScanInfo.Category -ne 'Success'
    ) {

        throw (
            'Dell Command Update scan failed. ' +
            "Exit code: $($ScanInfo.ExitCode). " +
            "$($ScanInfo.Description)"
        )
    }


    # ========================================================
    # READ FRESH DCU REPORT
    # ========================================================

    if (-not (
        Test-Path -LiteralPath $ApplicableUpdatesXml
    )) {

        Write-Log -Message (
            'Dell Command Update scan completed successfully but no ' +
            'DCUApplicableUpdates.xml report was generated. ' +
            'Treating this as no applicable driver updates.'
        )


        return
    }


    Write-Log -Message (
        "Reading fresh Dell DCU scan report: $ApplicableUpdatesXml"
    )


    try {

        $DellScanXml =
            New-Object System.Xml.XmlDocument


        $DellScanXml.PreserveWhitespace =
            $true


        $DellScanXml.Load(
            $ApplicableUpdatesXml
        )
    }
    catch {

        throw (
            'Unable to parse Dell DCU applicable-updates report. ' +
            "Reason: $($_.Exception.Message)"
        )
    }


    $ApplicableUpdates =
        @(
            $DellScanXml.updates.update
        )


    $ApplicableCount =
        $ApplicableUpdates.Count


    Write-Log -Message (
        "Dell fresh scan applicable driver update count: $ApplicableCount"
    )


    if (
        $ApplicableCount -eq 0
    ) {

        Write-Log -Message (
            'Dell Command Update fresh scan found no applicable driver updates. ' +
            'Skipping /applyUpdates.'
        )


        return
    }


    # ========================================================
    # LOG UPDATE DETAILS
    # ========================================================

    foreach (
        $DellUpdate in $ApplicableUpdates
    ) {

        $UpdateName =
            [string]$DellUpdate.name


        $UpdateVersion =
            [string]$DellUpdate.version


        $UpdateType =
            [string]$DellUpdate.type


        if (
            [string]::IsNullOrWhiteSpace(
                $UpdateName
            )
        ) {

            $UpdateName =
                'Unnamed Dell update'
        }


        Write-Log -Message (
            'Dell Command Update found: ' +
            "$UpdateName | Version=$UpdateVersion | Type=$UpdateType"
        )
    }


    # ========================================================
    # APPLY WITH RETRY + EXIT-CODE INTERPRETATION
    # ========================================================

    Write-Log -Message (
        "Applying $ApplicableCount Dell driver update(s) reported by the fresh scan."
    )


    $ApplyResult =
        Invoke-DellDCUWithRetry `
            -FilePath $DCU `
            -ArgumentList @(
                '/applyUpdates'
                '-updateType=driver'
                '-silent'
                '-reboot=disable'
                "-outputLog=`"$ApplyLog`""
            ) `
            -Operation 'Apply' `
            -ProcessName 'Dell Command Update apply' `
            -MaximumAttempts 3 `
            -RetryDelaySeconds 30


    $ApplyInfo =
        $ApplyResult.ExitInfo


    if (
        $ApplyInfo.RestartRequired
    ) {

        Set-RestartRequired `
            -Reason (
                'Dell Command Update requested a restart.'
            )


        Write-Log -Message (
            'Dell driver update completed and requested a restart.'
        )


        return
    }


    if (
        $ApplyInfo.Category -ne 'Success'
    ) {

        throw (
            'Dell Command Update apply failed. ' +
            "Exit code: $($ApplyInfo.ExitCode). " +
            "$($ApplyInfo.Description)"
        )
    }


    Write-Log -Message (
        'Dell driver update completed successfully.'
    )
}


# ============================================================
# HP IMAGE ASSISTANT
# ============================================================

function Get-HPImageAssistantPath {

    $PossibleRoots =
        @(
            (
                Join-Path `
                    $ToolsPath `
                    'HP\HPIA'
            )

            'C:\Program Files\HP\HPIA'

            'C:\Program Files (x86)\HP\HPIA'
        )


    foreach (
        $Root in $PossibleRoots
    ) {

        if (-not (
            Test-Path -LiteralPath $Root
        )) {

            continue
        }


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


    return $null
}


function Invoke-HPDriverUpdate {

    Write-Log -Message (
        'Starting HP Image Assistant driver update.'
    )


    $HPIA =
        Get-HPImageAssistantPath


    if (-not $HPIA) {

        throw (
            'HP Image Assistant was not found.'
        )
    }


    Write-Log -Message (
        "HP Image Assistant executable: $HPIA"
    )


    $HPWorkingPath =
        Join-Path `
            $WorkingPath `
            'HP'


    $DownloadFolder =
        Join-Path `
            $HPWorkingPath `
            'Downloads'


    $ReportFolder =
        Join-Path `
            $HPWorkingPath `
            'Reports'


    foreach (
        $Directory in @(
            $HPWorkingPath,
            $DownloadFolder,
            $ReportFolder
        )
    ) {

        if (-not (
            Test-Path -LiteralPath $Directory
        )) {

            New-Item `
                -Path $Directory `
                -ItemType Directory `
                -Force |
                Out-Null
        }
    }


    $Process =
        Invoke-ProcessWithTimeout `
            -FilePath $HPIA `
            -ArgumentList @(
                '/Operation:Analyze'
                '/Category:Drivers'
                '/Selection:All'
                '/Action:Install'
                '/Silent'
                "/SoftpaqDownloadFolder:`"$DownloadFolder`""
                "/ReportFolder:`"$ReportFolder`""
            ) `
            -TimeoutSeconds $OEMProcessTimeoutSeconds `
            -ProcessName 'HP Image Assistant'


    Write-Log -Message (
        "HP Image Assistant exit code: $($Process.ExitCode)"
    )


    if (
        $Process.ExitCode -eq 3010
    ) {

        Set-RestartRequired `
            -Reason (
                'HP Image Assistant requested a restart.'
            )


        return
    }


    if (
        $Process.ExitCode -ne 0
    ) {

        throw (
            'HP Image Assistant failed. ' +
            "Exit code: $($Process.ExitCode)"
        )
    }


    Write-Log -Message (
        'HP driver update completed successfully.'
    )
}



# ============================================================
# LENOVO PROCESS / WEB HELPERS
# ============================================================

function Get-ItinoExceptionResponseUrl {

    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )


    $Current =
        $Exception


    while ($Current) {

        try {

            if (
                $Current.Response -and
                $Current.Response.ResponseUri
            ) {

                return [string]$Current.Response.ResponseUri.AbsoluteUri
            }
        }
        catch {

        }


        $Current =
            $Current.InnerException
    }


    return $null
}


function Invoke-LenovoSystemUpdateProcess {

    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [Parameter(Mandatory)]
        [int]$TimeoutSeconds
    )


    $ArgumentString =
        $ArgumentList -join ' '


    Write-Log -Message (
        "Starting Lenovo System Update process directly. Timeout: $TimeoutSeconds seconds."
    )


    Write-Log -Message (
        "Lenovo System Update arguments: $ArgumentString"
    )


    $StartInfo =
        New-Object System.Diagnostics.ProcessStartInfo


    $StartInfo.FileName =
        $FilePath


    $StartInfo.Arguments =
        $ArgumentString


    $StartInfo.UseShellExecute =
        $false


    $StartInfo.CreateNoWindow =
        $true


    $Process =
        New-Object System.Diagnostics.Process


    $Process.StartInfo =
        $StartInfo


    try {

        if (
            -not $Process.Start()
        ) {

            throw (
                'System.Diagnostics.Process.Start() returned False.'
            )
        }


        Write-Log -Message (
            "Lenovo System Update process ID: $($Process.Id)"
        )


        $Completed =
            $Process.WaitForExit(
                $TimeoutSeconds * 1000
            )


        if (-not $Completed) {

            Write-Log `
                -Message (
                    'Lenovo System Update exceeded the configured timeout. ' +
                    "Stopping process ID $($Process.Id)."
                ) `
                -Level 'ERROR'


            try {

                $Process.Kill()
            }
            catch {

                Write-Log `
                    -Message (
                        'Unable to terminate Lenovo System Update process. ' +
                        "Reason: $($_.Exception.Message)"
                    ) `
                    -Level 'WARNING'
            }


            throw (
                "Lenovo System Update timed out after $TimeoutSeconds seconds."
            )
        }


        # A parameterless WaitForExit() after the timed wait makes sure
        # asynchronous process state has been completely finalized before
        # ExitCode is read.
        $Process.WaitForExit()


        $ExitCode =
            [int]$Process.ExitCode


        Write-Log -Message (
            "Lenovo System Update process returned exit code: $ExitCode"
        )


        return [PSCustomObject]@{
            ExitCode = $ExitCode
            ProcessId = $Process.Id
        }
    }
    finally {

        if ($Process) {

            $Process.Dispose()
        }
    }
}


function Resolve-LenovoPackageFileUrl {

    param(
        [Parameter(Mandatory)]
        [string]$PackageXmlUrl,

        [Parameter(Mandatory)]
        [string]$FileName
    )


    if (
        [string]::IsNullOrWhiteSpace(
            $FileName
        )
    ) {

        return $FileName
    }


    if (
        $FileName -match '^https?://'
    ) {

        return $FileName
    }


    try {

        $BaseUri =
            New-Object System.Uri(
                $PackageXmlUrl
            )


        $ResolvedUri =
            New-Object System.Uri(
                $BaseUri,
                $FileName
            )


        return $ResolvedUri.AbsoluteUri
    }
    catch {

        return $FileName
    }
}



function Get-LenovoPackageReferencedUrls {

    param(
        [Parameter(Mandatory)]
        [string]$PackageXmlPath,

        [Parameter(Mandatory)]
        [string]$OriginalPackageUrl
    )


    $PackageXml =
        New-Object System.Xml.XmlDocument


    $PackageXml.PreserveWhitespace =
        $true


    $PackageXml.Load(
        $PackageXmlPath
    )


    $ReferencedUrls =
        @()


    $FileNodes =
        @(
            $PackageXml.SelectNodes(
                '//*[local-name()="File"]'
            )
        )


    foreach (
        $FileNode in $FileNodes
    ) {

        $FileName =
            $null


        $NameAttribute =
            $FileNode.Attributes['Name']


        if ($NameAttribute) {

            $FileName =
                [string]$NameAttribute.Value
        }
        else {

            $NameNode =
                $FileNode.SelectSingleNode(
                    '*[local-name()="Name"]'
                )


            if ($NameNode) {

                $FileName =
                    [string]$NameNode.InnerText
            }
        }


        if (
            [string]::IsNullOrWhiteSpace(
                $FileName
            )
        ) {

            continue
        }


        $ResolvedUrl =
            Resolve-LenovoPackageFileUrl `
                -PackageXmlUrl $OriginalPackageUrl `
                -FileName $FileName


        if (
            $ResolvedUrl -match '^https?://'
        ) {

            $ReferencedUrls +=
                $ResolvedUrl
        }
    }


    return @(
        $ReferencedUrls |
        Sort-Object -Unique
    )
}


function Test-LenovoPackageReferencedFiles {

    param(
        [Parameter(Mandatory)]
        [string]$PackageXmlPath,

        [Parameter(Mandatory)]
        [string]$OriginalPackageUrl
    )


    $ReferencedUrls =
        @(
            Get-LenovoPackageReferencedUrls `
                -PackageXmlPath $PackageXmlPath `
                -OriginalPackageUrl $OriginalPackageUrl
        )


    $Unavailable =
        @()


    foreach (
        $ReferencedUrl in $ReferencedUrls
    ) {

        $TestResult =
            Test-LenovoCatalogPackageUrl `
                -Url $ReferencedUrl


        if (-not $TestResult.Success) {

            $Unavailable +=
                [PSCustomObject]@{
                    Url = $ReferencedUrl
                    StatusCode = $TestResult.StatusCode
                    Error = $TestResult.Error
                }
        }
    }


    return [PSCustomObject]@{
        ReferencedCount = $ReferencedUrls.Count
        Unavailable = $Unavailable
    }
}


function Convert-LenovoPackageXmlForLocalRepository {

    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$OriginalPackageUrl,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )


    $PackageXml =
        New-Object System.Xml.XmlDocument


    $PackageXml.PreserveWhitespace =
        $true


    $PackageXml.Load(
        $SourcePath
    )


    $FileNodes =
        @(
            $PackageXml.SelectNodes(
                '//*[local-name()="File"]'
            )
        )


    $RewrittenFileCount =
        0


    foreach (
        $FileNode in $FileNodes
    ) {

        $FileName =
            $null


        $NameAttribute =
            $FileNode.Attributes['Name']


        if ($NameAttribute) {

            $FileName =
                [string]$NameAttribute.Value
        }
        elseif (
            $FileNode.SelectSingleNode(
                '*[local-name()="Name"]'
            )
        ) {

            $FileName =
                [string]$FileNode.SelectSingleNode(
                    '*[local-name()="Name"]'
                ).InnerText
        }


        if (
            [string]::IsNullOrWhiteSpace(
                $FileName
            )
        ) {

            continue
        }


        $ResolvedFileUrl =
            Resolve-LenovoPackageFileUrl `
                -PackageXmlUrl $OriginalPackageUrl `
                -FileName $FileName


        if (
            $ResolvedFileUrl -eq $FileName
        ) {

            continue
        }


        if ($NameAttribute) {

            $NameAttribute.Value =
                $ResolvedFileUrl
        }
        else {

            $FileNode.SelectSingleNode(
                '*[local-name()="Name"]'
            ).InnerText =
                $ResolvedFileUrl
        }


        $RewrittenFileCount++
    }


    $PackageXml.Save(
        $DestinationPath
    )


    return $RewrittenFileCount
}


function New-LenovoMirroredFilteredRepository {

    param(
        [Parameter(Mandatory)]
        [string]$OriginalCatalogPath,

        [Parameter(Mandatory)]
        [string]$RepositoryPath
    )


    if (
        Test-Path -LiteralPath $RepositoryPath
    ) {

        Remove-Item `
            -LiteralPath $RepositoryPath `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }


    New-Item `
        -Path $RepositoryPath `
        -ItemType Directory `
        -Force |
        Out-Null


    $CatalogXml =
        New-Object System.Xml.XmlDocument


    $CatalogXml.PreserveWhitespace =
        $true


    $CatalogXml.Load(
        $OriginalCatalogPath
    )


    $PackageNodes =
        @(
            $CatalogXml.SelectNodes(
                '/packages/package'
            )
        )


    $Removed =
        @()


    $MirroredCount =
        0


    $ValidatedReferencedFileCount =
        0


    $RewrittenFileReferenceCount =
        0


    foreach (
        $PackageNode in $PackageNodes
    ) {

        $LocationNode =
            $PackageNode.SelectSingleNode(
                'location'
            )


        if (-not $LocationNode) {

            continue
        }


        $PackageUrl =
            $LocationNode.InnerText.Trim()


        if (
            [string]::IsNullOrWhiteSpace(
                $PackageUrl
            )
        ) {

            continue
        }


        $TemporaryPackagePath =
            $null


        $LocalPackagePath =
            $null


        try {

            $PackageUri =
                New-Object System.Uri(
                    $PackageUrl
                )


            $PackageFileName =
                [System.IO.Path]::GetFileName(
                    $PackageUri.AbsolutePath
                )


            if (
                [string]::IsNullOrWhiteSpace(
                    $PackageFileName
                )
            ) {

                $PackageFileName =
                    "Package-$MirroredCount.xml"
            }


            $TemporaryPackagePath =
                Join-Path `
                    $RepositoryPath `
                    (
                        'tmp-' +
                        $PackageFileName
                    )


            $LocalPackagePath =
                Join-Path `
                    $RepositoryPath `
                    $PackageFileName


            $WebClient =
                New-Object System.Net.WebClient


            try {

                $WebClient.DownloadFile(
                    $PackageUrl,
                    $TemporaryPackagePath
                )
            }
            finally {

                $WebClient.Dispose()
            }


            $ReferenceValidation =
                Test-LenovoPackageReferencedFiles `
                    -PackageXmlPath $TemporaryPackagePath `
                    -OriginalPackageUrl $PackageUrl


            $ValidatedReferencedFileCount +=
                $ReferenceValidation.ReferencedCount


            if (
                $ReferenceValidation.Unavailable.Count -gt 0
            ) {

                foreach (
                    $UnavailableReference in $ReferenceValidation.Unavailable
                ) {

                    Write-Log `
                        -Message (
                            '[RECOVERY] Lenovo package contains an unavailable referenced file. ' +
                            "Package=$PackageUrl; " +
                            "HTTP=$($UnavailableReference.StatusCode); " +
                            "File=$($UnavailableReference.Url)"
                        )
                }


                $FirstUnavailable =
                    $ReferenceValidation.Unavailable |
                    Select-Object -First 1


                $Removed +=
                    [PSCustomObject]@{
                        PackageUrl = $PackageUrl
                        Url = $FirstUnavailable.Url
                        Error = $FirstUnavailable.Error
                        Reason = 'ReferencedFileUnavailable'
                        BrokenReferenceCount = $ReferenceValidation.Unavailable.Count
                    }


                [void]$PackageNode.ParentNode.RemoveChild(
                    $PackageNode
                )


                Remove-Item `
                    -LiteralPath $TemporaryPackagePath `
                    -Force `
                    -ErrorAction SilentlyContinue


                Write-Log `
                    -Message (
                        '[RECOVERY] Removed Lenovo package from recovery repository because ' +
                        "$($ReferenceValidation.Unavailable.Count) referenced file(s) are unavailable. " +
                        "Package: $PackageUrl"
                    )


                continue
            }


            $RewrittenCount =
                Convert-LenovoPackageXmlForLocalRepository `
                    -SourcePath $TemporaryPackagePath `
                    -OriginalPackageUrl $PackageUrl `
                    -DestinationPath $LocalPackagePath


            $RewrittenFileReferenceCount +=
                $RewrittenCount


            Remove-Item `
                -LiteralPath $TemporaryPackagePath `
                -Force `
                -ErrorAction SilentlyContinue


            $LocationNode.InnerText =
                $PackageFileName


            $MirroredCount++
        }
        catch {

            $FailedUrl =
                Get-ItinoExceptionResponseUrl `
                    -Exception $_.Exception


            if (
                [string]::IsNullOrWhiteSpace(
                    $FailedUrl
                )
            ) {

                $FailedUrl =
                    $PackageUrl
            }


            $Removed +=
                [PSCustomObject]@{
                    PackageUrl = $PackageUrl
                    Url = $FailedUrl
                    Error = $_.Exception.Message
                    Reason = 'PackageXmlUnavailableOrInvalid'
                    BrokenReferenceCount = 0
                }


            [void]$PackageNode.ParentNode.RemoveChild(
                $PackageNode
            )


            if (
                $TemporaryPackagePath -and
                (
                    Test-Path -LiteralPath $TemporaryPackagePath
                )
            ) {

                Remove-Item `
                    -LiteralPath $TemporaryPackagePath `
                    -Force `
                    -ErrorAction SilentlyContinue
            }


            if (
                $LocalPackagePath -and
                (
                    Test-Path -LiteralPath $LocalPackagePath
                )
            ) {

                Remove-Item `
                    -LiteralPath $LocalPackagePath `
                    -Force `
                    -ErrorAction SilentlyContinue
            }


            Write-Log `
                -Message (
                    '[RECOVERY] Skipping Lenovo catalog package that could not be mirrored: ' +
                    "$FailedUrl. Reason: $($_.Exception.Message)"
                )
        }
    }


    $Remaining =
        @(
            $CatalogXml.SelectNodes(
                '/packages/package'
            )
        )


    if (
        $CatalogXml.DocumentElement -and
        $CatalogXml.DocumentElement.HasAttribute(
            'count'
        )
    ) {

        $CatalogXml.DocumentElement.SetAttribute(
            'count',
            [string]$Remaining.Count
        )
    }


    $MachineType =
        Get-LenovoMachineType


    $RepositoryCatalogPath =
        Join-Path `
            $RepositoryPath `
            "${MachineType}_Win11.xml"


    $CatalogXml.Save(
        $RepositoryCatalogPath
    )


    return [PSCustomObject]@{
        Removed = $Removed
        MirroredCount = $MirroredCount
        RemainingCount = $Remaining.Count
        ValidatedReferencedFileCount = $ValidatedReferencedFileCount
        RewrittenFileReferenceCount = $RewrittenFileReferenceCount
        RepositoryCatalogPath = $RepositoryCatalogPath
    }
}


# ============================================================
# LENOVO SYSTEM UPDATE
# ============================================================

function Get-LenovoSystemUpdateShimPath {

    $PossiblePaths =
        @(
            'C:\Program Files (x86)\Lenovo\System Update\tvsuShim.exe'
            'C:\Program Files\Lenovo\System Update\tvsuShim.exe'
        )


    foreach (
        $Path in $PossiblePaths
    ) {

        if (
            Test-Path -LiteralPath $Path
        ) {

            return $Path
        }
    }


    return $null
}


function Invoke-LenovoSystemUpdate {

    Write-Log -Message (
        'Starting Lenovo System Update.'
    )


    $TVSUShim =
        Get-LenovoSystemUpdateShimPath


    if (-not $TVSUShim) {

        throw (
            'Lenovo System Update tvsuShim.exe was not found.'
        )
    }


    Write-Log -Message (
        "Lenovo System Update executable: $TVSUShim"
    )


    $Arguments =
        @(
            '/CM'
            '-search'
            'C'
            '-action'
            'INSTALL'
            '-includerebootpackages'
            '1,3,4'
            '-noicon'
            '-noreboot'
            '-nolicense'
            '-defaultupdate'
        )


    Write-Log -Message (
        'Running Lenovo System Update using tvsuShim.exe.'
    )


    $Process =
        Invoke-LenovoSystemUpdateProcess `
            -FilePath $TVSUShim `
            -ArgumentList $Arguments `
            -TimeoutSeconds $OEMProcessTimeoutSeconds


    Write-Log -Message (
        "Lenovo System Update exit code: $($Process.ExitCode)"
    )


    if (
        $Process.ExitCode -eq 3010
    ) {

        Set-RestartRequired `
            -Reason (
                'Lenovo System Update requested a restart.'
            )


        return
    }


    if (
        $Process.ExitCode -ne 0
    ) {

        throw (
            'Lenovo System Update failed. ' +
            "Exit code: $($Process.ExitCode)"
        )
    }


    Write-Log -Message (
        'Lenovo System Update completed successfully.'
    )
}



# ============================================================
# LENOVO LSUCLIENT
# ============================================================

function Initialize-LenovoLSUClient {

    Write-Log -Message (
        'Preparing LSUClient for Lenovo update discovery.'
    )

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12

    $Installed =
        @(
            Get-Module `
                -ListAvailable `
                -Name $LenovoLSUClientModuleName `
                -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending
        )

    if (
        $Installed.Count -eq 0
    ) {

        Write-Log -Message (
            "$LenovoLSUClientModuleName is not installed. Installing from $LenovoLSUClientRepository."
        )

        $NuGet =
            Get-PackageProvider `
                -Name 'NuGet' `
                -ListAvailable `
                -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if (-not $NuGet) {

            Install-PackageProvider `
                -Name 'NuGet' `
                -MinimumVersion '2.8.5.201' `
                -Scope AllUsers `
                -Force `
                -Confirm:$false `
                -ErrorAction Stop |
                Out-Null
        }

        $Repository =
            Get-PSRepository `
                -Name $LenovoLSUClientRepository `
                -ErrorAction Stop

        $OriginalPolicy =
            [string]$Repository.InstallationPolicy

        try {

            if (
                $OriginalPolicy -ne 'Trusted'
            ) {

                Set-PSRepository `
                    -Name $LenovoLSUClientRepository `
                    -InstallationPolicy Trusted `
                    -ErrorAction Stop
            }

            Install-Module `
                -Name $LenovoLSUClientModuleName `
                -Repository $LenovoLSUClientRepository `
                -Scope AllUsers `
                -Force `
                -AllowClobber `
                -Confirm:$false `
                -ErrorAction Stop
        }
        finally {

            if (
                $OriginalPolicy -and
                $OriginalPolicy -ne 'Trusted'
            ) {

                try {

                    Set-PSRepository `
                        -Name $LenovoLSUClientRepository `
                        -InstallationPolicy $OriginalPolicy `
                        -ErrorAction Stop
                }
                catch {

                    Write-Log `
                        -Message (
                            "Could not restore PowerShell repository policy. Reason: $($_.Exception.Message)"
                        ) `
                        -Level 'WARNING'
                }
            }
        }
    }

    Import-Module `
        -Name $LenovoLSUClientModuleName `
        -Force `
        -ErrorAction Stop

    $LoadedModule =
        Get-Module `
            -Name $LenovoLSUClientModuleName |
        Sort-Object Version -Descending |
        Select-Object -First 1

    Write-Log -Message (
        "LSUClient loaded. Version: $($LoadedModule.Version)"
    )

    try {

        Set-LSUClientConfiguration `
            -MaxInstallerRuntime (
                New-TimeSpan -Seconds $OEMProcessTimeoutSeconds
            ) `
            -ErrorAction Stop

        Write-Log -Message (
            "LSUClient installer timeout set to $OEMProcessTimeoutSeconds seconds."
        )
    }
    catch {

        Write-Log `
            -Message (
                "Could not set LSUClient installer timeout. Reason: $($_.Exception.Message)"
            ) `
            -Level 'WARNING'
    }
}


function Get-LenovoMachineType {

    $ComputerSystem =
        Get-CimInstance `
            -ClassName Win32_ComputerSystem `
            -ErrorAction Stop

    $MachineType =
        ([string]$ComputerSystem.Model).Trim()

    if (
        $MachineType.Length -gt 4
    ) {

        $MachineType =
            $MachineType.Substring(
                0,
                4
            )
    }

    return $MachineType
}


function Test-LenovoCatalogPackageUrl {

    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    try {

        $Request =
            [System.Net.HttpWebRequest]::Create(
                $Url
            )

        $Request.Method =
            'GET'

        $Request.AllowAutoRedirect =
            $true

        $Request.Timeout =
            15000

        $Response =
            $Request.GetResponse()

        try {

            return [PSCustomObject]@{
                Success = $true
                StatusCode = [int]$Response.StatusCode
                Error = $null
            }
        }
        finally {

            $Response.Close()
        }
    }
    catch [System.Net.WebException] {

        $StatusCode =
            $null

        if (
            $_.Exception.Response
        ) {

            try {

                $StatusCode =
                    [int]$_.Exception.Response.StatusCode
            }
            catch {

                $StatusCode =
                    $null
            }
        }

        return [PSCustomObject]@{
            Success = $false
            StatusCode = $StatusCode
            Error = $_.Exception.Message
        }
    }
}


function New-LenovoFilteredCatalog {

    param(
        [Parameter(Mandatory)]
        [string]$OriginalCatalogPath,

        [Parameter(Mandatory)]
        [string]$FilteredCatalogPath
    )

    $CatalogXml =
        New-Object System.Xml.XmlDocument

    $CatalogXml.PreserveWhitespace =
        $true

    $CatalogXml.Load(
        $OriginalCatalogPath
    )

    $PackageNodes =
        @(
            $CatalogXml.SelectNodes(
                '/packages/package'
            )
        )

    $Removed =
        @()

    foreach (
        $PackageNode in $PackageNodes
    ) {

        $LocationNode =
            $PackageNode.SelectSingleNode(
                'location'
            )

        if (-not $LocationNode) {
            continue
        }

        $Url =
            $LocationNode.InnerText.Trim()

        if (
            [string]::IsNullOrWhiteSpace(
                $Url
            )
        ) {
            continue
        }

        $Result =
            Test-LenovoCatalogPackageUrl `
                -Url $Url

        if (-not $Result.Success) {

            $Removed +=
                [PSCustomObject]@{
                    Url = $Url
                    StatusCode = $Result.StatusCode
                    Error = $Result.Error
                }

            [void]$PackageNode.ParentNode.RemoveChild(
                $PackageNode
            )
        }
    }

    $Remaining =
        @(
            $CatalogXml.SelectNodes(
                '/packages/package'
            )
        )

    if (
        $CatalogXml.DocumentElement -and
        $CatalogXml.DocumentElement.HasAttribute(
            'count'
        )
    ) {

        $CatalogXml.DocumentElement.SetAttribute(
            'count',
            [string]$Remaining.Count
        )
    }

    $CatalogXml.Save(
        $FilteredCatalogPath
    )

    return [PSCustomObject]@{
        Removed = $Removed
        RemainingCount = $Remaining.Count
    }
}


function Invoke-LSUClientCatalogScanWithFallback {

    # If a cleaned recovery repository was already created earlier
    # in this script run, reuse it instead of downloading and
    # rebuilding the same Lenovo catalog for every LSUClient round.
    if (
        -not [string]::IsNullOrWhiteSpace(
            $script:LenovoLSURecoveryRepository
        ) -and
        (
            Test-Path `
                -LiteralPath $script:LenovoLSURecoveryRepository
        )
    ) {

        Write-Log -Message (
            '[RECOVERY] Reusing cleaned Lenovo LSUClient repository from ' +
            "an earlier round: $script:LenovoLSURecoveryRepository"
        )


        try {

            return @(
                Get-LSUpdate `
                    -Repository $script:LenovoLSURecoveryRepository `
                    -ErrorAction Stop
            )
        }
        catch {

            $CachedFailedUrl =
                Get-ItinoExceptionResponseUrl `
                    -Exception $_.Exception


            $CachedFailureDetail =
                $_.Exception.Message


            if (
                -not [string]::IsNullOrWhiteSpace(
                    $CachedFailedUrl
                )
            ) {

                $CachedFailureDetail +=
                    " URL: $CachedFailedUrl"
            }


            Write-Log `
                -Message (
                    'Cached Lenovo recovery repository could not be used. ' +
                    'The script will rebuild it. ' +
                    "Reason: $CachedFailureDetail"
                ) `
                -Level 'WARNING'


            $script:LenovoLSURecoveryRepository =
                $null
        }
    }


    try {

        return @(
            Get-LSUpdate `
                -ErrorAction Stop
        )
    }
    catch {

        $OriginalError =
            $_.Exception.Message


        $OriginalFailedUrl =
            Get-ItinoExceptionResponseUrl `
                -Exception $_.Exception


        $OriginalFailureDetail =
            $OriginalError


        if (
            -not [string]::IsNullOrWhiteSpace(
                $OriginalFailedUrl
            )
        ) {

            $OriginalFailureDetail +=
                " URL: $OriginalFailedUrl"
        }


        Write-Log `
            -Message (
                'Normal Get-LSUpdate failed. Attempting mirrored Lenovo catalog recovery. ' +
                "Reason: $OriginalFailureDetail"
            ) `
            -Level 'WARNING'
    }


    $MachineType =
        Get-LenovoMachineType


    $CatalogUrl =
        "https://download.lenovo.com/catalog/${MachineType}_Win11.xml"


    $RecoveryPath =
        Join-Path `
            $LenovoLSUPackagePath `
            'CatalogRecovery'


    if (
        -not (
            Test-Path -LiteralPath $RecoveryPath
        )
    ) {

        New-Item `
            -Path $RecoveryPath `
            -ItemType Directory `
            -Force |
            Out-Null
    }


    $OriginalCatalog =
        Join-Path `
            $RecoveryPath `
            "${MachineType}_Win11-Original.xml"


    $WebClient =
        New-Object System.Net.WebClient


    try {

        $WebClient.DownloadFile(
            $CatalogUrl,
            $OriginalCatalog
        )
    }
    finally {

        $WebClient.Dispose()
    }


    $LocalRepository =
        Join-Path `
            $RecoveryPath `
            'Repository'


    $MirrorResult =
        New-LenovoMirroredFilteredRepository `
            -OriginalCatalogPath $OriginalCatalog `
            -RepositoryPath $LocalRepository


    Write-Log -Message (
        'Lenovo mirrored recovery repository created. ' +
        "Mirrored packages: $($MirrorResult.MirroredCount). " +
        "Removed packages: $($MirrorResult.Removed.Count). " +
        "Remaining packages: $($MirrorResult.RemainingCount). " +
        "Validated referenced files: $($MirrorResult.ValidatedReferencedFileCount). " +
        "Rewritten package file references: $($MirrorResult.RewrittenFileReferenceCount)."
    )


    Write-Log -Message (
        '[RECOVERY] Lenovo catalog recovery completed successfully. ' +
        'The cleaned local repository is ready for the LSUClient retry.'
    )


    foreach (
        $RemovedPackage in $MirrorResult.Removed
    ) {

        Write-Log `
            -Message (
                '[RECOVERY] Removed Lenovo package from recovery repository. ' +
                "Reason=$($RemovedPackage.Reason); " +
                "Package=$($RemovedPackage.PackageUrl); " +
                "FailedReference=$($RemovedPackage.Url); " +
                "BrokenReferences=$($RemovedPackage.BrokenReferenceCount)"
            )
    }


    if (
        $MirrorResult.RemainingCount -eq 0
    ) {

        throw (
            'Lenovo mirrored catalog recovery produced no usable packages.'
        )
    }


    # Store the cleaned repository for later LSUClient rounds.
    $script:LenovoLSURecoveryRepository =
        $LocalRepository


    Write-Log -Message (
        '[RECOVERY] Cleaned Lenovo repository cached for later ' +
        "LSUClient rounds in this run: $LocalRepository"
    )


    Write-Log -Message (
        "Retrying LSUClient against mirrored local repository: $LocalRepository"
    )


    try {

        return @(
            Get-LSUpdate `
                -Repository $LocalRepository `
                -ErrorAction Stop
        )
    }
    catch {

        $RetryFailedUrl =
            Get-ItinoExceptionResponseUrl `
                -Exception $_.Exception


        $RetryDetail =
            $_.Exception.Message


        if (
            -not [string]::IsNullOrWhiteSpace(
                $RetryFailedUrl
            )
        ) {

            $RetryDetail +=
                " URL: $RetryFailedUrl"
        }


        # Do not preserve a repository that failed its own retry.
        $script:LenovoLSURecoveryRepository =
            $null


        throw (
            'LSUClient mirrored local repository retry failed. ' +
            "Reason: $RetryDetail"
        )
    }
}


function Get-LenovoLSUApplicableUpdates {

    $Updates =
        @(
            Invoke-LSUClientCatalogScanWithFallback
        )

    $Selected =
        @(
            $Updates |
            Where-Object {

                $Unattended =
                    $false

                if (
                    $_.Installer -and
                    $null -ne $_.Installer.Unattended
                ) {

                    $Unattended =
                        [bool]$_.Installer.Unattended
                }

                $UpdateType =
                    [string]$_.Type

                $IsFirmwareClass =
                    $UpdateType -in @(
                        'BIOS',
                        'Firmware'
                    )

                $TypeAllowed =
                    (
                        $UpdateType -in $LenovoLSUUpdateTypes
                    ) -and
                    (
                        $AllowFirmwareUpdates -or
                        -not $IsFirmwareClass
                    )

                $SeverityAllowed =
                    ([string]$_.Severity) -in $LenovoLSUSeverities

                $Unattended -and
                $TypeAllowed -and
                $SeverityAllowed
            }
        )

    if (-not $AllowFirmwareUpdates) {

        $BlockedFirmwareUpdates =
            @(
                $Updates |
                Where-Object {
                    ([string]$_.Type) -in @(
                        'BIOS',
                        'Firmware'
                    )
                }
            )

        foreach (
            $BlockedFirmwareUpdate in $BlockedFirmwareUpdates
        ) {
            Write-Log `
                -Message (
                    '[FIRMWARE-SAFETY] Skipping Lenovo ' +
                    "$($BlockedFirmwareUpdate.Type) update. " +
                    "Title=$($BlockedFirmwareUpdate.Title); " +
                    "Version=$($BlockedFirmwareUpdate.Version)"
                ) `
                -Level 'WARNING'
        }
    }


    Write-Log -Message (
        "LSUClient selected $($Selected.Count) unattended update(s)."
    )

    foreach (
        $Update in $Selected
    ) {

        Write-Log -Message (
            'LSUClient found: ' +
            "Title=$($Update.Title); Version=$($Update.Version); " +
            "Type=$($Update.Type); Severity=$($Update.Severity)"
        )
    }

    return $Selected
}


function Get-LenovoLSUUpdateKey {

    param(
        [Parameter(Mandatory)]
        [object]$Update
    )


    $Title =
        [string]$Update.Title


    $Version =
        [string]$Update.Version


    $Type =
        [string]$Update.Type


    return (
        (
            $Title.Trim() +
            '|' +
            $Version.Trim() +
            '|' +
            $Type.Trim()
        ).ToLowerInvariant()
    )
}


function Test-LenovoLSUResultRequiresRestart {

    param(
        [Parameter(Mandatory)]
        [object[]]$InstallResults
    )

    foreach (
        $Result in $InstallResults
    ) {

        if (
            [string]$Result.PendingAction -in @(
                'REBOOT_SUGGESTED'
                'REBOOT_MANDATORY'
                'SHUTDOWN'
            )
        ) {
            return $true
        }
    }

    return $false
}


function Invoke-LenovoLSUClientUpdate {

    Write-Log -Message (
        'Starting Lenovo update scan/install through LSUClient.'
    )

    Initialize-LenovoLSUClient

    if (
        -not (
            Test-Path -LiteralPath $LenovoLSUPackagePath
        )
    ) {

        New-Item `
            -Path $LenovoLSUPackagePath `
            -ItemType Directory `
            -Force |
            Out-Null
    }


    # Tracks updates that installed successfully during this run
    # and are waiting for a restart before their final state can
    # be evaluated correctly by Lenovo.
    $InstalledPendingRestart =
        @{}


    for (
        $Round = 1;
        $Round -le $MaximumLenovoLSURounds;
        $Round++
    ) {

        Write-Log -Message (
            "LENOVO LSUCLIENT ROUND $Round OF $MaximumLenovoLSURounds"
        )

        $DiscoveredUpdates =
            @(
                Get-LenovoLSUApplicableUpdates
            )

        if (
            $DiscoveredUpdates.Count -eq 0
        ) {

            Write-Log -Message (
                "LSUClient round $Round found no selected updates."
            )

            return
        }


        $Updates =
            @()


        foreach (
            $Update in $DiscoveredUpdates
        ) {

            $UpdateKey =
                Get-LenovoLSUUpdateKey `
                    -Update $Update


            if (
                $InstalledPendingRestart.ContainsKey(
                    $UpdateKey
                )
            ) {

                Write-Log -Message (
                    '[REBOOT-PENDING] Skipping LSUClient package already ' +
                    'installed successfully during this run and still ' +
                    'reported as applicable before restart. ' +
                    "Title=$($Update.Title); Version=$($Update.Version); " +
                    "Type=$($Update.Type)"
                )

                continue
            }


            $Updates +=
                $Update
        }


        if (
            $Updates.Count -eq 0
        ) {

            Write-Log -Message (
                "LSUClient round $Round contains only package(s) already " +
                'installed successfully and waiting for restart. ' +
                'No repeated installation will be attempted.'
            )

            return
        }


        if (
            $Updates.Count -ne $DiscoveredUpdates.Count
        ) {

            Write-Log -Message (
                "LSUClient round $Round will process $($Updates.Count) " +
                "new update(s) after skipping " +
                "$($DiscoveredUpdates.Count - $Updates.Count) " +
                'reboot-pending repeated update(s).'
            )
        }


        Write-Log -Message (
            "Pre-downloading $($Updates.Count) Lenovo package(s)."
        )

        $Updates |
            Save-LSUpdate `
                -Path $LenovoLSUPackagePath `
                -ErrorAction Stop |
            Out-Null

        foreach (
            $Update in $Updates
        ) {

            Write-Log -Message (
                "Installing LSUClient package: $($Update.Title)"
            )

            $InstallResults =
                @(
                    Install-LSUpdate `
                        -Package $Update `
                        -Path $LenovoLSUPackagePath `
                        -SaveBIOSUpdateInfoToRegistry `
                        -ErrorAction Stop
                )


            $InstallSucceeded =
                $false


            $FailedInstallResults =
                @()


            foreach (
                $InstallResult in $InstallResults
            ) {

                Write-Log -Message (
                    'LSUClient result: ' +
                    "Title=$($Update.Title); " +
                    "Success=$($InstallResult.Success); " +
                    "ExitCode=$($InstallResult.ExitCode); " +
                    "PendingAction=$($InstallResult.PendingAction); " +
                    "FailureReason=$($InstallResult.FailureReason)"
                )


                if (
                    [bool]$InstallResult.Success
                ) {

                    $InstallSucceeded =
                        $true
                }
                else {

                    $FailedInstallResults +=
                        $InstallResult
                }
            }


            if (
                $FailedInstallResults.Count -gt 0
            ) {

                $FailureDetails =
                    @()


                foreach (
                    $FailedResult in $FailedInstallResults
                ) {

                    $FailureDetails +=
                        (
                            "ExitCode=$($FailedResult.ExitCode), " +
                            "PendingAction=$($FailedResult.PendingAction), " +
                            "FailureReason=$($FailedResult.FailureReason)"
                        )
                }


                throw (
                    'LSUClient returned an unsuccessful install result for ' +
                    "'$($Update.Title)' version '$($Update.Version)'. " +
                    'This is treated as a real Lenovo update failure so ' +
                    'the Lenovo System Update fallback can take over. ' +
                    "Result: $($FailureDetails -join ' | ')"
                )
            }


            $RequiresRestart =
                Test-LenovoLSUResultRequiresRestart `
                    -InstallResults $InstallResults


            if (
                $RequiresRestart
            ) {

                Set-RestartRequired `
                    -Reason (
                        "LSUClient requested restart for $($Update.Title)."
                    )
            }


            if (
                $InstallSucceeded -and
                $RequiresRestart
            ) {

                $InstalledUpdateKey =
                    Get-LenovoLSUUpdateKey `
                        -Update $Update


                $InstalledPendingRestart[
                    $InstalledUpdateKey
                ] =
                    [PSCustomObject]@{
                        Title = [string]$Update.Title
                        Version = [string]$Update.Version
                        Type = [string]$Update.Type
                        InstalledRound = $Round
                    }


                Write-Log -Message (
                    '[REBOOT-PENDING] Recorded successfully installed ' +
                    'LSUClient package so it will not be installed again ' +
                    'during this run before restart. ' +
                    "Title=$($Update.Title); Version=$($Update.Version); " +
                    "Type=$($Update.Type); Round=$Round"
                )
            }
        }
    }
}


# ============================================================
# LENOVO COMPLETE FLOW
# ============================================================

function Invoke-LenovoDriverUpdate {

    Write-Log -Message (
        '============================================================'
    )

    Write-Log -Message (
        'LENOVO STEP 1 - INITIAL WINDOWS UPDATE'
    )

    Write-Log -Message (
        '============================================================'
    )

    Invoke-WindowsUpdateDriverUpdate `
        -PhaseName 'Lenovo initial Windows Update' `
        -MaximumPasses $MaximumWindowsUpdatePasses `
        -MaximumDownloadRetries $MaximumDownloadAttempts `
        -PassDelaySeconds $WindowsUpdatePassDelaySeconds `
        -RetryWaitSeconds $WindowsUpdateRetryWaitSeconds

    Write-Log -Message (
        '============================================================'
    )

    Write-Log -Message (
        'LENOVO STEP 2 - LSUCLIENT'
    )

    Write-Log -Message (
        '============================================================'
    )

    $LSUSucceeded =
        $false

    try {

        Invoke-LenovoLSUClientUpdate

        $LSUSucceeded =
            $true
    }
    catch {

        Write-Log `
            -Message (
                'LSUClient did not complete successfully. ' +
                'Lenovo System Update/tvsuShim.exe will now be used as backup. ' +
                "Reason: $($_.Exception.Message)"
            ) `
            -Level 'WARNING'
    }

    if (-not $LSUSucceeded) {

        Write-Log -Message (
            '============================================================'
        )

        Write-Log -Message (
            'LENOVO BACKUP - SYSTEM UPDATE / TVSUSHIM'
        )

        Write-Log -Message (
            '============================================================'
        )

        try {

            Invoke-LenovoSystemUpdate
        }
        catch {

            Write-Log `
                -Message (
                    'Lenovo System Update fallback also failed. ' +
                    'Continuing with final Windows Update. ' +
                    "Reason: $($_.Exception.Message)"
                ) `
                -Level 'WARNING'
        }
    }
    else {

        Write-Log -Message (
            'LSUClient completed successfully. ' +
            'Lenovo System Update remains installed for future maintenance.'
        )
    }

    Write-Log -Message (
        '============================================================'
    )

    Write-Log -Message (
        'LENOVO STEP 3 - FINAL WINDOWS UPDATE'
    )

    Write-Log -Message (
        '============================================================'
    )

    Invoke-WindowsUpdateDriverUpdate `
        -PhaseName 'Lenovo final Windows Update' `
        -MaximumPasses $MaximumWindowsUpdatePasses `
        -MaximumDownloadRetries $MaximumDownloadAttempts `
        -PassDelaySeconds $WindowsUpdatePassDelaySeconds `
        -RetryWaitSeconds $WindowsUpdateRetryWaitSeconds

    Write-Log -Message (
        'Lenovo driver update sequence completed.'
    )
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
            -ScriptName '03-Update-Drivers.ps1'


    Write-Log -Message (
        'Driver update stage started.'
    )


    Write-Log -Message (
        "Script version: $ScriptVersion"
    )


    # ========================================================
    # SETTINGS
    # ========================================================

    Write-Log -Message (
        "Write log files: $WriteLogFiles"
    )


    Write-Log -Message (
        "Unattended mode: $UnattendedMode"
    )


    Write-Log -Message (
        "Force Windows Update: $ForceWindowsUpdate"
    )


    Write-Log -Message (
        "Trigger Windows Update scan: $TriggerWindowsUpdateScan"
    )


    Write-Log -Message (
        "Maximum Windows Update passes: $MaximumWindowsUpdatePasses"
    )


    Write-Log -Message (
        "Maximum download attempts: $MaximumDownloadAttempts"
    )


    Write-Log -Message (
        "OEM process timeout: $OEMProcessTimeoutSeconds seconds"
    )


    Write-Log -Message (
        "BIOS/Firmware allowed by controller safety gate: $AllowFirmwareUpdates"
    )


    # ========================================================
    # ADMINISTRATOR
    # ========================================================

    $Identity =
        [Security.Principal.WindowsIdentity]::GetCurrent()


    $IsAdministrator =
        Test-IsAdministrator


    Write-Log -Message (
        "Running as user: $($Identity.Name)"
    )


    Write-Log -Message (
        "Running elevated as administrator: $IsAdministrator"
    )


    Write-Log -Message (
        "Require administrator: $RequireAdministrator"
    )


    if (
        $RequireAdministrator -and
        -not $IsAdministrator
    ) {

        throw (
            '03-Update-Drivers.ps1 must run with an ' +
            'elevated administrator token.'
        )
    }


    # ========================================================
    # HARDWARE INFORMATION
    # ========================================================

    if (-not (
        Test-Path -LiteralPath $HardwareFile
    )) {

        throw (
            'HardwareInformation.json was not found. ' +
            'Run 01-Gather-Hardware.ps1 first.'
        )
    }


    $Hardware =
        Get-Content `
            -LiteralPath $HardwareFile `
            -Raw |
        ConvertFrom-Json


    $Manufacturer =
        [string]$Hardware.Computer.Manufacturer


    $Model =
        [string]$Hardware.Computer.Model


    if (
        [string]::IsNullOrWhiteSpace(
            $Manufacturer
        )
    ) {

        throw (
            'Computer manufacturer could not be determined.'
        )
    }


    Write-Log -Message (
        "Manufacturer: $Manufacturer"
    )


    Write-Log -Message (
        "Model: $Model"
    )


    if (
        $Manufacturer -match 'LENOVO'
    ) {

        Write-Log -Message (
            "Close Lenovo Hotkey popup: $CloseLenovoHotkeyPopup"
        )

        Write-Log -Message (
            "Lenovo LSUClient module: $LenovoLSUClientModuleName"
        )

        Write-Log -Message (
            "Lenovo LSUClient repository: $LenovoLSUClientRepository"
        )

        Write-Log -Message (
            "Lenovo maximum LSUClient rounds: $MaximumLenovoLSURounds"
        )

        Write-Log -Message (
            "Lenovo LSUClient update types: $($LenovoLSUUpdateTypes -join ',')"
        )

        Write-Log -Message (
            "Lenovo LSUClient severities: $($LenovoLSUSeverities -join ',')"
        )
    }


    # ========================================================
    # FORCE WINDOWS UPDATE
    # ========================================================

    if ($ForceWindowsUpdate) {

        Write-Log `
            -Message (
                'ForceWindowsUpdate is enabled. ' +
                "OEM update method for '$Manufacturer' is bypassed."
            ) `
            -Level 'WARNING'


        Invoke-WindowsUpdateDriverUpdate `
            -PhaseName 'Forced Windows Update' `
            -MaximumPasses $MaximumWindowsUpdatePasses `
            -MaximumDownloadRetries $MaximumDownloadAttempts `
            -PassDelaySeconds $WindowsUpdatePassDelaySeconds `
            -RetryWaitSeconds $WindowsUpdateRetryWaitSeconds
    }
    else {

        # ====================================================
        # OEM SELECTION
        # ====================================================

        switch -Regex (
            $Manufacturer
        ) {

            # =================================================
            # DELL
            # =================================================
			'Dell' {

				Write-Log -Message (
					'Dell system detected.'
				)


				Write-Log -Message (
					'============================================================'
				)

				Write-Log -Message (
					'DELL STEP 1 - INITIAL WINDOWS UPDATE'
				)

				Write-Log -Message (
					'============================================================'
				)


				Invoke-WindowsUpdateDriverUpdate `
					-PhaseName 'Dell initial Windows Update' `
					-MaximumPasses $MaximumWindowsUpdatePasses `
					-MaximumDownloadRetries $MaximumDownloadAttempts `
					-PassDelaySeconds $WindowsUpdatePassDelaySeconds `
					-RetryWaitSeconds $WindowsUpdateRetryWaitSeconds


				Write-Log -Message (
					'============================================================'
				)

				Write-Log -Message (
					'DELL STEP 2 - DELL COMMAND UPDATE'
				)

				Write-Log -Message (
					'============================================================'
				)


				try {

					Invoke-DellDriverUpdate
				}
				catch {

					Write-Log `
						-Message (
							'Dell Command Update did not complete successfully. ' +
							'Continuing with final Windows Update. ' +
							"Reason: $($_.Exception.Message)"
						) `
						-Level 'WARNING'
				}


				Write-Log -Message (
					'============================================================'
				)

				Write-Log -Message (
					'DELL STEP 3 - FINAL WINDOWS UPDATE'
				)

				Write-Log -Message (
					'============================================================'
				)


				Invoke-WindowsUpdateDriverUpdate `
					-PhaseName 'Dell final Windows Update' `
					-MaximumPasses $MaximumWindowsUpdatePasses `
					-MaximumDownloadRetries $MaximumDownloadAttempts `
					-PassDelaySeconds $WindowsUpdatePassDelaySeconds `
					-RetryWaitSeconds $WindowsUpdateRetryWaitSeconds


				Write-Log -Message (
					'Dell driver update sequence completed.'
				)


				break
			}


			# ============================================================
			# HP
			# ============================================================

			'HP|Hewlett-Packard' {

				Write-Log -Message (
					'HP system detected.'
				)


				Write-Log -Message (
					'============================================================'
				)

				Write-Log -Message (
					'HP STEP 1 - INITIAL WINDOWS UPDATE'
				)

				Write-Log -Message (
					'============================================================'
				)


				Invoke-WindowsUpdateDriverUpdate `
					-PhaseName 'HP initial Windows Update' `
					-MaximumPasses $MaximumWindowsUpdatePasses `
					-MaximumDownloadRetries $MaximumDownloadAttempts `
					-PassDelaySeconds $WindowsUpdatePassDelaySeconds `
					-RetryWaitSeconds $WindowsUpdateRetryWaitSeconds


				Write-Log -Message (
					'============================================================'
				)

				Write-Log -Message (
					'HP STEP 2 - HP IMAGE ASSISTANT'
				)

				Write-Log -Message (
					'============================================================'
				)


				try {

					Invoke-HPDriverUpdate
				}
				catch {

					Write-Log `
						-Message (
							'HP Image Assistant did not complete successfully. ' +
							'Continuing with final Windows Update. ' +
							"Reason: $($_.Exception.Message)"
						) `
						-Level 'WARNING'
				}


				Write-Log -Message (
					'============================================================'
				)

				Write-Log -Message (
					'HP STEP 3 - FINAL WINDOWS UPDATE'
				)

				Write-Log -Message (
					'============================================================'
				)


				Invoke-WindowsUpdateDriverUpdate `
					-PhaseName 'HP final Windows Update' `
					-MaximumPasses $MaximumWindowsUpdatePasses `
					-MaximumDownloadRetries $MaximumDownloadAttempts `
					-PassDelaySeconds $WindowsUpdatePassDelaySeconds `
					-RetryWaitSeconds $WindowsUpdateRetryWaitSeconds


				Write-Log -Message (
					'HP driver update sequence completed.'
				)


				break
			}

            # =================================================
            # LENOVO
            # =================================================

            'Lenovo' {

                Write-Log -Message (
                    'Lenovo system detected.'
                )


                Invoke-LenovoDriverUpdate


                break
            }


            # =================================================
            # OTHER
            # =================================================

            default {

                Write-Log `
                    -Message (
                        "Manufacturer '$Manufacturer' does not have " +
                        'a configured OEM update method. ' +
                        'Using Windows Update.'
                    ) `
                    -Level 'WARNING'


                Invoke-WindowsUpdateDriverUpdate `
                    -PhaseName 'Windows Update' `
                    -MaximumPasses $MaximumWindowsUpdatePasses `
                    -MaximumDownloadRetries $MaximumDownloadAttempts `
                    -PassDelaySeconds $WindowsUpdatePassDelaySeconds `
                    -RetryWaitSeconds $WindowsUpdateRetryWaitSeconds


                break
            }
        }
    }


    # ========================================================
    # COMPLETE
    # ========================================================

    Write-Log -Message (
        'Driver update stage completed.'
    )


    # ========================================================
    # RESTART REQUIRED
    # ========================================================

    if (
        Test-Path -LiteralPath $RestartFile
    ) {

        Write-Log `
            -Message (
                'Driver update completed successfully. Restart required.'
            ) `
            -Level 'WARNING'


        Stop-LogRun `
            -RunID $RunID `
            -Result 'SUCCESS - RESTART REQUIRED'


        exit 3010
    }


    # ========================================================
    # SUCCESS
    # ========================================================

    Write-Log -Message (
        'Driver update completed successfully. No restart reported.'
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