<#
.SYNOPSIS
    Exports all mail users with external forwarding addresses to CSV.

.DESCRIPTION
    Retrieves all MailUser objects (external-forwarding users) and exports
    DisplayName, UserPrincipalName, and ExternalEmailAddress.

    Output: <OutputCSV>\<ProjectKey>\MailUsers_Fwd_<ProjectKey>.csv

    Bug fix from V1: $OutputCSV is treated as a base directory (not a file path).
    The erroneous Split-Path call present in V1 has been removed.

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllMailUserFwd -OutputCSV "C:\CSV" -ProjectKey "Acme"

    Exports to C:\CSV\Acme\MailUsers_Fwd_Acme.csv

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    Tested   : 2025-02-24
#>

function Get-AllMailUserFwd {
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

        $outputFile   = Join-Path $folderPath "MailUsers_Fwd_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllMailUserFwd. Output: $outputFile" -Level Info
    }

    process {
        try {
            $mailUsers = Get-MailUser -ResultSize Unlimited -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve mail users: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($mu in $mailUsers) {
            Write-Verbose "Processing: $($mu.UserPrincipalName)"
            try {
                $results.Add([PSCustomObject]@{
                    DisplayName          = $mu.DisplayName
                    UserPrincipalName    = $mu.UserPrincipalName
                    ExternalEmailAddress = $mu.ExternalEmailAddress
                })
                $successCount++
            }
            catch {
                Write-Log "Failed to process mail user '$($mu.UserPrincipalName)': $($_.Exception.Message)" -Level Error
                $errorCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) mail users to: $outputFile" -Level Success
        } else {
            Write-Log "No mail users were exported." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllMailUserFwd'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
