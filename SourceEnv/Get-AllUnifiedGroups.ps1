<#
.SYNOPSIS
    Exports all Microsoft 365 Unified Groups (M365 Groups) from the source tenant to CSV.

.DESCRIPTION
    Retrieves all UnifiedGroup objects and exports key properties for reference.
    This is an export-only script. Creation of M365 Groups in the destination tenant
    is typically handled by the migration tool (e.g. BitTitan) or manually, as group
    creation also provisions SharePoint sites and Teams workloads.

    Output: <OutputCSV>\<ProjectKey>\Unified_Groups_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllUnifiedGroups -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    Note     : No import script exists for this object type by design.
               Use this CSV as reference or feed it into your migration tool.
#>

function Get-AllUnifiedGroups {
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

        $outputFile   = Join-Path $folderPath "Unified_Groups_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllUnifiedGroups. Output: $outputFile" -Level Info
    }

    process {
        try {
            $groups = Get-UnifiedGroup -ResultSize Unlimited -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve unified groups: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($group in $groups) {
            Write-Verbose "Processing: $($group.PrimarySmtpAddress)"
            try {
                $aliases = ($group.EmailAddresses |
                    ForEach-Object { $_.ToString() -replace '^(SMTP|smtp):', '' } |
                    Where-Object { $_ -notmatch 'onmicrosoft' }) -join ';'

                $owners  = ''
                $members = ''
                try {
                    $owners  = (Get-UnifiedGroupLinks -Identity $group.Identity -LinkType Owners  -ErrorAction Stop | Select-Object -ExpandProperty PrimarySmtpAddress) -join ';'
                    $members = (Get-UnifiedGroupLinks -Identity $group.Identity -LinkType Members -ErrorAction Stop | Select-Object -ExpandProperty PrimarySmtpAddress) -join ';'
                }
                catch {
                    Write-Log "Warning: Could not retrieve members/owners for '$($group.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Warning
                }

                $results.Add([PSCustomObject]@{
                    DisplayName        = $group.DisplayName
                    PrimarySmtpAddress = $group.PrimarySmtpAddress
                    Alias              = $aliases
                    AccessType         = $group.AccessType
                    Language           = $group.Language
                    Owners             = $owners
                    Members            = $members
                    SharePointSiteUrl  = $group.SharePointSiteUrl
                    ManagedBy          = $group.ManagedBy -join ';'
                })
                $successCount++
            }
            catch {
                Write-Log "Failed to process group '$($group.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Error
                $errorCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) unified groups to: $outputFile" -Level Success
        } else {
            Write-Log "No unified groups were exported." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllUnifiedGroups'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
