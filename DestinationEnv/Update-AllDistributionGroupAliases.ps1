<#
.SYNOPSIS
    Adds source SMTP addresses as secondary aliases to destination distribution groups.

.DESCRIPTION
    For each group in the CSV, looks up the destination group by its derived alias
    and adds the original source addresses (primary + additional aliases from the
    'Alias' column) as secondary SMTP addresses.

.PARAMETER CSVFile
    Full path to the input CSV.
    Required columns: PrimarySmtpAddress, Alias (semicolon-separated list).

.PARAMETER Domain
    Destination tenant SMTP domain.

.PARAMETER Prefix
    Optional. Prefix used when the groups were created (must match what was used in Import-AllDistributionGroups).

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Update-AllDistributionGroupAliases -CSVFile "C:\CSV\Contoso\Distribution_Groups_Contoso.csv" `
        -Domain "amorim.rocks"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : PrimarySmtpAddress (req), Alias (semicolon-separated, req)
#>

function Update-AllDistributionGroupAliases {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CSVFile,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

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
        foreach ($col in @('PrimarySmtpAddress', 'Alias')) {
            if ($col -notin $headers) { throw "CSV missing required column: '$col'" }
        }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Update-AllDistributionGroupAliases. CSV: $CSVFile" -Level Info
    }

    process {
        $Groups = Import-Csv -Path $CSVFile -Encoding UTF8

        foreach ($Group in $Groups) {
            $localPart = ($Group.PrimarySmtpAddress -split '@')[0]
            $aliasBase = if ($Prefix) { "$Prefix-$localPart" } else { $localPart }
            $DestAlias = (("$aliasBase" -replace '[^a-zA-Z0-9._-]', '') + "@$Domain").ToLower()

            try {
                $ExistingGroup = Get-DistributionGroup -Identity $DestAlias -ErrorAction Stop
            }
            catch {
                Write-Log "Distribution group '$DestAlias' not found. Skipping." -Level Warning
                $errorCount++
                continue
            }

            Write-Verbose "Processing: $($ExistingGroup.PrimarySmtpAddress)"

            $aliasList = [System.Collections.Generic.List[string]]::new()

            if ($Group.PrimarySmtpAddress -notmatch 'onmicrosoft\.com') {
                $aliasList.Add($Group.PrimarySmtpAddress)
            }

            if ($Group.Alias) {
                $Group.Alias -split ';' | Where-Object { $_ -ne '' -and $_ -notmatch 'onmicrosoft\.com' } | ForEach-Object {
                    $aliasList.Add($_.Trim())
                }
            }

            $aliasList = $aliasList | Select-Object -Unique |
                Where-Object { $_ -ne $ExistingGroup.PrimarySmtpAddress.ToString() }

            foreach ($alias in $aliasList) {
                if ($PSCmdlet.ShouldProcess($($ExistingGroup.PrimarySmtpAddress), "Add alias '$alias'")) {
                    try {
                        Set-DistributionGroup -Identity $ExistingGroup.Identity `
                            -EmailAddresses @{ add = "smtp:$alias" } -ErrorAction Stop
                        Write-Log "Added alias '$alias' to '$($ExistingGroup.PrimarySmtpAddress)'." -Level Success
                        $successCount++
                    }
                    catch {
                        Write-Log "Failed to add alias '$alias' to '$($ExistingGroup.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Error
                        $errorCount++
                    }
                }
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Update-AllDistributionGroupAliases'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
