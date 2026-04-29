<#
.SYNOPSIS
    Creates shared mailboxes in the destination tenant from a source CSV.

.DESCRIPTION
    For each row in the CSV, resolves a unique destination alias using Resolve-UniqueAlias
    (which checks Get-Recipient in the destination tenant to avoid collisions) and creates
    a shared mailbox. If forwarding data is present, configures it after creation.

    Alias format: <sourceLocalPart>@<Domain>
    Collision handling: john.smith -> john.smith2 -> john.smith3 ...

    DisplayName format: '<Company> - <SourceDisplayName>' when Company is provided,
    otherwise uses the source DisplayName as-is.

.PARAMETER CSVFile
    Full path to the input CSV. Required columns: DisplayName, PrimarySmtpAddress.
    Optional columns: ForwardingAddress, ForwardingSmtpAddress, DeliverToMailboxAndForward.

.PARAMETER Domain
    Destination tenant SMTP domain (e.g. "acme.com").

.PARAMETER Company
    Optional. Company name prepended to DisplayName (e.g. "Contoso").

.PARAMETER Prefix
    Optional. Short prefix prepended to the alias (e.g. a department or project code).
    When provided: <Prefix>-<localPart>@<Domain>.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Import-AllSharedMailboxes -CSVFile "C:\CSV\Contoso\Shared_Mailboxes_Contoso.csv" `
        -Domain "amorim.rocks"

.EXAMPLE
    Import-AllSharedMailboxes -CSVFile "C:\CSV\Contoso\Shared_Mailboxes_Contoso.csv" `
        -Domain "amorim.rocks" -Company "Contoso" -WhatIf

    Dry-run — shows what would be created without making changes.

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : DisplayName (req), PrimarySmtpAddress (req),
               ForwardingAddress, ForwardingSmtpAddress, DeliverToMailboxAndForward
#>

function Import-AllSharedMailboxes {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CSVFile,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

        [Parameter(Mandatory = $false)]
        [string]$Company,

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
        foreach ($col in @('DisplayName', 'PrimarySmtpAddress')) {
            if ($col -notin $headers) { throw "CSV missing required column: '$col'" }
        }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Import-AllSharedMailboxes. CSV: $CSVFile" -Level Info
    }

    process {
        $Mailboxes = Import-Csv -Path $CSVFile -Encoding UTF8

        foreach ($Mailbox in $Mailboxes) {
            $resolveParams = @{ SourceAddress = $Mailbox.PrimarySmtpAddress; Domain = $Domain }
            if ($Prefix) { $resolveParams['Prefix'] = $Prefix }

            $PrimarySmtpAddress   = Resolve-UniqueAlias @resolveParams
            $Alias                = ($PrimarySmtpAddress -split '@')[0]
            $FormattedDisplayName = if ($Company) { "$Company - $($Mailbox.DisplayName)" } else { $Mailbox.DisplayName }

            Write-Verbose "Processing: $FormattedDisplayName -> $PrimarySmtpAddress"

            if ($PSCmdlet.ShouldProcess($PrimarySmtpAddress, 'Create shared mailbox')) {
                try {
                    New-Mailbox -Shared -Name $FormattedDisplayName -DisplayName $FormattedDisplayName `
                        -Alias $Alias -PrimarySmtpAddress $PrimarySmtpAddress -ErrorAction Stop -Confirm:$false

                    if ($Mailbox.ForwardingAddress -or $Mailbox.ForwardingSmtpAddress) {
                        $deliverAndFwd = $false
                        if ($Mailbox.DeliverToMailboxAndForward) {
                            try { $deliverAndFwd = [System.Convert]::ToBoolean($Mailbox.DeliverToMailboxAndForward) } catch { $deliverAndFwd = $false }
                        }
                        Set-Mailbox -Identity $PrimarySmtpAddress `
                            -ForwardingAddress     $Mailbox.ForwardingAddress `
                            -ForwardingSmtpAddress $Mailbox.ForwardingSmtpAddress `
                            -DeliverToMailboxAndForward $deliverAndFwd
                    }

                    Write-Log "Created shared mailbox '$FormattedDisplayName' ($PrimarySmtpAddress)." -Level Success
                    $successCount++
                }
                catch {
                    Write-Log "Failed to create '$FormattedDisplayName': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Import-AllSharedMailboxes'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
