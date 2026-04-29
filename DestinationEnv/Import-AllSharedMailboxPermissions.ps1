<#
.SYNOPSIS
    Assigns FullAccess and SendAs permissions to shared mailboxes in the destination tenant.

.DESCRIPTION
    Reads a CSV produced by Get-AllSharedMailboxes and, for each row, derives the
    destination alias from the source PrimarySmtpAddress local part, then grants
    FullAccess and SendAs to the users listed in the FullAccessUsers and SendAsUsers columns.

    Only entries that contain '@' are processed (invalid entries are skipped with a warning).

.PARAMETER CSVFile
    Full path to the input CSV.
    Required columns: PrimarySmtpAddress, FullAccessUsers (semicolon-separated), SendAsUsers (semicolon-separated).

.PARAMETER Domain
    Destination tenant SMTP domain.

.PARAMETER Prefix
    Optional. Prefix used when the mailboxes were created (must match what was used in Import-AllSharedMailboxes).

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Import-AllSharedMailboxPermissions -CSVFile "C:\CSV\Contoso\Shared_Mailboxes_Contoso.csv" `
        -Domain "amorim.rocks"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : PrimarySmtpAddress (req), FullAccessUsers (semicolon-sep), SendAsUsers (semicolon-sep)
#>

function Import-AllSharedMailboxPermissions {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
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
        foreach ($col in @('PrimarySmtpAddress', 'FullAccessUsers', 'SendAsUsers')) {
            if ($col -notin $headers) { throw "CSV missing required column: '$col'" }
        }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Import-AllSharedMailboxPermissions. CSV: $CSVFile" -Level Info
    }

    process {
        $Mailboxes = Import-Csv -Path $CSVFile -Encoding UTF8

        foreach ($Mailbox in $Mailboxes) {
            $localPart = ($Mailbox.PrimarySmtpAddress -split '@')[0]
            $aliasBase = if ($Prefix) { "$Prefix-$localPart" } else { $localPart }
            $Alias     = ($aliasBase -replace '[^a-zA-Z0-9._-]', '').ToLower()
            $PrimarySmtpAddress = "$Alias@$Domain"

            Write-Verbose "Processing permissions for: $PrimarySmtpAddress"

            $FullAccessUsers = $Mailbox.FullAccessUsers -split ';' | Where-Object { $_ -match '@' }
            $SendAsUsers     = $Mailbox.SendAsUsers     -split ';' | Where-Object { $_ -match '@' }

            foreach ($User in $FullAccessUsers) {
                $CleanUser = $User.Trim()
                if ($PSCmdlet.ShouldProcess($PrimarySmtpAddress, "Grant FullAccess to '$CleanUser'")) {
                    try {
                        Add-MailboxPermission -Identity $PrimarySmtpAddress -User $CleanUser `
                            -AccessRights FullAccess -Confirm:$false -ErrorAction Stop | Out-Null
                        Write-Log "FullAccess granted to '$CleanUser' on '$PrimarySmtpAddress'." -Level Success
                        $successCount++
                    }
                    catch {
                        Write-Log "Failed FullAccess '$CleanUser' on '$PrimarySmtpAddress': $($_.Exception.Message)" -Level Error
                        $errorCount++
                    }
                }
            }

            foreach ($User in $SendAsUsers) {
                $CleanUser = $User.Trim()
                if ($PSCmdlet.ShouldProcess($PrimarySmtpAddress, "Grant SendAs to '$CleanUser'")) {
                    try {
                        Add-RecipientPermission -Identity $PrimarySmtpAddress -Trustee $CleanUser `
                            -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
                        Write-Log "SendAs granted to '$CleanUser' on '$PrimarySmtpAddress'." -Level Success
                        $successCount++
                    }
                    catch {
                        Write-Log "Failed SendAs '$CleanUser' on '$PrimarySmtpAddress': $($_.Exception.Message)" -Level Error
                        $errorCount++
                    }
                }
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Import-AllSharedMailboxPermissions'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
