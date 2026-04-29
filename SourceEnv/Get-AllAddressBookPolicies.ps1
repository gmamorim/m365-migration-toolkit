<#
.SYNOPSIS
    Exports all Address Book Policies from the source tenant to CSV.

.DESCRIPTION
    Retrieves all AddressBookPolicy objects and exports their associated
    address lists, room lists, offline address books, and global address lists.
    Used by Import-AllAddressBookPolicies to recreate them in the destination tenant.

    Output: <OutputCSV>\<ProjectKey>\Address_Book_Policies_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllAddressBookPolicies -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    Note     : Address lists, OABs, and GALs referenced by the policy must exist
               in the destination tenant before importing.
#>

function Get-AllAddressBookPolicies {
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

        $outputFile   = Join-Path $folderPath "Address_Book_Policies_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllAddressBookPolicies. Output: $outputFile" -Level Info
    }

    process {
        try {
            $policies = Get-AddressBookPolicy -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve address book policies: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($policy in $policies) {
            Write-Verbose "Processing: $($policy.Name)"
            try {
                $results.Add([PSCustomObject]@{
                    Name                  = $policy.Name
                    AddressLists          = $policy.AddressLists -join ';'
                    RoomList              = $policy.RoomList
                    OfflineAddressBook    = $policy.OfflineAddressBook
                    GlobalAddressList     = $policy.GlobalAddressList
                })
                $successCount++
            }
            catch {
                Write-Log "Failed to process policy '$($policy.Name)': $($_.Exception.Message)" -Level Error
                $errorCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) address book policies to: $outputFile" -Level Success
        } else {
            Write-Log "No address book policies were exported." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllAddressBookPolicies'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
