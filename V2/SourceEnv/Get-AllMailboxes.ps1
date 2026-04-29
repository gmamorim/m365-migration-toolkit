<#
.SYNOPSIS
    Exports all user mailboxes from the connected Exchange Online tenant to CSV.

.DESCRIPTION
    Retrieves all UserMailbox objects and exports DisplayName, PrimarySmtpAddress,
    Alias, RecipientType, AddressBookPolicy, and filtered EmailAddresses (SIP, SPO,
    and onmicrosoft.com addresses are excluded).

    The output file is saved to: <OutputCSV>\<ProjectKey>\Mailboxes_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory where the project CSV subfolder will be created.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file. Output is appended.

.EXAMPLE
    Get-AllMailboxes -OutputCSV "C:\CSV" -ProjectKey "Acme"

    Exports all mailboxes to C:\CSV\Acme\Mailboxes_Acme.csv

.EXAMPLE
    Get-AllMailboxes -OutputCSV "C:\CSV" -ProjectKey "Acme" -LogPath "C:\CSV\Acme\Logs\export.log" -Verbose

    Exports with verbose per-mailbox output and writes a log file.

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    Tested   : 2025-03-11
#>

function Get-AllMailboxes {
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

        $outputFile    = Join-Path $folderPath "Mailboxes_$ProjectKey.csv"
        $successCount  = 0
        $errorCount    = 0
        $results       = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllMailboxes. Output: $outputFile" -Level Info
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
                $user = Get-User -Identity $mb.Identity -ErrorAction Stop

                $filteredEmails = ($mb.EmailAddresses | Where-Object {
                    $_ -notmatch '^(SIP|sip|SPO):' -and
                    $_ -notmatch '@.*\.onmicrosoft\.com$'
                }) -join ';'

                $results.Add([PSCustomObject]@{
                    DisplayName        = $mb.DisplayName
                    PrimarySmtpAddress = $mb.PrimarySmtpAddress
                    Alias              = $mb.Alias
                    RecipientType      = $mb.RecipientTypeDetails
                    AddressBookPolicy  = $mb.AddressBookPolicy
                    EmailAddresses     = $filteredEmails
                })
                $successCount++
            }
            catch {
                Write-Log "Failed to process mailbox '$($mb.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Error
                $errorCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) mailboxes to: $outputFile" -Level Success
        } else {
            Write-Log "No mailboxes were exported." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllMailboxes'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
