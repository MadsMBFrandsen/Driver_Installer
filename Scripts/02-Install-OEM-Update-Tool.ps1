# ========================================================================
# 02-Install-OEM-Update-Tool.ps1
#
# Purpose:
#   Detect the computer manufacturer and prepare/install the appropriate
#   OEM driver update utility.
#
# Supported:
#   Dell   -> Dell Command Update
#   HP     -> HP Image Assistant
#   Lenovo -> no separate OEM utility required
#             Script 03 uses LSUClient for dynamic Lenovo updates
#
# Other manufacturers:
#   No OEM utility is installed.
#   Script 03 will use Windows Update.
#
# Exit codes:
#   0 = Success
#   1 = Failure
#
# The script never restarts Windows.
# ========================================================================

[CmdletBinding()]
param()

$ErrorActionPreference =
    'Stop'



# ========================================================================
# CONTROLLER OPTIONS
# ========================================================================

# ============================================================
# PHASE 10.9 - SHARED COMMON HELPERS
# ============================================================

$ItinoCommonHelperPath =
    Join-Path `
        $PSScriptRoot `
        'Common\Itino-DriverCommon.ps1'


if (-not (
    Test-Path `
        -LiteralPath $ItinoCommonHelperPath `
        -PathType Leaf
)) {

    throw (
        'Required ITINO shared helper file was not found: ' +
        $ItinoCommonHelperPath
    )
}


. $ItinoCommonHelperPath


function Get-ItinoStringOption {

    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentVariable
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

        return ''
    }


    return $Value.Trim()
}


$WriteLogFiles =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_WRITE_LOG_FILES' `
        -DefaultValue $true


$UnattendedMode =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_UNATTENDED_MODE' `
        -DefaultValue $true


$RequireAdministrator =
    Get-ItinoBooleanOption `
        -EnvironmentVariable 'ITINO_REQUIRE_ADMINISTRATOR' `
        -DefaultValue $true


# OEM source configuration is owned by Run-DriverDeployment.ps1.
# Script 02 intentionally contains no OEM download URLs.
# Dell, HP and Lenovo source settings are owned by the controller.
# Lenovo System Update is installed for future maintenance, while
# Script 03 uses LSUClient for first-start automated Lenovo updates.

$DellCommandUpdateOfficialPageUrl =
    Get-ItinoStringOption `
        -EnvironmentVariable 'ITINO_DELL_COMMAND_UPDATE_OFFICIAL_PAGE_URL'

$DellCommandUpdateFallbackVersionString =
    Get-ItinoStringOption `
        -EnvironmentVariable 'ITINO_DELL_COMMAND_UPDATE_FALLBACK_VERSION'

$DellCommandUpdateFallbackDownloadUrl =
    Get-ItinoStringOption `
        -EnvironmentVariable 'ITINO_DELL_COMMAND_UPDATE_FALLBACK_DOWNLOAD_URL'


$HPImageAssistantOfficialPageUrl =
    Get-ItinoStringOption `
        -EnvironmentVariable 'ITINO_HP_IMAGE_ASSISTANT_OFFICIAL_PAGE_URL'

$HPImageAssistantFallbackVersionString =
    Get-ItinoStringOption `
        -EnvironmentVariable 'ITINO_HP_IMAGE_ASSISTANT_FALLBACK_VERSION'

$HPImageAssistantFallbackDownloadUrl =
    Get-ItinoStringOption `
        -EnvironmentVariable 'ITINO_HP_IMAGE_ASSISTANT_FALLBACK_DOWNLOAD_URL'


$LenovoSystemUpdateVersionString =
    Get-ItinoStringOption `
        -EnvironmentVariable 'ITINO_LENOVO_SYSTEM_UPDATE_VERSION'

$LenovoSystemUpdateDownloadUrl =
    Get-ItinoStringOption `
        -EnvironmentVariable 'ITINO_LENOVO_SYSTEM_UPDATE_DOWNLOAD_URL'


# OEM tool failure is allowed because script 03 can still use
# Windows Update as the driver fallback.

$AllowWindowsUpdateFallback =
    $true


# HP Image Assistant SoftPaq extraction must never be able to
# hold the full deployment sequence indefinitely.
#
# If extraction times out or fails, script 02 throws into its
# existing OEM fallback handler. Because Windows Update fallback
# is enabled, the deployment continues to script 03.

$HPImageAssistantExtractionTimeoutSeconds =
    120

$HPImageAssistantExecutableWaitSeconds =
    30


# ========================================================================
# PATHS
# ========================================================================

$BasePath =
    'C:\ProgramData\Itino\DriverDeployment'


$LogsPath =
    Join-Path `
        $BasePath `
        'Logs'


$DownloadsPath =
    Join-Path `
        $BasePath `
        'Downloads'


$ToolsPath =
    Join-Path `
        $BasePath `
        'Tools'


$PackagesPath =
    Join-Path `
        $PSScriptRoot `
        'Packages'


$HardwareInformationPath =
    Join-Path `
        $BasePath `
        'HardwareInformation.json'


$LogPath =
    Join-Path `
        $LogsPath `
        'Install-OEM-Update-Tool.log'


$RestartFile =
    Join-Path `
        $BasePath `
        'RestartRequired.txt'


# ========================================================================
# CREATE REQUIRED DIRECTORIES
# ========================================================================

foreach (
    $Directory in @(
        $BasePath,
        $DownloadsPath,
        $ToolsPath
    )
) {

    if (
        -not (
            Test-Path -LiteralPath $Directory
        )
    ) {

        New-Item `
            -Path $Directory `
            -ItemType Directory `
            -Force |
            Out-Null
    }
}


if (
    $WriteLogFiles -and
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


# ========================================================================
# RUN INFORMATION
# ========================================================================

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


$ScriptStartTime =
    Get-Date


# ========================================================================
# LOGGING
# ========================================================================

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


    $Timestamp =
        Get-Date -Format 'yyyy-MM-dd HH:mm:ss'


    $Line =
        "[$Timestamp] [$Level] $Message"


    Write-Host $Line


    if ($WriteLogFiles) {

        Add-Content `
            -LiteralPath $LogPath `
            -Value $Line `
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

            "Start Time   : $($ScriptStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"

            '==========================================================================='

            ''
        )


    foreach (
        $Line in $Lines
    ) {

        Write-Host $Line


        if ($WriteLogFiles) {

            Add-Content `
                -LiteralPath $LogPath `
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


    foreach (
        $Line in $Lines
    ) {

        Write-Host $Line


        if ($WriteLogFiles) {

            Add-Content `
                -LiteralPath $LogPath `
                -Value $Line `
                -Encoding UTF8
        }
    }
}


# ========================================================================
# RESTART MARKER
# ========================================================================

function Set-RestartRequired {

    param(
        [Parameter(Mandatory)]
        [string]$Reason
    )


    Write-Log `
        -Message (
            "Restart required: $Reason"
        ) `
        -Level 'WARNING'


    @(
        'RestartRequired=True'
        "Date=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "Reason=$Reason"
    ) |
        Set-Content `
            -LiteralPath $RestartFile `
            -Encoding ASCII
}


# ========================================================================
# ADMINISTRATOR CHECK
# ========================================================================

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


# ========================================================================
# VERSION HELPERS
# ========================================================================

function ConvertTo-NormalizedVersion {

    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$VersionString
    )


    if (
        [string]::IsNullOrWhiteSpace(
            $VersionString
        )
    ) {

        return $null
    }


    try {

        $CleanVersion =
            $VersionString.
                Replace(',', '.').
                Replace(' ', '')


        $Match =
            [regex]::Match(
                $CleanVersion,
                '(\d+(?:\.\d+){1,3})'
            )


        if (
            -not $Match.Success
        ) {

            return $null
        }


        $VersionParts =
            $Match.Groups[1].
                Value.
                Split('.')


        while (
            $VersionParts.Count -lt 3
        ) {

            $VersionParts +=
                '0'
        }


        $NormalizedString =
            $VersionParts -join '.'


        return [version]$NormalizedString
    }
    catch {

        return $null
    }
}


function Get-ExecutableVersion {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )


    if (
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


        foreach (
            $Candidate in @(
                $VersionInfo.ProductVersion,
                $VersionInfo.FileVersion
            )
        ) {

            $Version =
                ConvertTo-NormalizedVersion `
                    -VersionString $Candidate


            if ($Version) {

                return $Version
            }
        }
    }
    catch {

        return $null
    }


    return $null
}


# ========================================================================
# WEB HELPERS
# ========================================================================

function Get-WebPageContent {

    param(
        [Parameter(Mandatory)]
        [string]$Url
    )


    $WebClient =
        New-Object `
            System.Net.WebClient


    try {

        $WebClient.Headers.Add(
            'User-Agent',
            'Mozilla/5.0'
        )


        return (
            $WebClient.DownloadString(
                $Url
            )
        )
    }
    finally {

        $WebClient.Dispose()
    }
}


function Invoke-FileDownload {

    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Destination,

        [long]$MinimumBytes = 1
    )


    $MaximumAttempts =
        3


    for (
        $Attempt = 1
        $Attempt -le $MaximumAttempts
        $Attempt++
    ) {

        try {

            Write-Log -Message (
                "Downloading: $Url"
            )


            Write-Log -Message (
                "Destination: $Destination"
            )


            if (
                Test-Path -LiteralPath $Destination
            ) {

                Remove-Item `
                    -LiteralPath $Destination `
                    -Force `
                    -ErrorAction SilentlyContinue
            }


            $WebClient =
                New-Object `
                    System.Net.WebClient


            try {

                $WebClient.Headers.Add(
                    'User-Agent',
                    'Mozilla/5.0'
                )


                $WebClient.DownloadFile(
                    $Url,
                    $Destination
                )
            }
            finally {

                $WebClient.Dispose()
            }


            if (
                -not (
                    Test-Path -LiteralPath $Destination
                )
            ) {

                throw (
                    'Downloaded file does not exist.'
                )
            }


            $File =
                Get-Item `
                    -LiteralPath $Destination


            if (
                $File.Length -lt $MinimumBytes
            ) {

                throw (
                    "Downloaded file is too small. " +
                    "Size: $($File.Length) bytes."
                )
            }


            $SizeMB =
                [math]::Round(
                    $File.Length / 1MB,
                    2
                )


            Write-Log -Message (
                "Download completed. Size: $SizeMB MB"
            )


            return $Destination
        }
        catch {

            $DownloadError =
                $_.Exception.Message


            Write-Log `
                -Message (
                    "Download attempt $Attempt of $MaximumAttempts failed. " +
                    "URL: $Url. " +
                    "Destination: $Destination. " +
                    "Reason: $DownloadError"
                ) `
                -Level 'WARNING'


            if (
                Test-Path -LiteralPath $Destination
            ) {

                Remove-Item `
                    -LiteralPath $Destination `
                    -Force `
                    -ErrorAction SilentlyContinue
            }


            if (
                $Attempt -ge $MaximumAttempts
            ) {

                throw (
                    "Download failed after $MaximumAttempts attempts. " +
                    "URL: $Url. " +
                    "Destination: $Destination. " +
                    "Reason: $DownloadError"
                )
            }


            Start-Sleep `
                -Seconds 5
        }
    }
}


# ========================================================================
# DIGITAL SIGNATURE
# ========================================================================

function Test-InstallerSignature {

    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$ExpectedPublisher
    )


    Write-Log -Message (
        "Checking digital signature: $Path"
    )


    if (
        -not (
            Test-Path -LiteralPath $Path
        )
    ) {

        throw (
            "Installer does not exist: $Path"
        )
    }


    $Signature =
        Get-AuthenticodeSignature `
            -LiteralPath $Path


    if (
        $Signature.Status -ne 'Valid'
    ) {

        throw (
            "Installer digital signature is not valid. " +
            "Status: $($Signature.Status)"
        )
    }


    $Publisher =
        $Signature.SignerCertificate.Subject


    Write-Log -Message (
        "Digital signature publisher: $Publisher"
    )


    $PublisherValid =
        $false


    foreach (
        $Expected in $ExpectedPublisher
    ) {

        if (
            $Publisher -match
            [regex]::Escape(
                $Expected
            )
        ) {

            $PublisherValid =
                $true

            break
        }
    }


    if (
        -not $PublisherValid
    ) {

        throw (
            "Unexpected installer publisher: $Publisher"
        )
    }


    Write-Log -Message (
        'Digital signature validation successful.'
    )


    return $true
}


# ========================================================================
# DELL - FIND LATEST COMMAND UPDATE
# ========================================================================

function Get-LatestDellCommandUpdateInformation {

    # ========================================================
    # FALLBACK
    # ========================================================

    $FallbackVersionString =
        $DellCommandUpdateFallbackVersionString


    $FallbackVersion =
        ConvertTo-NormalizedVersion `
            -VersionString $FallbackVersionString


    $FallbackDownloadUrl =
        $DellCommandUpdateFallbackDownloadUrl


    # ========================================================
    # OFFICIAL DELL SOURCE
    # ========================================================

    $DellPage =
        $DellCommandUpdateOfficialPageUrl


    Write-Log -Message (
        'Checking Dell official support page for the latest ' +
        'Dell Command Update version.'
    )


    try {

        $PageContent =
            Get-WebPageContent `
                -Url $DellPage


        if (
            [string]::IsNullOrWhiteSpace(
                $PageContent
            )
        ) {

            throw (
                'Dell support page returned no content.'
            )
        }


        # ====================================================
        # FIND VERSION
        # ====================================================

        $Patterns =
            @(

                'Dell\s+Command\s*(?:\||&\#124;)?\s*Update[^0-9]{0,50}([0-9]+\.[0-9]+(?:\.[0-9]+)?)',

                'DCU[^0-9]{0,30}([0-9]+\.[0-9]+(?:\.[0-9]+)?)'
            )


        $DiscoveredVersions =
            @()


        foreach (
            $Pattern in $Patterns
        ) {

            $Matches =
                [regex]::Matches(
                    $PageContent,
                    $Pattern,
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
                )


            foreach (
                $Match in $Matches
            ) {

                $VersionString =
                    $Match.Groups[1].Value


                $NormalizedVersion =
                    ConvertTo-NormalizedVersion `
                        -VersionString $VersionString


                if ($NormalizedVersion) {

                    $DiscoveredVersions +=
                        [PSCustomObject]@{

                            VersionString =
                                $VersionString

                            Version =
                                $NormalizedVersion
                        }
                }
            }
        }


        if (
            $DiscoveredVersions.Count -eq 0
        ) {

            throw (
                'No Dell Command Update version could be found ' +
                'on the official Dell page.'
            )
        }


        $Latest =
            $DiscoveredVersions |
            Sort-Object `
                -Property Version `
                -Descending |
            Select-Object `
                -First 1


        if (
            -not $Latest
        ) {

            throw (
                'Unable to determine the latest Dell Command ' +
                'Update version.'
            )
        }


        $LatestVersion =
            $Latest.Version


        if (
            $LatestVersion.Build -lt 0
        ) {

            $LatestVersionString =
                "$($LatestVersion.Major).$($LatestVersion.Minor).0"


            $LatestVersion =
                [version]$LatestVersionString
        }
        else {

            $LatestVersionString =
                $LatestVersion.ToString()
        }


        Write-Log -Message (
            "Latest Dell Command Update version detected: $LatestVersion"
        )


        # ====================================================
        # KNOWN FALLBACK IS NEWER
        # ====================================================

        if (
            $LatestVersion -lt $FallbackVersion
        ) {

            Write-Log `
                -Message (
                    "Dell page detected version $LatestVersion, " +
                    "but known fallback version $FallbackVersion is newer. " +
                    'Using the known newer Dell package.'
                ) `
                -Level 'WARNING'


            return [PSCustomObject]@{

                VersionString =
                    $FallbackVersionString

                Version =
                    $FallbackVersion

                DownloadUrl =
                    $FallbackDownloadUrl

                Source =
                    'ConfiguredFallbackNewer'

                UsedFallback =
                    $true
            }
        }


        # ====================================================
        # FIND EXACT DOWNLOAD URL
        # ====================================================

        $DownloadMatches =
            [regex]::Matches(
                $PageContent,
                'https:\/\/dl\.dell\.com\/[^"''<>\s]+\.exe',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )


        $DownloadUrl =
            $null


        foreach (
            $Match in $DownloadMatches
        ) {

            $CandidateUrl =
                [System.Net.WebUtility]::HtmlDecode(
                    $Match.Value
                )


            if (
                $CandidateUrl -match
                    'Dell-Command-Update' -and
                $CandidateUrl -match
                    [regex]::Escape(
                        $LatestVersionString
                    )
            ) {

                $DownloadUrl =
                    $CandidateUrl

                break
            }
        }


        # ====================================================
        # EXACT LINK NOT FOUND
        # ====================================================

        if (
            [string]::IsNullOrWhiteSpace(
                $DownloadUrl
            )
        ) {

            Write-Log `
                -Message (
                    "Dell Command Update version $LatestVersion was " +
                    'detected, but no matching download URL was found.'
                ) `
                -Level 'WARNING'


            if (
                $FallbackVersion -ge $LatestVersion
            ) {

                Write-Log `
                    -Message (
                        "Using known Dell Command Update fallback " +
                        "version $FallbackVersion."
                    ) `
                    -Level 'WARNING'


                return [PSCustomObject]@{

                    VersionString =
                        $FallbackVersionString

                    Version =
                        $FallbackVersion

                    DownloadUrl =
                        $FallbackDownloadUrl

                    Source =
                        'ConfiguredFallback'

                    UsedFallback =
                        $true
                }
            }


            throw (
                "Dell reports Command Update version $LatestVersion, " +
                'but its matching download URL could not be found and ' +
                "fallback version $FallbackVersion is older."
            )
        }


        Write-Log -Message (
            "Dell Command Update download URL: $DownloadUrl"
        )


        return [PSCustomObject]@{

            VersionString =
                $LatestVersionString

            Version =
                $LatestVersion

            DownloadUrl =
                $DownloadUrl

            Source =
                'DellOfficialPage'

            UsedFallback =
                $false
        }
    }
    catch {

        if (
            $LatestVersion -and
            $FallbackVersion -and
            $LatestVersion -gt $FallbackVersion
        ) {

            throw (
                "Dell reports Command Update version $LatestVersion, " +
                "which is newer than fallback version $FallbackVersion, " +
                'but the current package could not be resolved. ' +
                'Refusing to silently use an older fallback package.'
            )
        }


        Write-Log `
            -Message (
                'Unable to automatically determine the latest ' +
                'Dell Command Update package. ' +
                "Using fallback version $FallbackVersionString. " +
                "Reason: $($_.Exception.Message)"
            ) `
            -Level 'WARNING'


        return [PSCustomObject]@{

            VersionString =
                $FallbackVersionString

            Version =
                $FallbackVersion

            DownloadUrl =
                $FallbackDownloadUrl

            Source =
                'ConfiguredFallback'

            UsedFallback =
                $true
        }
    }
}


# ========================================================================
# DELL - GET INSTALLER
# ========================================================================

function Get-DellCommandUpdateInstaller {

    $PackagedInstaller =
        Join-Path `
            $PackagesPath `
            'Dell\DellCommandUpdate.exe'


    if (
        Test-Path -LiteralPath $PackagedInstaller
    ) {

        Write-Log -Message (
            "Using packaged Dell Command Update installer: $PackagedInstaller"
        )


        Test-InstallerSignature `
            -Path $PackagedInstaller `
            -ExpectedPublisher @(
                'Dell'
            ) |
            Out-Null


        $PackagedVersion =
            Get-ExecutableVersion `
                -Path $PackagedInstaller


        return [PSCustomObject]@{

            Path =
                $PackagedInstaller

            Version =
                $PackagedVersion

            VersionString =
                if ($PackagedVersion) {
                    $PackagedVersion.ToString()
                }
                else {
                    $null
                }

            Source =
                'Packaged'
        }
    }


    Write-Log -Message (
        'No packaged Dell Command Update installer found.'
    )


    $LatestInformation =
        Get-LatestDellCommandUpdateInformation


    Write-Log -Message (
        "Selected Dell Command Update version: " +
        "$($LatestInformation.Version)"
    )


    Write-Log -Message (
        "Dell package source: $($LatestInformation.Source)"
    )


    $Destination =
        Join-Path `
            $DownloadsPath `
            (
                'DellCommandUpdate-' +
                "$($LatestInformation.VersionString).exe"
            )


    Invoke-FileDownload `
        -Url $LatestInformation.DownloadUrl `
        -Destination $Destination `
        -MinimumBytes 5MB |
        Out-Null


    Test-InstallerSignature `
        -Path $Destination `
        -ExpectedPublisher @(
            'Dell'
        ) |
        Out-Null


    return [PSCustomObject]@{

        Path =
            $Destination

        Version =
            $LatestInformation.Version

        VersionString =
            $LatestInformation.VersionString

        Source =
            $LatestInformation.Source
    }
}


# ========================================================================
# DELL - LOCATE INSTALLED DCU
# ========================================================================

function Get-DellCommandUpdateExecutable {

    $PossiblePaths =
        @(

            'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe',

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


# ========================================================================
# DELL - INSTALL
# ========================================================================

function Install-DellCommandUpdate {

    $ExistingExecutable =
        Get-DellCommandUpdateExecutable


    if ($ExistingExecutable) {

        Write-Log -Message (
            "Existing Dell Command Update found: $ExistingExecutable"
        )
    }
    else {

        Write-Log -Message (
            'Dell Command Update is not currently installed.'
        )
    }


    $InstallerInformation =
    Get-DellCommandUpdateInstaller


	$Installer =
		$InstallerInformation.Path


	$InstallerVersion =
		$InstallerInformation.Version


    $InstalledVersion =
        $null


    if ($ExistingExecutable) {

        $InstalledVersion =
            Get-ExecutableVersion `
                -Path $ExistingExecutable
    }


    Write-Log -Message (
        "Installed Dell Command Update version: $InstalledVersion"
    )


    Write-Log -Message (
        "Available Dell Command Update version: $InstallerVersion"
    )


    if (
        $InstalledVersion -and
        $InstallerVersion -and
        $InstalledVersion -ge $InstallerVersion
    ) {

        Write-Log -Message (
            'Installed Dell Command Update version is current or newer.'
        )


        return
    }


    Write-Log -Message (
        'Installing Dell Command Update silently.'
    )


    $Process =
        Start-Process `
            -FilePath $Installer `
            -ArgumentList '/s' `
            -Wait `
            -PassThru `
            -NoNewWindow


    Write-Log -Message (
        "Dell Command Update installer exit code: $($Process.ExitCode)"
    )


    if (
        $Process.ExitCode -eq 3010
    ) {

        Set-RestartRequired `
            -Reason (
                'Dell Command Update installer requested a restart.'
            )
    }


    if (
        $Process.ExitCode -notin @(
            0,
            3010
        )
    ) {

        throw (
            'Dell Command Update installation failed. ' +
            "Exit code: $($Process.ExitCode)"
        )
    }


    $InstalledExecutable =
        Get-DellCommandUpdateExecutable


    if (
        -not $InstalledExecutable
    ) {

        throw (
            'Dell Command Update installation completed, but ' +
            'dcu-cli.exe could not be found.'
        )
    }


    Test-InstallerSignature `
        -Path $InstalledExecutable `
        -ExpectedPublisher @(
            'Dell'
        ) |
        Out-Null


    Write-Log -Message (
        'Dell Command Update is ready.'
    )
}


# ========================================================================
# HP - FIND LATEST IMAGE ASSISTANT
# ========================================================================

function Get-LatestHPImageAssistantInformation {

    # ========================================================
    # FALLBACK
    # ========================================================

    $FallbackVersionString =
        $HPImageAssistantFallbackVersionString


    $FallbackVersion =
        ConvertTo-NormalizedVersion `
            -VersionString $FallbackVersionString


    $FallbackDownloadUrl =
        $HPImageAssistantFallbackDownloadUrl


    # ========================================================
    # OFFICIAL HP SOURCE
    # ========================================================

    $HPPage =
        $HPImageAssistantOfficialPageUrl


    Write-Log -Message (
        'Checking HP official HPIA page for the latest ' +
        'HP Image Assistant version.'
    )


    try {

        $PageContent =
            Get-WebPageContent `
                -Url $HPPage


        if (
            [string]::IsNullOrWhiteSpace(
                $PageContent
            )
        ) {

            throw (
                'HP HPIA page returned no content.'
            )
        }


        # ====================================================
        # FIND VERSIONS
        # ====================================================

        $Patterns =
            @(

                'VERSION[^0-9]{0,20}([0-9]+\.[0-9]+\.[0-9]+)',

                'hp-hpia-([0-9]+\.[0-9]+\.[0-9]+)\.exe'
            )


        $DiscoveredVersions =
            @()


        foreach (
            $Pattern in $Patterns
        ) {

            $Matches =
                [regex]::Matches(
                    $PageContent,
                    $Pattern,
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
                )


            foreach (
                $Match in $Matches
            ) {

                $VersionString =
                    $Match.Groups[1].Value


                $Version =
                    ConvertTo-NormalizedVersion `
                        -VersionString $VersionString


                if ($Version) {

                    $DiscoveredVersions +=
                        [PSCustomObject]@{

                            VersionString =
                                $VersionString

                            Version =
                                $Version
                        }
                }
            }
        }


        if (
            $DiscoveredVersions.Count -eq 0
        ) {

            throw (
                'No HP Image Assistant version could be found ' +
                'on the official HP page.'
            )
        }


        $Latest =
            $DiscoveredVersions |
            Sort-Object `
                -Property Version `
                -Descending |
            Select-Object `
                -First 1


        $LatestVersion =
            $Latest.Version


        $LatestVersionString =
            $Latest.VersionString


        Write-Log -Message (
            "Latest HP Image Assistant version detected: $LatestVersion"
        )


        # ====================================================
        # KNOWN FALLBACK NEWER
        # ====================================================

        if (
            $LatestVersion -lt $FallbackVersion
        ) {

            Write-Log `
                -Message (
                    "HP page detected version $LatestVersion, " +
                    "but known fallback version $FallbackVersion is newer. " +
                    'Using the known newer HP package.'
                ) `
                -Level 'WARNING'


            return [PSCustomObject]@{

                VersionString =
                    $FallbackVersionString

                Version =
                    $FallbackVersion

                DownloadUrl =
                    $FallbackDownloadUrl

                Source =
                    'ConfiguredFallbackNewer'

                UsedFallback =
                    $true
            }
        }


        # ====================================================
        # FIND EXACT VERSION URL
        # ====================================================

        $DownloadMatches =
            [regex]::Matches(
                $PageContent,
                'https:\/\/hpia\.hpcloud\.hp\.com\/downloads\/(?:hpia\/)?hp-hpia-[0-9]+\.[0-9]+\.[0-9]+\.exe',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )


        $DownloadUrl =
            $null


        foreach (
            $Match in $DownloadMatches
        ) {

            $CandidateUrl =
                [System.Net.WebUtility]::HtmlDecode(
                    $Match.Value
                )


            if (
                $CandidateUrl -match
                [regex]::Escape(
                    "hp-hpia-$LatestVersionString.exe"
                )
            ) {

                $DownloadUrl =
                    $CandidateUrl

                break
            }
        }


        # ====================================================
        # URL NOT FOUND
        # ====================================================

        if (
            [string]::IsNullOrWhiteSpace(
                $DownloadUrl
            )
        ) {

            if (
                $FallbackVersion -ge $LatestVersion
            ) {

                Write-Log `
                    -Message (
                        "HP Image Assistant version $LatestVersion was " +
                        'detected, but no matching URL was found. ' +
                        "Using fallback version $FallbackVersion."
                    ) `
                    -Level 'WARNING'


                return [PSCustomObject]@{

                    VersionString =
                        $FallbackVersionString

                    Version =
                        $FallbackVersion

                    DownloadUrl =
                        $FallbackDownloadUrl

                    Source =
                        'ConfiguredFallback'

                    UsedFallback =
                        $true
                }
            }


            throw (
                "HP reports Image Assistant version $LatestVersion, " +
                'but a matching download URL could not be found and ' +
                "fallback version $FallbackVersion is older."
            )
        }


        Write-Log -Message (
            "HP Image Assistant download URL: $DownloadUrl"
        )


        return [PSCustomObject]@{

            VersionString =
                $LatestVersionString

            Version =
                $LatestVersion

            DownloadUrl =
                $DownloadUrl

            Source =
                'HPOfficialPage'

            UsedFallback =
                $false
        }
    }
    catch {

        if (
            $LatestVersion -and
            $FallbackVersion -and
            $LatestVersion -gt $FallbackVersion
        ) {

            throw (
                "HP reports Image Assistant version $LatestVersion, " +
                "which is newer than fallback version $FallbackVersion, " +
                'but the current package could not be resolved. ' +
                'Refusing to silently use an older fallback package.'
            )
        }


        Write-Log `
            -Message (
                'Unable to automatically determine the latest ' +
                'HP Image Assistant package. ' +
                "Using fallback version $FallbackVersionString. " +
                "Reason: $($_.Exception.Message)"
            ) `
            -Level 'WARNING'


        return [PSCustomObject]@{

            VersionString =
                $FallbackVersionString

            Version =
                $FallbackVersion

            DownloadUrl =
                $FallbackDownloadUrl

            Source =
                'ConfiguredFallback'

            UsedFallback =
                $true
        }
    }
}


# ========================================================================
# HP - GET INSTALLER
# ========================================================================

function Get-HPImageAssistantInstaller {

    $PackagedInstaller =
        Join-Path `
            $PackagesPath `
            'HP\HPImageAssistant.exe'


    if (
        Test-Path -LiteralPath $PackagedInstaller
    ) {

        Write-Log -Message (
            "Using packaged HP Image Assistant installer: $PackagedInstaller"
        )


        Test-InstallerSignature `
            -Path $PackagedInstaller `
            -ExpectedPublisher @(
                'HP Inc.',
                'Hewlett-Packard',
                'HP'
            ) |
            Out-Null


        $PackagedVersion =
            Get-ExecutableVersion `
                -Path $PackagedInstaller


        return [PSCustomObject]@{

            Path =
                $PackagedInstaller

            Version =
                $PackagedVersion

            VersionString =
                if ($PackagedVersion) {
                    $PackagedVersion.ToString()
                }
                else {
                    $null
                }

            Source =
                'Packaged'
        }
    }


    Write-Log -Message (
        'No packaged HP Image Assistant installer found.'
    )


    Write-Log -Message (
        'Resolving latest HP Image Assistant download.'
    )


    $LatestInformation =
        Get-LatestHPImageAssistantInformation


    if (
        -not $LatestInformation
    ) {

        throw (
            'Unable to determine HP Image Assistant information.'
        )
    }


    Write-Log -Message (
        "Selected HP Image Assistant version: " +
        "$($LatestInformation.Version)"
    )


    Write-Log -Message (
        "HP Image Assistant source: $($LatestInformation.Source)"
    )


    if (
        $LatestInformation.UsedFallback
    ) {

        Write-Log `
            -Message (
                'HP Image Assistant automatic discovery used the ' +
                'configured fallback package.'
            ) `
            -Level 'WARNING'
    }


    $Destination =
        Join-Path `
            $DownloadsPath `
            (
                'HPImageAssistant-' +
                "$($LatestInformation.VersionString).exe"
            )


    Invoke-FileDownload `
        -Url $LatestInformation.DownloadUrl `
        -Destination $Destination `
        -MinimumBytes 1MB |
        Out-Null


    Test-InstallerSignature `
        -Path $Destination `
        -ExpectedPublisher @(
            'HP Inc.',
            'Hewlett-Packard',
            'HP'
        ) |
        Out-Null


    Write-Log -Message (
        'HP Image Assistant installer downloaded and verified successfully.'
    )


    return [PSCustomObject]@{

        Path =
            $Destination

        Version =
            $LatestInformation.Version

        VersionString =
            $LatestInformation.VersionString

        Source =
            $LatestInformation.Source
    }
}


# ========================================================================
# HP - INSTALL / EXTRACT HPIA
# ========================================================================

function Install-HPImageAssistant {

    $PermanentHPIARoot =
        'C:\Program Files\HP\HP Image Assistant'


    $HPIAExecutable =
        Join-Path `
            $PermanentHPIARoot `
            'HPImageAssistant.exe'


    $LegacyHPIAExecutable =
        Join-Path `
            $ToolsPath `
            'HPImageAssistant\HPImageAssistant.exe'


    # --------------------------------------------------------
    # PHASE 10.1 - MIGRATE EXISTING TEMPORARY HPIA
    #
    # Older deployment cycles extracted HPIA below the ITINO
    # working tree. If that validated copy exists and the new
    # permanent location does not, migrate the complete extracted
    # application before doing another download.
    # --------------------------------------------------------

    if (
        -not (
            Test-Path `
                -LiteralPath $HPIAExecutable `
                -PathType Leaf
        ) -and
        (
            Test-Path `
                -LiteralPath $LegacyHPIAExecutable `
                -PathType Leaf
        )
    ) {

        Write-Log -Message (
            'Existing temporary HP Image Assistant found. ' +
            'Migrating it to the permanent Program Files location.'
        )


        Test-InstallerSignature `
            -Path $LegacyHPIAExecutable `
            -ExpectedPublisher @(
                'HP Inc.',
                'Hewlett-Packard',
                'HP'
            ) |
            Out-Null


        if (
            Test-Path -LiteralPath $PermanentHPIARoot
        ) {

            Remove-Item `
                -LiteralPath $PermanentHPIARoot `
                -Recurse `
                -Force `
                -ErrorAction Stop
        }


        New-Item `
            -Path $PermanentHPIARoot `
            -ItemType Directory `
            -Force `
            -ErrorAction Stop |
            Out-Null


        $LegacyRoot =
            Split-Path `
                -Parent `
                $LegacyHPIAExecutable


        Copy-Item `
            -Path (
                Join-Path `
                    $LegacyRoot `
                    '*'
            ) `
            -Destination $PermanentHPIARoot `
            -Recurse `
            -Force `
            -ErrorAction Stop


        if (-not (
            Test-Path `
                -LiteralPath $HPIAExecutable `
                -PathType Leaf
        )) {

            throw (
                'HP Image Assistant migration failed. ' +
                "Permanent executable not found: $HPIAExecutable"
            )
        }


        Test-InstallerSignature `
            -Path $HPIAExecutable `
            -ExpectedPublisher @(
                'HP Inc.',
                'Hewlett-Packard',
                'HP'
            ) |
            Out-Null


        Write-Log -Message (
            "HP Image Assistant migrated permanently: $HPIAExecutable"
        )


        return
    }


    if (
        Test-Path -LiteralPath $HPIAExecutable
    ) {

        Write-Log -Message (
            "Existing HP Image Assistant found: $HPIAExecutable"
        )


        Test-InstallerSignature `
            -Path $HPIAExecutable `
            -ExpectedPublisher @(
                'HP Inc.',
                'Hewlett-Packard',
                'HP'
            ) |
            Out-Null


        Write-Log -Message (
            'Permanent HP Image Assistant is already ready.'
        )


        return
    }


    $InstallerInformation =
        Get-HPImageAssistantInstaller


    $Installer =
        $InstallerInformation.Path


    $InstallerVersion =
        $InstallerInformation.Version


    $ExtractionPath =
        $PermanentHPIARoot

    Write-Log -Message (
        "Available HP Image Assistant version: $InstallerVersion"
    )


    Write-Log -Message (
        "HP installer source: $($InstallerInformation.Source)"
    )

    if (
        Test-Path -LiteralPath $ExtractionPath
    ) {

        Remove-Item `
            -LiteralPath $ExtractionPath `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }


    New-Item `
        -Path $ExtractionPath `
        -ItemType Directory `
        -Force |
        Out-Null


    Write-Log -Message (
        "Extracting HP Image Assistant to '$ExtractionPath'."
    )

    Write-Log -Message (
        "HP Image Assistant extraction timeout: " +
        "$HPImageAssistantExtractionTimeoutSeconds seconds."
    )

    # HP SoftPaq extraction syntax:
    #
    #   /s = silent
    #   /e = extract
    #   /f = extraction folder
    #
    # Using /f as a separate switch/value is more compatible with
    # HP SoftPaq wrappers than the previous /e="<path>" form.

    $Arguments =
        @(
            '/s'
            '/e'
            '/f'
            "`"$ExtractionPath`""
        )


    $Process =
        Start-Process `
            -FilePath $Installer `
            -ArgumentList $Arguments `
            -PassThru `
            -NoNewWindow


    $CompletedInTime =
        $Process.WaitForExit(
            $HPImageAssistantExtractionTimeoutSeconds * 1000
        )


    if (-not $CompletedInTime) {

        Write-Log `
            -Message (
                'HP Image Assistant extractor exceeded the configured ' +
                "$HPImageAssistantExtractionTimeoutSeconds second timeout. " +
                'Stopping the extractor so deployment can continue.'
            ) `
            -Level 'WARNING'


        try {

            if (-not $Process.HasExited) {

                $Process.Kill()
                $Process.WaitForExit()
            }
        }
        catch {

            Write-Log `
                -Message (
                    'Unable to stop timed-out HP Image Assistant extractor. ' +
                    "Reason: $($_.Exception.Message)"
                ) `
                -Level 'WARNING'
        }
    }


    $ExtractorExitCode =
        $null


    if ($Process.HasExited) {

        try {

            $ExtractorExitCode =
                [int]$Process.ExitCode
        }
        catch {

            $ExtractorExitCode =
                $null
        }
    }


    if ($null -ne $ExtractorExitCode) {

        Write-Log -Message (
            "HP Image Assistant extractor exit code: $ExtractorExitCode"
        )
    }
    else {

        Write-Log `
            -Message (
                'HP Image Assistant extractor exit code is unavailable ' +
                'because the process did not complete normally.'
            ) `
            -Level 'WARNING'
    }


    if (
        $ExtractorExitCode -eq 3010
    ) {

        Set-RestartRequired `
            -Reason (
                'HP Image Assistant extractor requested a restart.'
            )
    }


    # Do not trust the process exit code alone. Some SoftPaq wrappers
    # can return an unusual code even though extraction has completed.
    # Give the expected executable a short, bounded discovery window.

    Write-Log -Message (
        'Waiting up to ' +
        "$HPImageAssistantExecutableWaitSeconds seconds for " +
        'HPImageAssistant.exe to become available.'
    )


    $HPIAExecutable =
        $null


    $ExecutableDeadline =
        (Get-Date).AddSeconds(
            $HPImageAssistantExecutableWaitSeconds
        )


    do {

        $HPIAExecutable =
            Get-ChildItem `
                -Path $ExtractionPath `
                -Filter 'HPImageAssistant.exe' `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue |
            Select-Object `
                -First 1 `
                -ExpandProperty FullName


        if ($HPIAExecutable) {
            break
        }


        if ((Get-Date) -lt $ExecutableDeadline) {

            Start-Sleep -Seconds 2
        }

    } while (
        (Get-Date) -lt $ExecutableDeadline
    )


    if ($HPIAExecutable) {

        if (
            -not $CompletedInTime -or
            (
                $null -ne $ExtractorExitCode -and
                $ExtractorExitCode -notin @(
                    0,
                    3010
                )
            )
        ) {

            Write-Log `
                -Message (
                    'HPImageAssistant.exe was found despite the extractor ' +
                    'timeout/non-standard exit result. Continuing with the ' +
                    'validated extracted utility.'
                ) `
                -Level 'WARNING'
        }
    }
    else {

        if (-not $CompletedInTime) {

            throw (
                'HP Image Assistant extraction timed out and ' +
                'HPImageAssistant.exe was not found. Windows Update ' +
                'fallback can continue the deployment.'
            )
        }


        if (
            $null -ne $ExtractorExitCode -and
            $ExtractorExitCode -notin @(
                0,
                3010
            )
        ) {

            throw (
                'HP Image Assistant extraction failed. ' +
                "Exit code: $ExtractorExitCode. " +
                'HPImageAssistant.exe was not found. Windows Update ' +
                'fallback can continue the deployment.'
            )
        }


        throw (
            'HP Image Assistant extraction completed, but ' +
            'HPImageAssistant.exe could not be found within the ' +
            "$HPImageAssistantExecutableWaitSeconds second discovery window. " +
            'Windows Update fallback can continue the deployment.'
        )
    }


    Test-InstallerSignature `
        -Path $HPIAExecutable `
        -ExpectedPublisher @(
            'HP Inc.',
            'Hewlett-Packard',
            'HP'
        ) |
        Out-Null


    Write-Log -Message (
        "Permanent HP Image Assistant ready: $HPIAExecutable"
    )
}


# ========================================================================
# LENOVO - FIND LATEST SYSTEM UPDATE
# ========================================================================

function Get-LatestLenovoSystemUpdateInformation {

    # Lenovo support HTML is intentionally not scraped.
    # It returns HTTP 403 to scripted requests.
    #
    # The Lenovo System Update application itself performs dynamic
    # driver/firmware discovery through Lenovo's machine-readable XML
    # package catalog. This function only resolves the System Update
    # application installer configured by the controller.

    $ConfiguredVersionString =
        $LenovoSystemUpdateVersionString


    $ConfiguredVersion =
        ConvertTo-NormalizedVersion `
            -VersionString $ConfiguredVersionString


    if (
        -not $ConfiguredVersion
    ) {

        throw (
            'Lenovo System Update configuration error: controller value ' +
            "ITINO_LENOVO_SYSTEM_UPDATE_VERSION='$ConfiguredVersionString' " +
            'could not be converted to a valid version.'
        )
    }


    if (
        [string]::IsNullOrWhiteSpace(
            $LenovoSystemUpdateDownloadUrl
        )
    ) {

        throw (
            'Lenovo System Update configuration error: ' +
            'ITINO_LENOVO_SYSTEM_UPDATE_DOWNLOAD_URL is empty. ' +
            'Configure it in Run-DriverDeployment.ps1.'
        )
    }


    Write-Log -Message (
        'Lenovo System Update application uses the controller-configured ' +
        'known-good package. Lenovo driver/firmware discovery remains ' +
        'dynamic inside Lenovo System Update.'
    )


    Write-Log -Message (
        "Configured Lenovo System Update version: $ConfiguredVersion"
    )


    Write-Log -Message (
        'Configured Lenovo System Update download URL: ' +
        $LenovoSystemUpdateDownloadUrl
    )


    return [PSCustomObject]@{
        VersionString =
            $ConfiguredVersionString

        Version =
            $ConfiguredVersion

        DownloadUrl =
            $LenovoSystemUpdateDownloadUrl

        Source =
            'ControllerConfigured'

        UsedFallback =
            $false
    }
}


function Get-LenovoSystemUpdatePaths {

    $PossibleDirectories =
        @(

            'C:\Program Files (x86)\Lenovo\System Update',

            'C:\Program Files\Lenovo\System Update'
        )


    foreach (
        $Directory in $PossibleDirectories
    ) {

        $TvsuPath =
            Join-Path `
                $Directory `
                'tvsu.exe'


        $TvsuShimPath =
            Join-Path `
                $Directory `
                'tvsuShim.exe'


        if (
            Test-Path -LiteralPath $TvsuPath
        ) {

            return [PSCustomObject]@{

                Directory =
                    $Directory

                Tvsu =
                    $TvsuPath

                TvsuShim =
                    $TvsuShimPath
            }
        }
    }


    return $null
}


# ========================================================================
# LENOVO - GET INSTALLER
# ========================================================================

function Get-LenovoSystemUpdateInstaller {

    $PackagedInstaller =
        Join-Path `
            $PackagesPath `
            'Lenovo\LenovoSystemUpdate.exe'


    if (
        Test-Path -LiteralPath $PackagedInstaller
    ) {

        Write-Log -Message (
            "Using packaged Lenovo System Update installer: $PackagedInstaller"
        )


        Test-InstallerSignature `
            -Path $PackagedInstaller `
            -ExpectedPublisher @(
                'Lenovo'
            ) |
            Out-Null


        return [PSCustomObject]@{

            Path =
                $PackagedInstaller

            Version =
                Get-ExecutableVersion `
                    -Path $PackagedInstaller

            VersionString =
                $null

            Source =
                'Packaged'
        }
    }


    Write-Log -Message (
        'No packaged Lenovo System Update installer found.'
    )


    $LatestInformation =
        Get-LatestLenovoSystemUpdateInformation


    Write-Log -Message (
        "Selected Lenovo System Update version: " +
        "$($LatestInformation.Version)"
    )


    Write-Log -Message (
        "Lenovo package source: $($LatestInformation.Source)"
    )


    Write-Log -Message (
        "Lenovo System Update version selected for download: " +
        "$($LatestInformation.Version)"
    )


    Write-Log -Message (
        "Lenovo System Update URL selected for download: " +
        "$($LatestInformation.DownloadUrl)"
    )


    $Destination =
        Join-Path `
            $DownloadsPath `
            (
                'LenovoSystemUpdate-' +
                "$($LatestInformation.VersionString).exe"
            )


    Invoke-FileDownload `
        -Url $LatestInformation.DownloadUrl `
        -Destination $Destination `
        -MinimumBytes 5MB |
        Out-Null


    Test-InstallerSignature `
        -Path $Destination `
        -ExpectedPublisher @(
            'Lenovo'
        ) |
        Out-Null


    return [PSCustomObject]@{

        Path =
            $Destination

        Version =
            $LatestInformation.Version

        VersionString =
            $LatestInformation.VersionString

        Source =
            $LatestInformation.Source
    }
}


# ========================================================================
# LENOVO - INSTALL SYSTEM UPDATE
# ========================================================================

function Install-LenovoSystemUpdate {

    $Existing =
        Get-LenovoSystemUpdatePaths


    $InstalledVersion =
        $null


    if ($Existing) {

        Write-Log -Message (
            "Existing Lenovo System Update found: $($Existing.Tvsu)"
        )


        $InstalledVersion =
            Get-ExecutableVersion `
                -Path $Existing.Tvsu


        Write-Log -Message (
            "Installed Lenovo System Update version: $InstalledVersion"
        )
    }
    else {

        Write-Log -Message (
            'Lenovo System Update is not currently installed.'
        )
    }


    # ========================================================
    # QUICK VERSION CHECK BEFORE DOWNLOAD
    # ========================================================

    $LatestInformation =
        Get-LatestLenovoSystemUpdateInformation


    if (
        $Existing -and
        $InstalledVersion -and
        $LatestInformation.Version -and
        $InstalledVersion -ge $LatestInformation.Version -and
        (
            Test-Path -LiteralPath $Existing.TvsuShim
        )
    ) {

        Write-Log -Message (
            'Installed Lenovo System Update version is current or newer.'
        )


        Test-InstallerSignature `
            -Path $Existing.Tvsu `
            -ExpectedPublisher @(
                'Lenovo'
            ) |
            Out-Null


        Test-InstallerSignature `
            -Path $Existing.TvsuShim `
            -ExpectedPublisher @(
                'Lenovo'
            ) |
            Out-Null


        Write-Log -Message (
            'Lenovo System Update is ready.'
        )


        return
    }


    # ========================================================
    # GET INSTALLER
    # ========================================================

    $InstallerInformation =
        Get-LenovoSystemUpdateInstaller


    $Installer =
        $InstallerInformation.Path


    $AvailableVersion =
        $InstallerInformation.Version


    Write-Log -Message (
        "Available Lenovo System Update version: $AvailableVersion"
    )


    if (
        $Existing -and
        $InstalledVersion -and
        $AvailableVersion -and
        $InstalledVersion -ge $AvailableVersion -and
        (
            Test-Path -LiteralPath $Existing.TvsuShim
        )
    ) {

        Write-Log -Message (
            'Installed Lenovo System Update version is current or newer.'
        )


        return
    }


    # ========================================================
    # INSTALL
    # ========================================================

    Write-Log -Message (
        'Installing Lenovo System Update silently.'
    )


    $Process =
        Start-Process `
            -FilePath $Installer `
            -ArgumentList @(
                '/verysilent',
                '/norestart'
            ) `
            -Wait `
            -PassThru `
            -NoNewWindow


    Write-Log -Message (
        "Lenovo System Update installer exit code: $($Process.ExitCode)"
    )


    if (
        $Process.ExitCode -eq 3010
    ) {

        Set-RestartRequired `
            -Reason (
                'Lenovo System Update installer requested a restart.'
            )
    }


    if (
        $Process.ExitCode -notin @(
            0,
            3010
        )
    ) {

        throw (
            'Lenovo System Update installation failed. ' +
            "Exit code: $($Process.ExitCode)"
        )
    }


    # ========================================================
    # VERIFY INSTALLATION
    # ========================================================

    $Installed =
        Get-LenovoSystemUpdatePaths


    if (
        -not $Installed
    ) {

        throw (
            'Lenovo System Update installation completed, but ' +
            'tvsu.exe could not be found.'
        )
    }


    if (
        -not (
            Test-Path -LiteralPath $Installed.TvsuShim
        )
    ) {

        throw (
            'Lenovo System Update installation is incomplete. ' +
            'tvsuShim.exe could not be found.'
        )
    }


    Test-InstallerSignature `
        -Path $Installed.Tvsu `
        -ExpectedPublisher @(
            'Lenovo'
        ) |
        Out-Null


    Test-InstallerSignature `
        -Path $Installed.TvsuShim `
        -ExpectedPublisher @(
            'Lenovo'
        ) |
        Out-Null


    Write-Log -Message (
        'Lenovo System Update is ready.'
    )
}


# ========================================================================
# OEM CONFIGURATION VALIDATION
# ========================================================================

function Assert-ConfiguredHttpsUrl {

    param(
        [Parameter(Mandatory)]
        [string]$SettingName,

        [AllowEmptyString()]
        [string]$Value
    )


    if (
        [string]::IsNullOrWhiteSpace(
            $Value
        )
    ) {

        throw (
            "OEM configuration error: '$SettingName' is empty. " +
            'Set it in Run-DriverDeployment.ps1.'
        )
    }


    $Uri =
        $null


    if (
        -not [Uri]::TryCreate(
            $Value,
            [UriKind]::Absolute,
            [ref]$Uri
        ) -or
        $Uri.Scheme -ne 'https'
    ) {

        throw (
            "OEM configuration error: '$SettingName' must be a valid HTTPS URL. " +
            "Configured value: '$Value'."
        )
    }
}


function Assert-OemConfigurationForManufacturer {

    param(
        [Parameter(Mandatory)]
        [string]$Manufacturer
    )


    switch -Regex ($Manufacturer) {

        'Dell' {

            if (
                [string]::IsNullOrWhiteSpace(
                    $DellCommandUpdateFallbackVersionString
                )
            ) {

                throw (
                    'Dell configuration error: ' +
                    'ITINO_DELL_COMMAND_UPDATE_FALLBACK_VERSION is empty.'
                )
            }


            Assert-ConfiguredHttpsUrl `
                -SettingName 'Dell official discovery URL' `
                -Value $DellCommandUpdateOfficialPageUrl

            Assert-ConfiguredHttpsUrl `
                -SettingName 'Dell fallback download URL' `
                -Value $DellCommandUpdateFallbackDownloadUrl

            break
        }


        'HP|Hewlett-Packard|Hewlett Packard' {

            if (
                [string]::IsNullOrWhiteSpace(
                    $HPImageAssistantFallbackVersionString
                )
            ) {

                throw (
                    'HP configuration error: ' +
                    'ITINO_HP_IMAGE_ASSISTANT_FALLBACK_VERSION is empty.'
                )
            }


            Assert-ConfiguredHttpsUrl `
                -SettingName 'HP official discovery URL' `
                -Value $HPImageAssistantOfficialPageUrl

            Assert-ConfiguredHttpsUrl `
                -SettingName 'HP fallback download URL' `
                -Value $HPImageAssistantFallbackDownloadUrl

            break
        }


        'Lenovo' {

            if (
                [string]::IsNullOrWhiteSpace(
                    $LenovoSystemUpdateVersionString
                )
            ) {

                throw (
                    'Lenovo configuration error: ' +
                    'ITINO_LENOVO_SYSTEM_UPDATE_VERSION is empty.'
                )
            }


            Assert-ConfiguredHttpsUrl `
                -SettingName 'Lenovo System Update download URL' `
                -Value $LenovoSystemUpdateDownloadUrl

            break
        }
    }
}


# ========================================================================
# MAIN
# ========================================================================

Write-RunHeader


try {

    Write-Log -Message (
        'OEM update tool preparation started.'
    )


    Write-Log -Message (
        "Write log files: $WriteLogFiles"
    )


    Write-Log -Message (
        "Unattended mode: $UnattendedMode"
    )


    Write-Log -Message (
        "Require administrator: $RequireAdministrator"
    )


    Write-Log -Message (
        "Windows Update fallback allowed: $AllowWindowsUpdateFallback"
    )

    Write-Log -Message (
        "HP Image Assistant extraction timeout: $HPImageAssistantExtractionTimeoutSeconds seconds"
    )

    Write-Log -Message (
        "HP Image Assistant executable wait: $HPImageAssistantExecutableWaitSeconds seconds"
    )


    Write-Log -Message (
        'HP Image Assistant permanent path: ' +
        'C:\Program Files\HP\HP Image Assistant\HPImageAssistant.exe'
    )


    $CurrentIdentity =
        [Security.Principal.WindowsIdentity]::GetCurrent()


    Write-Log -Message (
        "Running as user: $($CurrentIdentity.Name)"
    )


    $IsAdministrator =
        Test-IsAdministrator


    Write-Log -Message (
        "Running elevated as administrator: $IsAdministrator"
    )


    if (
        $RequireAdministrator -and
        -not $IsAdministrator
    ) {

        throw (
            '02-Install-OEM-Update-Tool.ps1 must run with ' +
            'an elevated administrator token.'
        )
    }


    if (
        -not $RequireAdministrator -and
        -not $IsAdministrator
    ) {

        Write-Log `
            -Message (
                'Running in non-elevated development mode. ' +
                'OEM software installation may fail.'
            ) `
            -Level 'WARNING'
    }


    # ====================================================================
    # TLS 1.2
    # ====================================================================

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12


    Write-Log -Message (
        'TLS 1.2 enabled.'
    )


    # ====================================================================
    # READ HARDWARE INFORMATION
    # ====================================================================

    if (
        Test-Path -LiteralPath $HardwareInformationPath
    ) {

        $HardwareInformation =
            Get-Content `
                -LiteralPath $HardwareInformationPath `
                -Raw |
            ConvertFrom-Json


        $Manufacturer =
            [string]$HardwareInformation.Computer.Manufacturer


        $Model =
            [string]$HardwareInformation.Computer.Model
    }
    else {

        Write-Log `
            -Message (
                'HardwareInformation.json was not found. ' +
                'Reading manufacturer directly from WMI.'
            ) `
            -Level 'WARNING'


        $ComputerSystem =
            Get-CimInstance `
                -ClassName Win32_ComputerSystem


        $Manufacturer =
            [string]$ComputerSystem.Manufacturer


        $Model =
            [string]$ComputerSystem.Model
    }


    Write-Log -Message (
        "Manufacturer: $Manufacturer"
    )


    Write-Log -Message (
        "Model: $Model"
    )


    Write-Log -Message (
        'Validating OEM configuration received from controller.'
    )


    Assert-OemConfigurationForManufacturer `
        -Manufacturer $Manufacturer


    Write-Log -Message (
        'OEM configuration for this manufacturer is valid.'
    )


    # ====================================================================
    # OEM DETECTION
    # ====================================================================

    try {

        switch -Regex (
            $Manufacturer
        ) {

            'Dell' {

                Write-Log -Message (
                    'Dell system detected.'
                )


                Install-DellCommandUpdate


                break
            }


            'HP|Hewlett-Packard|Hewlett Packard' {

                Write-Log -Message (
                    'HP system detected.'
                )


                Install-HPImageAssistant


                break
            }


            'Lenovo' {

                Write-Log -Message (
                    'Lenovo system detected.'
                )


                Write-Log -Message (
                    'Installing or validating Lenovo System Update for ' +
                    'future maintenance. Script 03 will still use LSUClient ' +
                    'for first-start automated driver, BIOS and firmware updates.'
                )


                Install-LenovoSystemUpdate


                break
            }


            default {

                Write-Log `
                    -Message (
                        "No supported OEM utility is configured for " +
                        "manufacturer '$Manufacturer'. " +
                        'Windows Update will be used for driver updates.'
                    ) `
                    -Level 'WARNING'
            }
        }
    }
    catch {

        if (
            $AllowWindowsUpdateFallback
        ) {

            Write-Log `
                -Message (
                    'OEM update tool preparation failed, but Windows ' +
                    'Update fallback is allowed. ' +
                    "Reason: $($_.Exception.Message)"
                ) `
                -Level 'WARNING'
        }
        else {

            throw
        }
    }


    # ====================================================================
    # SUCCESS
    # ====================================================================

    Write-Log -Message (
        'OEM update tool preparation completed successfully.'
    )


    Write-RunFooter `
        -Result 'SUCCESS'


    exit 0
}
catch {

    Write-Log `
        -Message $_.Exception.Message `
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


    Write-RunFooter `
        -Result 'FAILED'


    exit 1
}