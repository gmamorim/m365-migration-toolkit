<#
.SYNOPSIS
    Reports all OWA mailbox policies from the source tenant.

.DESCRIPTION
    Retrieves all OwaMailboxPolicy objects and exports their key settings
    for reference. This is a report-only script — OWA policies are
    organization-specific and should be reviewed before recreating in the
    destination tenant.

    Output: <OutputCSV>\<ProjectKey>\OWA_Mailbox_Policies_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllOwaMailboxPolicies -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-AllOwaMailboxPolicies {
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

        $outputFile   = Join-Path $folderPath "OWA_Mailbox_Policies_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllOwaMailboxPolicies. Output: $outputFile" -Level Info
    }

    process {
        try {
            $policies = Get-OwaMailboxPolicy -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to retrieve OWA mailbox policies: $($_.Exception.Message)" -Level Error
            return
        }

        foreach ($policy in $policies) {
            Write-Verbose "Processing: $($policy.Name)"
            try {
                $results.Add([PSCustomObject]@{
                    Name                            = $policy.Name
                    IsDefault                       = $policy.IsDefault
                    InstantMessagingEnabled         = $policy.InstantMessagingEnabled
                    TextMessagingEnabled            = $policy.TextMessagingEnabled
                    ActiveSyncIntegrationEnabled    = $policy.ActiveSyncIntegrationEnabled
                    ContactsEnabled                 = $policy.ContactsEnabled
                    TasksEnabled                    = $policy.TasksEnabled
                    JournalEnabled                  = $policy.JournalEnabled
                    NotesEnabled                    = $policy.NotesEnabled
                    OnSendAddinsEnabled             = $policy.OnSendAddinsEnabled
                    SignaturesEnabled               = $policy.SignaturesEnabled
                    ThemeSelectionEnabled           = $policy.ThemeSelectionEnabled
                    PublicFoldersEnabled            = $policy.PublicFoldersEnabled
                    RecoverDeletedItemsEnabled      = $policy.RecoverDeletedItemsEnabled
                    DirectFileAccessOnPublicComputersEnabled = $policy.DirectFileAccessOnPublicComputersEnabled
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
            Write-Log "Exported $($results.Count) OWA mailbox policies to: $outputFile" -Level Success
        } else {
            Write-Log "No OWA mailbox policies were exported." -Level Warning
        }

        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllOwaMailboxPolicies'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
