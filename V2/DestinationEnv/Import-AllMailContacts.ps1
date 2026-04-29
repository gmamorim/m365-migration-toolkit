<#
.SYNOPSIS
    Creates mail contacts (external recipients) in the destination tenant from a CSV.

.DESCRIPTION
    Mail contacts are external email addresses that appear in the Global Address List.
    For each row in the CSV, a MailContact is created with the provided DisplayName
    and ExternalEmailAddress. An optional Alias can be specified; if omitted, it is
    derived from the ExternalEmailAddress.

.PARAMETER CSVFile
    Full path to the input CSV.
    Required columns: DisplayName, ExternalEmailAddress.
    Optional columns: Alias.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Import-AllMailContacts -CSVFile "C:\CSV\Acme\Mail_Contacts_Acme.csv"

.EXAMPLE
    Import-AllMailContacts -CSVFile "C:\CSV\Acme\Mail_Contacts_Acme.csv" -WhatIf

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : DisplayName (req), ExternalEmailAddress (req), Alias (optional)
#>

function Import-AllMailContacts {
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
        foreach ($col in @('DisplayName', 'ExternalEmailAddress')) {
            if ($col -notin $headers) { throw "CSV missing required column: '$col'" }
        }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Import-AllMailContacts. CSV: $CSVFile" -Level Info
    }

    process {
        $Contacts = Import-Csv -Path $CSVFile -Encoding UTF8

        foreach ($Contact in $Contacts) {
            # Build alias from email local part if not provided
            $alias = if ($Contact.PSObject.Properties.Name -contains 'Alias' -and $Contact.Alias) {
                $Contact.Alias
            } else {
                (($Contact.ExternalEmailAddress -split '@')[0] -replace '[^a-zA-Z0-9._-]', '').ToLower()
            }

            Write-Verbose "Processing: $($Contact.DisplayName) -> $($Contact.ExternalEmailAddress)"

            if ($PSCmdlet.ShouldProcess($Contact.ExternalEmailAddress, "Create mail contact '$($Contact.DisplayName)'")) {
                try {
                    New-MailContact -Name $Contact.DisplayName -DisplayName $Contact.DisplayName `
                        -ExternalEmailAddress $Contact.ExternalEmailAddress `
                        -Alias $alias -ErrorAction Stop -Confirm:$false | Out-Null
                    Write-Log "Created mail contact '$($Contact.DisplayName)' ($($Contact.ExternalEmailAddress))." -Level Success
                    $successCount++
                }
                catch {
                    Write-Log "Failed to create contact '$($Contact.DisplayName)': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Import-AllMailContacts'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
