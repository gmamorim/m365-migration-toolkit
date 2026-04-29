<#
.SYNOPSIS
    Exports all mailboxes with Litigation Hold enabled from the source tenant to CSV.

.DESCRIPTION
    Retrieves all user mailboxes and exports those with LitigationHoldEnabled = True,
    including hold duration and date. The output CSV is used by Import-AllLitigationHold
    to apply the same holds in the destination tenant.

    Requires E3/E5 or equivalent license in the destination tenant to apply holds.

    Output: <OutputCSV>\<ProjectKey>\Litigation_Hold_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllLitigationHold -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-AllLitigationHold {
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

        $outputFile   = Join-Path $folderPath "Litigation_Hold_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllLitigationHold. Output: $outputFile" -Level Info
    }

    process {
        try {
            $mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited `
                -Filter { LitigationHoldEnabled -eq $true } -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve mailboxes: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($mb in $mailboxes) {
            Write-Verbose "Processing: $($mb.PrimarySmtpAddress)"
            try {
                $results.Add([PSCustomObject]@{
                    DisplayName              = $mb.DisplayName
                    PrimarySmtpAddress       = $mb.PrimarySmtpAddress
                    LitigationHoldEnabled    = $mb.LitigationHoldEnabled
                    LitigationHoldDuration   = $mb.LitigationHoldDuration
                    LitigationHoldDate       = $mb.LitigationHoldDate
                    LitigationHoldOwner      = $mb.LitigationHoldOwner
                })
                $successCount++
            }
            catch {
                Write-Log "Failed to process '$($mb.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Error
                $errorCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) litigation hold entries to: $outputFile" -Level Success
        } else {
            Write-Log "No mailboxes with Litigation Hold enabled were found." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllLitigationHold'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
