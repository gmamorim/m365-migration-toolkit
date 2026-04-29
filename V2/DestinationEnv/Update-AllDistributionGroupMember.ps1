<#
.SYNOPSIS
    Adds members to distribution groups in the destination tenant.

.DESCRIPTION
    For each group in the CSV, derives the destination group address from the source
    local part and attempts to add each member. If a member is not found directly,
    falls back to Get-Recipient for resolution before giving up.

.PARAMETER CSVFile
    Full path to the input CSV.
    Required columns: PrimarySmtpAddress, Members (semicolon-separated).

.PARAMETER Domain
    Destination tenant SMTP domain.

.PARAMETER Prefix
    Optional. Prefix used when the groups were created (must match what was used in Import-AllDistributionGroups).

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Update-AllDistributionGroupMember -CSVFile "C:\CSV\Contoso\Distribution_Groups_Contoso.csv" `
        -Domain "dest.com"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : PrimarySmtpAddress (req), Members (semicolon-separated)
#>

function Update-AllDistributionGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CSVFile,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

        [Parameter(Mandatory = $false)]
        [string]$Prefix,

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
        foreach ($col in @('PrimarySmtpAddress', 'Members')) {
            if ($col -notin $headers) { throw "CSV missing required column: '$col'" }
        }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Update-AllDistributionGroupMember. CSV: $CSVFile" -Level Info
    }

    process {
        $Groups = Import-Csv -Path $CSVFile -Encoding UTF8

        foreach ($Group in $Groups) {
            $localPart        = ($Group.PrimarySmtpAddress -split '@')[0]
            $aliasBase        = if ($Prefix) { "$Prefix-$localPart" } else { $localPart }
            $DestGroupAddress = (($aliasBase -replace '[^a-zA-Z0-9._-]', '') + "@$Domain").ToLower()

            if (-not $Group.Members) {
                Write-Verbose "Group '$DestGroupAddress' has no members in CSV. Skipping."
                continue
            }

            $Members = $Group.Members -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            foreach ($Member in $Members) {
                $CleanMember = $Member.Trim()

                if ($PSCmdlet.ShouldProcess($DestGroupAddress, "Add member '$CleanMember'")) {
                    try {
                        Add-DistributionGroupMember -Identity $DestGroupAddress -Member $CleanMember -ErrorAction Stop
                        Write-Log "Added '$CleanMember' to '$DestGroupAddress'." -Level Success
                        $successCount++
                    }
                    catch {
                        $errMsg = $_.Exception.Message
                        if ($errMsg -like '*cannot be found*' -or $errMsg -like "*couldn't be found*") {
                            $recipient = Get-Recipient -RecipientTypeDetails MailUser, UserMailbox, MailContact `
                                -Identity $CleanMember -ErrorAction SilentlyContinue
                            if ($recipient) {
                                try {
                                    Add-DistributionGroupMember -Identity $DestGroupAddress `
                                        -Member $recipient.PrimarySmtpAddress -ErrorAction Stop
                                    Write-Log "Resolved and added '$($recipient.PrimarySmtpAddress)' (from '$CleanMember') to '$DestGroupAddress'." -Level Success
                                    $successCount++
                                }
                                catch {
                                    Write-Log "Failed to add resolved '$($recipient.PrimarySmtpAddress)' to '$DestGroupAddress': $($_.Exception.Message)" -Level Error
                                    $errorCount++
                                }
                            }
                            else {
                                Write-Log "Member '$CleanMember' not found even after resolution. Skipping." -Level Warning
                                $errorCount++
                            }
                        }
                        else {
                            Write-Log "Failed to add '$CleanMember' to '$DestGroupAddress': $errMsg" -Level Error
                            $errorCount++
                        }
                    }
                }
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Update-AllDistributionGroupMember'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
