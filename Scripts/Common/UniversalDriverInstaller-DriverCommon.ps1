#requires -version 5.1
<#
.SYNOPSIS
    Universal Driver Installer shared helper functions.

.DESCRIPTION
    Phase 10.9 introduces a deliberately small shared helper file.

    Only functions that were confirmed identical in the existing scripts
    are moved here. Script-specific Write-Log, restart-marker, admin,
    configuration and OEM logic remain in their original scripts.

    This keeps the refactor low-risk while establishing the common-helper
    structure for future consolidation.
#>

function Get-UniversalDriverInstallerBooleanOption {

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

