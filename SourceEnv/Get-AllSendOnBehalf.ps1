<#
.SYNOPSIS
    Reports all mailboxes with SendOnBehalf delegation configured in the source tenant.

.DESCRIPTION
    Retrieves all user and shared mailboxes and exports those with GrantSendOnBehalfTo
    populated. This is a report-only script; delegation must be reconfigured manually
    in the destination tenant after mailboxes are provisioned.

    Output: <OutputCSV>\<ProjectKey>\SendOnBehalf_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllSendOnBehalf -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-AllSendOnBehalf {
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

        $outputFile   = Join-Path $folderPath "SendOnBehalf_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllSendOnBehalf. Output: $outputFile" -Level Info
    }

    process {
        try {
            $mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox, SharedMailbox -ResultSize Unlimited -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve mailboxes: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($mb in $mailboxes) {
            Write-Verbose "Processing: $($mb.PrimarySmtpAddress)"
            try {
                if ($mb.GrantSendOnBehalfTo.Count -gt 0) {
                    $delegates = ($mb.GrantSendOnBehalfTo | ForEach-Object {
                        try { (Get-Recipient -Identity $_ -ErrorAction Stop).PrimarySmtpAddress } catch { $_ }
                    }) -join ';'

                    $results.Add([PSCustomObject]@{
                        DisplayName        = $mb.DisplayName
                        PrimarySmtpAddress = $mb.PrimarySmtpAddress
                        RecipientType      = $mb.RecipientTypeDetails
                        SendOnBehalfTo     = $delegates
                    })
                    $successCount++
                }
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
            Write-Log "Exported $($results.Count) SendOnBehalf entries to: $outputFile" -Level Success
        } else {
            Write-Log "No SendOnBehalf delegations found." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllSendOnBehalf'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
