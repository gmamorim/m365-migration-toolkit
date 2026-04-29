<#
.SYNOPSIS
    Reports all retention policies and their assigned mailboxes from the source tenant.

.DESCRIPTION
    Exports all RetentionPolicy objects with their associated tags, and a separate
    report of which mailboxes have a non-default retention policy assigned.

    This is a report-only script. Retention policies should be reviewed and recreated
    manually in the destination tenant to avoid conflicts with existing M365 defaults.

    Output: <OutputCSV>\<ProjectKey>\Retention_Policies_<ProjectKey>.csv
            <OutputCSV>\<ProjectKey>\Retention_Policies_Mailboxes_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllRetentionPolicies -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-AllRetentionPolicies {
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

        $outputPolicies  = Join-Path $folderPath "Retention_Policies_$ProjectKey.csv"
        $outputMailboxes = Join-Path $folderPath "Retention_Policies_Mailboxes_$ProjectKey.csv"

        Write-Log "Starting Get-AllRetentionPolicies. Output: $outputPolicies" -Level Info
    }

    process {
        # Export retention policies
        try {
            $policies = Get-RetentionPolicy -ErrorAction Stop
            $policyResults = foreach ($policy in $policies) {
                [PSCustomObject]@{
                    Name        = $policy.Name
                    IsDefault   = $policy.IsDefault
                    RetentionId = $policy.RetentionId
                    RetentionPolicyTagLinks = $policy.RetentionPolicyTagLinks -join ';'
                }
            }
            $policyResults | Export-Csv -Path $outputPolicies -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($policies.Count) retention policies to: $outputPolicies" -Level Success
        }
        catch {
            Write-Log "Failed to retrieve retention policies: $($_.Exception.Message)" -Level Error
        }

        # Export mailboxes with non-default retention policy
        try {
            $mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited -ErrorAction Stop |
                Where-Object { $_.RetentionPolicy -and $_.RetentionPolicy -ne 'Default MRM Policy' }

            $mbResults = foreach ($mb in $mailboxes) {
                [PSCustomObject]@{
                    DisplayName        = $mb.DisplayName
                    PrimarySmtpAddress = $mb.PrimarySmtpAddress
                    RetentionPolicy    = $mb.RetentionPolicy
                }
            }

            if ($mbResults) {
                $mbResults | Export-Csv -Path $outputMailboxes -NoTypeInformation -Encoding UTF8
                Write-Log "Exported $($mbResults.Count) mailboxes with custom retention policy to: $outputMailboxes" -Level Success
            } else {
                Write-Log "No mailboxes with custom retention policy found." -Level Warning
            }
        }
        catch {
            Write-Log "Failed to retrieve mailbox retention assignments: $($_.Exception.Message)" -Level Error
        }
    }

    end {
        [PSCustomObject]@{
            Function     = 'Get-AllRetentionPolicies'
            OutputFile   = $outputPolicies
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
