<#
.SYNOPSIS
    Exports all dynamic distribution groups from the source tenant to CSV.

.DESCRIPTION
    Retrieves all DynamicDistributionGroup objects and exports DisplayName,
    PrimarySmtpAddress, Alias, RecipientFilter, and IncludedRecipients.

    Output: <OutputCSV>\<ProjectKey>\Dynamic_Distribution_Groups_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllDynamicDistributionGroups -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-AllDynamicDistributionGroups {
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

        $outputFile   = Join-Path $folderPath "Dynamic_Distribution_Groups_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllDynamicDistributionGroups. Output: $outputFile" -Level Info
    }

    process {
        try {
            $groups = Get-DynamicDistributionGroup -ResultSize Unlimited -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve dynamic distribution groups: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($group in $groups) {
            Write-Verbose "Processing: $($group.PrimarySmtpAddress)"
            try {
                $aliases = ($group.EmailAddresses |
                    ForEach-Object { $_.ToString() -replace '^(SMTP|smtp):', '' } |
                    Where-Object { $_ -notmatch 'onmicrosoft' }) -join ';'

                $results.Add([PSCustomObject]@{
                    DisplayName         = $group.DisplayName
                    PrimarySmtpAddress  = $group.PrimarySmtpAddress
                    Alias               = $aliases
                    RecipientFilter     = $group.RecipientFilter
                    IncludedRecipients  = $group.IncludedRecipients
                    ConditionalDept     = $group.ConditionalDepartment -join ';'
                    ConditionalCompany  = $group.ConditionalCompany -join ';'
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
            Write-Log "Exported $($results.Count) dynamic distribution groups to: $outputFile" -Level Success
        } else {
            Write-Log "No dynamic distribution groups were exported." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllDynamicDistributionGroups'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
