#requires -version 5.1

# ============================================================
# PARAMETERS
# ============================================================
#
# IMPORTANT:
# In Windows PowerShell, the param() block must appear before
# executable statements such as variable assignments.
# ============================================================

param(
    [switch]$ResumeFromTask
)


<#
.SYNOPSIS
    Universal Driver Installer launcher with optional reboot resume.

.DESCRIPTION
    Runs Run-DriverDeployment.ps1 and creates a temporary Scheduled Task ONLY
    when the controller returns exit code 3010, so deployment can continue
    after Windows restarts.

    When the wrapper is started by that task after a reboot, the task is
    deleted before the next deployment cycle starts. If that cycle again
    returns 3010, a fresh task is created for the next reboot.


    Compatible with Windows PowerShell 5.1. The param() block is placed
    before all executable configuration statements.

    Exit code handling:
        0    = Final success. Resume task is removed.
        1    = Failure. Resume task is removed.
        1618 = Another Universal Driver Installer is already running.
               Resume task is kept because the active deployment still owns it.
        3010 = Success, restart required.
               Resume task is kept.
               If automatic restart is enabled, Windows is restarted.

    The task runs as SYSTEM at startup with highest privileges.

    IMPORTANT:
    Keep this file and Run-DriverDeployment.ps1 in the same folder.
#>


# ============================================================
# OPTIONS
# ============================================================

# Create a temporary startup task that resumes this deployment
# after Windows restarts.
$EnableResumeAfterRestart =
    $true


# Automatically restart Windows when Run-DriverDeployment.ps1
# returns exit code 3010.
#
# $true:
#   Controller returns 3010
#       -> task remains registered
#       -> PC automatically restarts
#       -> task starts this wrapper after boot
#
# $false:
#   Controller returns 3010
#       -> task remains registered
#       -> PC is NOT restarted automatically
#       -> deployment resumes after the next manual restart
$AutomaticallyRestartOn3010 =
    $true


# Delay before automatic reboot after exit code 3010.
$RestartDelaySeconds =
    30


# Delay after Windows startup before the scheduled task runs.
# This gives networking and Windows services time to initialize.
$ResumeDelayAfterStartupSeconds =
    60


# Name of the temporary Windows Scheduled Task.
$ResumeTaskName =
    'Universal Driver Installer Resume'


# Main deployment controller. Expected beside this wrapper.
$ControllerFileName =
    'Run-DriverDeployment.ps1'



# Keep a live copy of AutoResume.log beside the deployment
# package so the restart/resume history survives ProgramData
# cleanup by the controller.
$CopyLogsToScriptLocation =
    $true


# Folder created beside this wrapper.
$CopiedLogsFolderName =
    'Logs'


# Install.ps1 creates this marker inside the downloaded package. It allows the
# wrapper to remove only bootstrap-installed files after final success. Git
# clones, USB copies, and manually extracted packages do not carry the marker.
$BootstrapCleanupMarkerName =
    '.universal-driver-installer-install-root'


# ============================================================
# PATHS
# ============================================================

$WrapperPath =
    $PSCommandPath


$WrapperDirectory =
    Split-Path `
        -Parent `
        $WrapperPath


$ControllerPath =
    Join-Path `
        $WrapperDirectory `
        $ControllerFileName



$CopiedLogsRoot =
    Join-Path `
        $WrapperDirectory `
        $CopiedLogsFolderName


$DeploymentStateFile =
    'C:\ProgramData\UniversalDriverInstaller\DriverDeploymentState.json'


$script:ControllerExecutionCompleted =
    $false


function Get-UniversalDriverInstallerManufacturerFolder {

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


    switch -Regex ($Manufacturer) {

        'HP|Hewlett' {
            return 'Hp'
        }

        'LENOVO' {
            return 'Lenovo'
        }

        'DELL' {
            return 'Dell'
        }

        default {

            if (
                [string]::IsNullOrWhiteSpace(
                    $Manufacturer
                )
            ) {
                return 'Unknown'
            }


            return (
                $Manufacturer `
                    -replace '[\\/:*?"<>|]', '_'
            ).Trim()
        }
    }
}


function Get-UniversalDriverInstallerUsbSessionDirectory {

    $ManufacturerFolder =
        Get-UniversalDriverInstallerManufacturerFolder


    $ComputerDirectory =
        Join-Path `
            (
                Join-Path `
                    $CopiedLogsRoot `
                    $ManufacturerFolder
            ) `
            $env:COMPUTERNAME


    $SessionId =
        $null


    if (
        Test-Path `
            -LiteralPath $DeploymentStateFile `
            -PathType Leaf
    ) {

        try {

            $State =
                Get-Content `
                    -LiteralPath $DeploymentStateFile `
                    -Raw `
                    -ErrorAction Stop |
                ConvertFrom-Json `
                    -ErrorAction Stop


            $SessionId =
                [string]$State.SessionId
        }
        catch {
        }
    }


    if (
        -not [string]::IsNullOrWhiteSpace(
            $SessionId
        )
    ) {

        return (
            Join-Path `
                $ComputerDirectory `
                $SessionId
        )
    }


    # On final exit 0 the controller may already have deleted
    # C:\ProgramData\UniversalDriverInstaller. The controller copies the session
    # logs to USB before that cleanup, so use the newest session
    # folder as the final logging destination.
    if (
        Test-Path `
            -LiteralPath $ComputerDirectory `
            -PathType Container
    ) {

        $NewestSessionDirectory =
            Get-ChildItem `
                -LiteralPath $ComputerDirectory `
                -Directory `
                -ErrorAction SilentlyContinue |
            Sort-Object `
                -Property LastWriteTime `
                -Descending |
            Select-Object `
                -First 1


        if ($NewestSessionDirectory) {
            return $NewestSessionDirectory.FullName
        }
    }


    return $null
}


# Dedicated wrapper log. This is separate from the controller
# transcript so restart/resume behavior can be verified easily.
$AutoResumeLogDirectory =
    'C:\ProgramData\UniversalDriverInstaller\DriverDeployment'


$AutoResumeLogPath =
    Join-Path `
        $AutoResumeLogDirectory `
        'AutoResume.log'

$TempAutoResumeLogDirectory =
    'C:\Windows\Temp\UniversalDriverInstaller-Deployment\Driver'

$TempAutoResumeLogPath =
    Join-Path `
        $TempAutoResumeLogDirectory `
        'AutoResume.log'


# ============================================================
# HELPERS
# ============================================================

function Write-AutoResumeLog {

    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet(
            'INFO',
            'WARNING',
            'ERROR'
        )]
        [string]$Level = 'INFO'
    )


    try {

        $Line =
            (
                '[{0}] [{1}] {2}' -f
                (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
                $Level,
                $Message
            )


        # Before/during controller execution, ProgramData is the
        # working AutoResume log. After the controller has
        # completed, do NOT recreate DriverDeployment if final
        # cleanup already removed C:\ProgramData\UniversalDriverInstaller.
        if (
            (
                Test-Path `
                    -LiteralPath $AutoResumeLogDirectory `
                    -PathType Container
            ) -or
            (-not $script:ControllerExecutionCompleted)
        ) {

            if (-not (
                Test-Path `
                    -LiteralPath $AutoResumeLogDirectory `
                    -PathType Container
            )) {

                New-Item `
                    -ItemType Directory `
                    -Path $AutoResumeLogDirectory `
                    -Force `
                    -ErrorAction Stop |
                Out-Null
            }


            Add-Content `
                -LiteralPath $AutoResumeLogPath `
                -Value $Line `
                -Encoding UTF8 `
                -ErrorAction Stop
        }


        if ($CopyLogsToScriptLocation) {

            $UsbSessionDirectory =
                Get-UniversalDriverInstallerUsbSessionDirectory


            if (
                -not [string]::IsNullOrWhiteSpace(
                    $UsbSessionDirectory
                )
            ) {

                if (-not (
                    Test-Path `
                        -LiteralPath $UsbSessionDirectory `
                        -PathType Container
                )) {

                    New-Item `
                        -ItemType Directory `
                        -Path $UsbSessionDirectory `
                        -Force `
                        -ErrorAction Stop |
                    Out-Null
                }


                $UsbAutoResumeLogPath =
                    Join-Path `
                        $UsbSessionDirectory `
                        'AutoResume.log'


                Add-Content `
                    -LiteralPath $UsbAutoResumeLogPath `
                    -Value $Line `
                    -Encoding UTF8 `
                    -ErrorAction Stop
            }
        }


        # Keep an independent live copy in Windows Temp. This copy survives
        # the controller's production cleanup of C:\ProgramData\UniversalDriverInstaller.
        if (-not (
            Test-Path `
                -LiteralPath $TempAutoResumeLogDirectory `
                -PathType Container
        )) {

            New-Item `
                -ItemType Directory `
                -Path $TempAutoResumeLogDirectory `
                -Force `
                -ErrorAction Stop |
            Out-Null
        }

        Add-Content `
            -LiteralPath $TempAutoResumeLogPath `
            -Value $Line `
            -Encoding UTF8 `
            -ErrorAction Stop
    }
    catch {

        # Logging must never block deployment.
    }
}


function Test-IsAdministrator {

    try {

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
    catch {

        return $false
    }
}


function Remove-UniversalDriverInstallerResumeTask {

    try {

        $ExistingTask =
            Get-ScheduledTask `
                -TaskName $ResumeTaskName `
                -ErrorAction SilentlyContinue


        if ($ExistingTask) {

            Unregister-ScheduledTask `
                -TaskName $ResumeTaskName `
                -Confirm:$false `
                -ErrorAction Stop


            Write-Host (
                "Removed temporary resume task: $ResumeTaskName"
            )

            Write-AutoResumeLog -Message (
                "Removed temporary resume task: $ResumeTaskName"
            )
        }
    }
    catch {

        Write-Host (
            'WARNING: Unable to remove temporary resume task. ' +
            "Reason: $($_.Exception.Message)"
        )
    }
}


function Register-UniversalDriverInstallerResumeTask {

    if (-not $EnableResumeAfterRestart) {
        return
    }


    if (-not (
        Test-Path -LiteralPath $WrapperPath
    )) {

        throw (
            "Resume wrapper was not found: $WrapperPath"
        )
    }


    $PowerShellExe =
        Join-Path `
            $PSHOME `
            'powershell.exe'


    $Arguments =
        (
            '-NoLogo -NoProfile -ExecutionPolicy Bypass ' +
            '-File "' +
            $WrapperPath +
            '" -ResumeFromTask'
        )


    $Action =
        New-ScheduledTaskAction `
            -Execute $PowerShellExe `
            -Argument $Arguments `
            -WorkingDirectory $WrapperDirectory


    $Trigger =
        New-ScheduledTaskTrigger `
            -AtStartup


    try {

        $Trigger.Delay =
            'PT' +
            [int]$ResumeDelayAfterStartupSeconds +
            'S'
    }
    catch {

        Write-Host (
            'WARNING: Unable to set startup task delay. ' +
            'The task will run immediately after startup.'
        )
    }


    $Principal =
        New-ScheduledTaskPrincipal `
            -UserId 'SYSTEM' `
            -LogonType ServiceAccount `
            -RunLevel Highest


    $Settings =
        New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -MultipleInstances IgnoreNew


    $Task =
        New-ScheduledTask `
            -Action $Action `
            -Trigger $Trigger `
            -Principal $Principal `
            -Settings $Settings


    Register-ScheduledTask `
        -TaskName $ResumeTaskName `
        -InputObject $Task `
        -Force `
        -ErrorAction Stop |
    Out-Null


    Write-Host (
        "Resume task ready: $ResumeTaskName"
    )

    Write-Host (
        "Resume delay after startup: $ResumeDelayAfterStartupSeconds seconds"
    )

    Write-AutoResumeLog -Message (
        "Resume task created. Task='$ResumeTaskName'; StartupDelaySeconds=$ResumeDelayAfterStartupSeconds"
    )
}


function Invoke-UniversalDriverInstallerAutomaticRestart {

    Write-Host ''
    Write-Host '============================================================'
    Write-Host 'RESTART REQUIRED'
    Write-Host '============================================================'
    Write-Host ''
    Write-Host (
        "Automatic restart enabled. Restarting in $RestartDelaySeconds seconds."
    )

    Write-Host (
        'The temporary resume task will continue the driver deployment after startup.'
    )
    Write-Host ''

    Write-AutoResumeLog -Message (
        "Automatic restart scheduled in $RestartDelaySeconds seconds after controller exit code 3010."
    )


    # shutdown.exe is used instead of Restart-Computer so the
    # command can include a visible delay and reason.
    & "$env:SystemRoot\System32\shutdown.exe" `
        /r `
        /t $RestartDelaySeconds `
        /f `
        /d p:2:4 `
        /c "Universal Driver Installer requires a restart."


    $ShutdownExitCode =
        $LASTEXITCODE


    if ($ShutdownExitCode -ne 0) {

        throw (
            "Unable to schedule Windows restart. shutdown.exe exit code: $ShutdownExitCode"
        )
    }
}


function Start-UniversalDriverInstallerBootstrapCleanup {

    $MarkerPath =
        Join-Path `
            $WrapperDirectory `
            $BootstrapCleanupMarkerName


    if (-not (
        Test-Path `
            -LiteralPath $MarkerPath `
            -PathType Leaf
    )) {
        return $false
    }


    try {

        $InstallRoot =
            (
                Get-Content `
                    -LiteralPath $MarkerPath `
                    -Raw `
                    -ErrorAction Stop
            ).Trim().TrimStart([char]0xFEFF)


        if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
            throw 'The bootstrap cleanup marker is empty.'
        }


        $InstallRoot =
            [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')

        $FullWrapperDirectory =
            [IO.Path]::GetFullPath($WrapperDirectory).TrimEnd('\')


        if (
            [IO.Path]::GetFileName($InstallRoot) -ne
            'UniversalDriverInstaller'
        ) {
            throw (
                'The bootstrap cleanup target has an unexpected directory ' +
                "name: $InstallRoot"
            )
        }


        if (-not $FullWrapperDirectory.StartsWith(
            $InstallRoot + '\',
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw (
                'The running package is not located inside the requested ' +
                "cleanup target. Package='$FullWrapperDirectory'; " +
                "Target='$InstallRoot'."
            )
        }


        $CleanupLogPath =
            'C:\Windows\Temp\UniversalDriverInstaller-Cleanup.log'

        $DeploymentTempRoot =
            'C:\Windows\Temp\UniversalDriverInstaller-Deployment'

        $EscapedInstallRoot =
            $InstallRoot.Replace("'", "''")

        $EscapedCleanupLogPath =
            $CleanupLogPath.Replace("'", "''")

        $EscapedDeploymentTempRoot =
            $DeploymentTempRoot.Replace("'", "''")


        $CleanupScript = @"
`$ErrorActionPreference = 'Stop'
`$Target = '$EscapedInstallRoot'
`$DeploymentTempRoot = '$EscapedDeploymentTempRoot'
`$LogPath = '$EscapedCleanupLogPath'
for (`$Attempt = 1; `$Attempt -le 12; `$Attempt++) {
    Start-Sleep -Seconds 5
    try {
        if (Test-Path -LiteralPath `$Target) {
            Remove-Item -LiteralPath `$Target -Recurse -Force -ErrorAction Stop
        }
        if (Test-Path -LiteralPath `$DeploymentTempRoot) {
            Remove-Item -LiteralPath `$DeploymentTempRoot -Recurse -Force -ErrorAction Stop
        }
        Add-Content -LiteralPath `$LogPath -Value "`$(Get-Date -Format o) Success cleanup completed. Bootstrap='`$Target'; DeploymentTemp='`$DeploymentTempRoot'"
        exit 0
    }
    catch {
        Add-Content -LiteralPath `$LogPath -Value "`$(Get-Date -Format o) Cleanup attempt `$Attempt failed: `$(`$_.Exception.Message)"
    }
}
exit 1
"@


        $EncodedCleanupScript =
            [Convert]::ToBase64String(
                [Text.Encoding]::Unicode.GetBytes($CleanupScript)
            )


        Start-Process `
            -FilePath "$PSHOME\powershell.exe" `
            -ArgumentList @(
                '-NoLogo',
                '-NoProfile',
                '-ExecutionPolicy',
                'Bypass',
                '-WindowStyle',
                'Hidden',
                '-EncodedCommand',
                $EncodedCleanupScript
            ) `
            -WindowStyle Hidden `
            -ErrorAction Stop |
        Out-Null


        Write-Host (
            'Success cleanup scheduled for the bootstrap installation and ' +
            'deployment Temp folder.'
        )

        Write-AutoResumeLog -Message (
            'Success cleanup scheduled. ' +
            "Bootstrap='$InstallRoot'; " +
            "DeploymentTemp='$DeploymentTempRoot'"
        )

        return $true
    }
    catch {

        Write-Host (
            'WARNING: Unable to schedule success cleanup. ' +
            "Reason: $($_.Exception.Message)"
        )

        Write-AutoResumeLog `
            -Message (
                'Unable to schedule success cleanup. ' +
                "Reason: $($_.Exception.Message)"
            ) `
            -Level WARNING

        return $false
    }
}


# ============================================================
# START
# ============================================================

Write-Host ''
Write-Host '============================================================'
Write-Host 'Universal Driver Installer Auto Resume'
Write-Host '============================================================'
Write-Host ''

Write-Host (
    "Resume after restart : $EnableResumeAfterRestart"
)

Write-Host (
    "Automatic restart    : $AutomaticallyRestartOn3010"
)

Write-Host (
    "Controller           : $ControllerPath"
)

Write-Host (
    "Started from task    : $ResumeFromTask"
)

Write-Host ''

Write-AutoResumeLog -Message (
    "Wrapper started. ResumeFromTask=$ResumeFromTask; User=$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name); Wrapper='$WrapperPath'"
)


# ============================================================
# REQUIRE ADMINISTRATOR
# ============================================================

if (-not (
    Test-IsAdministrator
)) {

    Write-Host 'ERROR: Administrator rights are required.'
    exit 1
}


# ============================================================
# VALIDATE CONTROLLER
# ============================================================

if (-not (
    Test-Path -LiteralPath $ControllerPath
)) {

    Write-Host (
        "ERROR: Controller was not found: $ControllerPath"
    )

    Remove-UniversalDriverInstallerResumeTask

    exit 1
}


# ============================================================
# RESUME TASK CREATION POLICY
# ============================================================
#
# IMPORTANT:
# The resume task is NOT created before the deployment starts.
#
# It is created ONLY when Run-DriverDeployment.ps1 returns 3010.
#
# This means:
#   Exit 0    -> no task is created
#   Exit 1    -> no task is created
#   Exit 1618 -> no task is created/changed
#   Exit 3010 -> create/refresh resume task
#
# ============================================================


# ============================================================
# STARTED BY RESUME TASK
# ============================================================
#
# If Windows has restarted and this wrapper was launched by the
# temporary startup task, remove that task immediately.
#
# If the next deployment cycle returns 3010, the task will be
# created again before the next reboot.
# ============================================================

if ($ResumeFromTask) {

    Write-Host (
        'Deployment resumed after restart. Removing the temporary startup task.'
    )

    Write-AutoResumeLog -Message (
        'Started by scheduled task after restart. Removing the temporary resume task before starting the next deployment cycle.'
    )

    Remove-UniversalDriverInstallerResumeTask
}


# ============================================================
# RUN DRIVER DEPLOYMENT CONTROLLER
# ============================================================

Write-Host ''
Write-Host '============================================================'
Write-Host 'STARTING DRIVER DEPLOYMENT CONTROLLER'
Write-Host '============================================================'
Write-Host ''

Write-AutoResumeLog -Message (
    "Starting controller: $ControllerPath"
)


& "$PSHOME\powershell.exe" `
    -NoLogo `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $ControllerPath


$ControllerExitCode =
    [int]$LASTEXITCODE


$script:ControllerExecutionCompleted =
    $true


Write-Host ''
Write-Host '============================================================'
Write-Host 'DRIVER DEPLOYMENT CONTROLLER FINISHED'
Write-Host '============================================================'
Write-Host ''

Write-Host (
    "Controller Exit Code: $ControllerExitCode"
)

Write-Host ''

Write-AutoResumeLog -Message (
    "Controller finished. ExitCode=$ControllerExitCode"
)


# ============================================================
# HANDLE CONTROLLER RESULT
# ============================================================

switch ($ControllerExitCode) {

    0 {

        # Final clean success.
        # Run-DriverDeployment.ps1 may already have removed
        # C:\ProgramData\UniversalDriverInstaller. The Scheduled Task is separate
        # and must be removed here.

        Remove-UniversalDriverInstallerResumeTask

        Write-Host (
            'Driver deployment completed successfully.'
        )

        Write-AutoResumeLog -Message (
            'Deployment completed successfully. ExitCode=0. No further resume task required.'
        )

        [void](
            Start-UniversalDriverInstallerBootstrapCleanup
        )

        exit 0
    }


    3010 {

        if (-not $EnableResumeAfterRestart) {

            Write-Host (
                'Restart required, but automatic resume is disabled.'
            )

            Write-AutoResumeLog -Message (
                'Controller returned 3010, but resume-after-restart is disabled.'
            ) -Level WARNING

            exit 3010
        }


        # ----------------------------------------------------
        # CREATE RESUME TASK ONLY AFTER EXIT CODE 3010
        # ----------------------------------------------------

        try {

            Register-UniversalDriverInstallerResumeTask
        }
        catch {

            Write-Host (
                'ERROR: Driver deployment requires a restart, but the ' +
                'resume task could not be created. ' +
                "Reason: $($_.Exception.Message)"
            )

            Write-Host (
                'Automatic reboot will NOT be started because the ' +
                'deployment would not be able to resume safely.'
            )

            exit 3010
        }


        Write-Host (
            'Restart required. Resume task was created successfully.'
        )


        if ($AutomaticallyRestartOn3010) {

            try {

                Invoke-UniversalDriverInstallerAutomaticRestart
            }
            catch {

                Write-Host (
                    'ERROR: Automatic restart failed. ' +
                    "Reason: $($_.Exception.Message)"
                )

                Write-Host (
                    'The resume task is registered. A manual restart will continue the deployment.'
                )

                exit 3010
            }
        }
        else {

            Write-Host (
                'Automatic restart is disabled. Restart Windows manually to continue.'
            )
        }


        exit 3010
    }


    1618 {

        # Another controller process owns the deployment.
        # Do not create, remove or change the resume task here.

        Write-Host (
            'Another Universal Driver Installer is already running.'
        )

        Write-Host (
            'No resume task was created or changed by this launcher instance.'
        )

        Write-AutoResumeLog -Message (
            'Controller returned 1618. Another deployment instance is already running. Resume task unchanged.'
        ) -Level WARNING

        exit 1618
    }


    default {

        # Actual failure. Do not create a reboot loop.
        Remove-UniversalDriverInstallerResumeTask

        Write-Host (
            "Driver deployment failed with exit code $ControllerExitCode."
        )

        Write-Host (
            'Automatic restart/resume has been disabled for this failed deployment.'
        )

        exit $ControllerExitCode
    }
}
