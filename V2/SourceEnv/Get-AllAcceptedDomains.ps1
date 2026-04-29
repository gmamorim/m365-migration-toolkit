<#
.SYNOPSIS
    Exports all accepted domains (Authoritative type) from the source tenant to CSV.

.DESCRIPTION
    Retrieves all AcceptedDomain objects of type Authoritative and exports
    Name, DomainName, DomainType, and Default flag.

    This function is promoted from the .Imported/Functions directory and standardised
    to the V2 pattern. It is useful for cross-referencing domains before running
    Import-AllAcceptedDomains on the destination tenant.

    Output: <OutputCSV>\<ProjectKey>\Accepted_Domains_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllAcceptedDomains -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-AllAcceptedDomains {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$OutputCSV,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectKey,

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

        $folderPath = Join-Path $OutputCSV $ProjectKey
        if (-not (Test-Path $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        }

        $outputFile   = Join-Path $folderPath "Accepted_Domains_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllAcceptedDomains. Output: $outputFile" -Level Info
    }

    process {
        try {
            $domains = Get-AcceptedDomain -ErrorAction Stop |
                Where-Object { $_.DomainType -eq 'Authoritative' }
        }
        catch {
            Write-Log "Failed to retrieve accepted domains: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($domain in $domains) {
            Write-Verbose "Processing: $($domain.DomainName)"
            try {
                $results.Add([PSCustomObject]@{
                    Name       = $domain.Name
                    DomainName = $domain.DomainName
                    DomainType = $domain.DomainType
                    Default    = $domain.Default
                })
                $successCount++
            }
            catch {
                Write-Log "Failed to process domain '$($domain.DomainName)': $($_.Exception.Message)" -Level Error
                $errorCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) accepted domains to: $outputFile" -Level Success
        } else {
            Write-Log "No accepted domains were exported." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllAcceptedDomains'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
