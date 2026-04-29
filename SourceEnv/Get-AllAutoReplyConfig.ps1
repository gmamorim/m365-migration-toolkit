<#
.SYNOPSIS
    Reports all mailboxes with auto-reply (OOF) configured in the source tenant.

.DESCRIPTION
    Retrieves Get-MailboxAutoReplyConfiguration for all user mailboxes and exports
    only those with AutoReplyState set to Enabled or Scheduled.

    This is a report-only script. Auto-reply settings must be reconfigured manually
    in the destination tenant by the user or administrator.

    Output: <OutputCSV>\<ProjectKey>\AutoReply_Config_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllAutoReplyConfig -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-AllAutoReplyConfig {
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

        $outputFile   = Join-Path $folderPath "AutoReply_Config_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllAutoReplyConfig. Output: $outputFile" -Level Info
    }

    process {
        try {
            $mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve mailboxes: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($mb in $mailboxes) {
            Write-Verbose "Processing: $($mb.PrimarySmtpAddress)"
            try {
                $config = Get-MailboxAutoReplyConfiguration -Identity $mb.Identity -ErrorAction Stop

                if ($config.AutoReplyState -ne 'Disabled') {
                    $results.Add([PSCustomObject]@{
                        DisplayName          = $mb.DisplayName
                        PrimarySmtpAddress   = $mb.PrimarySmtpAddress
                        AutoReplyState       = $config.AutoReplyState
                        StartTime            = $config.StartTime
                        EndTime              = $config.EndTime
                        InternalMessage      = $config.InternalMessage
                        ExternalMessage      = $config.ExternalAudience + ' | ' + $config.ExternalMessage
                    })
                    $successCount++
                }
            }
            catch {
                Write-Log "Failed to get auto-reply config for '$($mb.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Error
                $errorCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) auto-reply configurations to: $outputFile" -Level Success
        } else {
            Write-Log "No active auto-reply configurations found." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllAutoReplyConfig'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
