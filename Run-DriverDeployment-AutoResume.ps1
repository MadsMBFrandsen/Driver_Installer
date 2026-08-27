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
    ITINO driver deployment launcher with optional reboot resume.

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
        1618 = Another ITINO deployment is already running.
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
    'ITINO Driver Deployment Resume'


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


$CopiedAutoResumeLogDirectory =
    Join-Path `
        $CopiedLogsRoot `
        $env:COMPUTERNAME


$CopiedAutoResumeLogPath =
    Join-Path `
        $CopiedAutoResumeLogDirectory `
        'AutoResume.log'


# Dedicated wrapper log. This is separate from the controller
# transcript so restart/resume behavior can be verified easily.
$AutoResumeLogDirectory =
    'C:\ProgramData\Itino\DriverDeployment'


$AutoResumeLogPath =
    Join-Path `
        $AutoResumeLogDirectory `
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

        if (-not (
            Test-Path -LiteralPath $AutoResumeLogDirectory
        )) {

            New-Item `
                -ItemType Directory `
                -Path $AutoResumeLogDirectory `
                -Force `
                -ErrorAction Stop |
            Out-Null
        }


        $Line =
            (
                '[{0}] [{1}] {2}' -f
                (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
                $Level,
                $Message
            )


        Add-Content `
            -LiteralPath $AutoResumeLogPath `
            -Value $Line `
            -Encoding UTF8 `
            -ErrorAction Stop


        if ($CopyLogsToScriptLocation) {

            if (-not (
                Test-Path `
                    -LiteralPath $CopiedAutoResumeLogDirectory
            )) {

                New-Item `
                    -ItemType Directory `
                    -Path $CopiedAutoResumeLogDirectory `
                    -Force `
                    -ErrorAction Stop |
                Out-Null
            }


            Add-Content `
                -LiteralPath $CopiedAutoResumeLogPath `
                -Value $Line `
                -Encoding UTF8 `
                -ErrorAction Stop
        }
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


function Remove-ItinoResumeTask {

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


function Register-ItinoResumeTask {

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
            -Argument $Arguments


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


function Invoke-ItinoAutomaticRestart {

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
        /c "ITINO driver deployment requires a restart."


    $ShutdownExitCode =
        $LASTEXITCODE


    if ($ShutdownExitCode -ne 0) {

        throw (
            "Unable to schedule Windows restart. shutdown.exe exit code: $ShutdownExitCode"
        )
    }
}


# ============================================================
# START
# ============================================================

Write-Host ''
Write-Host '============================================================'
Write-Host 'ITINO Driver Deployment Auto Resume'
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

    Remove-ItinoResumeTask

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

    Remove-ItinoResumeTask
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
        # C:\ProgramData\Itino. The Scheduled Task is separate
        # and must be removed here.

        Remove-ItinoResumeTask

        Write-Host (
            'Driver deployment completed successfully.'
        )

        Write-AutoResumeLog -Message (
            'Deployment completed successfully. ExitCode=0. No further resume task required.'
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

            Register-ItinoResumeTask
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

                Invoke-ItinoAutomaticRestart
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
            'Another ITINO driver deployment is already running.'
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
        Remove-ItinoResumeTask

        Write-Host (
            "Driver deployment failed with exit code $ControllerExitCode."
        )

        Write-Host (
            'Automatic restart/resume has been disabled for this failed deployment.'
        )

        exit $ControllerExitCode
    }
}
