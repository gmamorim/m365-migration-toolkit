<#
.SYNOPSIS
    Exports all anti-spam and anti-phishing policies from the source tenant to CSV.

.DESCRIPTION
    Retrieves HostedContentFilterPolicy (anti-spam) and AntiPhishPolicy objects
    and exports their key settings for reference. Admins should review this report
    and manually recreate relevant policies (IP/domain allow/block lists, etc.)
    in the destination tenant via the Security portal.

    Output: <OutputCSV>\<ProjectKey>\AntiSpam_Policies_<ProjectKey>.csv
            <OutputCSV>\<ProjectKey>\AntiPhish_Policies_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllAntiSpamPolicies -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-AllAntiSpamPolicies {
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

        $outputAntiSpam  = Join-Path $folderPath "AntiSpam_Policies_$ProjectKey.csv"
        $outputAntiPhish = Join-Path $folderPath "AntiPhish_Policies_$ProjectKey.csv"

        Write-Log "Starting Get-AllAntiSpamPolicies." -Level Info
    }

    process {
        # Anti-spam (hosted content filter)
        try {
            $spamPolicies = Get-HostedContentFilterPolicy -ErrorAction Stop
            $spamResults = foreach ($p in $spamPolicies) {
                [PSCustomObject]@{
                    Name                          = $p.Name
                    IsDefault                     = $p.IsDefault
                    SpamAction                    = $p.SpamAction
                    HighConfidenceSpamAction      = $p.HighConfidenceSpamAction
                    PhishSpamAction               = $p.PhishSpamAction
                    BulkSpamAction                = $p.BulkSpamAction
                    BulkThreshold                 = $p.BulkThreshold
                    AllowedSenderDomains          = $p.AllowedSenderDomains -join ';'
                    AllowedSenders                = $p.AllowedSenders -join ';'
                    BlockedSenderDomains          = $p.BlockedSenderDomains -join ';'
                    BlockedSenders                = $p.BlockedSenders -join ';'
                    EnableSafeList                = $p.EnableSafeList
                    QuarantineRetentionPeriod     = $p.QuarantineRetentionPeriod
                }
            }
            $spamResults | Export-Csv -Path $outputAntiSpam -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($spamPolicies.Count) anti-spam policies to: $outputAntiSpam" -Level Success
        }
        catch {
            Write-Log "Failed to retrieve anti-spam policies: $($_.Exception.Message)" -Level Error
        }

        # Anti-phishing
        try {
            $phishPolicies = Get-AntiPhishPolicy -ErrorAction Stop
            $phishResults = foreach ($p in $phishPolicies) {
                [PSCustomObject]@{
                    Name                              = $p.Name
                    IsDefault                         = $p.IsDefault
                    Enabled                           = $p.Enabled
                    EnableMailboxIntelligence         = $p.EnableMailboxIntelligence
                    EnableSpoofIntelligence           = $p.EnableSpoofIntelligence
                    EnableFirstContactSafetyTips      = $p.EnableFirstContactSafetyTips
                    PhishThresholdLevel               = $p.PhishThresholdLevel
                    TargetedUserProtectionAction      = $p.TargetedUserProtectionAction
                    TargetedDomainProtectionAction    = $p.TargetedDomainProtectionAction
                    MailboxIntelligenceProtectionAction = $p.MailboxIntelligenceProtectionAction
                }
            }
            $phishResults | Export-Csv -Path $outputAntiPhish -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($phishPolicies.Count) anti-phishing policies to: $outputAntiPhish" -Level Success
        }
        catch {
            Write-Log "Failed to retrieve anti-phishing policies: $($_.Exception.Message)" -Level Error
        }
    }

    end {
        [PSCustomObject]@{
            Function        = 'Get-AllAntiSpamPolicies'
            AntiSpamFile    = $outputAntiSpam
            AntiPhishFile   = $outputAntiPhish
            TimestampUTC    = (Get-Date).ToUniversalTime()
        }
    }
}
