<#
.SYNOPSIS
    Exports details for specific distribution groups listed in an input CSV.

.DESCRIPTION
    Reads a list of PrimarySmtpAddress values from the input CSV and retrieves
    distribution group details and member lists for each.

    Members are joined with semicolons (';') — consistent with all other scripts.

    Output: <OutputCSV>\<ProjectKey>\Distribution_Groups_<ProjectKey>.csv

.PARAMETER InputCSV
    Path to the input CSV file. Must contain a 'PrimarySmtpAddress' column.

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-CSVDistributionGroups -InputCSV "C:\CSV\Acme\groups_list.csv" `
        -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : PrimarySmtpAddress (required)
    CSV Out  : DisplayName, PrimarySmtpAddress, Alias, Members (semicolon-separated)
#>

function Get-CSVDistributionGroups {
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

        $outputFile   = Join-Path $folderPath "Distribution_Groups_$ProjectKey.csv"
        $successCount = 0
        $notFound     = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-CSVDistributionGroups. Input: $InputCSV | Output: $outputFile" -Level Info
    }

    process {
        $groupList = Import-Csv -Path $InputCSV -Encoding UTF8 | Select-Object -ExpandProperty PrimarySmtpAddress

        if (-not $groupList) {
            Write-Log "Input CSV contains no group addresses." -Level Warning
            return
        }

        foreach ($address in $groupList) {
            Write-Verbose "Looking up: $address"
            try {
                $grp = Get-DistributionGroup -Identity $address -ErrorAction Stop

                $aliases = ($grp.EmailAddresses |
                    ForEach-Object { $_.ToString() -replace '^(SMTP|smtp):', '' } |
                    Where-Object { $_ -notmatch 'onmicrosoft|SPO:|SIP:' }) -join ';'

                $members = ''
                try {
                    $memberList = Get-DistributionGroupMember -Identity $address -ErrorAction Stop
                    $members    = ($memberList | Select-Object -ExpandProperty PrimarySmtpAddress) -join ';'
                } catch {
                    Write-Log "Warning: Could not get members for '$address': $($_.Exception.Message)" -Level Warning
                }

                $results.Add([PSCustomObject]@{
                    DisplayName        = $grp.DisplayName
                    PrimarySmtpAddress = $grp.PrimarySmtpAddress
                    Alias              = $aliases
                    Members            = $members
                })
                $successCount++
            }
            catch {
                if ($_.Exception.Message -match "couldn't be found|cannot be found") {
                    Write-Log "Distribution group not found: '$address'" -Level Warning
                    $notFound++
                } else {
                    Write-Log "Error retrieving distribution group '$address': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) distribution groups to: $outputFile" -Level Success
        } else {
            Write-Log "No distribution groups were exported." -Level Warning
        }

        Write-Log "Summary | Found: $successCount | Not Found: $notFound | Errors: $errorCount" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-CSVDistributionGroups'
            Succeeded    = $successCount
            Failed       = $errorCount + $notFound
            Total        = $successCount + $errorCount + $notFound
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
