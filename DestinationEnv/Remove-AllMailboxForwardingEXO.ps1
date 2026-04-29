<#
.SYNOPSIS
    Removes forwarding settings from mailboxes in Exchange Online, scoped to a CSV file.

.DESCRIPTION
    Reads a CSV of source mailboxes (produced by Get-AllMailboxes or Get-AllSharedMailboxes),
    derives the destination address for each row, and clears ForwardingAddress and
    ForwardingSmtpAddress on any mailbox that has forwarding configured.

    Using the CSV as scope ensures only objects belonging to this migration project are
    touched, regardless of what else exists in the destination tenant.

    Run this AFTER the migration cutover to stop forwarding from the destination tenant
    to the source addresses.

.PARAMETER CSVFile
    Full path to the input CSV. Required column: PrimarySmtpAddress.

.PARAMETER Domain
    Destination tenant SMTP domain. Used to derive the destination address from the source.

.PARAMETER Prefix
    Optional. Prefix used when the mailboxes were created (must match what was used in Import-*).

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Remove-AllMailboxForwardingEXO -CSVFile "C:\CSV\Contoso\Mailboxes_Contoso.csv" `
        -Domain "amorim.rocks"

.EXAMPLE
    Remove-AllMailboxForwardingEXO -CSVFile "C:\CSV\Contoso\Mailboxes_Contoso.csv" `
        -Domain "amorim.rocks" -WhatIf

    Dry-run — shows which mailboxes would have forwarding removed.

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : PrimarySmtpAddress (req)
#>

function Remove-AllMailboxForwardingEXO {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CSVFile,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

        [Parameter(Mandatory = $false)]
        [string]$Prefix,

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
        if ('PrimarySmtpAddress' -notin $headers) { throw "CSV missing required column: 'PrimarySmtpAddress'" }

        $successCount = 0
        $errorCount   = 0
        $skipped      = 0
        Write-Log "Starting Remove-AllMailboxForwardingEXO. CSV: $CSVFile | Domain: $Domain" -Level Info
    }

    process {
        $Rows = Import-Csv -Path $CSVFile -Encoding UTF8

        foreach ($Row in $Rows) {
            $localPart  = ($Row.PrimarySmtpAddress -split '@')[0]
            $aliasBase  = if ($Prefix) { "$Prefix-$localPart" } else { $localPart }
            $DestAddress = (($aliasBase -replace '[^a-zA-Z0-9._-]', '') + "@$Domain").ToLower()

            Write-Verbose "Checking forwarding on: $DestAddress"

            try {
                $mb = Get-Mailbox -Identity $DestAddress -ErrorAction Stop
            }
            catch {
                Write-Log "Mailbox '$DestAddress' not found. Skipping." -Level Warning
                $skipped++
                continue
            }

            if (-not $mb.ForwardingAddress -and -not $mb.ForwardingSmtpAddress) {
                Write-Verbose "No forwarding on '$DestAddress'. Skipping."
                $skipped++
                continue
            }

            if ($PSCmdlet.ShouldProcess($DestAddress, 'Remove mailbox forwarding')) {
                try {
                    Set-Mailbox -Identity $DestAddress `
                        -ForwardingAddress $null `
                        -ForwardingSmtpAddress $null `
                        -ErrorAction Stop
                    Write-Log "Forwarding removed from '$DestAddress'." -Level Success
                    $successCount++
                }
                catch {
                    Write-Log "Failed to remove forwarding from '$DestAddress': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        Write-Log "Summary | Removed: $successCount | No forwarding (skipped): $skipped | Failed: $errorCount" -Level Info
        [PSCustomObject]@{
            Function     = 'Remove-AllMailboxForwardingEXO'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount + $skipped
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
