<#
.SYNOPSIS
    Exports all transport rules from the source tenant to CSV.

.DESCRIPTION
    Retrieves all TransportRule objects and exports their key properties.
    The output CSV is used by Import-AllTransportRules to recreate the rules
    in the destination tenant.

    Note: Complex rule conditions/actions with custom predicates may require
    manual review after import.

    Output: <OutputCSV>\<ProjectKey>\Transport_Rules_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllTransportRules -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-AllTransportRules {
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

        $outputFile   = Join-Path $folderPath "Transport_Rules_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllTransportRules. Output: $outputFile" -Level Info
    }

    process {
        try {
            $rules = Get-TransportRule -ResultSize Unlimited -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve transport rules: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($rule in $rules) {
            Write-Verbose "Processing: $($rule.Name)"
            try {
                $results.Add([PSCustomObject]@{
                    Name                          = $rule.Name
                    Priority                      = $rule.Priority
                    State                         = $rule.State
                    Mode                          = $rule.Mode
                    Comments                      = $rule.Comments
                    FromScope                     = $rule.FromScope
                    SentToScope                   = $rule.SentToScope
                    SubjectContainsWords          = $rule.SubjectContainsWords -join ';'
                    SubjectOrBodyContainsWords    = $rule.SubjectOrBodyContainsWords -join ';'
                    FromAddressContainsWords      = $rule.FromAddressContainsWords -join ';'
                    SenderDomainIs                = $rule.SenderDomainIs -join ';'
                    RecipientDomainIs             = $rule.RecipientDomainIs -join ';'
                    AnyOfRecipientAddressContainsWords = $rule.AnyOfRecipientAddressContainsWords -join ';'
                    HeaderContainsMessageHeader   = $rule.HeaderContainsMessageHeader
                    HeaderContainsWords           = $rule.HeaderContainsWords -join ';'
                    AddHeader                     = $rule.AddHeader
                    SetHeaderName                 = $rule.SetHeaderName
                    SetHeaderValue                = $rule.SetHeaderValue
                    RejectMessageReasonText       = $rule.RejectMessageReasonText
                    RedirectMessageTo             = $rule.RedirectMessageTo -join ';'
                    AddToRecipients               = $rule.AddToRecipients -join ';'
                    CopyTo                        = $rule.CopyTo -join ';'
                    BlindCopyTo                   = $rule.BlindCopyTo -join ';'
                    ApplyHtmlDisclaimerText       = $rule.ApplyHtmlDisclaimerText
                    ApplyHtmlDisclaimerLocation   = $rule.ApplyHtmlDisclaimerLocation
                    ApplyHtmlDisclaimerFallbackAction = $rule.ApplyHtmlDisclaimerFallbackAction
                    SetSCL                        = $rule.SetSCL
                    DeleteMessage                 = $rule.DeleteMessage
                    StopRuleProcessing            = $rule.StopRuleProcessing
                })
                $successCount++
            }
            catch {
                Write-Log "Failed to process rule '$($rule.Name)': $($_.Exception.Message)" -Level Error
                $errorCount++
            }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) transport rules to: $outputFile" -Level Success
        } else {
            Write-Log "No transport rules were exported." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllTransportRules'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
