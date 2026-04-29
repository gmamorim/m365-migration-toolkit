<#
.SYNOPSIS
    Exports details for specific resource mailboxes listed in an input CSV.

.DESCRIPTION
    Reads a list of PrimarySmtpAddress values from the input CSV and retrieves
    full resource mailbox details (capacity, location, booking delegates, etc.) for each.

    Output: <OutputCSV>\<ProjectKey>\Resource_Mailboxes_<ProjectKey>.csv

.PARAMETER InputCSV
    Path to the input CSV file. Must contain a 'PrimarySmtpAddress' column.

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-CSVResourceMailboxes -InputCSV "C:\CSV\Acme\resource_list.csv" `
        -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : PrimarySmtpAddress (required)
    CSV Out  : ResourceType, DisplayName, PrimarySmtpAddress, Alias, BookingDelegates,
               Capacity, Location, Telephone, Department, Company, ADP,
               Street, City, StateProvince, Zip, Country
#>

function Get-CSVResourceMailboxes {
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

        $headers = (Get-Content $InputCSV -TotalCount 1) -split ',' | ForEach-Object { $_.Trim('"').Trim() }
        if ('PrimarySmtpAddress' -notin $headers) {
            throw "InputCSV is missing required column: 'PrimarySmtpAddress'"
        }

        $folderPath = Join-Path $OutputCSV $ProjectKey
        if (-not (Test-Path $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        }

        $outputFile   = Join-Path $folderPath "Resource_Mailboxes_$ProjectKey.csv"
        $successCount = 0
        $notFound     = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-CSVResourceMailboxes. Input: $InputCSV | Output: $outputFile" -Level Info
    }

    process {
        $mailboxList = Import-Csv -Path $InputCSV -Encoding UTF8 | Select-Object -ExpandProperty PrimarySmtpAddress

        if (-not $mailboxList) {
            Write-Log "Input CSV contains no addresses." -Level Warning
            return
        }

        foreach ($address in $mailboxList) {
            Write-Verbose "Looking up: $address"
            try {
                $mbx = Get-Mailbox -Identity $address -ErrorAction Stop

                if ($mbx.RecipientTypeDetails -notin @('RoomMailbox', 'EquipmentMailbox')) {
                    Write-Log "'$address' is not a resource mailbox (type: $($mbx.RecipientTypeDetails)). Skipping." -Level Warning
                    $notFound++
                    continue
                }

                $resourceType = if ($mbx.RecipientTypeDetails -eq 'RoomMailbox') { 'Room' } else { 'Equipment' }

                $bookingDelegates = ''
                try {
                    $cal = Get-CalendarProcessing -Identity $address -ErrorAction Stop
                    $bookingDelegates = if ($cal.ResourceDelegates) { $cal.ResourceDelegates -join ';' } else { '' }
                } catch {
                    Write-Log "Warning: Could not get CalendarProcessing for '$address': $($_.Exception.Message)" -Level Warning
                }

                $user = $null
                try {
                    $user = Get-User -Identity $address -ErrorAction Stop
                } catch {
                    Write-Log "Warning: Could not get User details for '$address': $($_.Exception.Message)" -Level Warning
                }

                $results.Add([PSCustomObject]@{
                    ResourceType       = $resourceType
                    DisplayName        = $mbx.DisplayName
                    PrimarySmtpAddress = $mbx.PrimarySmtpAddress
                    Alias              = $mbx.Alias
                    BookingDelegates   = $bookingDelegates
                    Capacity           = $mbx.ResourceCapacity
                    Location           = $user?.Office
                    Telephone          = $user?.Phone
                    Department         = $user?.Department
                    Company            = $user?.Company
                    ADP                = $mbx.AddressBookPolicy
                    Street             = $user?.StreetAddress
                    City               = $user?.City
                    StateProvince      = $user?.StateOrProvince
                    Zip                = $user?.PostalCode
                    Country            = $user?.CountryOrRegion
                })
                $successCount++
            }
            catch {
                if ($_.Exception.Message -match "couldn't be found|cannot be found") {
                    Write-Log "Resource mailbox not found: '$address'" -Level Warning
                    $notFound++
                } else {
                    Write-Log "Error retrieving resource mailbox '$address': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) resource mailboxes to: $outputFile" -Level Success
        } else {
            Write-Log "No resource mailboxes were exported." -Level Warning
        }

        Write-Log "Summary | Found: $successCount | Not Found/Skipped: $notFound | Errors: $errorCount" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-CSVResourceMailboxes'
            Succeeded    = $successCount
            Failed       = $errorCount + $notFound
            Total        = $successCount + $errorCount + $notFound
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
