<#
.SYNOPSIS
    Adds source SMTP addresses as secondary aliases to destination shared mailboxes.

.DESCRIPTION
    Looks up each shared mailbox in the destination tenant using the destination alias
    derived from the source local part, and adds the original source PrimarySmtpAddress
    as a secondary SMTP address.

    This preserves source email addresses as aliases so that messages sent to the
    old address continue to be delivered.

.PARAMETER CSVFile
    Full path to the input CSV. Required column: PrimarySmtpAddress.

.PARAMETER Domain
    Destination tenant SMTP domain.

.PARAMETER Prefix
    Optional. Prefix used when the mailboxes were created (must match what was used in Import-AllSharedMailboxes).

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Update-AllSharedMailboxesAliases -CSVFile "C:\CSV\Contoso\Shared_Mailboxes_Contoso.csv" `
        -Domain "amorim.rocks"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : PrimarySmtpAddress (req)
#>

function Update-AllSharedMailboxesAliases {
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
        if ('PrimarySmtpAddress' -notin $headers) { throw "CSV missing required column: 'PrimarySmtpAddress'" }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Update-AllSharedMailboxesAliases. CSV: $CSVFile" -Level Info
    }

    process {
        $Mailboxes = Import-Csv -Path $CSVFile -Encoding UTF8

        foreach ($Mailbox in $Mailboxes) {
            $localPart  = ($Mailbox.PrimarySmtpAddress -split '@')[0]
            $aliasBase  = if ($Prefix) { "$Prefix-$localPart" } else { $localPart }
            $DestAlias  = ("$aliasBase@$Domain" -replace '[^a-zA-Z0-9.@_-]', '').ToLower()
            $SourceSMTP = $Mailbox.PrimarySmtpAddress

            Write-Verbose "Looking up '$DestAlias' to add alias '$SourceSMTP'"

            try {
                $ExistingMailbox = Get-Mailbox -Identity $DestAlias -ErrorAction Stop

                if ($PSCmdlet.ShouldProcess($ExistingMailbox.PrimarySmtpAddress, "Add alias '$SourceSMTP'")) {
                    try {
                        Set-Mailbox -Identity $ExistingMailbox.Identity `
                            -EmailAddresses @{ add = "smtp:$SourceSMTP" } -ErrorAction Stop
                        Write-Log "Added alias '$SourceSMTP' to '$($ExistingMailbox.PrimarySmtpAddress)'." -Level Success
                        $successCount++
                    }
                    catch {
                        Write-Log "Failed to add alias '$SourceSMTP' to '$DestAlias': $($_.Exception.Message)" -Level Error
                        $errorCount++
                    }
                }
            }
            catch {
                Write-Log "Mailbox '$DestAlias' not found in destination. Skipping." -Level Warning
                $errorCount++
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Update-AllSharedMailboxesAliases'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
