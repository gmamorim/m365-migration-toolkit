<#
.SYNOPSIS
    Configures forwarding on source tenant mailboxes to their corresponding destination addresses.

.DESCRIPTION
    Reads a CSV of source mailboxes (produced by Get-AllMailboxes), derives the destination
    address for each row using the same alias logic as the Import-* scripts, and sets
    ForwardingSmtpAddress with DeliverToMailboxAndForward = $true.

    This enables a co-existence period where mail is delivered to the source mailbox AND
    forwarded to the destination, ensuring no messages are lost during migration.

    Run this BEFORE cutover, after destination mailboxes have been provisioned and licensed.
    After cutover, use Remove-AllMailboxForwardingEXO (DestinationEnv) to clean up.

.PARAMETER CSVFile
    Full path to the input CSV. Required column: PrimarySmtpAddress.

.PARAMETER DestDomain
    Destination tenant SMTP domain used to build the forwarding address.
    Can be the onmicrosoft.com domain (e.g. "amorim.onmicrosoft.com") or a custom domain
    (e.g. "amorim.rocks") — whichever is active on the destination mailbox at the time.

.PARAMETER Prefix
    Optional. Prefix used when destination mailboxes were created (must match Import-* scripts).

.PARAMETER LogPath
    Optional. Full path to a log file. Output is appended.

.EXAMPLE
    Set-AllMailboxForwardingEXO -CSVFile "C:\CSV\Acme\Mailboxes_Acme.csv" `
        -DestDomain "amorim.rocks"

    Sets forwarding on all source mailboxes to their counterpart at amorim.rocks.

.EXAMPLE
    Set-AllMailboxForwardingEXO -CSVFile "C:\CSV\Acme\Mailboxes_Acme.csv" `
        -DestDomain "amorim.onmicrosoft.com" -WhatIf

    Dry-run — shows what forwarding would be configured without making changes.

.NOTES
    Author   : Gabriel Amorim
    Version  : 1.0
    Requires : ExchangeOnlineManagement module, active EXO session (source tenant)
    CSV In   : PrimarySmtpAddress (req)
    Note     : DeliverToMailboxAndForward is always set to $true — mail is delivered
               to the source mailbox AND forwarded to the destination.
#>

function Set-AllMailboxForwardingEXO {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CSVFile,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestDomain,

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
        Write-Log "Starting Set-AllMailboxForwardingEXO. CSV: $CSVFile | DestDomain: $DestDomain" -Level Info
    }

    process {
        $Rows = Import-Csv -Path $CSVFile -Encoding UTF8

        foreach ($Row in $Rows) {
            $localPart   = ($Row.PrimarySmtpAddress -split '@')[0]
            $aliasBase   = if ($Prefix) { "$Prefix-$localPart" } else { $localPart }
            $DestAddress = (($aliasBase -replace '[^a-zA-Z0-9._-]', '') + "@$DestDomain").ToLower()
            $SrcAddress  = $Row.PrimarySmtpAddress

            Write-Verbose "Processing: $SrcAddress → $DestAddress"

            try {
                $mb = Get-Mailbox -Identity $SrcAddress -ErrorAction Stop
            }
            catch {
                Write-Log "Mailbox '$SrcAddress' not found in source tenant. Skipping." -Level Warning
                $skipped++
                continue
            }

            if ($mb.ForwardingSmtpAddress -eq "smtp:$DestAddress") {
                Write-Verbose "Forwarding already set on '$SrcAddress'. Skipping."
                $skipped++
                continue
            }

            if ($PSCmdlet.ShouldProcess($SrcAddress, "Set forwarding to $DestAddress")) {
                try {
                    Set-Mailbox -Identity $SrcAddress `
                        -ForwardingSmtpAddress "smtp:$DestAddress" `
                        -DeliverToMailboxAndForward $true `
                        -ErrorAction Stop
                    Write-Log "Forwarding set: $SrcAddress → $DestAddress" -Level Success
                    $successCount++
                }
                catch {
                    Write-Log "Failed to set forwarding on '$SrcAddress': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        Write-Log "Summary | Configured: $successCount | Already set (skipped): $skipped | Failed: $errorCount" -Level Info
        [PSCustomObject]@{
            Function     = 'Set-AllMailboxForwardingEXO'
            Succeeded    = $successCount
            Failed       = $errorCount
            Skipped      = $skipped
            Total        = $successCount + $errorCount + $skipped
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
