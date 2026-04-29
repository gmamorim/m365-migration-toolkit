<#
.SYNOPSIS
    Creates Address Book Policies in the destination tenant from a source CSV.

.DESCRIPTION
    For each row in the CSV, creates an AddressBookPolicy using the exported
    address lists, room list, offline address book, and global address list names.

    Prerequisites: All referenced address lists, room lists, OABs, and GALs must
    already exist in the destination tenant before running this script.

.PARAMETER CSVFile
    Full path to the input CSV (output of Get-AllAddressBookPolicies).
    Required columns: Name, GlobalAddressList, OfflineAddressBook, RoomList, AddressLists.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Import-AllAddressBookPolicies -CSVFile "C:\CSV\Acme\Address_Book_Policies_Acme.csv"

.EXAMPLE
    Import-AllAddressBookPolicies -CSVFile "C:\CSV\Acme\Address_Book_Policies_Acme.csv" -WhatIf

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : Name (req), GlobalAddressList (req), OfflineAddressBook (req),
               RoomList (req), AddressLists (req)
#>

function Import-AllAddressBookPolicies {
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
        foreach ($col in @('Name', 'GlobalAddressList', 'OfflineAddressBook', 'RoomList', 'AddressLists')) {
            if ($col -notin $headers) { throw "CSV missing required column: '$col'" }
        }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Import-AllAddressBookPolicies. CSV: $CSVFile" -Level Info
    }

    process {
        try {
            $policies = Import-Csv -Path $CSVFile -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to import CSV: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($policy in $policies) {
            Write-Verbose "Processing: $($policy.Name)"

            if ($PSCmdlet.ShouldProcess($policy.Name, 'Create address book policy')) {
                try {
                    $addressLists = $policy.AddressLists -split ';' | Where-Object { $_ -ne '' }

                    New-AddressBookPolicy -Name $policy.Name `
                        -GlobalAddressList $policy.GlobalAddressList `
                        -OfflineAddressBook $policy.OfflineAddressBook `
                        -RoomList $policy.RoomList `
                        -AddressLists $addressLists `
                        -ErrorAction Stop

                    Write-Log "Created address book policy '$($policy.Name)'." -Level Success
                    $successCount++
                }
                catch {
                    Write-Log "Failed to create policy '$($policy.Name)': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Import-AllAddressBookPolicies'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
