<#
.SYNOPSIS
    Exports DNS records for a specified domain to CSV.

.DESCRIPTION
    Resolves DNS records of types A, AAAA, MX, NS, SOA, TXT, CNAME, SRV, and PTR
    for the given domain name and exports the results to a CSV file.

    Failures per record type are logged as warnings and counted separately.
    A missing record type does not abort the export.

    Output: <OutputCSV>\<ProjectKey>\DNS_Records_<domain>_<ProjectKey>.csv

.PARAMETER DomainName
    The domain name to resolve (e.g. "acme.com").

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllDomainRecords -DomainName "acme.com" -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : No external modules (uses Resolve-DnsName, available on Windows)
    Tested   : 2025-03-27
#>

function Get-AllDomainRecords {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

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

        $safeDomain   = $DomainName.Replace('.', '_')
        $outputFile   = Join-Path $folderPath "DNS_Records_${safeDomain}_$ProjectKey.csv"
        $recordTypes  = @('A', 'AAAA', 'MX', 'NS', 'SOA', 'TXT', 'CNAME', 'SRV', 'PTR')
        $successCount = 0
        $warningCount = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllDomainRecords for domain: $DomainName" -Level Info
    }

    process {
        foreach ($type in $recordTypes) {
            try {
                $resolved = Resolve-DnsName -Name $DomainName -Type $type -ErrorAction Stop
                foreach ($record in $resolved) {
                    $data = $record.IPAddress ?? $record.NameHost ?? ($record.Strings -join ';') ?? ''
                    $results.Add([PSCustomObject]@{
                        Domain     = $DomainName
                        RecordType = $record.Type
                        Name       = $record.Name
                        TTL        = $record.TTL
                        Data       = $data
                    })
                    $successCount++
                }
                Write-Verbose "Resolved $type records for $DomainName"
            }
            catch {
                Write-Log "No $type records found for '$DomainName' (or query failed)." -Level Warning
                $warningCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) DNS records to: $outputFile" -Level Success
        } else {
            Write-Log "No DNS records were resolved for domain '$DomainName'." -Level Warning
        }

        Write-Log "Summary | Records exported: $successCount | Record types with no data: $warningCount" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllDomainRecords'
            Succeeded    = $successCount
            Failed       = 0
            Total        = $successCount
            Warnings     = $warningCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
