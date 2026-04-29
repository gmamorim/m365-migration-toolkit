<#
.SYNOPSIS
    Exports all mail-enabled security groups and their members from the source tenant to CSV.

.DESCRIPTION
    Retrieves all MailUniversalSecurityGroup objects and exports DisplayName,
    PrimarySmtpAddress, Alias (semicolon-separated SMTP addresses, onmicrosoft excluded),
    and Members (semicolon-separated PrimarySmtpAddress values).

    Output: <OutputCSV>\<ProjectKey>\Mail_Enabled_Security_Groups_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllMailEnabledSecurityGroups -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-AllMailEnabledSecurityGroups {
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

        $outputFile   = Join-Path $folderPath "Mail_Enabled_Security_Groups_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllMailEnabledSecurityGroups. Output: $outputFile" -Level Info
    }

    process {
        try {
            $groups = Get-DistributionGroup -RecipientTypeDetails MailUniversalSecurityGroup -ResultSize Unlimited -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve mail-enabled security groups: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($group in $groups) {
            Write-Verbose "Processing: $($group.PrimarySmtpAddress)"
            try {
                $aliases = ($group.EmailAddresses |
                    ForEach-Object { $_.ToString() -replace '^(SMTP|smtp):', '' } |
                    Where-Object { $_ -notmatch 'onmicrosoft' }) -join ';'

                $members = ''
                try {
                    $memberList = Get-DistributionGroupMember -Identity $group.PrimarySmtpAddress -ErrorAction Stop
                    $members    = ($memberList | Select-Object -ExpandProperty PrimarySmtpAddress) -join ';'
                }
                catch {
                    Write-Log "Warning: Could not retrieve members for '$($group.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Warning
                }

                $results.Add([PSCustomObject]@{
                    DisplayName        = $group.DisplayName
                    PrimarySmtpAddress = $group.PrimarySmtpAddress
                    Alias              = $aliases
                    Members            = $members
                })
                $successCount++
            }
            catch {
                Write-Log "Failed to process group '$($group.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Error
                $errorCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) mail-enabled security groups to: $outputFile" -Level Success
        } else {
            Write-Log "No mail-enabled security groups were exported." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllMailEnabledSecurityGroups'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
