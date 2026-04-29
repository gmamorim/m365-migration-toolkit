<#
.SYNOPSIS
    Exports details for specific mailboxes listed in an input CSV.

.DESCRIPTION
    Reads a list of PrimarySmtpAddress values from the input CSV and retrieves
    the mailbox details for each. Useful when you need to export a subset of
    mailboxes rather than the entire tenant.

    Output: <OutputCSV>\<ProjectKey>\Mailboxes_<ProjectKey>.csv

.PARAMETER InputCSV
    Path to the input CSV file. Must contain a 'PrimarySmtpAddress' column.

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-CSVMailboxes -InputCSV "C:\CSV\Acme\mailbox_list.csv" `
        -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : PrimarySmtpAddress (required)
    CSV Out  : DisplayName, PrimarySmtpAddress, EmailAddresses, RecipientType, AddressBookPolicy
#>

function Get-CSVMailboxes {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$InputCSV,

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

        # Validate CSV columns
        $headers = (Get-Content $InputCSV -TotalCount 1) -split ',' | ForEach-Object { $_.Trim('"').Trim() }
        if ('PrimarySmtpAddress' -notin $headers) {
            throw "InputCSV is missing required column: 'PrimarySmtpAddress'"
        }

        $folderPath = Join-Path $OutputCSV $ProjectKey
        if (-not (Test-Path $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        }

        $outputFile   = Join-Path $folderPath "Mailboxes_$ProjectKey.csv"
        $successCount = 0
        $notFound     = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-CSVMailboxes. Input: $InputCSV | Output: $outputFile" -Level Info
    }

    process {
        $mailboxList = Import-Csv -Path $InputCSV -Encoding UTF8 | Select-Object -ExpandProperty PrimarySmtpAddress

        if (-not $mailboxList) {
            Write-Log "Input CSV contains no mailbox addresses." -Level Warning
            return
        }

        foreach ($address in $mailboxList) {
            Write-Verbose "Looking up: $address"
            try {
                $mbx = Get-Mailbox -Identity $address -ErrorAction Stop

                $emailAddresses = ($mbx.EmailAddresses |
                    ForEach-Object { $_.ToString() -replace '^(SMTP|smtp):', '' } |
                    Where-Object { $_ -notmatch 'onmicrosoft|SPO:|SIP:' }) -join ';'

                $results.Add([PSCustomObject]@{
                    DisplayName        = $mbx.DisplayName
                    PrimarySmtpAddress = $mbx.PrimarySmtpAddress
                    EmailAddresses     = $emailAddresses
                    RecipientType      = $mbx.RecipientTypeDetails
                    AddressBookPolicy  = $mbx.AddressBookPolicy
                })
                $successCount++
            }
            catch {
                if ($_.Exception.Message -match "couldn't be found|cannot be found") {
                    Write-Log "Mailbox not found: '$address'" -Level Warning
                    $notFound++
                } else {
                    Write-Log "Error retrieving mailbox '$address': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
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

        Write-Log "Summary | Found: $successCount | Not Found: $notFound | Errors: $errorCount" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-CSVMailboxes'
            Succeeded    = $successCount
            Failed       = $errorCount + $notFound
            Total        = $successCount + $errorCount + $notFound
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
