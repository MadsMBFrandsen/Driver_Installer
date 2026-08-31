<#
.SYNOPSIS
    Runs the complete ITINO Driver Check And Update workflow.

.DESCRIPTION
    Runs the following scripts in order:

        00-Preflight.ps1
        01-Gather-Hardware.ps1
        02-Install-OEM-Update-Tool.ps1
        03-Update-Drivers.ps1
        04-Verify-Drivers.ps1

    The controller:
        - Verifies all scripts exist
        - Runs each script in a separate PowerShell process
        - Streams child script console output live
        - Captures child script output in memory
        - Stops on real failures
        - Continues when exit code 3010 is returned
        - Optionally creates normal debug logs
        - Preserves one error log only if deployment fails
        - Removes temporary working files after final completion
        - Does NOT remove working files when restart is required
        - Returns 0, 1, or 3010 to the parent deployment sequence

.EXIT CODES
    0    Complete success, no restart required
    1    Deployment failed
    3010 Complete success, restart required

.NOTES
    This script does not restart Windows.

    The surrounding PowerShell deployment sequence should:

        1. Run this controller
        2. Check the exit code
        3. If 3010:
            - save deployment state
            - restart Windows
            - resume deployment
            - run this controller again

    The parent deployment should limit complete driver deployment
    cycles to prevent an endless reboot loop.
#>

[CmdletBinding()]
param()


# ============================================================
# ITINO DRIVER DEPLOYMENT CONTROLLER
# ============================================================

$ScriptName =
    'Run-DriverDeployment.ps1'


# ============================================================
# VERSION HISTORY
# ============================================================

# ------------------------------------------------------------
# Title   : Cleanup Policy Simplification
# Version : 1.1.14
# Reason  : Removes the duplicate DriverRollback cleanup switch.
#           CleanupAfterDeployment is now the only setting that
#           controls final successful ITINO root deletion.
# Date    : 2026-08-31
# ------------------------------------------------------------

# ------------------------------------------------------------
# Title   : Session-Aware Console Transcript
# Version : 1.1.11
# Reason  : Prevents Cycle1/Cycle2 transcript files from an old
#           completed deployment session being overwritten when
#           a completely new deployment starts at Cycle 1.
# Date    : 2026-08-27
# ------------------------------------------------------------


# ------------------------------------------------------------
# Title   : Single Cleanup Switch
# Version : 1.1.7
# Reason  : Removes DeleteEntireItinoRootOnCleanSuccess and uses
#           CleanupAfterDeployment as the single master switch
#           for complete ITINO-root deletion on final success.
# Date    : 2026-08-26
# ------------------------------------------------------------


# ------------------------------------------------------------
# Title   : Validated Cycle / Single Instance Result
# Version : 1.1.6
# Reason  : Console transcript starts only after the deployment
#           mutex and cycle validation. Concurrent runs return
#           exit code 1618 without modifying active artifacts.
# Date    : 2026-08-26
# ------------------------------------------------------------


# ------------------------------------------------------------
# Title   : Reliable AC Power Detection
# Version : 1.1.5
# Reason  : Replaces Win32_Battery.BatteryStatus AC inference
#           with SystemInformation.PowerStatus.PowerLineStatus.
#           Firmware battery safety threshold raised to 50%.
# Date    : 2026-08-26
# ------------------------------------------------------------


# ------------------------------------------------------------
# Title   : Safe Native Console Transcript
# Version : 1.1.4
# Reason  : Uses Start-Transcript instead of the Phase 9.3
#           custom Write-Host wrapper. Keeps separate console
#           logs per restart cycle without changing startup.
# Date    : 2026-08-26
# ------------------------------------------------------------


# ------------------------------------------------------------
# Title   : Driver Verification Console Reporting
# Version : 1.0.0
# Reason  : Fixes blank device names in the final verification
#           output by falling back to FriendlyName, InstanceId,
#           DeviceID and PNPDeviceID. Also aligns the controller
#           summary with the current DriverVerification.json
#           property names and reads NewErrors correctly.
# Date    : 2026-08-21
# ------------------------------------------------------------

# ------------------------------------------------------------
# Title   : Deployment Sequence Integration
# Version : 1.1.0
# Reason  : Adds restart-cycle state, original rollback-baseline
#           preservation, maximum cycle protection, single-
#           instance protection, firmware power-safety gating,
#           failure artifact preservation and complete ITINO
#           cleanup after final clean success.
# Date    : 2026-08-25
# ------------------------------------------------------------

$ScriptVersion =
    '1.1.17'

$ScriptUpdated =
    '2026-08-31'


# ============================================================
# PHASE 10.20 - REPORTING CORRECTNESS RELEASE CANDIDATE
# ============================================================

$DriverDeploymentName =
    'ITINO Driver Deployment'

$DriverDeploymentVersion =
    '1.0.0-rc1'

$DriverDeploymentPhase =
    '10.20'

$DriverDeploymentReleaseChannel =
    'ReleaseCandidate'

$DriverDeploymentBuildDate =
    '2026-08-31'


# Optional GitHub/build-pipeline values.
$DriverDeploymentGitTag =
    [string]$env:ITINO_GIT_TAG

$DriverDeploymentGitCommit =
    [string]$env:ITINO_GIT_COMMIT


$env:ITINO_DRIVER_DEPLOYMENT_NAME =
    $DriverDeploymentName

$env:ITINO_DRIVER_DEPLOYMENT_VERSION =
    $DriverDeploymentVersion

$env:ITINO_DRIVER_DEPLOYMENT_PHASE =
    $DriverDeploymentPhase

$env:ITINO_DRIVER_DEPLOYMENT_RELEASE_CHANNEL =
    $DriverDeploymentReleaseChannel

$env:ITINO_DRIVER_DEPLOYMENT_BUILD_DATE =
    $DriverDeploymentBuildDate

$env:ITINO_CONTROLLER_VERSION =
    $ScriptVersion


$ErrorActionPreference =
    'Stop'


# ============================================================
# DEPLOYMENT OPTIONS
# ============================================================
#
# TEST PC
#
# $WriteLogFiles             = $true
# $KeepErrorLogOnFailure     = $true
# $CleanupAfterDeployment    = $false
# $UnattendedMode            = $true
# $CloseLenovoHotkeyPopup    = $true
# $RequireAdministrator      = $false
#
#
# PRODUCTION / CUSTOMER PC
#
# $WriteLogFiles             = $false
# $KeepErrorLogOnFailure     = $true
# $CleanupAfterDeployment    = $true
# $UnattendedMode            = $true
# $CloseLenovoHotkeyPopup    = $true
# $RequireAdministrator      = $true
#
# ============================================================


# Create persistent normal log files.
#
# Production:
#     $false
#
# Testing:
#     $true

$WriteLogFiles =
    $false


# Save a complete native PowerShell transcript for each
# deployment cycle.
#
# Testing:
#     $true
#
# Production:
#     $false
#
# Files:
#   C:\ProgramData\Itino\DriverDeployment\ConsoleOutput-SessionA1B2C3D4-Cycle1.log
#   C:\ProgramData\Itino\DriverDeployment\ConsoleOutput-SessionA1B2C3D4-Cycle2.log
#
# The transcript survives exit 3010 and exit 1.
# On final exit 0 the transcript is stopped before the complete
# C:\ProgramData\Itino folder is deleted.

$SaveFullConsoleOutput =
    $true


# If deployment fails, preserve one combined error log:
#
# C:\ProgramData\Itino\DriverDeployment-Error.log

$KeepErrorLogOnFailure =
    $true


# MASTER CLEANUP SWITCH
#
# $false:
#   Keep all C:\ProgramData\Itino deployment data.
#   Useful while testing/debugging.
#
# $true:
#   On FINAL clean success (exit 0), remove the complete:
#       C:\ProgramData\Itino\
#
# IMPORTANT:
#   - Exit 3010 always preserves ITINO state for the next cycle.
#   - Real failures preserve artifacts when
#     $PreserveArtifactsOnFailure = $true.
#
# This is the only switch controlling complete ITINO-root
# deletion after a successful deployment.
#
# DriverRollback is part of C:\ProgramData\Itino and follows
# this same switch. There is no separate rollback cleanup option.

$CleanupAfterDeployment =
    $false


# Copy the AutoResume log and console transcript files to the
# same drive/location as this deployment package.
#
# Example when scripts run from:
#   D:\Driver_Installer
#
# Logs are copied to:
#   D:\Driver_Installer\Logs\<Manufacturer>\<Computer>\<SessionId>\
#
# This happens before final ProgramData cleanup, so the logs
# survive even when CleanupAfterDeployment = $true.
$CopyLogsToScriptLocation =
    $true


# Folder created beside Run-DriverDeployment.ps1.
$CopiedLogsFolderName =
    'Logs'



# Run without requiring user interaction.

$UnattendedMode =
    $true


# Automatically close Lenovo Hotkey Installer completion popup.

$CloseLenovoHotkeyPopup =
    $true


# Require administrator rights for OEM tool installation
# and driver installation.
#
# Production:
#     $true
#
# Developer testing without elevation:
#     $false

$RequireAdministrator =
    $true

# ============================================================
# PHASE 9 - DEPLOYMENT SEQUENCE SAFETY
# ============================================================

$PreserveInitialDriverBaselineAcrossRestarts =
    $true

$MaximumDeploymentCycles =
    3

$EnableSingleInstanceProtection =
    $true

# Keep ALL ITINO diagnostics/rollback data on a real failure.
$PreserveArtifactsOnFailure =
    $true

# If a battery exists, BIOS/Firmware updates require at least
# this charge level and the battery must not be discharging.
$MinimumFirmwareBatteryPercent =
    50

# Guard checked between controller stages.
$MaximumControllerRuntimeMinutes =
    120


# ============================================================
# PREFLIGHT REQUIREMENTS
# ============================================================

$MinimumSystemDriveFreeGB =
    10


$WebTimeoutSeconds =
    15


# Minimum required PowerShell major version.
#
# Example:
#
# 5 = PowerShell 5 or newer is allowed.
#
# PowerShell 4 or older will fail preflight.

$MinimumPowerShellMajorVersion =
    5

# ============================================================
# OEM DOWNLOAD CONFIGURATION
# ============================================================
#
# Keep all OEM discovery/download URLs and known-good fallback versions
# here so they can be maintained in one place.
#
# Script 02 reads these values through environment variables.
#
# Dell and HP:
#   The official page is used for dynamic latest-version discovery.
#   The fallback package is used only when discovery cannot safely resolve
#   a package that is at least as new as the configured fallback.
#
# Lenovo:
#   Script 02 installs Lenovo System Update for future maintenance.
#   The Lenovo support HTML page is not scraped because it returns HTTP 403
#   to scripted requests, so the known-good installer version and direct
#   download URL are configured here.
#   Script 03 still uses LSUClient for the first-start automated driver,
#   BIOS and firmware update workflow.
#

$DellCommandUpdateOfficialPageUrl =
    'https://www.dell.com/support/kbdoc/en-us/000177325/dell-command-update'

$DellCommandUpdateFallbackVersion =
    '5.7.1'

$DellCommandUpdateFallbackDownloadUrl =
    'https://dl.dell.com/FOLDER14847331M/2/Dell-Command-Update-Windows-Universal-Application_P0P70_WIN64_5.7.1_A00.EXE'


$HPImageAssistantOfficialPageUrl =
    'https://ftp.ext.hp.com/pub/caps-softpaq/cmit/HPIA.html'

$HPImageAssistantFallbackVersion =
    '5.3.6'

$HPImageAssistantFallbackDownloadUrl =
    'https://hpia.hpcloud.hp.com/downloads/hpia/hp-hpia-5.3.6.exe'


$LenovoSystemUpdateVersion =
    '5.08.03.59'

# Lenovo support/reference page only.
# Do not scrape this page from PowerShell because Lenovo currently
# returns HTTP 403 to scripted requests.
# https://support.lenovo.com/nz/en/solutions/ht037099

$LenovoSystemUpdateDownloadUrl =
    'https://download.lenovo.com/pccbbs/thinkvantage_en/system_update_5.08.03.59.exe'


$LenovoLSUClientModuleName =
    'LSUClient'

$LenovoLSUClientRepository =
    'PSGallery'

$LenovoLSUClientMaximumRounds =
    3

$LenovoLSUClientUpdateTypes =
    'Driver,BIOS,Firmware'

$LenovoLSUClientSeverities =
    'Critical,Recommended'


# ============================================================
# EXPORT OPTIONS TO CHILD POWERSHELL PROCESSES
# ============================================================

$env:ITINO_WRITE_LOG_FILES =
    if ($WriteLogFiles) {
        '1'
    }
    else {
        '0'
    }




$env:ITINO_UNATTENDED_MODE =
    if ($UnattendedMode) {
        '1'
    }
    else {
        '0'
    }


$env:ITINO_CLOSE_LENOVO_HOTKEY_POPUP =
    if ($CloseLenovoHotkeyPopup) {
        '1'
    }
    else {
        '0'
    }


$env:ITINO_REQUIRE_ADMINISTRATOR =
    if ($RequireAdministrator) {
        '1'
    }
    else {
        '0'
    }


$env:ITINO_PRESERVE_INITIAL_DRIVER_BASELINE =
    if ($PreserveInitialDriverBaselineAcrossRestarts) {
        '1'
    }
    else {
        '0'
    }


$env:ITINO_MINIMUM_FIRMWARE_BATTERY_PERCENT =
    [string]$MinimumFirmwareBatteryPercent


$env:ITINO_MINIMUM_SYSTEM_DRIVE_FREE_GB =
    [string]$MinimumSystemDriveFreeGB


$env:ITINO_WEB_TIMEOUT_SECONDS =
    [string]$WebTimeoutSeconds


$env:ITINO_MINIMUM_POWERSHELL_MAJOR_VERSION =
    [string]$MinimumPowerShellMajorVersion


# OEM source configuration for 02-Install-OEM-Update-Tool.ps1

$env:ITINO_DELL_COMMAND_UPDATE_OFFICIAL_PAGE_URL =
    [string]$DellCommandUpdateOfficialPageUrl

$env:ITINO_DELL_COMMAND_UPDATE_FALLBACK_VERSION =
    [string]$DellCommandUpdateFallbackVersion

$env:ITINO_DELL_COMMAND_UPDATE_FALLBACK_DOWNLOAD_URL =
    [string]$DellCommandUpdateFallbackDownloadUrl

$env:ITINO_HP_IMAGE_ASSISTANT_OFFICIAL_PAGE_URL =
    [string]$HPImageAssistantOfficialPageUrl

$env:ITINO_HP_IMAGE_ASSISTANT_FALLBACK_VERSION =
    [string]$HPImageAssistantFallbackVersion

$env:ITINO_HP_IMAGE_ASSISTANT_FALLBACK_DOWNLOAD_URL =
    [string]$HPImageAssistantFallbackDownloadUrl


$env:ITINO_LENOVO_SYSTEM_UPDATE_VERSION =
    [string]$LenovoSystemUpdateVersion

$env:ITINO_LENOVO_SYSTEM_UPDATE_DOWNLOAD_URL =
    [string]$LenovoSystemUpdateDownloadUrl
$env:ITINO_LENOVO_LSUCLIENT_MODULE_NAME =
    [string]$LenovoLSUClientModuleName

$env:ITINO_LENOVO_LSUCLIENT_REPOSITORY =
    [string]$LenovoLSUClientRepository

$env:ITINO_LENOVO_LSUCLIENT_MAXIMUM_ROUNDS =
    [string]$LenovoLSUClientMaximumRounds

$env:ITINO_LENOVO_LSUCLIENT_UPDATE_TYPES =
    [string]$LenovoLSUClientUpdateTypes

$env:ITINO_LENOVO_LSUCLIENT_SEVERITIES =
    [string]$LenovoLSUClientSeverities

# ============================================================
# PATHS
# ============================================================

$ScriptRoot =
    $PSScriptRoot


$ScriptsPath =
    Join-Path `
        $ScriptRoot `
        'Scripts'



$CopiedLogsRoot =
    Join-Path `
        $ScriptRoot `
        $CopiedLogsFolderName


$ItinoRoot =
    'C:\ProgramData\Itino'


$BasePath =
    Join-Path `
        $ItinoRoot `
        'DriverDeployment'


$DeploymentStateFile =
    Join-Path `
        $ItinoRoot `
        'DriverDeploymentState.json'


$DeploymentResultFile =
    Join-Path `
        $ItinoRoot `
        'DriverDeploymentResult.json'


$LogPath =
    Join-Path `
        $BasePath `
        'Logs'


$MainLogFile =
    Join-Path `
        $LogPath `
        'DriverDeployment-Main.log'


$script:ConsoleOutputFile =
    $null

$script:ConsoleOutputCycle =
    1

$script:ConsoleTranscriptStarted =
    $false


$RestartFile =
    Join-Path `
        $BasePath `
        'RestartRequired.txt'


# ============================================================
# PHASE 10.2 - COMMON OEM UPDATE RESULT
# ============================================================

$OEMUpdateResultFile =
    Join-Path `
        (
            Join-Path `
                $BasePath `
                'DriverUpdates'
        ) `
        'OEMUpdateResult.json'


$SummaryFile =
    Join-Path `
        $BasePath `
        'DeploymentSummary.json'


$DeploymentVersionFile =
    Join-Path `
        $BasePath `
        'DeploymentVersion.json'


$VerificationFile =
    Join-Path `
        $BasePath `
        'DriverVerification.json'


$HardwareFile =
    Join-Path `
        $BasePath `
        'HardwareInformation.json'


# This file deliberately exists OUTSIDE $BasePath.
#
# That means normal cleanup cannot remove the failure log.

$PersistentErrorLog =
    'C:\ProgramData\Itino\DriverDeployment-Error.log'



$DriverRollbackRoot =
    'C:\ProgramData\Itino\DriverRollback'


# ============================================================
# SCRIPTS
# ============================================================

$Scripts =
    @(
	
		[PSCustomObject]@{
	
            Name =
                'Preflight'

            File =
                '00-Preflight.ps1'
        }

        [PSCustomObject]@{

            Name =
                'Gather Hardware'

            File =
                '01-Gather-Hardware.ps1'
        }


        [PSCustomObject]@{

            Name =
                'Install OEM Update Tool'

            File =
                '02-Install-OEM-Update-Tool.ps1'
        }


        [PSCustomObject]@{

            Name =
                'Update Drivers'

            File =
                '03-Update-Drivers.ps1'
        }


        [PSCustomObject]@{

            Name =
                'Verify Drivers'

            File =
                '04-Verify-Drivers.ps1'
        }
    )


# ============================================================
# CREATE REQUIRED DIRECTORIES
# ============================================================

if (
    -not (
        Test-Path -LiteralPath $ItinoRoot
    )
) {

    New-Item `
        -Path $ItinoRoot `
        -ItemType Directory `
        -Force |
        Out-Null
}


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
            Test-Path -LiteralPath $LogPath
        )
    ) {

        New-Item `
            -Path $LogPath `
            -ItemType Directory `
            -Force |
        Out-Null
    }
}


# ============================================================
# PHASE 9.7 - VALIDATED-CYCLE CONSOLE TRANSCRIPT
# ============================================================
#
# Transcript startup is deferred until AFTER:
#   1. The single-instance mutex is acquired.
#   2. Persistent deployment state is loaded.
#   3. The deployment cycle is validated.
#
# A blocked second process therefore cannot create a false
# ConsoleOutput-Cycle4.log.
# ============================================================

function Start-ItinoConsoleTranscript {

    if (-not $SaveFullConsoleOutput) {
        return
    }

    if (-not $script:DeploymentSession) {

        Write-Host (
            'WARNING: Console transcript cannot start because the ' +
            'deployment session is not initialized.'
        )

        return
    }


    $script:ConsoleOutputCycle =
        [int]$script:DeploymentSession.Cycle


    $ConsoleSessionId =
        [string]$script:DeploymentSession.SessionId


    if (
        [string]::IsNullOrWhiteSpace(
            $ConsoleSessionId
        )
    ) {

        $ConsoleSessionId =
            Get-Date -Format 'yyyyMMdd-HHmmss'
    }
    elseif ($ConsoleSessionId.Length -gt 8) {

        $ConsoleSessionId =
            $ConsoleSessionId.Substring(
                0,
                8
            )
    }


    $script:ConsoleOutputFile =
        Join-Path `
            $BasePath `
            (
                'ConsoleOutput-Session{0}-Cycle{1}.log' -f
                    $ConsoleSessionId,
                    $script:ConsoleOutputCycle
            )


    try {

        Start-Transcript `
            -LiteralPath $script:ConsoleOutputFile `
            -Force `
            -ErrorAction Stop |
        Out-Null


        $script:ConsoleTranscriptStarted =
            $true


        Write-Log -Message (
            "Console transcript session: $ConsoleSessionId"
        )

        Write-Log -Message (
            "Console transcript cycle: $($script:ConsoleOutputCycle)"
        )

        Write-Log -Message (
            "Console transcript file: $($script:ConsoleOutputFile)"
        )
    }
    catch {

        Write-Host (
            'WARNING: Full console transcript could not be started. ' +
            "Reason: $($_.Exception.Message)"
        )
    }
}


function Copy-ItinoLogsToScriptLocation {

    if (-not $CopyLogsToScriptLocation) {
        return
    }


    try {

        $SessionId =
            if (
                $script:DeploymentSession -and
                $script:DeploymentSession.SessionId
            ) {
                [string]$script:DeploymentSession.SessionId
            }
            else {
                'UnknownSession'
            }


        $Manufacturer =
            $null


        if (
            Test-Path `
                -LiteralPath $HardwareFile `
                -PathType Leaf
        ) {

            try {

                $HardwareData =
                    Get-Content `
                        -LiteralPath $HardwareFile `
                        -Raw `
                        -ErrorAction Stop |
                    ConvertFrom-Json `
                        -ErrorAction Stop


                $Manufacturer =
                    [string]$HardwareData.ComputerSystem.Manufacturer


                if (
                    [string]::IsNullOrWhiteSpace(
                        $Manufacturer
                    )
                ) {

                    $Manufacturer =
                        [string]$HardwareData.Manufacturer
                }
            }
            catch {
            }
        }


        if (
            [string]::IsNullOrWhiteSpace(
                $Manufacturer
            )
        ) {

            try {

                $Manufacturer =
                    [string](
                        Get-CimInstance `
                            -ClassName Win32_ComputerSystem `
                            -ErrorAction Stop
                    ).Manufacturer
            }
            catch {

                $Manufacturer =
                    'Unknown'
            }
        }


        switch -Regex ($Manufacturer) {

            'HP|Hewlett' {
                $ManufacturerFolder =
                    'Hp'

                break
            }

            'LENOVO' {
                $ManufacturerFolder =
                    'Lenovo'

                break
            }

            'DELL' {
                $ManufacturerFolder =
                    'Dell'

                break
            }

            default {

                $ManufacturerFolder =
                    if (
                        [string]::IsNullOrWhiteSpace(
                            $Manufacturer
                        )
                    ) {
                        'Unknown'
                    }
                    else {
                        (
                            $Manufacturer `
                                -replace '[\\/:*?"<>|]', '_'
                        ).Trim()
                    }
            }
        }


        $ManufacturerDirectory =
            Join-Path `
                $CopiedLogsRoot `
                $ManufacturerFolder


        $ComputerDirectory =
            Join-Path `
                $ManufacturerDirectory `
                $env:COMPUTERNAME


        $DestinationDirectory =
            Join-Path `
                $ComputerDirectory `
                $SessionId


        if (-not (
            Test-Path `
                -LiteralPath $DestinationDirectory
        )) {

            New-Item `
                -ItemType Directory `
                -Path $DestinationDirectory `
                -Force `
                -ErrorAction Stop |
            Out-Null
        }


        # Copy every console transcript belonging to the current
        # deployment session. This preserves Cycle 1, Cycle 2, etc.
        #
        # Newer transcript names contain the short session ID.
        # The fallback also copies the current transcript explicitly.

        $ShortSessionId =
            if ($SessionId.Length -gt 8) {
                $SessionId.Substring(0, 8)
            }
            else {
                $SessionId
            }


        $SessionTranscriptPattern =
            "ConsoleOutput-Session$ShortSessionId-Cycle*.log"


        $TranscriptFiles =
            @(
                Get-ChildItem `
                    -LiteralPath $BasePath `
                    -Filter $SessionTranscriptPattern `
                    -File `
                    -ErrorAction SilentlyContinue
            )


        if (
            $script:ConsoleOutputFile -and
            (
                Test-Path `
                    -LiteralPath $script:ConsoleOutputFile `
                    -PathType Leaf
            )
        ) {

            $CurrentTranscript =
                Get-Item `
                    -LiteralPath $script:ConsoleOutputFile `
                    -ErrorAction SilentlyContinue


            if (
                $CurrentTranscript -and
                -not (
                    $TranscriptFiles.FullName -contains
                    $CurrentTranscript.FullName
                )
            ) {

                $TranscriptFiles +=
                    $CurrentTranscript
            }
        }


        foreach ($TranscriptFile in $TranscriptFiles) {

            Copy-Item `
                -LiteralPath $TranscriptFile.FullName `
                -Destination (
                    Join-Path `
                        $DestinationDirectory `
                        $TranscriptFile.Name
                ) `
                -Force `
                -ErrorAction Stop
        }


        $AutoResumeLog =
            Join-Path `
                $BasePath `
                'AutoResume.log'


        if (
            Test-Path `
                -LiteralPath $AutoResumeLog `
                -PathType Leaf
        ) {

            Copy-Item `
                -LiteralPath $AutoResumeLog `
                -Destination (
                    Join-Path `
                        $DestinationDirectory `
                        'AutoResume.log'
                ) `
                -Force `
                -ErrorAction Stop
        }


        Write-Host (
            "Deployment logs copied to: $DestinationDirectory"
        )
    }
    catch {

        # Log copying must never change deployment success/failure.
        Write-Host (
            'WARNING: Unable to copy deployment logs to the script ' +
            "location. Reason: $($_.Exception.Message)"
        )
    }
}


function Stop-ItinoConsoleTranscript {

    if (-not $script:ConsoleTranscriptStarted) {
        return
    }

    try {

        Stop-Transcript |
            Out-Null
    }
    catch {
    }

    $script:ConsoleTranscriptStarted =
        $false
}


# ============================================================
# PREVIOUS-RUN MARKER CLEANUP
# ============================================================
#
# These are called only after the mutex has been acquired.
# A second blocked controller must not modify files that belong
# to the active deployment.
# ============================================================

function Remove-ItinoPreviousFailureLog {

    if (
        Test-Path -LiteralPath $PersistentErrorLog
    ) {

        try {

            Remove-Item `
                -LiteralPath $PersistentErrorLog `
                -Force `
                -ErrorAction Stop
        }
        catch {

            Write-Host (
                'WARNING: Unable to remove previous driver deployment ' +
                "error log. Error: $($_.Exception.Message)"
            )
        }
    }
}


function Remove-ItinoPreviousRestartMarker {

    if (
        Test-Path -LiteralPath $RestartFile
    ) {

        try {

            Remove-Item `
                -LiteralPath $RestartFile `
                -Force `
                -ErrorAction Stop
        }
        catch {

            Write-Host (
                'WARNING: Unable to remove previous restart marker. ' +
                "Error: $($_.Exception.Message)"
            )
        }
    }
}


# ============================================================
# IN-MEMORY DEPLOYMENT OUTPUT
# ============================================================
#
# All controller messages and child script output are stored here.
#
# On success:
#
#     The buffer disappears when PowerShell exits.
#
# On failure:
#
#     The buffer is written to:
#
#     C:\ProgramData\Itino\DriverDeployment-Error.log
#
# ============================================================

$DeploymentOutputBuffer =
    New-Object `
        'System.Collections.Generic.List[string]'


# ============================================================
# ADD BUFFER LINE
# ============================================================

function Add-DeploymentBufferLine {

    param(
        [AllowNull()]
        [string]$Line
    )


    if (
        $null -eq $Line
    ) {

        $Line =
            ''
    }


    [void]$DeploymentOutputBuffer.Add(
        [string]$Line
    )
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


    $Entry =
        "[$TimeStamp] [$Level] $Message"


    # Always show controller output.

    Write-Host $Entry


    # Always preserve controller information in memory.

    Add-DeploymentBufferLine `
        -Line $Entry


    # Persistent normal logs only when enabled.

    if ($WriteLogFiles) {

        Add-Content `
            -LiteralPath $MainLogFile `
            -Value $Entry `
            -Encoding UTF8
    }
}


# ============================================================
# RUN CHILD SCRIPT
# ============================================================

function Invoke-DeploymentScript {

    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Path
    )


    Write-Host ''
    Write-Host '============================================================'
    Write-Host "Starting: $Name"
    Write-Host '============================================================'
    Write-Host ''


    Write-Log -Message (
        "Starting stage: $Name"
    )


    if (
        -not (
            Test-Path -LiteralPath $Path
        )
    ) {

        throw (
            "Required deployment script was not found: $Path"
        )
    }


    $StartTime =
        Get-Date


    # ========================================================
    # ADD STAGE HEADER TO FAILURE BUFFER
    # ========================================================

    Add-DeploymentBufferLine `
        -Line ''


    Add-DeploymentBufferLine `
        -Line '============================================================'


    Add-DeploymentBufferLine `
        -Line "STAGE: $Name"


    Add-DeploymentBufferLine `
        -Line "SCRIPT: $Path"


    Add-DeploymentBufferLine `
        -Line '============================================================'


    # ========================================================
    # RUN CHILD POWERSHELL
    # ========================================================
    #
    # powershell.exe is called directly instead of using
    # Start-Process with output redirection.
    #
    # This gives:
    #
    #     - live child script console output
    #     - captured output for failure logging
    #     - the child process exit code
    #
    # ========================================================

    try {

        & powershell.exe `
            -NoLogo `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $Path `
            2>&1 |
        ForEach-Object {

            $Line =
                [string]$_


            # Show child output immediately.

            Write-Host $Line


            # Keep the exact same output in memory.

            Add-DeploymentBufferLine `
                -Line $Line
        }


        $ExitCode =
            $LASTEXITCODE


        if (
            $null -eq $ExitCode
        ) {

            $ExitCode =
                1
        }
    }
    catch {

        $ExitCode =
            1


        $LaunchError =
            (
                'Unable to run child PowerShell process. ' +
                $_.Exception.Message
            )


        Write-Host (
            "ERROR: $LaunchError"
        )


        Add-DeploymentBufferLine `
            -Line "ERROR: $LaunchError"
    }


    $EndTime =
        Get-Date


    $DurationSeconds =
        [math]::Round(
            (
                $EndTime -
                $StartTime
            ).TotalSeconds,
            1
        )


    # ========================================================
    # STORE FINAL STAGE RESULT
    # ========================================================

    Add-DeploymentBufferLine `
        -Line "EXIT CODE: $ExitCode"


    Add-DeploymentBufferLine `
        -Line (
            "DURATION: $DurationSeconds seconds"
        )


    Write-Log -Message (
        "Stage '$Name' finished with exit code $ExitCode."
    )


    Write-Log -Message (
        "Stage duration: $DurationSeconds seconds."
    )


    return [PSCustomObject]@{

        Name =
            $Name

        Path =
            $Path

        ExitCode =
            $ExitCode

        StartTime =
            $StartTime

        EndTime =
            $EndTime

        DurationSeconds =
            $DurationSeconds
    }
}


# ============================================================
# SAVE FAILURE LOG
# ============================================================

function Save-DeploymentErrorLog {

    param(
        [Parameter(Mandatory)]
        [string]$FailedStage,

        [Parameter(Mandatory)]
        [int]$ExitCode
    )


    if (
        -not $KeepErrorLogOnFailure
    ) {

        return
    }


    try {

        $ErrorLogContent =
            @(

                '============================================================'

                'ITINO DRIVER DEPLOYMENT FAILURE'

                '============================================================'

                "Computer     : $env:COMPUTERNAME"

                "Time         : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

                "Failed Stage : $FailedStage"

                "Exit Code    : $ExitCode"

                '============================================================'

                ''
            )


        $ErrorLogContent +=
            $DeploymentOutputBuffer


        $ErrorLogContent |
            Set-Content `
                -LiteralPath $PersistentErrorLog `
                -Encoding UTF8


        Write-Host ''

        Write-Host (
            "Driver deployment error log saved to: $PersistentErrorLog"
        )
    }
    catch {

        Write-Host (
            'ERROR: Unable to create driver deployment error log. ' +
            "Error: $($_.Exception.Message)"
        )
    }
}



# ============================================================
# PHASE 9 - DEPLOYMENT SESSION / SAFETY
# ============================================================

$script:DeploymentMutex =
    $null

$script:DeploymentMutexOwned =
    $false

$script:DeploymentSession =
    $null

$script:ControllerSpecialExitCode =
    $null


function Enter-ItinoDeploymentMutex {

    if (-not $EnableSingleInstanceProtection) {
        return
    }

    $script:DeploymentMutex =
        New-Object System.Threading.Mutex(
            $false,
            'Global\ITINO-DriverDeployment'
        )

    try {
        $script:DeploymentMutexOwned =
            $script:DeploymentMutex.WaitOne(0, $false)
    }
    catch [System.Threading.AbandonedMutexException] {
        $script:DeploymentMutexOwned =
            $true
    }

    if (-not $script:DeploymentMutexOwned) {

        $script:ControllerSpecialExitCode =
            1618

        throw 'Another ITINO driver deployment is already running.'
    }
}


function Exit-ItinoDeploymentMutex {

    if (
        $script:DeploymentMutex -and
        $script:DeploymentMutexOwned
    ) {
        try {
            $script:DeploymentMutex.ReleaseMutex()
        }
        catch {
        }

        $script:DeploymentMutexOwned =
            $false
    }

    if ($script:DeploymentMutex) {
        try {
            $script:DeploymentMutex.Dispose()
        }
        catch {
        }

        $script:DeploymentMutex =
            $null
    }
}


function Save-ItinoDeploymentSession {

    param(
        [Parameter(Mandatory)]
        [string]$Status
    )

    if (-not $script:DeploymentSession) {
        return
    }

    $script:DeploymentSession.Status =
        $Status

    $script:DeploymentSession.LastUpdated =
        Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $script:DeploymentSession |
        ConvertTo-Json -Depth 8 |
        Set-Content `
            -LiteralPath $DeploymentStateFile `
            -Encoding UTF8
}


function Initialize-ItinoDeploymentSession {

    $Existing =
        $null

    if (
        Test-Path -LiteralPath $DeploymentStateFile
    ) {
        try {
            $Existing =
                Get-Content `
                    -LiteralPath $DeploymentStateFile `
                    -Raw `
                    -ErrorAction Stop |
                ConvertFrom-Json `
                    -ErrorAction Stop
        }
        catch {
            Write-Log `
                -Message (
                    'Existing deployment state could not be read. ' +
                    'A new session will be created. ' +
                    "Reason: $($_.Exception.Message)"
                ) `
                -Level 'WARNING'
        }
    }

    if (
        $Existing -and
        [string]$Existing.ComputerName -eq [string]$env:COMPUTERNAME -and
        [string]$Existing.Status -in @(
            'InProgress',
            'RestartRequired'
        )
    ) {

        $Cycle =
            ([int]$Existing.Cycle) + 1

        if (
            $Cycle -gt $MaximumDeploymentCycles
        ) {
            throw (
                'Maximum driver deployment cycles exceeded. ' +
                "Maximum=$MaximumDeploymentCycles; NextCycle=$Cycle."
            )
        }

        $script:DeploymentSession =
            [pscustomobject]@{
                SessionId = [string]$Existing.SessionId
                ComputerName = $env:COMPUTERNAME
                Started = [string]$Existing.Started
                LastUpdated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Cycle = $Cycle
                MaximumCycles = $MaximumDeploymentCycles
                Status = 'InProgress'
            }
    }
    else {

        $script:DeploymentSession =
            [pscustomobject]@{
                SessionId = ([guid]::NewGuid().ToString('N'))
                ComputerName = $env:COMPUTERNAME
                Started = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                LastUpdated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Cycle = 1
                MaximumCycles = $MaximumDeploymentCycles
                Status = 'InProgress'
            }
    }

    Save-ItinoDeploymentSession -Status 'InProgress'

    $env:ITINO_DEPLOYMENT_SESSION_ID =
        [string]$script:DeploymentSession.SessionId

    $env:ITINO_DEPLOYMENT_CYCLE =
        [string]$script:DeploymentSession.Cycle


    Write-ItinoProjectMetadata


    Write-Log -Message (
        'Deployment session: ' +
        "$($script:DeploymentSession.SessionId); " +
        "Cycle=$($script:DeploymentSession.Cycle)/$MaximumDeploymentCycles"
    )
}


function Get-ItinoProjectMetadata {

    return [PSCustomObject]@{

        Name =
            $DriverDeploymentName

        Version =
            $DriverDeploymentVersion

        Phase =
            $DriverDeploymentPhase

        ReleaseChannel =
            $DriverDeploymentReleaseChannel

        BuildDate =
            $DriverDeploymentBuildDate

        ControllerVersion =
            $ScriptVersion

        ControllerUpdated =
            $ScriptUpdated

        GitTag =
            if (
                [string]::IsNullOrWhiteSpace(
                    $DriverDeploymentGitTag
                )
            ) {
                $null
            }
            else {
                $DriverDeploymentGitTag
            }

        GitCommit =
            if (
                [string]::IsNullOrWhiteSpace(
                    $DriverDeploymentGitCommit
                )
            ) {
                $null
            }
            else {
                $DriverDeploymentGitCommit
            }
    }
}


function Write-ItinoProjectMetadata {

    try {

        if (-not (
            Test-Path `
                -LiteralPath $BasePath `
                -PathType Container
        )) {

            New-Item `
                -Path $BasePath `
                -ItemType Directory `
                -Force `
                -ErrorAction Stop |
            Out-Null
        }


        Get-ItinoProjectMetadata |
            ConvertTo-Json `
                -Depth 6 |
            Set-Content `
                -LiteralPath $DeploymentVersionFile `
                -Encoding UTF8 `
                -ErrorAction Stop


        Write-Log -Message (
            "Deployment version metadata saved to '$DeploymentVersionFile'."
        )
    }
    catch {

        Write-Log `
            -Message (
                'Unable to save deployment version metadata. ' +
                "Reason: $($_.Exception.Message)"
            ) `
            -Level 'WARNING'
    }
}


function Get-ItinoFirmwareSafety {

    $BatteryPresent =
        $false

    $BatteryPercent =
        $null

    $OnExternalPower =
        $false

    $PowerLineStatus =
        'Unknown'

    $Reason =
        'Power state has not yet been evaluated.'


    # --------------------------------------------------------
    # AC POWER DETECTION
    # --------------------------------------------------------
    #
    # Win32_Battery.BatteryStatus is not reliable for deciding
    # whether AC power is connected. Some systems report the
    # battery as discharging even while external power is
    # present.
    #
    # Use Windows Forms PowerStatus.PowerLineStatus instead.
    # --------------------------------------------------------

    try {

        Add-Type `
            -AssemblyName System.Windows.Forms `
            -ErrorAction Stop


        $PowerLineStatus =
            [string][System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus


        $OnExternalPower =
            (
                $PowerLineStatus -eq 'Online'
            )
    }
    catch {

        $PowerLineStatus =
            'Unknown'

        $OnExternalPower =
            $false
    }


    # --------------------------------------------------------
    # BATTERY DETECTION / CHARGE LEVEL
    # --------------------------------------------------------

    try {

        $Batteries =
            @(
                Get-CimInstance `
                    -ClassName Win32_Battery `
                    -ErrorAction Stop
            )


        if ($Batteries.Count -gt 0) {

            $BatteryPresent =
                $true


            $PercentValues =
                @(
                    $Batteries |
                    ForEach-Object {

                        if (
                            $null -ne $_.EstimatedChargeRemaining
                        ) {

                            [int]$_.EstimatedChargeRemaining
                        }
                    }
                )


            if ($PercentValues.Count -gt 0) {

                $BatteryPercent =
                    (
                        $PercentValues |
                        Measure-Object -Minimum
                    ).Minimum
            }
        }
    }
    catch {

        # If battery enumeration fails, keep BatteryPresent false
        # and continue using the AC state. On portable systems the
        # final safety gate will fail safe if charge is unknown.
    }


    # --------------------------------------------------------
    # FIRMWARE SAFETY DECISION
    # --------------------------------------------------------

    if (-not $OnExternalPower) {

        $Reason =
            (
                'External AC power is not connected. ' +
                "PowerLineStatus=$PowerLineStatus."
            )
    }
    elseif (
        $BatteryPresent -and
        $null -eq $BatteryPercent
    ) {

        $Reason =
            (
                'Battery is present, but charge percentage could not be determined.'
            )
    }
    elseif (
        $BatteryPresent -and
        $BatteryPercent -lt $MinimumFirmwareBatteryPercent
    ) {

        $Reason =
            (
                "Battery charge is $BatteryPercent%. " +
                "Minimum required is $MinimumFirmwareBatteryPercent%."
            )
    }
    else {

        $Reason =
            (
                'External AC power is connected and firmware battery ' +
                'safety requirements are satisfied.'
            )
    }


    $Allowed =
        $OnExternalPower -and
        (
            -not $BatteryPresent -or
            (
                $null -ne $BatteryPercent -and
                $BatteryPercent -ge $MinimumFirmwareBatteryPercent
            )
        )


    return [pscustomobject]@{

        Allowed =
            $Allowed

        BatteryPresent =
            $BatteryPresent

        BatteryPercent =
            $BatteryPercent

        OnExternalPower =
            $OnExternalPower

        PowerLineStatus =
            $PowerLineStatus

        MinimumBatteryPercent =
            $MinimumFirmwareBatteryPercent

        Reason =
            $Reason
    }
}

function Get-ItinoBitLockerSummary {

    try {

        $ManageBde =
            Join-Path `
                $env:SystemRoot `
                'System32\manage-bde.exe'

        if (-not (
            Test-Path -LiteralPath $ManageBde
        )) {
            return 'Unknown - manage-bde.exe not found'
        }

        $Output =
            @(
                & $ManageBde `
                    -status `
                    $env:SystemDrive `
                    2>&1
            )

        $ProtectionLine =
            $Output |
            Where-Object {
                [string]$_ -match 'Protection Status|Beskyttelsesstatus'
            } |
            Select-Object -First 1

        if ($ProtectionLine) {
            return ([string]$ProtectionLine).Trim()
        }

        return 'BitLocker queried; protection line not recognized.'
    }
    catch {
        return (
            'Unknown - BitLocker query failed: ' +
            $_.Exception.Message
        )
    }
}


function Save-ItinoMachineReadableResult {

    param(
        [Parameter(Mandatory)]
        [int]$ExitCode,

        [Parameter(Mandatory)]
        [string]$Status
    )

    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        SessionId =
            if ($script:DeploymentSession) {
                $script:DeploymentSession.SessionId
            }
            else {
                $null
            }
        Cycle =
            if ($script:DeploymentSession) {
                $script:DeploymentSession.Cycle
            }
            else {
                $null
            }
        Status = $Status
        ExitCode = $ExitCode
        RestartRequired = ($ExitCode -eq 3010)
        FailedStage = $FailedStage
        Completed = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    } |
        ConvertTo-Json -Depth 6 |
        Set-Content `
            -LiteralPath $DeploymentResultFile `
            -Encoding UTF8
}


function Remove-EntireItinoRoot {

    # CleanupAfterDeployment is the single master cleanup switch.
    #
    # If disabled, keep the complete ITINO tree including:
    #   - console transcripts
    #   - deployment state/results
    #   - hardware/verification reports
    #   - rollback data
    #
    # This also makes testing behavior predictable.

    if (-not $CleanupAfterDeployment) {

        Write-Log -Message (
            'Final ITINO root cleanup skipped because ' +
            'CleanupAfterDeployment is False.'
        )

        return
    }

    # Close the transcript file handle before deleting its
    # parent C:\ProgramData\Itino directory.
    Stop-ItinoConsoleTranscript

    Copy-ItinoLogsToScriptLocation

    Write-Host ''
    Write-Host (
        "Final clean success. Removing complete ITINO data root: $ItinoRoot"
    )

    try {

        if (
            Test-Path -LiteralPath $ItinoRoot
        ) {
            Remove-Item `
                -LiteralPath $ItinoRoot `
                -Recurse `
                -Force `
                -ErrorAction Stop
        }

        Write-Host (
            'All ITINO-generated ProgramData files were removed.'
        )
    }
    catch {
        Write-Host (
            'WARNING: Deployment succeeded, but the complete ITINO ' +
            "ProgramData root could not be removed. Error: $($_.Exception.Message)"
        )
    }
}


# ============================================================
# CLEANUP
# ============================================================


function Update-DriverRollbackManifestMetadata {

    param(
        [Parameter(Mandatory)]
        [object]$DeploymentSummary,

        [Parameter(Mandatory)]
        [int]$FinalExitCode
    )


    try {

        if (-not (
            Test-Path `
                -LiteralPath $HardwareFile `
                -PathType Leaf
        )) {

            Write-Log `
                -Message (
                    'Rollback metadata enrichment skipped because ' +
                    "HardwareInformation.json was not found: $HardwareFile"
                ) `
                -Level 'WARNING'

            return
        }


        $HardwareInformation =
            Get-Content `
                -LiteralPath $HardwareFile `
                -Raw `
                -ErrorAction Stop |
            ConvertFrom-Json


        $RollbackManifestPath =
            [string]$HardwareInformation.DriverRollbackBackup.Manifest


        if (
            [string]::IsNullOrWhiteSpace(
                $RollbackManifestPath
            ) -or
            -not (
                Test-Path `
                    -LiteralPath $RollbackManifestPath `
                    -PathType Leaf
            )
        ) {

            Write-Log `
                -Message (
                    'Rollback metadata enrichment skipped because the ' +
                    'active rollback manifest could not be resolved.'
                ) `
                -Level 'WARNING'

            return
        }


        $RollbackManifest =
            Get-Content `
                -LiteralPath $RollbackManifestPath `
                -Raw `
                -ErrorAction Stop |
            ConvertFrom-Json


        # Add newer properties to older manifests without breaking
        # rollback archives created before Phase 10.12.

        if (-not (
            $RollbackManifest.PSObject.Properties.Name -contains
            'SchemaVersion'
        )) {

            $RollbackManifest |
                Add-Member `
                    -NotePropertyName SchemaVersion `
                    -NotePropertyValue 2
        }
        else {

            $RollbackManifest.SchemaVersion =
                2
        }


        if (-not (
            $RollbackManifest.PSObject.Properties.Name -contains
            'DeploymentSessionId'
        )) {

            $RollbackManifest |
                Add-Member `
                    -NotePropertyName DeploymentSessionId `
                    -NotePropertyValue $(
                        if ($script:DeploymentSession) {
                            $script:DeploymentSession.SessionId
                        }
                        else {
                            $null
                        }
                    )
        }


        if (-not (
            $RollbackManifest.PSObject.Properties.Name -contains
            'CycleHistory'
        )) {

            $RollbackManifest |
                Add-Member `
                    -NotePropertyName CycleHistory `
                    -NotePropertyValue @()
        }


        $CurrentCycle =
            if ($script:DeploymentSession) {
                [int]$script:DeploymentSession.Cycle
            }
            else {
                $null
            }


        $CycleRecord =
            [PSCustomObject]@{

                Cycle =
                    $CurrentCycle

                CompletionTime =
                    Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

                ExitCode =
                    $FinalExitCode

                Status =
                    $DeploymentSummary.Status

                FinalOutcome =
                    if ($DeploymentSummary.FinalSummary) {
                        $DeploymentSummary.FinalSummary.Outcome
                    }
                    else {
                        $null
                    }

                RestartRequired =
                    [bool]$DeploymentSummary.RestartRequired

                FailedStage =
                    $DeploymentSummary.FailedStage

                OEMStatus =
                    if ($DeploymentSummary.OEMUpdateResult) {
                        $DeploymentSummary.OEMUpdateResult.Status
                    }
                    else {
                        $null
                    }

                VerificationStatus =
                    if ($DeploymentSummary.VerificationV2) {
                        $DeploymentSummary.VerificationV2.OverallStatus
                    }
                    else {
                        $null
                    }
            }


        $ExistingCycleHistory =
            @(
                $RollbackManifest.CycleHistory |
                Where-Object {
                    [string]$_.Cycle -ne
                    [string]$CurrentCycle
                }
            )


        $RollbackManifest.CycleHistory =
            @(
                $ExistingCycleHistory
                $CycleRecord
            )


        $DeploymentMetadata =
            [PSCustomObject]@{

                LastUpdated =
                    Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

                SessionId =
                    if ($script:DeploymentSession) {
                        $script:DeploymentSession.SessionId
                    }
                    else {
                        $null
                    }

                FinalCycle =
                    $CurrentCycle

                ControllerStatus =
                    $DeploymentSummary.Status

                FinalOutcome =
                    if ($DeploymentSummary.FinalSummary) {
                        $DeploymentSummary.FinalSummary.Outcome
                    }
                    else {
                        $null
                    }

                ExitCode =
                    $FinalExitCode

                RestartRequired =
                    [bool]$DeploymentSummary.RestartRequired

                FailedStage =
                    $DeploymentSummary.FailedStage

                Computer =
                    $DeploymentSummary.Computer

                OEMUpdate =
                    $DeploymentSummary.OEMUpdateResult

                Verification =
                    $DeploymentSummary.VerificationV2

                DriverChanges =
                    if ($DeploymentSummary.FinalSummary) {
                        $DeploymentSummary.FinalSummary.DriverChanges
                    }
                    else {
                        $DeploymentSummary.DriverChanges
                    }

                RestartReasons =
                    @(
                        $DeploymentSummary.RestartReasons
                    )

                Artifacts =
                    [PSCustomObject]@{

                        DeploymentSummary =
                            $SummaryFile

                        OEMUpdateResult =
                            $OEMUpdateResultFile

                        DriverVerification =
                            $VerificationFile

                        HardwareInformation =
                            $HardwareFile
                    }
            }


        if (-not (
            $RollbackManifest.PSObject.Properties.Name -contains
            'Deployment'
        )) {

            $RollbackManifest |
                Add-Member `
                    -NotePropertyName Deployment `
                    -NotePropertyValue $DeploymentMetadata
        }
        else {

            $RollbackManifest.Deployment =
                $DeploymentMetadata
        }


        $RollbackManifest |
            ConvertTo-Json `
                -Depth 16 |
            Set-Content `
                -LiteralPath $RollbackManifestPath `
                -Encoding UTF8


        Write-Log -Message (
            'Rollback manifest enriched with deployment metadata. ' +
            "Manifest='$RollbackManifestPath'; " +
            "Cycle=$CurrentCycle; " +
            "ExitCode=$FinalExitCode; " +
            "Outcome=$($DeploymentMetadata.FinalOutcome)."
        )
    }
    catch {

        # Metadata enrichment is useful for rollback auditing, but must
        # never convert an otherwise valid deployment into a failure.

        Write-Log `
            -Message (
                'Unable to enrich rollback manifest metadata. ' +
                "Reason: $($_.Exception.Message)"
            ) `
            -Level 'WARNING'
    }
}


function Invoke-FinalCleanup {

    if (
        -not $CleanupAfterDeployment
    ) {

        Write-Log -Message (
            'Deployment cleanup is disabled.'
        )


        return
    }


    Write-Host ''

    Write-Host (
        "Cleaning driver deployment working folder: $BasePath"
    )


    try {

        if (
            Test-Path -LiteralPath $BasePath
        ) {

            Remove-Item `
                -LiteralPath $BasePath `
                -Recurse `
                -Force `
                -ErrorAction Stop
        }


        Write-Host (
            'Driver deployment working files removed.'
        )
    }
    catch {

        Write-Host (
            'WARNING: Unable to completely remove driver deployment ' +
            "working files. Error: $($_.Exception.Message)"
        )
    }


    # DriverRollback is intentionally not deleted separately here.
    #
    # On final clean success, Remove-EntireItinoRoot removes the
    # complete C:\ProgramData\Itino tree, including DriverRollback,
    # when CleanupAfterDeployment = $true.
    #
    # During failure cleanup, rollback data remains available for
    # recovery and diagnostics.

}


# ============================================================
# OEM CONFIGURATION VALIDATION
# ============================================================

function Test-ConfiguredHttpsUrl {

    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [AllowEmptyString()]
        [string]$Value
    )

    if (
        [string]::IsNullOrWhiteSpace(
            $Value
        )
    ) {

        throw (
            "OEM configuration error: '$Name' is empty. " +
            'Fix the OEM DOWNLOAD CONFIGURATION section in ' +
            'Run-DriverDeployment.ps1.'
        )
    }


    $Uri =
        $null


    if (
        -not [Uri]::TryCreate(
            $Value,
            [UriKind]::Absolute,
            [ref]$Uri
        )
    ) {

        throw (
            "OEM configuration error: '$Name' is not a valid absolute URL. " +
            "Configured value: '$Value'."
        )
    }


    if (
        $Uri.Scheme -ne 'https'
    ) {

        throw (
            "OEM configuration error: '$Name' must use HTTPS. " +
            "Configured value: '$Value'."
        )
    }
}


function Test-ConfiguredVersion {

    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [AllowEmptyString()]
        [string]$Value
    )

    if (
        [string]::IsNullOrWhiteSpace(
            $Value
        )
    ) {

        throw (
            "OEM configuration error: '$Name' is empty. " +
            'Fix the OEM DOWNLOAD CONFIGURATION section in ' +
            'Run-DriverDeployment.ps1.'
        )
    }


    $Normalized =
        $Value.Trim() -replace '[^0-9\.]', ''


    $ParsedVersion =
        $null


    if (
        -not [version]::TryParse(
            $Normalized,
            [ref]$ParsedVersion
        )
    ) {

        throw (
            "OEM configuration error: '$Name' is not a valid version. " +
            "Configured value: '$Value'."
        )
    }
}


function Assert-OemControllerConfiguration {

    Test-ConfiguredHttpsUrl `
        -Name 'Dell official page URL' `
        -Value $DellCommandUpdateOfficialPageUrl

    Test-ConfiguredVersion `
        -Name 'Dell fallback version' `
        -Value $DellCommandUpdateFallbackVersion

    Test-ConfiguredHttpsUrl `
        -Name 'Dell fallback download URL' `
        -Value $DellCommandUpdateFallbackDownloadUrl


    Test-ConfiguredHttpsUrl `
        -Name 'HP Image Assistant official page URL' `
        -Value $HPImageAssistantOfficialPageUrl

    Test-ConfiguredVersion `
        -Name 'HP Image Assistant fallback version' `
        -Value $HPImageAssistantFallbackVersion

    Test-ConfiguredHttpsUrl `
        -Name 'HP Image Assistant fallback download URL' `
        -Value $HPImageAssistantFallbackDownloadUrl


    Test-ConfiguredVersion `
        -Name 'Lenovo System Update version' `
        -Value $LenovoSystemUpdateVersion

    Test-ConfiguredHttpsUrl `
        -Name 'Lenovo System Update download URL' `
        -Value $LenovoSystemUpdateDownloadUrl


    if (
        [string]::IsNullOrWhiteSpace(
            $LenovoLSUClientModuleName
        )
    ) {

        throw (
            'OEM configuration error: Lenovo LSUClient module name is empty. ' +
            'Fix the OEM DOWNLOAD CONFIGURATION section in ' +
            'Run-DriverDeployment.ps1.'
        )
    }


    if (
        [string]::IsNullOrWhiteSpace(
            $LenovoLSUClientRepository
        )
    ) {

        throw (
            'OEM configuration error: Lenovo LSUClient repository is empty. ' +
            'Fix the OEM DOWNLOAD CONFIGURATION section in ' +
            'Run-DriverDeployment.ps1.'
        )
    }


    if (
        $LenovoLSUClientMaximumRounds -lt 1
    ) {

        throw (
            'OEM configuration error: Lenovo LSUClient maximum rounds must ' +
            'be 1 or greater.'
        )
    }
}


# ============================================================


# ============================================================
# FINAL CONSOLE OUTPUT
# ============================================================

function Show-DeploymentFinished {
    param(
        [Parameter(Mandatory)]
        [int]$ExitCode,

        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter(Mandatory)]
        [bool]$RestartRequired,

        [AllowNull()]
        [string]$FailedStage
    )

    Write-Host ''
    Write-Host '============================================================'
    Write-Host 'Deployment Finished'
    Write-Host '============================================================'
    Write-Host ''
    Write-Host "Status           : $Status"
    Write-Host "Exit Code        : $ExitCode"
    Write-Host "Restart Required : $RestartRequired"

    if (-not [string]::IsNullOrWhiteSpace($FailedStage)) {
        Write-Host "Failed Stage     : $FailedStage"
    }

    Write-Host ''
    Write-Host '============================================================'
}


function Read-ItinoJsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log -Message "$Description was not available at '$Path'." -Level 'WARNING'
        return $null
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        Write-Log -Message ("Unable to read $Description from '$Path'. Reason: " + $_.Exception.Message) -Level 'WARNING'
        return $null
    }
}

function Get-RestartMarkerReasons {
    $Reasons = @()

    if (-not (Test-Path -LiteralPath $RestartFile)) {
        return $Reasons
    }

    try {
        foreach ($Line in @(Get-Content -LiteralPath $RestartFile -ErrorAction Stop)) {
            if ($Line -match '^\s*Reason\s*=\s*(.+?)\s*$') {
                $Reasons += $Matches[1]
            }
        }
    }
    catch {
        Write-Log -Message ('Unable to read restart reasons from RestartRequired.txt. Reason: ' + $_.Exception.Message) -Level 'WARNING'
    }

    return @($Reasons | Select-Object -Unique)
}

function Get-StageSummaryByName {
    param(
        [Parameter(Mandatory)][object[]]$Results,
        [Parameter(Mandatory)][string]$Name
    )

    return ($Results | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
}

function Get-FirstPropertyValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string[]]$Names
    )

    foreach ($Name in $Names) {
        if ($null -ne $Object.PSObject.Properties[$Name]) {
            return $Object.$Name
        }
    }

    return $null
}

function Get-ControllerDeviceDisplayName {

    param(
        [Parameter(Mandatory)]
        [object]$Device
    )


    $CandidateProperties =
        @(
            'Name',
            'FriendlyName',
            'InstanceId',
            'InstanceID',
            'DeviceID',
            'PNPDeviceID'
        )


    foreach (
        $PropertyName in $CandidateProperties
    ) {

        $Property =
            $Device.PSObject.Properties[
                $PropertyName
            ]


        if (
            $null -eq $Property
        ) {

            continue
        }


        $Value =
            [string]$Property.Value


        if (
            -not [string]::IsNullOrWhiteSpace(
                $Value
            )
        ) {

            return $Value.Trim()
        }
    }


    return 'Unknown device'
}


function Show-DriverVerification {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host 'Driver Verification'
    Write-Host '============================================================'
    Write-Host ''

    if (-not (Test-Path -LiteralPath $VerificationFile)) {
        Write-Host '[WARNING] DriverVerification.json was not available.'
        Write-Host ''
        Write-Host '============================================================'
        return
    }

    try {
        $Verification =
            Get-Content `
                -LiteralPath $VerificationFile `
                -Raw |
            ConvertFrom-Json


        $VerificationStatus =
            $null


        $VerificationRestartRequired =
            $null


        if (
            $Verification.Results
        ) {

            $VerificationStatus =
                $Verification.Results.Status

            $VerificationRestartRequired =
                $Verification.Results.RestartRequired
        }


        if (
            $null -eq $VerificationStatus
        ) {

            $VerificationStatus =
                $Verification.Status
        }


        if (
            $null -eq $VerificationRestartRequired
        ) {

            $VerificationRestartRequired =
                $Verification.RestartRequired
        }


        if (
            $null -ne $VerificationStatus
        ) {

            Write-Host (
                "Status             : $VerificationStatus"
            )
        }


        if (
            $null -ne $VerificationRestartRequired
        ) {

            Write-Host (
                "Restart Required   : $VerificationRestartRequired"
            )
        }


        if (
            $Verification.Results
        ) {

            $BeforeErrors =
                if (
                    $null -ne $Verification.Results.DeviceErrorsBefore
                ) {
                    $Verification.Results.DeviceErrorsBefore
                }
                else {
                    $Verification.Results.BeforeErrorCount
                }


            $AfterErrors =
                if (
                    $null -ne $Verification.Results.DeviceErrorsAfter
                ) {
                    $Verification.Results.DeviceErrorsAfter
                }
                else {
                    $Verification.Results.AfterErrorCount
                }


            $FixedErrors =
                if (
                    $null -ne $Verification.Results.FixedDeviceErrors
                ) {
                    $Verification.Results.FixedDeviceErrors
                }
                else {
                    $Verification.Results.FixedCount
                }


            $RemainingErrors =
                if (
                    $null -ne $Verification.Results.RemainingDeviceErrors
                ) {
                    $Verification.Results.RemainingDeviceErrors
                }
                else {
                    $Verification.Results.RemainingCount
                }


            $NewErrors =
                if (
                    $null -ne $Verification.Results.NewDeviceErrors
                ) {
                    $Verification.Results.NewDeviceErrors
                }
                else {
                    $Verification.Results.NewCount
                }


            $RestartDevices =
                if (
                    $null -ne $Verification.Results.RestartDevices
                ) {
                    $Verification.Results.RestartDevices
                }
                else {
                    $Verification.Results.RestartDeviceCount
                }


            if (
                $null -ne $BeforeErrors
            ) {
                Write-Host (
                    "Before Errors      : $BeforeErrors"
                )
            }


            if (
                $null -ne $AfterErrors
            ) {
                Write-Host (
                    "After Errors       : $AfterErrors"
                )
            }


            if (
                $null -ne $FixedErrors
            ) {
                Write-Host (
                    "Fixed Errors       : $FixedErrors"
                )
            }


            if (
                $null -ne $RemainingErrors
            ) {
                Write-Host (
                    "Remaining Errors   : $RemainingErrors"
                )
            }


            if (
                $null -ne $NewErrors
            ) {
                Write-Host (
                    "New Errors         : $NewErrors"
                )
            }


            if (
                $null -ne $RestartDevices
            ) {
                Write-Host (
                    "Restart Devices    : $RestartDevices"
                )
            }
        }


        if (
            $Verification.FixedDevices -and
            $Verification.FixedDevices.Count -gt 0
        ) {

            Write-Host ''
            Write-Host 'Fixed Devices:'


            foreach (
                $Device in $Verification.FixedDevices
            ) {

                $DisplayName =
                    Get-ControllerDeviceDisplayName `
                        -Device $Device


                Write-Host (
                    "  [FIXED] $DisplayName"
                )
            }
        }


        if (
            $Verification.RemainingDevices -and
            $Verification.RemainingDevices.Count -gt 0
        ) {

            Write-Host ''
            Write-Host 'Remaining Device Errors:'


            foreach (
                $Device in $Verification.RemainingDevices
            ) {

                $DisplayName =
                    Get-ControllerDeviceDisplayName `
                        -Device $Device


                Write-Host (
                    "  [REMAINING] $DisplayName " +
                    "(Code $($Device.ConfigManagerErrorCode))"
                )
            }
        }


        $CurrentNewErrors =
            $null


        if (
            $Verification.NewErrors
        ) {

            $CurrentNewErrors =
                $Verification.NewErrors
        }
        elseif (
            $Verification.NewDevices
        ) {

            $CurrentNewErrors =
                $Verification.NewDevices
        }


        if (
            $CurrentNewErrors -and
            $CurrentNewErrors.Count -gt 0
        ) {

            Write-Host ''
            Write-Host 'New Device Errors:'


            foreach (
                $Device in $CurrentNewErrors
            ) {

                $DisplayName =
                    Get-ControllerDeviceDisplayName `
                        -Device $Device


                Write-Host (
                    "  [NEW] $DisplayName " +
                    "(Code $($Device.ConfigManagerErrorCode))"
                )
            }
        }
    }
    catch {

        Write-Host (
            '[WARNING] Unable to read DriverVerification.json. Reason: ' +
            $_.Exception.Message
        )
    }

    Write-Host ''
    Write-Host '============================================================'
}

# MAIN STATE
# ============================================================

$Results =
    @()


$RestartRequired =
    $false


$DeploymentFailed =
    $false


$FailedStage =
    $null


$FinalExitCode =
    1


# ============================================================
# MAIN
# ============================================================

try {

    Write-Host ''
    Write-Host '============================================================'
    Write-Host 'ITINO Driver Deployment'
    Write-Host '============================================================'
    Write-Host ''


    Write-Log -Message (
        'Driver deployment started.'
    )


    Write-Log -Message (
        "Controller script: $ScriptName"
    )


    Write-Log -Message (
        "Controller version: $ScriptVersion"
    )


    Write-Log -Message (
        "Controller updated: $ScriptUpdated"
    )


    Write-Log -Message (
        'PROJECT RELEASE: ' +
        "Name=$DriverDeploymentName | " +
        "Version=$DriverDeploymentVersion | " +
        "Phase=$DriverDeploymentPhase | " +
        "Channel=$DriverDeploymentReleaseChannel | " +
        "BuildDate=$DriverDeploymentBuildDate"
    )


    if (
        -not [string]::IsNullOrWhiteSpace(
            $DriverDeploymentGitTag
        ) -or
        -not [string]::IsNullOrWhiteSpace(
            $DriverDeploymentGitCommit
        )
    ) {

        Write-Log -Message (
            'PROJECT SOURCE: ' +
            "GitTag=$DriverDeploymentGitTag | " +
            "GitCommit=$DriverDeploymentGitCommit"
        )
    }


    Write-Log -Message (
        "Controller directory: $ScriptRoot"
    )


    Write-Log -Message (
        "Scripts directory: $ScriptsPath"
    )


    Write-Log -Message (
        "Write log files: $WriteLogFiles"
    )

    Write-Log -Message (
        "Save full console output: $SaveFullConsoleOutput"
    )


    Write-Log -Message (
        "Copy logs to script location: $CopyLogsToScriptLocation"
    )

    if ($CopyLogsToScriptLocation) {
        Write-Log -Message (
            "Copied logs root: $CopiedLogsRoot"
        )
    }

    if (
        $SaveFullConsoleOutput -and
        $script:ConsoleTranscriptStarted
    ) {
        Write-Log -Message (
            "Console transcript file: $ConsoleOutputFile"
        )
    }


    Write-Log -Message (
        "Keep error log on failure: $KeepErrorLogOnFailure"
    )


    Write-Log -Message (
        "Cleanup after deployment: $CleanupAfterDeployment"
    )

    Write-Log -Message (
        'Final clean-success ITINO root deletion, including rollback data, follows ' +
        "CleanupAfterDeployment: $CleanupAfterDeployment"
    )



    Write-Log -Message (
        "Unattended mode: $UnattendedMode"
    )


    Write-Log -Message (
        "Close Lenovo Hotkey popup: $CloseLenovoHotkeyPopup"
    )


    Write-Log -Message (
        "Require administrator: $RequireAdministrator"
    )


    Write-Log -Message (
        "Maximum deployment cycles: $MaximumDeploymentCycles"
    )

    Write-Log -Message (
        "Preserve original driver baseline across restarts: $PreserveInitialDriverBaselineAcrossRestarts"
    )

    Write-Log -Message (
        "Preserve artifacts on failure: $PreserveArtifactsOnFailure"
    )

    Write-Log -Message (
        "Minimum firmware battery percent: $MinimumFirmwareBatteryPercent"
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
    # PHASE 9 - SESSION / SINGLE INSTANCE / FIRMWARE SAFETY
    # ========================================================

    Enter-ItinoDeploymentMutex

    Initialize-ItinoDeploymentSession

    Start-ItinoConsoleTranscript

    Remove-ItinoPreviousFailureLog

    Remove-ItinoPreviousRestartMarker

    $FirmwareSafety =
        Get-ItinoFirmwareSafety

    $env:ITINO_ALLOW_FIRMWARE_UPDATES =
        if ($FirmwareSafety.Allowed) {
            '1'
        }
        else {
            '0'
        }

    Write-Log -Message (
        'Firmware power safety: ' +
        "Allowed=$($FirmwareSafety.Allowed); " +
        "BatteryPresent=$($FirmwareSafety.BatteryPresent); " +
        "BatteryPercent=$($FirmwareSafety.BatteryPercent); " +
        "MinimumBatteryPercent=$($FirmwareSafety.MinimumBatteryPercent); " +
        "ExternalPower=$($FirmwareSafety.OnExternalPower); " +
        "PowerLineStatus=$($FirmwareSafety.PowerLineStatus); " +
        "Reason=$($FirmwareSafety.Reason)"
    )

    Write-Log -Message (
        "BitLocker: $(Get-ItinoBitLockerSummary)"
    )


    # ========================================================
    # OEM DOWNLOAD CONFIGURATION
    # ========================================================

    Write-Log -Message (
        "Dell official discovery URL: $DellCommandUpdateOfficialPageUrl"
    )

    Write-Log -Message (
        "Dell fallback version: $DellCommandUpdateFallbackVersion"
    )

    Write-Log -Message (
        "Dell fallback download URL: $DellCommandUpdateFallbackDownloadUrl"
    )

    Write-Log -Message (
        "HP official discovery URL: $HPImageAssistantOfficialPageUrl"
    )

    Write-Log -Message (
        "HP fallback version: $HPImageAssistantFallbackVersion"
    )

    Write-Log -Message (
        "HP fallback download URL: $HPImageAssistantFallbackDownloadUrl"
    )

    Write-Log -Message (
        "Lenovo System Update version for future maintenance: $LenovoSystemUpdateVersion"
    )

    Write-Log -Message (
        "Lenovo System Update download URL: $LenovoSystemUpdateDownloadUrl"
    )

    Write-Log -Message (
        "Lenovo first-start update engine: $LenovoLSUClientModuleName"
    )

    Write-Log -Message (
        "Lenovo module repository: $LenovoLSUClientRepository"
    )

    Write-Log -Message (
        "Lenovo maximum LSUClient rounds: $LenovoLSUClientMaximumRounds"
    )

    Write-Log -Message (
        "Lenovo LSUClient update types: $LenovoLSUClientUpdateTypes"
    )

    Write-Log -Message (
        "Lenovo LSUClient severities: $LenovoLSUClientSeverities"
    )


    Write-Log -Message (
        'Validating centralized OEM download configuration.'
    )


    Assert-OemControllerConfiguration


    Write-Log -Message (
        'Centralized OEM download configuration is valid.'
    )

    # ========================================================
    # VERIFY ALL SCRIPTS EXIST
    # ========================================================

    Write-Log -Message (
        'Checking required deployment scripts.'
    )


    foreach (
        $Script in $Scripts
    ) {

        $Path =
            Join-Path `
                $ScriptsPath `
                $Script.File


        if (
            -not (
                Test-Path -LiteralPath $Path
            )
        ) {

            throw (
                "Required script missing: $Path"
            )
        }


        Write-Log -Message (
            "Found: $($Script.File)"
        )
    }


    # ========================================================
    # RUN STAGES
    # ========================================================

    $ControllerStartTime =
        Get-Date


    foreach (
        $Script in $Scripts
    ) {

        if (
            (
                (Get-Date) -
                $ControllerStartTime
            ).TotalMinutes -gt $MaximumControllerRuntimeMinutes
        ) {
            throw (
                'Maximum controller runtime exceeded before stage ' +
                "'$($Script.Name)'."
            )
        }


        $ScriptPath =
            Join-Path `
                $ScriptsPath `
                $Script.File


        $Result =
            Invoke-DeploymentScript `
                -Name $Script.Name `
                -Path $ScriptPath


        $Results +=
            $Result


        # ====================================================
        # HANDLE EXIT CODE
        # ====================================================

        switch (
            $Result.ExitCode
        ) {

            0 {

                Write-Log -Message (
                    "Stage '$($Script.Name)' completed successfully."
                )
            }


            3010 {

                Write-Log `
                    -Message (
                        "Stage '$($Script.Name)' completed successfully " +
                        'and requested a restart.'
                    ) `
                    -Level 'WARNING'


                $RestartRequired =
                    $true
            }


            default {

                Write-Log `
                    -Message (
                        "Stage '$($Script.Name)' failed with exit code " +
                        "$($Result.ExitCode)."
                    ) `
                    -Level 'ERROR'


                $DeploymentFailed =
                    $true


                $FailedStage =
                    $Script.Name
            }
        }


        if ($DeploymentFailed) {

            Write-Log `
                -Message (
                    'Stopping driver deployment because a stage failed.'
                ) `
                -Level 'ERROR'


            break
        }
    }


    # ========================================================
    # RESTART MARKER
    # ========================================================

    if (
        Test-Path -LiteralPath $RestartFile
    ) {

        $RestartRequired =
            $true


        Write-Log `
            -Message (
                'RestartRequired.txt exists. A restart is required.'
            ) `
            -Level 'WARNING'
    }


    # ========================================================
    # OVERALL STATUS
    # ========================================================

    if ($DeploymentFailed) {

        $OverallStatus =
            'Failed'
    }
    elseif ($RestartRequired) {

        $OverallStatus =
            'SuccessRestartRequired'
    }
    else {

        $OverallStatus =
            'Success'
    }


    # ========================================================
    # DEPLOYMENT SUMMARY
    # ========================================================

    $HardwareInformation =
        Read-ItinoJsonFile `
            -Path $HardwareFile `
            -Description 'HardwareInformation.json'

    $DriverVerification =
        Read-ItinoJsonFile `
            -Path $VerificationFile `
            -Description 'DriverVerification.json'

    $RestartReasons =
        @(
            Get-RestartMarkerReasons
        )

    $UpdateDriversStage =
        Get-StageSummaryByName `
            -Results $Results `
            -Name 'Update Drivers'

    $ComputerSummary =
        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Manufacturer = $null
            Model = $null
            SerialNumber = $null
            Windows = $null
        }

    if ($HardwareInformation) {
        if ($HardwareInformation.Computer) {
            $ComputerSummary.ComputerName =
                Get-FirstPropertyValue -Object $HardwareInformation.Computer -Names @('ComputerName','Name')

            $ComputerSummary.Manufacturer =
                Get-FirstPropertyValue -Object $HardwareInformation.Computer -Names @('Manufacturer')

            $ComputerSummary.Model =
                Get-FirstPropertyValue -Object $HardwareInformation.Computer -Names @('Model')
        }

        if ($HardwareInformation.BIOS) {
            $ComputerSummary.SerialNumber =
                Get-FirstPropertyValue -Object $HardwareInformation.BIOS -Names @('SerialNumber','Serial')
        }

        if ($HardwareInformation.Windows) {
            $ComputerSummary.Windows =
                [PSCustomObject]@{
                    Caption =
                        Get-FirstPropertyValue -Object $HardwareInformation.Windows -Names @('Caption','ProductName')

                    Version =
                        Get-FirstPropertyValue -Object $HardwareInformation.Windows -Names @('Version')

                    BuildNumber =
                        Get-FirstPropertyValue -Object $HardwareInformation.Windows -Names @('BuildNumber','Build')

                    Architecture =
                        Get-FirstPropertyValue -Object $HardwareInformation.Windows -Names @('Architecture','OSArchitecture')
                }
        }
    }

    $OEMUpdateSummary =
        $null


    if (
        Test-Path `
            -LiteralPath $OEMUpdateResultFile `
            -PathType Leaf
    ) {

        try {

            $OEMUpdateSummary =
                Get-Content `
                    -LiteralPath $OEMUpdateResultFile `
                    -Raw `
                    -ErrorAction Stop |
                ConvertFrom-Json
        }
        catch {

            Write-Log `
                -Message (
                    'Unable to load OEMUpdateResult.json for deployment summary. ' +
                    "Reason: $($_.Exception.Message)"
                ) `
                -Level 'WARNING'
        }
    }


    $VerificationSummary = $null
    $VerificationV2Summary = $null
    $DriverChangesSummary = $null
    $DriverSnapshotsSummary = $null
    $OEMToolsSummary = @()

    if ($DriverVerification) {

        if ($DriverVerification.Summary) {

            $VerificationV2Summary =
                $DriverVerification.Summary
        }


        $VerificationResults =
            if ($DriverVerification.Results) {
                $DriverVerification.Results
            }
            else {
                $DriverVerification
            }

        $VerificationSummary =
            [PSCustomObject]@{
                Status =
                    Get-FirstPropertyValue -Object $VerificationResults -Names @('Status')

                DeviceErrorsBefore =
                    Get-FirstPropertyValue -Object $VerificationResults -Names @('DeviceErrorsBefore','BeforeErrorCount')

                DeviceErrorsAfter =
                    Get-FirstPropertyValue -Object $VerificationResults -Names @('DeviceErrorsAfter','AfterErrorCount')

                FixedDeviceErrors =
                    Get-FirstPropertyValue -Object $VerificationResults -Names @('FixedDeviceErrors','FixedCount')

                RemainingDeviceErrors =
                    Get-FirstPropertyValue -Object $VerificationResults -Names @('RemainingDeviceErrors','RemainingCount')

                NewDeviceErrors =
                    Get-FirstPropertyValue -Object $VerificationResults -Names @('NewDeviceErrors','NewCount')

                RestartDevices =
                    Get-FirstPropertyValue -Object $VerificationResults -Names @('RestartDevices','RestartDeviceCount')

                RestartRequired =
                    Get-FirstPropertyValue -Object $VerificationResults -Names @('RestartRequired')

                WindowsPendingRestart =
                    Get-FirstPropertyValue -Object $VerificationResults -Names @('WindowsPendingRestart')

                WindowsPendingRestartReasons =
                    @(
                        Get-FirstPropertyValue -Object $VerificationResults -Names @('WindowsPendingRestartReasons')
                    )
            }

        if ($DriverVerification.DriverChanges) {
            $DriverChangesSummary = $DriverVerification.DriverChanges
        }

        if ($DriverVerification.DriverSnapshots) {
            $DriverSnapshotsSummary = $DriverVerification.DriverSnapshots
        }

        if ($DriverVerification.OEMTools) {
            $OEMToolsSummary = @($DriverVerification.OEMTools)
        }
    }

    $UpdateSummary =
        [PSCustomObject]@{
            StageExitCode =
                if ($UpdateDriversStage) {
                    $UpdateDriversStage.ExitCode
                }
                else {
                    $null
                }

            DurationSeconds =
                if ($UpdateDriversStage) {
                    $UpdateDriversStage.DurationSeconds
                }
                else {
                    $null
                }

            RestartRequested =
                if ($UpdateDriversStage) {
                    ($UpdateDriversStage.ExitCode -eq 3010)
                }
                else {
                    $false
                }
        }

    # ========================================================
    # PHASE 10.11 - NORMALIZED FINAL DEPLOYMENT SUMMARY
    # ========================================================

    $FinalVerificationStatus =
        if (
            $VerificationV2Summary -and
            $VerificationV2Summary.OverallStatus
        ) {
            [string]$VerificationV2Summary.OverallStatus
        }
        elseif (
            $VerificationSummary -and
            $VerificationSummary.Status
        ) {
            [string]$VerificationSummary.Status
        }
        else {
            'Unknown'
        }


    $FinalOEMStatus =
        if (
            $OEMUpdateSummary -and
            $OEMUpdateSummary.Status
        ) {
            [string]$OEMUpdateSummary.Status
        }
        else {
            'NotAvailable'
        }


    $FinalRestartRequired =
        [bool](
            $RestartRequired -or
            (
                $VerificationV2Summary -and
                $VerificationV2Summary.RestartRequired
            ) -or
            (
                $OEMUpdateSummary -and
                $OEMUpdateSummary.RestartRequired
            )
        )


    $WindowsUpdateInstalledThisCycle =
        if (
            $OEMUpdateSummary -and
            $OEMUpdateSummary.WindowsUpdate -and
            $OEMUpdateSummary.WindowsUpdate.Total
        ) {
            [int]$OEMUpdateSummary.WindowsUpdate.Total.Installed
        }
        else {
            0
        }


    $FinalOutcome =
        if ($DeploymentFailed) {
            'Failed'
        }
        elseif ($FinalVerificationStatus -eq 'Failed') {
            'Failed'
        }
        elseif (
            $FinalVerificationStatus -eq 'Warning' -or
            $FinalOEMStatus -eq 'Warning'
        ) {
            'Warning'
        }
        elseif ($FinalRestartRequired) {
            'SuccessRestartRequired'
        }
        elseif (
            $WindowsUpdateInstalledThisCycle -gt 0
        ) {
            'Success'
        }
        elseif (
            $FinalVerificationStatus -eq 'SuccessNoUpdates' -or
            $FinalOEMStatus -eq 'SuccessNoUpdates'
        ) {
            'SuccessNoUpdates'
        }
        elseif (
            $FinalVerificationStatus -eq 'Success' -or
            $FinalOEMStatus -match '^Success'
        ) {
            'Success'
        }
        else {
            'Unknown'
        }


    $FinalSummary =
        [PSCustomObject]@{

            SchemaVersion =
                3

            Project =
                Get-ItinoProjectMetadata

            Outcome =
                $FinalOutcome

            VerificationStatus =
                $FinalVerificationStatus

            OEMStatus =
                $FinalOEMStatus

            WindowsUpdateInstalledThisCycle =
                $WindowsUpdateInstalledThisCycle

            RestartRequired =
                $FinalRestartRequired

            OEM =
                [PSCustomObject]@{

                    Manufacturer =
                        if ($OEMUpdateSummary) {
                            $OEMUpdateSummary.Manufacturer
                        }
                        else {
                            $Manufacturer
                        }

                    Tool =
                        if ($OEMUpdateSummary) {
                            $OEMUpdateSummary.Tool
                        }
                        else {
                            $null
                        }

                    ToolVersion =
                        if ($OEMUpdateSummary) {
                            $OEMUpdateSummary.ToolVersion
                        }
                        else {
                            $null
                        }

                    Recommendations =
                        if ($OEMUpdateSummary) {
                            $OEMUpdateSummary.Recommendations
                        }
                        else {
                            $null
                        }

                    Downloaded =
                        if ($OEMUpdateSummary) {
                            $OEMUpdateSummary.Downloaded
                        }
                        else {
                            $null
                        }

                    Installed =
                        if ($OEMUpdateSummary) {
                            $OEMUpdateSummary.Installed
                        }
                        else {
                            $null
                        }

                    Failed =
                        if ($OEMUpdateSummary) {
                            $OEMUpdateSummary.Failed
                        }
                        else {
                            $null
                        }
                }

            WindowsUpdate =
                if (
                    $OEMUpdateSummary -and
                    $OEMUpdateSummary.WindowsUpdate
                ) {
                    $OEMUpdateSummary.WindowsUpdate
                }
                else {
                    $null
                }

            DeviceHealth =
                if (
                    $VerificationV2Summary -and
                    $VerificationV2Summary.DeviceHealth
                ) {
                    $VerificationV2Summary.DeviceHealth
                }
                else {
                    $null
                }

            DriverChanges =
                if (
                    $VerificationV2Summary -and
                    $VerificationV2Summary.DriverChanges
                ) {
                    $VerificationV2Summary.DriverChanges
                }
                else {
                    $DriverChangesSummary
                }

            FallbackTelemetry =
                if (
                    $OEMUpdateSummary -and
                    $OEMUpdateSummary.FallbackTelemetry
                ) {
                    $OEMUpdateSummary.FallbackTelemetry
                }
                else {
                    $null
                }
        }


    $Summary =
        [PSCustomObject]@{
            SchemaVersion = 3
            Project = Get-ItinoProjectMetadata
            ComputerName = $env:COMPUTERNAME
            SessionId =
                if ($script:DeploymentSession) {
                    $script:DeploymentSession.SessionId
                }
                else {
                    $null
                }
            DeploymentCycle =
                if ($script:DeploymentSession) {
                    $script:DeploymentSession.Cycle
                }
                else {
                    $null
                }
            MaximumDeploymentCycles = $MaximumDeploymentCycles
            CompletionTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Status = $OverallStatus
            RestartRequired = $RestartRequired
            FailedStage = $FailedStage
            Stages = $Results
            Computer = $ComputerSummary
            UpdateDrivers = $UpdateSummary
            Verification = $VerificationSummary
            VerificationV2 = $VerificationV2Summary
            FinalSummary = $FinalSummary
            DriverChanges = $DriverChangesSummary
            DriverSnapshots = $DriverSnapshotsSummary
            OEMTools = @($OEMToolsSummary)
            OEMUpdateResult = $OEMUpdateSummary
            RestartReasons = @($RestartReasons)
        }

    $Summary |
        ConvertTo-Json `
            -Depth 12 |
        Set-Content `
            -LiteralPath $SummaryFile `
            -Encoding UTF8

    Write-Log -Message (
        "Deployment summary saved to '$SummaryFile'."
    )


    $PredictedFinalExitCode =
        if ($OverallStatus -eq 'Failed') {
            1
        }
        elseif ($RestartRequired) {
            3010
        }
        else {
            0
        }


    Update-DriverRollbackManifestMetadata `
        -DeploymentSummary $Summary `
        -FinalExitCode $PredictedFinalExitCode


    # ========================================================
    # CONSOLE SUMMARY
    # ========================================================

    Write-Host ''
    Write-Host '============================================================'
    Write-Host 'Driver Deployment Summary'
    Write-Host '============================================================'
    Write-Host ''
    Write-Host 'Project'
Write-Host (
    'Version          : ' +
    $DriverDeploymentVersion
)
Write-Host (
    'Phase            : ' +
    $DriverDeploymentPhase
)
Write-Host (
    'Release Channel  : ' +
    $DriverDeploymentReleaseChannel
)
Write-Host (
    'Controller       : ' +
    $ScriptVersion
)
Write-Host ''

Write-Host 'Final Result'
    Write-Host "Outcome          : $($FinalSummary.Outcome)"
    Write-Host "Verification     : $($FinalSummary.VerificationStatus)"
    Write-Host "OEM Status       : $($FinalSummary.OEMStatus)"
    Write-Host "Restart Required : $($FinalSummary.RestartRequired)"
    Write-Host ''




    foreach (
        $Result in $Results
    ) {

        Write-Host (
            "{0,-30} Exit Code: {1}" -f `
                $Result.Name,
                $Result.ExitCode
        )
    }


    Write-Host ''

    Write-Host (
        "Status           : $OverallStatus"
    )


    Write-Host (
        "Restart Required : $RestartRequired"
    )


    if ($FailedStage) {

        Write-Host (
            "Failed Stage      : $FailedStage"
        )
    }

    if ($ComputerSummary) {
        Write-Host ''
        Write-Host "Computer         : $($ComputerSummary.ComputerName)"
        Write-Host "Manufacturer     : $($ComputerSummary.Manufacturer)"
        Write-Host "Model            : $($ComputerSummary.Model)"
    }

    if ($VerificationV2Summary) {

        Write-Host ''
        Write-Host 'Verification'
        Write-Host "Overall Status   : $($VerificationV2Summary.OverallStatus)"
        Write-Host "Restart Required : $($VerificationV2Summary.RestartRequired)"

        if ($VerificationV2Summary.DeviceHealth) {

            Write-Host ''
            Write-Host 'Device Health'
            Write-Host "Status           : $($VerificationV2Summary.DeviceHealth.Status)"
            Write-Host "Errors Before    : $($VerificationV2Summary.DeviceHealth.ErrorsBefore)"
            Write-Host "Errors After     : $($VerificationV2Summary.DeviceHealth.ErrorsAfter)"
            Write-Host "Fixed            : $($VerificationV2Summary.DeviceHealth.Fixed)"
            Write-Host "Remaining        : $($VerificationV2Summary.DeviceHealth.Remaining)"
            Write-Host "New Errors       : $($VerificationV2Summary.DeviceHealth.NewErrors)"
        }

        if ($VerificationV2Summary.DriverChanges) {

            Write-Host ''
            Write-Host 'Verified Driver Changes'
            Write-Host "Status           : $($VerificationV2Summary.DriverChanges.Status)"
            Write-Host "Changed          : $($VerificationV2Summary.DriverChanges.Changed)"
            Write-Host "Added            : $($VerificationV2Summary.DriverChanges.Added)"
            Write-Host "Removed          : $($VerificationV2Summary.DriverChanges.Removed)"
        }
    }
    elseif ($VerificationSummary) {

        Write-Host ''
        Write-Host 'Verification'
        Write-Host "Errors Before    : $($VerificationSummary.DeviceErrorsBefore)"
        Write-Host "Errors After     : $($VerificationSummary.DeviceErrorsAfter)"
        Write-Host "Fixed            : $($VerificationSummary.FixedDeviceErrors)"
        Write-Host "Remaining        : $($VerificationSummary.RemainingDeviceErrors)"
    }

    if (
        $OEMUpdateSummary -and
        $OEMUpdateSummary.WindowsUpdate
    ) {

        $WindowsUpdateSummary =
            $OEMUpdateSummary.WindowsUpdate


        Write-Host ''
        Write-Host 'Windows Update'


        if ($WindowsUpdateSummary.Initial) {

            Write-Host (
                'Initial          : ' +
                "Status=$($WindowsUpdateSummary.Initial.Status), " +
                "Passes=$($WindowsUpdateSummary.Initial.PassesExecuted), " +
                "Found=$($WindowsUpdateSummary.Initial.Found), " +
                "Downloaded=$($WindowsUpdateSummary.Initial.Downloaded), " +
                "Installed=$($WindowsUpdateSummary.Initial.Installed), " +
                "Failed=$($WindowsUpdateSummary.Initial.Failed), " +
                "Blocked=$($WindowsUpdateSummary.Initial.Blocked)"
            )
        }


        if ($WindowsUpdateSummary.Final) {

            Write-Host (
                'Final            : ' +
                "Status=$($WindowsUpdateSummary.Final.Status), " +
                "Passes=$($WindowsUpdateSummary.Final.PassesExecuted), " +
                "Found=$($WindowsUpdateSummary.Final.Found), " +
                "Downloaded=$($WindowsUpdateSummary.Final.Downloaded), " +
                "Installed=$($WindowsUpdateSummary.Final.Installed), " +
                "Failed=$($WindowsUpdateSummary.Final.Failed), " +
                "Blocked=$($WindowsUpdateSummary.Final.Blocked)"
            )
        }


        if ($WindowsUpdateSummary.Fallback) {

            Write-Host (
                'Fallback/Forced  : ' +
                "Status=$($WindowsUpdateSummary.Fallback.Status), " +
                "Passes=$($WindowsUpdateSummary.Fallback.PassesExecuted), " +
                "Found=$($WindowsUpdateSummary.Fallback.Found), " +
                "Downloaded=$($WindowsUpdateSummary.Fallback.Downloaded), " +
                "Installed=$($WindowsUpdateSummary.Fallback.Installed), " +
                "Failed=$($WindowsUpdateSummary.Fallback.Failed), " +
                "Blocked=$($WindowsUpdateSummary.Fallback.Blocked)"
            )
        }


        if ($WindowsUpdateSummary.Total) {

            Write-Host (
                'Total            : ' +
                "Runs=$($WindowsUpdateSummary.Total.Runs), " +
                "Passes=$($WindowsUpdateSummary.Total.Passes), " +
                "Found=$($WindowsUpdateSummary.Total.Found), " +
                "Downloaded=$($WindowsUpdateSummary.Total.Downloaded), " +
                "Installed=$($WindowsUpdateSummary.Total.Installed), " +
                "Failed=$($WindowsUpdateSummary.Total.Failed), " +
                "Blocked=$($WindowsUpdateSummary.Total.Blocked)"
            )
        }
    }


    if ($OEMUpdateSummary) {

        Write-Host ''
        Write-Host 'OEM Update'
        Write-Host "Manufacturer     : $($OEMUpdateSummary.Manufacturer)"
        Write-Host "Tool             : $($OEMUpdateSummary.Tool)"
        Write-Host "Tool Version     : $($OEMUpdateSummary.ToolVersion)"
        Write-Host "Status           : $($OEMUpdateSummary.Status)"
        Write-Host "Recommendations  : $($OEMUpdateSummary.Recommendations)"
        Write-Host "Downloaded       : $($OEMUpdateSummary.Downloaded)"
        Write-Host "Installed        : $($OEMUpdateSummary.Installed)"
        Write-Host "Failed           : $($OEMUpdateSummary.Failed)"
        Write-Host "Restart Required : $($OEMUpdateSummary.RestartRequired)"
        Write-Host "Exit Code        : $($OEMUpdateSummary.ExitCode)"


        if ($OEMUpdateSummary.FallbackTelemetry) {

            $FallbackUsed =
                [bool](
                    $OEMUpdateSummary.FallbackTelemetry.WindowsUpdateFallbackUsed -or
                    $OEMUpdateSummary.FallbackTelemetry.CatalogRecoveryUsed -or
                    $OEMUpdateSummary.FallbackTelemetry.SystemUpdateFallbackUsed -or
                    $OEMUpdateSummary.FallbackTelemetry.PrimaryOEMMethodFailed -or
                    $OEMUpdateSummary.FallbackTelemetry.PrimaryOEMMethodUnavailable
                )


            Write-Host "Fallback Used    : $FallbackUsed"
            Write-Host "WU Fallback      : $($OEMUpdateSummary.FallbackTelemetry.WindowsUpdateFallbackUsed)"
            Write-Host "OEM Failed       : $($OEMUpdateSummary.FallbackTelemetry.PrimaryOEMMethodFailed)"
            Write-Host "OEM Unavailable  : $($OEMUpdateSummary.FallbackTelemetry.PrimaryOEMMethodUnavailable)"
            Write-Host "Catalog Recovery : $($OEMUpdateSummary.FallbackTelemetry.CatalogRecoveryUsed)"
            Write-Host "SystemUpdate FB  : $($OEMUpdateSummary.FallbackTelemetry.SystemUpdateFallbackUsed)"

            if (
                -not [string]::IsNullOrWhiteSpace(
                    [string]$OEMUpdateSummary.FallbackTelemetry.Reason
                )
            ) {

                Write-Host "Fallback Reason  : $($OEMUpdateSummary.FallbackTelemetry.Reason)"
            }
        }
    }


    if (
        $DriverChangesSummary -and
        -not $VerificationV2Summary
    ) {

        Write-Host ''
        Write-Host 'Driver Changes'
        Write-Host "Changed          : $($DriverChangesSummary.ChangedCount)"
        Write-Host "Added            : $($DriverChangesSummary.AddedCount)"
        Write-Host "Removed          : $($DriverChangesSummary.RemovedCount)"
    }

    if ($RestartReasons.Count -gt 0) {
        Write-Host ''
        Write-Host 'Restart Reasons'

        foreach ($RestartReason in $RestartReasons) {
            Write-Host " - $RestartReason"
        }
    }

    Write-Host ''
    Write-Host '============================================================'
    Write-Host ''


    # ========================================================
    # FINAL EXIT CODE
    # ========================================================

    if ($DeploymentFailed) {

        $FinalExitCode =
            1
    }
    elseif ($RestartRequired) {

        $FinalExitCode =
            3010
    }
    else {

        $FinalExitCode =
            0
    }


    Write-Log -Message (
        'FINAL PROJECT VERSION: ' +
        "Version=$DriverDeploymentVersion | " +
        "Phase=$DriverDeploymentPhase | " +
        "Channel=$DriverDeploymentReleaseChannel | " +
        "Controller=$ScriptVersion"
    )


    Write-Log -Message (
        'FINAL OUTCOME INPUT: ' +
        "Verification=$FinalVerificationStatus | " +
        "OEM=$FinalOEMStatus | " +
        "WUInstalledThisCycle=$WindowsUpdateInstalledThisCycle | " +
        "RestartRequired=$FinalRestartRequired"
    )


    Write-Log -Message (
        'FINAL DEPLOYMENT SUMMARY: ' +
        "Outcome=$($FinalSummary.Outcome) | " +
        "Verification=$($FinalSummary.VerificationStatus) | " +
        "OEMStatus=$($FinalSummary.OEMStatus) | " +
        "RestartRequired=$($FinalSummary.RestartRequired)"
    )


    if (
        $FinalSummary.WindowsUpdate -and
        $FinalSummary.WindowsUpdate.Total
    ) {

        Write-Log -Message (
            'FINAL WINDOWS UPDATE SUMMARY: ' +
            "Runs=$($FinalSummary.WindowsUpdate.Total.Runs) | " +
            "Passes=$($FinalSummary.WindowsUpdate.Total.Passes) | " +
            "Found=$($FinalSummary.WindowsUpdate.Total.Found) | " +
            "Downloaded=$($FinalSummary.WindowsUpdate.Total.Downloaded) | " +
            "Installed=$($FinalSummary.WindowsUpdate.Total.Installed) | " +
            "Failed=$($FinalSummary.WindowsUpdate.Total.Failed) | " +
            "Blocked=$($FinalSummary.WindowsUpdate.Total.Blocked)"
        )
    }


    if ($FinalSummary.OEM) {

        Write-Log -Message (
            'FINAL OEM SUMMARY: ' +
            "Manufacturer=$($FinalSummary.OEM.Manufacturer) | " +
            "Tool=$($FinalSummary.OEM.Tool) | " +
            "Version=$($FinalSummary.OEM.ToolVersion) | " +
            "Recommendations=$($FinalSummary.OEM.Recommendations) | " +
            "Downloaded=$($FinalSummary.OEM.Downloaded) | " +
            "Installed=$($FinalSummary.OEM.Installed) | " +
            "Failed=$($FinalSummary.OEM.Failed)"
        )
    }


    # ========================================================
    # FINAL RESULT
    # ========================================================

    if ($DeploymentFailed) {

        Write-Log `
            -Message (
                "Driver deployment failed during '$FailedStage'."
            ) `
            -Level 'ERROR'


        Save-DeploymentErrorLog `
            -FailedStage $FailedStage `
            -ExitCode $FinalExitCode
    }
    elseif (
        $RestartRequired
    ) {

        Write-Log `
            -Message (
                'Driver deployment completed successfully. ' +
                'Restart required.'
            ) `
            -Level 'WARNING'
    }
    else {

        Write-Log -Message (
            'Driver deployment completed successfully. ' +
            'No restart required.'
        )
    }


    # ========================================================
    # SHOW FINAL INFORMATION BEFORE CLEANUP
    # ========================================================

    Show-DeploymentFinished `
        -ExitCode $FinalExitCode `
        -Status $OverallStatus `
        -RestartRequired $RestartRequired `
        -FailedStage $FailedStage

    Show-DriverVerification


    # ========================================================
    # CLEANUP
    # ========================================================
    #
    # Exit 0:
    #
    #     Deployment completed.
    #     Cleanup is allowed.
    #
    # Exit 1:
    #
    #     Deployment failed.
    #     Failure information has already been copied to the
    #     persistent error log.
    #     Cleanup is allowed.
    #
    # Exit 3010:
    #
    #     Deployment is not finished yet.
    #     Windows must restart and this controller must run
    #     again.
    #
    #     Do NOT cleanup.
    #
    # ========================================================

    Save-ItinoMachineReadableResult `
        -ExitCode $FinalExitCode `
        -Status $OverallStatus


    if (
        $FinalExitCode -eq 3010
    ) {

        Save-ItinoDeploymentSession `
            -Status 'RestartRequired'

        Write-Log `
            -Message (
                'Restart required. Preserving ITINO state, reports and ' +
                'the ORIGINAL rollback baseline for the next cycle.'
            ) `
            -Level 'WARNING'
    }
    elseif (
        $FinalExitCode -eq 1
    ) {

        Save-ItinoDeploymentSession `
            -Status 'Failed'

        if ($PreserveArtifactsOnFailure) {
            Write-Log `
                -Message (
                    'Deployment failed. Preserving complete ITINO ' +
                    'diagnostics and rollback data.'
                ) `
                -Level 'WARNING'
        }
        else {
            Invoke-FinalCleanup
        }
    }
    else {

        Save-ItinoDeploymentSession `
            -Status 'Success'

        Remove-EntireItinoRoot
    }


    # ========================================================
    # RETURN RESULT TO PARENT DEPLOYMENT
    # ========================================================

    Write-Host ''

    Write-Host (
        "Driver deployment controller exit code: $FinalExitCode"
    )


    Stop-ItinoConsoleTranscript

    Copy-ItinoLogsToScriptLocation

    Exit-ItinoDeploymentMutex


    exit $FinalExitCode
}
catch {

    $ErrorMessage =
        $_.Exception.Message


    # ========================================================
    # SPECIAL RESULT: ANOTHER INSTANCE IS ALREADY RUNNING
    # ========================================================
    #
    # This is not an actual driver deployment failure.
    #
    # Do not:
    #   - overwrite deployment state
    #   - create DriverDeployment-Error.log
    #   - change rollback data
    #   - change restart markers
    # ========================================================

    if (
        $script:ControllerSpecialExitCode -eq 1618
    ) {

        Write-Host ''
        Write-Host '============================================================'
        Write-Host 'ITINO Driver Deployment'
        Write-Host '============================================================'
        Write-Host ''
        Write-Host 'Another ITINO driver deployment is already running.'
        Write-Host 'No active deployment files were changed by this instance.'
        Write-Host ''
        Write-Host 'Exit Code : 1618'
        Write-Host ''

        Stop-ItinoConsoleTranscript

        Exit-ItinoDeploymentMutex

        exit 1618
    }


    $DeploymentFailed =
        $true


    if (
        [string]::IsNullOrWhiteSpace(
            $FailedStage
        )
    ) {

        $FailedStage =
            'Driver Deployment Controller'
    }


    try {

        Write-Log `
            -Message (
                "Unhandled deployment error: $ErrorMessage"
            ) `
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
    }
    catch {

        Write-Host (
            "ERROR: $ErrorMessage"
        )
    }


    # ========================================================
    # PRESERVE FAILURE INFORMATION
    # ========================================================

    Save-DeploymentErrorLog `
        -FailedStage $FailedStage `
        -ExitCode 1


    # ========================================================
    # CLEANUP TEMPORARY WORKING FILES
    # ========================================================
    #
    # Failure is final for this controller invocation.
    #
    # DriverDeployment-Error.log is outside $BasePath, so it
    # survives this cleanup.
    #
    # ========================================================


    try {
        Save-ItinoMachineReadableResult `
            -ExitCode 1 `
            -Status 'Failed'

        Save-ItinoDeploymentSession `
            -Status 'Failed'
    }
    catch {
    }


    if (-not $PreserveArtifactsOnFailure) {
        Invoke-FinalCleanup
    }
    else {
        Write-Host ''
        Write-Host (
            'Failure artifacts preserved under C:\ProgramData\Itino.'
        )
    }


    Stop-ItinoConsoleTranscript

    Copy-ItinoLogsToScriptLocation

    Exit-ItinoDeploymentMutex


    # ========================================================
    # RETURN FAILURE
    # ========================================================

    exit 1
}