<#
.SYNOPSIS
    Exports all shared mailboxes with permissions and forwarding settings to CSV.

.DESCRIPTION
    Retrieves all SharedMailbox objects and exports DisplayName, PrimarySmtpAddress,
    Alias, EmailAddresses, FullAccessUsers, SendAsUsers, ForwardingAddress,
    ForwardingSmtpAddress, and DeliverToMailboxAndForward.

    Permission queries (Get-MailboxPermission, Get-RecipientPermission) are wrapped
    in individual try/catch blocks — a failure on one mailbox does not abort the export.

    Output: <OutputCSV>\<ProjectKey>\Shared_Mailboxes_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllSharedMailboxes -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    Tested   : 2025-03-11
#>

function Get-AllSharedMailboxes {
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

        $outputFile   = Join-Path $folderPath "Shared_Mailboxes_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllSharedMailboxes. Output: $outputFile" -Level Info
    }

    process {
        try {
            $mailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve shared mailboxes: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($mb in $mailboxes) {
            Write-Verbose "Processing: $($mb.PrimarySmtpAddress)"
            try {
                # Permissions — non-fatal per mailbox
                $fullAccessUsers = @()
                try {
                    $fullAccessUsers = (Get-MailboxPermission -Identity $mb.Identity -ErrorAction Stop |
                        Where-Object { $_.IsInherited -eq $false -and $_.User -notlike 'NT AUTHORITY*' -and $_.AccessRights -contains 'FullAccess' } |
                        Select-Object -ExpandProperty User) -join ';'
                } catch {
                    Write-Log "Warning: Could not retrieve FullAccess permissions for '$($mb.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Warning
                    $fullAccessUsers = ''
                }

                $sendAsUsers = @()
                try {
                    $sendAsUsers = (Get-RecipientPermission -Identity $mb.Identity -ErrorAction Stop |
                        Where-Object { $_.IsInherited -eq $false -and $_.Trustee -notlike 'NT AUTHORITY*' } |
                        Select-Object -ExpandProperty Trustee) -join ';'
                } catch {
                    Write-Log "Warning: Could not retrieve SendAs permissions for '$($mb.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Warning
                    $sendAsUsers = ''
                }

                $filteredEmails = ($mb.EmailAddresses | Where-Object {
                    $_ -notmatch '^(SIP|sip|SPO):' -and $_ -notmatch '@.*\.onmicrosoft\.com$'
                }) -join ';'

                $results.Add([PSCustomObject]@{
                    DisplayName                = $mb.DisplayName
                    PrimarySmtpAddress         = $mb.PrimarySmtpAddress
                    Alias                      = $mb.Alias
                    EmailAddresses             = $filteredEmails
                    FullAccessUsers            = $fullAccessUsers
                    SendAsUsers                = $sendAsUsers
                    ForwardingAddress          = $mb.ForwardingAddress
                    ForwardingSmtpAddress      = $mb.ForwardingSmtpAddress
                    DeliverToMailboxAndForward = $mb.DeliverToMailboxAndForward
                })
                $successCount++
            }
            catch {
                Write-Log "Failed to process shared mailbox '$($mb.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Error
                $errorCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) shared mailboxes to: $outputFile" -Level Success
        } else {
            Write-Log "No shared mailboxes were exported." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllSharedMailboxes'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
