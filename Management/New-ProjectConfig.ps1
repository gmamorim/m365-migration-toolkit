<#
.SYNOPSIS
    Creates a new project configuration file from the standard template.

.DESCRIPTION
    Reads the ProjectConfig.TEMPLATE.ps1 file located in the same directory,
    substitutes all placeholder tokens with the provided values, and writes
    the result to a new file named "$ProjectKey-Config.ps1".

.PARAMETER ProjectKey
    Unique identifier for the migration project. Used as a prefix in CSV file
    names and directory names (e.g. "Contoso", "Fabrikam").

.PARAMETER Domain
    Source tenant primary SMTP domain (e.g. "contoso.com").

.PARAMETER DestinationDomain
    Destination tenant SMTP domain (e.g. "dest.com").

.PARAMETER CSVFolder
    Base directory path where all CSV exports and imports are stored.

.PARAMETER Prefix
    Optional. Short prefix prepended to destination object aliases.
    When omitted, aliases are derived directly from the source local part.

.PARAMETER OutputPath
    Directory where the generated config file will be written.
    Defaults to the directory containing this script.

.PARAMETER Force
    Overwrites an existing config file for the same ProjectKey without prompting.

.EXAMPLE
    New-ProjectConfig -ProjectKey "Contoso" -Domain "contoso.com" `
        -DestinationDomain "dest.com" -CSVFolder "C:\CSV"

    Creates "Contoso-Config.ps1" with no alias prefix.

.EXAMPLE
    New-ProjectConfig -ProjectKey "Fabrikam" -Domain "fabrikam.com" `
        -DestinationDomain "dest.com" -CSVFolder "C:\CSV" -Prefix "fab" -Force

    Creates or overwrites "Fabrikam-Config.ps1" with alias prefix "fab".

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : No external modules
#>

function New-ProjectConfig {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationDomain,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CSVFolder,

        [Parameter(Mandatory = $false)]
        [string]$Prefix = '',

        [Parameter(Mandatory = $false)]
        [string]$OutputPath = $PSScriptRoot,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    begin {
        $templatePath = Join-Path $PSScriptRoot 'ProjectConfig.TEMPLATE.ps1'

        if (-not (Test-Path $templatePath)) {
            throw "Template file not found at: $templatePath"
        }

        $outputFile = Join-Path $OutputPath "$ProjectKey-Config.ps1"

        if ((Test-Path $outputFile) -and -not $Force) {
            throw "Config file already exists: $outputFile. Use -Force to overwrite."
        }
    }

    process {
        if ($PSCmdlet.ShouldProcess($outputFile, 'Create project config')) {
            $templateContent = Get-Content -Path $templatePath -Raw

            $replacements = @{
                '{{ProjectKey}}'        = $ProjectKey
                '{{Prefix}}'            = $Prefix
                '{{Domain}}'            = $Domain
                '{{DestinationDomain}}' = $DestinationDomain
                '{{CSVFolder}}'         = $CSVFolder
                '{{GeneratedDate}}'     = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            }

            foreach ($token in $replacements.Keys) {
                $templateContent = $templateContent.Replace($token, $replacements[$token])
            }

            Set-Content -Path $outputFile -Value $templateContent -Encoding UTF8
            Write-Host "[Success] Config created: $outputFile" -ForegroundColor Green
        }
    }

    end {
        [PSCustomObject]@{
            Function      = 'New-ProjectConfig'
            ProjectKey    = $ProjectKey
            OutputFile    = $outputFile
            TimestampUTC  = (Get-Date).ToUniversalTime()
        }
    }
}
