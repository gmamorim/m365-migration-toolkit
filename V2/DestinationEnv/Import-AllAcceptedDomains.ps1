<#
.SYNOPSIS
    Adds accepted domains to the destination tenant from a CSV.

.DESCRIPTION
    For each domain in the CSV, creates an Authoritative AcceptedDomain entry.
    If the domain already exists, logs a warning and continues (non-fatal).

    NOTE: Adding an accepted domain has tenant-wide routing implications.
    This function has ConfirmImpact = 'High'. Use -WhatIf for a dry-run.

.PARAMETER CSVFile
    Full path to the input CSV. Required column: DomainName.
    Optional columns: DomainType (defaults to 'Authoritative').

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Import-AllAcceptedDomains -CSVFile "C:\CSV\Acme\Accepted_Domains_Acme.csv"

.EXAMPLE
    Import-AllAcceptedDomains -CSVFile "C:\CSV\Acme\Accepted_Domains_Acme.csv" -WhatIf

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session (Exchange Admin role)
    CSV In   : DomainName (req), DomainType (optional, defaults to Authoritative)
#>

function Import-AllAcceptedDomains {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CSVFile,

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
        if ('DomainName' -notin $headers) { throw "CSV missing required column: 'DomainName'" }

        $successCount = 0
        $errorCount   = 0
        $skipped      = 0
        Write-Log "Starting Import-AllAcceptedDomains. CSV: $CSVFile" -Level Info
    }

    process {
        $Domains = Import-Csv -Path $CSVFile -Encoding UTF8

        foreach ($Domain in $Domains) {
            $domainName = $Domain.DomainName.Trim()
            $domainType = if ($Domain.PSObject.Properties.Name -contains 'DomainType' -and $Domain.DomainType) {
                $Domain.DomainType
            } else {
                'Authoritative'
            }

            Write-Verbose "Processing: $domainName ($domainType)"

            if ($PSCmdlet.ShouldProcess($domainName, "Add accepted domain ($domainType)")) {
                try {
                    # Check if it already exists
                    $existing = Get-AcceptedDomain -Identity $domainName -ErrorAction SilentlyContinue
                    if ($existing) {
                        Write-Log "Domain '$domainName' already exists. Skipping." -Level Warning
                        $skipped++
                        continue
                    }

                    New-AcceptedDomain -Name $domainName -DomainName $domainName -DomainType $domainType -ErrorAction Stop | Out-Null
                    Write-Log "Added accepted domain '$domainName' ($domainType)." -Level Success
                    $successCount++
                }
                catch {
                    Write-Log "Failed to add domain '$domainName': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        Write-Log "Summary | Added: $successCount | Skipped (existing): $skipped | Failed: $errorCount" -Level Info
        [PSCustomObject]@{
            Function     = 'Import-AllAcceptedDomains'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount + $skipped
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
