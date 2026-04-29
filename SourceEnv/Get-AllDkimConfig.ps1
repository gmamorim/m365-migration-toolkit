<#
.SYNOPSIS
    Reports DKIM signing configuration for all domains in the source tenant.

.DESCRIPTION
    Retrieves all DkimSigningConfig objects and exports their status and selector
    information. This is a report-only script — DKIM cannot be "imported" as it
    requires DNS CNAME records to be published for each domain in the destination
    tenant before enabling signing.

    Output: <OutputCSV>\<ProjectKey>\DKIM_Config_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllDkimConfig -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    Note     : To enable DKIM in the destination, publish the CNAME records shown
               in the Microsoft 365 Defender portal for each domain, then run
               Set-DkimSigningConfig -Identity <domain> -Enabled $true
#>

function Get-AllDkimConfig {
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

        $outputFile   = Join-Path $folderPath "DKIM_Config_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllDkimConfig. Output: $outputFile" -Level Info
    }

    process {
        try {
            $configs = Get-DkimSigningConfig -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve DKIM signing configs: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($config in $configs) {
            Write-Verbose "Processing: $($config.Domain)"
            try {
                $results.Add([PSCustomObject]@{
                    Domain              = $config.Domain
                    Enabled             = $config.Enabled
                    Status              = $config.Status
                    Selector1           = $config.Selector1
                    Selector2           = $config.Selector2
                    Selector1CNAME      = $config.Selector1CNAME
                    Selector2CNAME      = $config.Selector2CNAME
                    LastChecked         = $config.LastChecked
                })
                $successCount++
            }
            catch {
                Write-Log "Failed to process domain '$($config.Domain)': $($_.Exception.Message)" -Level Error
                $errorCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) DKIM configurations to: $outputFile" -Level Success
        } else {
            Write-Log "No DKIM configurations were found." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllDkimConfig'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
