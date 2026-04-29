<#
.SYNOPSIS
    Applies Litigation Hold to mailboxes in the destination tenant from a source CSV.

.DESCRIPTION
    For each row in the CSV, locates the matching mailbox in the destination tenant
    by PrimarySmtpAddress and enables Litigation Hold with the original duration.

    Requires E3/E5 or equivalent license assigned to the destination mailbox.
    Mailboxes must already exist in the destination tenant before running this script.

.PARAMETER CSVFile
    Full path to the input CSV. Required columns: PrimarySmtpAddress, LitigationHoldEnabled.
    Optional columns: LitigationHoldDuration, LitigationHoldOwner.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Import-AllLitigationHold -CSVFile "C:\CSV\Acme\Litigation_Hold_Acme.csv"

.EXAMPLE
    Import-AllLitigationHold -CSVFile "C:\CSV\Acme\Litigation_Hold_Acme.csv" -WhatIf

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : PrimarySmtpAddress (req), LitigationHoldEnabled (req),
               LitigationHoldDuration (opt), LitigationHoldOwner (opt)
#>

function Import-AllLitigationHold {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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
        foreach ($col in @('PrimarySmtpAddress', 'LitigationHoldEnabled')) {
            if ($col -notin $headers) { throw "CSV missing required column: '$col'" }
        }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Import-AllLitigationHold. CSV: $CSVFile" -Level Info
    }

    process {
        try {
            $entries = Import-Csv -Path $CSVFile -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to import CSV: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($entry in $entries) {
            if ($entry.LitigationHoldEnabled -ne 'True') { continue }

            Write-Verbose "Processing: $($entry.PrimarySmtpAddress)"

            if ($PSCmdlet.ShouldProcess($entry.PrimarySmtpAddress, 'Enable Litigation Hold')) {
                try {
                    $setParams = @{
                        Identity               = $entry.PrimarySmtpAddress
                        LitigationHoldEnabled  = $true
                        ErrorAction            = 'Stop'
                    }

                    if ($entry.LitigationHoldDuration -and $entry.LitigationHoldDuration -notin @('', 'Unlimited')) {
                        $setParams['LitigationHoldDuration'] = $entry.LitigationHoldDuration
                    }

                    if ($entry.LitigationHoldOwner -and $entry.LitigationHoldOwner -ne '') {
                        $setParams['LitigationHoldOwner'] = $entry.LitigationHoldOwner
                    }

                    Set-Mailbox @setParams
                    Write-Log "Enabled Litigation Hold for '$($entry.PrimarySmtpAddress)'." -Level Success
                    $successCount++
                }
                catch {
                    Write-Log "Failed to set hold for '$($entry.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Import-AllLitigationHold'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
