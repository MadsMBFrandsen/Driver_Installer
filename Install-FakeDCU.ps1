<#
.SYNOPSIS
    Installs an ITINO lab-only fake Dell Command Update CLI.

.DESCRIPTION
    Builds a harmless dcu-cli.exe at the normal Dell Command Update path:

        C:\Program Files\Dell\CommandUpdate\dcu-cli.exe

    The fake executable:
        - Never installs drivers
        - Never changes firmware or BIOS
        - Never calls Dell services
        - Supports the command shapes used by 03-Update-Drivers.ps1
        - Creates DCUApplicableUpdates.xml for /scan
        - Returns controlled DCU-style exit codes
        - Persists "applied" state so a post-reboot scan can return no updates

    Supported scenarios:
        UpdatesRequireReboot
        UpdatesSuccess
        NoUpdates
        ScanRestartRequired
        ScanFailure
        ScanRetryThenSuccess
        ApplyFailure
        ApplyRetryThenSuccess

.EXAMPLE
    .\Install-FakeDCU.ps1 -Scenario UpdatesRequireReboot -ResetState
#>

[CmdletBinding()]
param(
    [ValidateSet(
        'UpdatesRequireReboot',
        'UpdatesSuccess',
        'NoUpdates',
        'ScanRestartRequired',
        'ScanFailure',
        'ScanRetryThenSuccess',
        'ApplyFailure',
        'ApplyRetryThenSuccess'
    )]
    [string]$Scenario = 'UpdatesRequireReboot',

    [switch]$ResetState
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $Identity =
        [Security.Principal.WindowsIdentity]::GetCurrent()

    $Principal =
        New-Object Security.Principal.WindowsPrincipal($Identity)

    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

if (-not (Test-IsAdministrator)) {
    throw 'Install-FakeDCU.ps1 must run as administrator.'
}

$InstallDirectory =
    'C:\Program Files\Dell\CommandUpdate'

$OutputPath =
    Join-Path `
        $InstallDirectory `
        'dcu-cli.exe'

$StateDirectory =
    'C:\ProgramData\Itino\FakeDCU'

if (-not (Test-Path -LiteralPath $InstallDirectory)) {
    New-Item `
        -Path $InstallDirectory `
        -ItemType Directory `
        -Force |
    Out-Null
}

if (-not (Test-Path -LiteralPath $StateDirectory)) {
    New-Item `
        -Path $StateDirectory `
        -ItemType Directory `
        -Force |
    Out-Null
}

if ($ResetState) {
    Get-ChildItem `
        -LiteralPath $StateDirectory `
        -File `
        -ErrorAction SilentlyContinue |
    Remove-Item `
        -Force `
        -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $OutputPath) {
    $ExistingProduct =
        $null

    try {
        $ExistingProduct =
            (
                [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
                    $OutputPath
                )
            ).ProductName
    }
    catch {
    }

    if (
        -not [string]::IsNullOrWhiteSpace(
            [string]$ExistingProduct
        ) -and
        $ExistingProduct -notmatch '^ITINO Fake Dell Command Update'
    ) {
        throw (
            'A non-lab dcu-cli.exe already exists at ' +
            "'$OutputPath'. It will not be overwritten."
        )
    }

    Remove-Item `
        -LiteralPath $OutputPath `
        -Force
}

$Source = @'
using System;
using System.IO;
using System.Reflection;
using System.Text;

[assembly: AssemblyVersion("99.0.0.0")]
[assembly: AssemblyFileVersion("99.0.0.0")]
[assembly: AssemblyProduct("ITINO Fake Dell Command Update")]
[assembly: AssemblyCompany("ITINO Lab")]
[assembly: AssemblyTitle("ITINO Fake dcu-cli")]
[assembly: AssemblyDescription("Lab-only Dell Command Update simulator. Does not install drivers.")]

namespace ItinoFakeDCU
{
    internal static class Program
    {
        private const string ScenarioVariable = "ITINO_FAKE_DCU_SCENARIO";

        private static string ProgramData
        {
            get
            {
                string value = Environment.GetEnvironmentVariable("ProgramData");
                if (String.IsNullOrEmpty(value))
                {
                    value = @"C:\ProgramData";
                }

                return value;
            }
        }

        private static string StateDirectory
        {
            get
            {
                return Path.Combine(
                    ProgramData,
                    "Itino",
                    "FakeDCU"
                );
            }
        }

        private static int Main(string[] args)
        {
            try
            {
                Directory.CreateDirectory(StateDirectory);

                string scenario = GetScenario();
                string outputLog = GetOptionValue(args, "-outputLog=");
                string reportDirectory = GetOptionValue(args, "-report=");

                WriteLog(
                    outputLog,
                    "ITINO Fake DCU started. Scenario=" + scenario
                );

                WriteLog(
                    outputLog,
                    "Arguments: " + String.Join(" ", args)
                );

                if (HasArgument(args, "/scan"))
                {
                    return RunScan(
                        scenario,
                        reportDirectory,
                        outputLog
                    );
                }

                if (HasArgument(args, "/applyUpdates"))
                {
                    return RunApply(
                        scenario,
                        outputLog
                    );
                }

                WriteLog(
                    outputLog,
                    "No supported fake DCU command was supplied."
                );

                return 101;
            }
            catch (Exception ex)
            {
                try
                {
                    File.AppendAllText(
                        Path.Combine(
                            StateDirectory,
                            "FakeDCU-Fatal.log"
                        ),
                        DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") +
                        " " +
                        ex.ToString() +
                        Environment.NewLine
                    );
                }
                catch
                {
                }

                return 2;
            }
        }

        private static int RunScan(
            string scenario,
            string reportDirectory,
            string outputLog
        )
        {
            WriteLog(
                outputLog,
                "Fake /scan operation selected."
            );

            if (IsApplied(scenario))
            {
                WriteLog(
                    outputLog,
                    "Fake updates were already applied in an earlier run. Returning 500 (no updates)."
                );

                return 500;
            }

            if (
                scenario.Equals(
                    "NoUpdates",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                WriteLog(
                    outputLog,
                    "Scenario requests no updates. Returning 500."
                );

                return 500;
            }

            if (
                scenario.Equals(
                    "ScanRestartRequired",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                WriteLog(
                    outputLog,
                    "Scenario requests restart during scan. Returning 1."
                );

                return 1;
            }

            if (
                scenario.Equals(
                    "ScanFailure",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                WriteLog(
                    outputLog,
                    "Scenario requests non-retry scan failure. Returning 502."
                );

                return 502;
            }

            if (
                scenario.Equals(
                    "ScanRetryThenSuccess",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                int attempt = IncrementCounter(
                    "ScanAttempts-" + SafeFileName(scenario) + ".txt"
                );

                if (attempt < 3)
                {
                    WriteLog(
                        outputLog,
                        "Simulating retryable scan failure. Attempt=" +
                        attempt.ToString() +
                        ". Returning 501."
                    );

                    return 501;
                }
            }

            if (String.IsNullOrEmpty(reportDirectory))
            {
                WriteLog(
                    outputLog,
                    "The -report option was not supplied. Returning 108."
                );

                return 108;
            }

            Directory.CreateDirectory(reportDirectory);

            string reportPath =
                Path.Combine(
                    reportDirectory,
                    "DCUApplicableUpdates.xml"
                );

            WriteFakeReport(reportPath);

            WriteLog(
                outputLog,
                "Fake scan report created: " + reportPath
            );

            WriteLog(
                outputLog,
                "Returning 0 for successful scan with three fake driver updates."
            );

            return 0;
        }

        private static int RunApply(
            string scenario,
            string outputLog
        )
        {
            WriteLog(
                outputLog,
                "Fake /applyUpdates operation selected."
            );

            if (
                scenario.Equals(
                    "ApplyFailure",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                WriteLog(
                    outputLog,
                    "Scenario requests apply failure. Returning 1001."
                );

                return 1001;
            }

            if (
                scenario.Equals(
                    "ApplyRetryThenSuccess",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                int attempt = IncrementCounter(
                    "ApplyAttempts-" + SafeFileName(scenario) + ".txt"
                );

                if (attempt < 3)
                {
                    WriteLog(
                        outputLog,
                        "Simulating retryable apply failure. Attempt=" +
                        attempt.ToString() +
                        ". Returning 1000."
                    );

                    return 1000;
                }
            }

            MarkApplied(scenario);

            if (
                scenario.Equals(
                    "UpdatesRequireReboot",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                WriteLog(
                    outputLog,
                    "Fake apply completed. Returning 3010 to request restart."
                );

                return 3010;
            }

            WriteLog(
                outputLog,
                "Fake apply completed successfully. Returning 0."
            );

            return 0;
        }

        private static void WriteFakeReport(
            string reportPath
        )
        {
            StringBuilder xml =
                new StringBuilder();

            xml.AppendLine(
                "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            );

            xml.AppendLine("<updates>");

            AppendUpdate(
                xml,
                "Intel Chipset Device Software",
                "10.1.20020.8623",
                "driver",
                "Recommended",
                "Chipset",
                "FAKE001",
                "A00"
            );

            AppendUpdate(
                xml,
                "Intel Wireless LAN Driver",
                "23.140.0.3",
                "driver",
                "Recommended",
                "Network",
                "FAKE002",
                "A01"
            );

            AppendUpdate(
                xml,
                "Realtek Audio Driver",
                "6.0.9780.1",
                "driver",
                "Recommended",
                "Audio",
                "FAKE003",
                "A02"
            );

            xml.AppendLine("</updates>");

            File.WriteAllText(
                reportPath,
                xml.ToString(),
                new UTF8Encoding(false)
            );
        }

        private static void AppendUpdate(
            StringBuilder xml,
            string name,
            string version,
            string type,
            string urgency,
            string category,
            string releaseId,
            string dellVersion
        )
        {
            xml.AppendLine("  <update>");
            xml.AppendLine(
                "    <name>" +
                EscapeXml(name) +
                "</name>"
            );
            xml.AppendLine(
                "    <version>" +
                EscapeXml(version) +
                "</version>"
            );
            xml.AppendLine(
                "    <type>" +
                EscapeXml(type) +
                "</type>"
            );
            xml.AppendLine(
                "    <urgency>" +
                EscapeXml(urgency) +
                "</urgency>"
            );
            xml.AppendLine(
                "    <category>" +
                EscapeXml(category) +
                "</category>"
            );
            xml.AppendLine(
                "    <releaseID>" +
                EscapeXml(releaseId) +
                "</releaseID>"
            );
            xml.AppendLine(
                "    <dellVersion>" +
                EscapeXml(dellVersion) +
                "</dellVersion>"
            );
            xml.AppendLine("  </update>");
        }

        private static string EscapeXml(
            string value
        )
        {
            if (value == null)
            {
                return String.Empty;
            }

            return value
                .Replace("&", "&amp;")
                .Replace("<", "&lt;")
                .Replace(">", "&gt;")
                .Replace("\"", "&quot;")
                .Replace("'", "&apos;");
        }

        private static string GetScenario()
        {
            string value =
                Environment.GetEnvironmentVariable(
                    ScenarioVariable
                );

            if (String.IsNullOrEmpty(value))
            {
                try
                {
                    value =
                        Environment.GetEnvironmentVariable(
                            ScenarioVariable,
                            EnvironmentVariableTarget.Machine
                        );
                }
                catch
                {
                }
            }

            if (String.IsNullOrEmpty(value))
            {
                value = "UpdatesRequireReboot";
            }

            return value.Trim();
        }

        private static bool HasArgument(
            string[] args,
            string expected
        )
        {
            foreach (string arg in args)
            {
                if (
                    String.Equals(
                        arg,
                        expected,
                        StringComparison.OrdinalIgnoreCase
                    )
                )
                {
                    return true;
                }
            }

            return false;
        }

        private static string GetOptionValue(
            string[] args,
            string prefix
        )
        {
            foreach (string arg in args)
            {
                if (
                    arg.StartsWith(
                        prefix,
                        StringComparison.OrdinalIgnoreCase
                    )
                )
                {
                    string value =
                        arg.Substring(prefix.Length);

                    return value.Trim().Trim('"');
                }
            }

            return null;
        }

        private static string SafeFileName(
            string value
        )
        {
            foreach (
                char invalid in
                Path.GetInvalidFileNameChars()
            )
            {
                value =
                    value.Replace(
                        invalid,
                        '_'
                    );
            }

            return value;
        }

        private static string AppliedFile(
            string scenario
        )
        {
            return Path.Combine(
                StateDirectory,
                "Applied-" +
                SafeFileName(scenario) +
                ".txt"
            );
        }

        private static bool IsApplied(
            string scenario
        )
        {
            return File.Exists(
                AppliedFile(scenario)
            );
        }

        private static void MarkApplied(
            string scenario
        )
        {
            File.WriteAllText(
                AppliedFile(scenario),
                DateTime.Now.ToString(
                    "yyyy-MM-dd HH:mm:ss"
                )
            );
        }

        private static int IncrementCounter(
            string fileName
        )
        {
            string path =
                Path.Combine(
                    StateDirectory,
                    fileName
                );

            int value = 0;

            if (File.Exists(path))
            {
                Int32.TryParse(
                    File.ReadAllText(path).Trim(),
                    out value
                );
            }

            value++;

            File.WriteAllText(
                path,
                value.ToString()
            );

            return value;
        }

        private static void WriteLog(
            string path,
            string message
        )
        {
            if (String.IsNullOrEmpty(path))
            {
                return;
            }

            string directory =
                Path.GetDirectoryName(path);

            if (
                !String.IsNullOrEmpty(directory)
            )
            {
                Directory.CreateDirectory(
                    directory
                );
            }

            File.AppendAllText(
                path,
                "[" +
                DateTime.Now.ToString(
                    "yyyy-MM-dd HH:mm:ss"
                ) +
                "] [FAKE-DCU] " +
                message +
                Environment.NewLine
            );
        }
    }
}
'@

$TemporaryAssembly =
    Join-Path `
        $env:TEMP `
        (
            'itino-fake-dcu-' +
            [guid]::NewGuid().ToString('N') +
            '.exe'
        )

try {
    Add-Type `
        -TypeDefinition $Source `
        -Language CSharp `
        -OutputAssembly $TemporaryAssembly `
        -OutputType ConsoleApplication `
        -ErrorAction Stop

    Copy-Item `
        -LiteralPath $TemporaryAssembly `
        -Destination $OutputPath `
        -Force
}
finally {
    Remove-Item `
        -LiteralPath $TemporaryAssembly `
        -Force `
        -ErrorAction SilentlyContinue
}

[Environment]::SetEnvironmentVariable(
    'ITINO_FAKE_DCU_SCENARIO',
    $Scenario,
    'Machine'
)

$env:ITINO_FAKE_DCU_SCENARIO =
    $Scenario

$VersionInfo =
    [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
        $OutputPath
    )

Write-Host ''
Write-Host '============================================================'
Write-Host 'ITINO FAKE DELL COMMAND UPDATE INSTALLED'
Write-Host '============================================================'
Write-Host ''
Write-Host "Path       : $OutputPath"
Write-Host "Product    : $($VersionInfo.ProductName)"
Write-Host "Version    : $($VersionInfo.FileVersion)"
Write-Host "Scenario   : $Scenario"
Write-Host "State path : $StateDirectory"
Write-Host ''
Write-Host 'This executable does NOT install any drivers or firmware.'
Write-Host ''

exit 0
