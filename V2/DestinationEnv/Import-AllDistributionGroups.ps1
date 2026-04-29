<#
.SYNOPSIS
    Creates distribution groups in the destination tenant from a source CSV.

.DESCRIPTION
    For each row, resolves a unique destination alias using Resolve-UniqueAlias
    (checks Get-Recipient to avoid collisions) and creates a distribution group.

    DisplayName format: '<Company> - <SourceDisplayName>' when Company is provided,
    otherwise uses the source DisplayName as-is.

.PARAMETER CSVFile
    Full path to the input CSV. Required columns: DisplayName, PrimarySmtpAddress.

.PARAMETER Domain
    Destination tenant SMTP domain (e.g. "contoso.com").

.PARAMETER Company
    Optional. Company name prepended to DisplayName.

.PARAMETER Prefix
    Optional. Short prefix prepended to the alias.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Import-AllDistributionGroups -CSVFile "C:\CSV\Contoso\Distribution_Groups_Contoso.csv" `
        -Domain "dest.com"

.EXAMPLE
    Import-AllDistributionGroups -CSVFile "C:\CSV\Contoso\Distribution_Groups_Contoso.csv" `
        -Domain "dest.com" -Company "Contoso" -WhatIf

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : DisplayName (req), PrimarySmtpAddress (req)
#>

function Import-AllDistributionGroups {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CSVFile,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

        [Parameter(Mandatory = $false)]
        [string]$Company,

        [Parameter(Mandatory = $false)]
        [string]$Prefix,

        [Parameter(Mandatory = $false)]
        [string]$LogPath
    )

    begin {
        function Write-Log {
            param([string]$Message, [string]$Level = 'Info')
            $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][$Level] $Message"
            switch ($Level) {
                'Success' { Write-Host $line -ForegroundColor Green }
                'Warning' { Write-Host $line -ForegroundColor Yellow }
                'Error'   { Write-Host $line -ForegroundColor Red }
                default   { Write-Host $line -ForegroundColor Cyan }
            }
            if ($LogPath) { Add-Content -Path $LogPath -Value $line -Encoding UTF8 }
        }

        $headers = (Get-Content $CSVFile -TotalCount 1) -split ',' | ForEach-Object { $_.Trim('"').Trim() }
        foreach ($col in @('DisplayName', 'PrimarySmtpAddress')) {
            if ($col -notin $headers) { throw "CSV missing required column: '$col'" }
        }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Import-AllDistributionGroups. CSV: $CSVFile" -Level Info
    }

    process {
        try {
            $Groups = Import-Csv -Path $CSVFile -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to import CSV: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($Group in $Groups) {
            $resolveParams = @{ SourceAddress = $Group.PrimarySmtpAddress; Domain = $Domain }
            if ($Prefix) { $resolveParams['Prefix'] = $Prefix }

            $PrimarySmtpAddress   = Resolve-UniqueAlias @resolveParams
            $Alias                = ($PrimarySmtpAddress -split '@')[0]
            $FormattedDisplayName = if ($Company) { "$Company - $($Group.DisplayName)" } else { $Group.DisplayName }

            Write-Verbose "Processing: $FormattedDisplayName -> $PrimarySmtpAddress"

            if ($PSCmdlet.ShouldProcess($PrimarySmtpAddress, 'Create distribution group')) {
                try {
                    New-DistributionGroup -Name $FormattedDisplayName -DisplayName $FormattedDisplayName `
                        -Alias $Alias -PrimarySmtpAddress $PrimarySmtpAddress -ErrorAction Stop
                    Write-Log "Created distribution group '$FormattedDisplayName' ($PrimarySmtpAddress)." -Level Success
                    $successCount++
                }
                catch {
                    Write-Log "Failed to create '$FormattedDisplayName': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Import-AllDistributionGroups'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
