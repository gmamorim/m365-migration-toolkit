<#
.SYNOPSIS
    Creates transport rules in the destination tenant from a source CSV.

.DESCRIPTION
    For each row in the CSV, recreates the transport rule using the exported
    properties. Only non-empty fields are passed to New-TransportRule to avoid
    overriding defaults with blank values.

    Note: Complex rules with custom predicates, recipient/sender references, or
    HTML disclaimers should be reviewed after import. Rules are created in Disabled
    state by default to allow review before activation.

.PARAMETER CSVFile
    Full path to the input CSV (output of Get-AllTransportRules).

.PARAMETER Enabled
    If specified, creates rules in Enabled state. Default is Disabled.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Import-AllTransportRules -CSVFile "C:\CSV\Acme\Transport_Rules_Acme.csv"

.EXAMPLE
    Import-AllTransportRules -CSVFile "C:\CSV\Acme\Transport_Rules_Acme.csv" -Enabled -WhatIf

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : Name (req) — all other columns optional
#>

function Import-AllTransportRules {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CSVFile,

        [Parameter(Mandatory = $false)]
        [switch]$Enabled,

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
        if ('Name' -notin $headers) { throw "CSV missing required column: 'Name'" }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Import-AllTransportRules. CSV: $CSVFile" -Level Info
        if (-not $Enabled) { Write-Log "Rules will be created in Disabled state. Use -Enabled to activate on creation." -Level Warning }
    }

    process {
        try {
            $rules = Import-Csv -Path $CSVFile -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to import CSV: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($rule in $rules) {
            Write-Verbose "Processing: $($rule.Name)"

            if ($PSCmdlet.ShouldProcess($rule.Name, 'Create transport rule')) {
                try {
                    $params = @{
                        Name        = $rule.Name
                        Enabled     = $Enabled.IsPresent
                        ErrorAction = 'Stop'
                    }

                    # Add optional string fields only when non-empty
                    $stringFields = @{
                        'Comments'                   = 'Comments'
                        'FromScope'                  = 'FromScope'
                        'SentToScope'                = 'SentToScope'
                        'AddHeader'                  = 'AddHeader'
                        'SetHeaderName'              = 'SetHeaderName'
                        'SetHeaderValue'             = 'SetHeaderValue'
                        'RejectMessageReasonText'    = 'RejectMessageReasonText'
                        'HeaderContainsMessageHeader'= 'HeaderContainsMessageHeader'
                        'ApplyHtmlDisclaimerText'    = 'ApplyHtmlDisclaimerText'
                        'ApplyHtmlDisclaimerLocation'= 'ApplyHtmlDisclaimerLocation'
                        'ApplyHtmlDisclaimerFallbackAction' = 'ApplyHtmlDisclaimerFallbackAction'
                    }
                    foreach ($field in $stringFields.Keys) {
                        if ($rule.$field -and $rule.$field -ne '') { $params[$stringFields[$field]] = $rule.$field }
                    }

                    # Add optional array fields (semicolon-separated)
                    $arrayFields = @(
                        'SubjectContainsWords', 'SubjectOrBodyContainsWords', 'FromAddressContainsWords',
                        'SenderDomainIs', 'RecipientDomainIs', 'AnyOfRecipientAddressContainsWords',
                        'HeaderContainsWords', 'RedirectMessageTo', 'AddToRecipients', 'CopyTo', 'BlindCopyTo'
                    )
                    foreach ($field in $arrayFields) {
                        if ($rule.$field -and $rule.$field -ne '') { $params[$field] = $rule.$field -split ';' }
                    }

                    # Boolean fields
                    if ($rule.DeleteMessage -eq 'True')       { $params['DeleteMessage']       = $true }
                    if ($rule.StopRuleProcessing -eq 'True')  { $params['StopRuleProcessing']  = $true }
                    if ($rule.SetSCL -match '^\d+$')          { $params['SetSCL']              = [int]$rule.SetSCL }

                    New-TransportRule @params
                    Write-Log "Created transport rule '$($rule.Name)'." -Level Success
                    $successCount++
                }
                catch {
                    Write-Log "Failed to create rule '$($rule.Name)': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Import-AllTransportRules'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
