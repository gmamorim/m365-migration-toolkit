<#
.SYNOPSIS
    Reports licensing and mailbox provisioning status for destination tenant users.

.DESCRIPTION
    Reads a CSV of source mailboxes (produced by Get-AllMailboxes), then queries the
    destination tenant via Microsoft Graph to check whether each corresponding user:
      - Exists in Azure AD
      - Has at least one license assigned
      - Has an active Exchange Online mailbox

    This report helps identify users who are not yet licensed or provisioned before
    running import scripts or configuring forwarding.

    Output: <OutputCSV>\<ProjectKey>\Licensing_Report_<ProjectKey>.csv

.PARAMETER CSVFile
    Full path to the source mailboxes CSV. Required column: PrimarySmtpAddress.

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER DestDomain
    Destination tenant SMTP domain used to derive the destination UPN/address.

.PARAMETER Prefix
    Optional. Prefix used when destination users were created (must match Import-* scripts).

.PARAMETER LogPath
    Optional. Full path to a log file. Output is appended.

.EXAMPLE
    Get-AllLicensingReport -CSVFile "C:\CSV\Acme\Mailboxes_Acme.csv" `
        -OutputCSV "C:\CSV" -ProjectKey "Acme" -DestDomain "amorim.rocks"

    Generates a licensing report for all users in the Acme migration project.

.EXAMPLE
    Get-AllLicensingReport -CSVFile "C:\CSV\Acme\Mailboxes_Acme.csv" `
        -OutputCSV "C:\CSV" -ProjectKey "Acme" -DestDomain "amorim.onmicrosoft.com"

    Uses the onmicrosoft.com domain to look up destination users.

.NOTES
    Author   : Gabriel Amorim
    Version  : 1.0
    Requires : Microsoft.Graph module (Connect-MgGraph with User.Read.All and
               Directory.Read.All scopes), active EXO session (destination tenant)
    CSV In   : PrimarySmtpAddress (req)

    Connect before running:
        Connect-MgGraph -Scopes "User.Read.All","Directory.Read.All"
        Connect-ExchangeOnline -UserPrincipalName admin@destination.onmicrosoft.com
#>

function Get-AllLicensingReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CSVFile,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$OutputCSV,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestDomain,

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

        # Validate Microsoft.Graph module
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
            throw "Microsoft.Graph.Users module not found. Run: Install-Module Microsoft.Graph"
        }

        $headers = (Get-Content $CSVFile -TotalCount 1) -split ',' | ForEach-Object { $_.Trim('"').Trim() }
        if ('PrimarySmtpAddress' -notin $headers) { throw "CSV missing required column: 'PrimarySmtpAddress'" }

        $folderPath = Join-Path $OutputCSV $ProjectKey
        if (-not (Test-Path $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        }

        $outputFile   = Join-Path $folderPath "Licensing_Report_$ProjectKey.csv"
        $successCount = 0
        $errorCount   = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Get-AllLicensingReport. CSV: $CSVFile | DestDomain: $DestDomain" -Level Info
    }

    process {
        $Rows = Import-Csv -Path $CSVFile -Encoding UTF8

        foreach ($Row in $Rows) {
            $localPart   = ($Row.PrimarySmtpAddress -split '@')[0]
            $aliasBase   = if ($Prefix) { "$Prefix-$localPart" } else { $localPart }
            $DestAddress = (($aliasBase -replace '[^a-zA-Z0-9._-]', '') + "@$DestDomain").ToLower()

            Write-Verbose "Checking: $DestAddress"

            $userExists    = $false
            $isLicensed    = $false
            $hasMailbox    = $false
            $assignedPlans = ''
            $graphError    = ''
            $exoError      = ''

            # Check Azure AD user and licensing via Graph
            try {
                $mgUser = Get-MgUser -UserId $DestAddress `
                    -Property "Id,DisplayName,AssignedLicenses,AssignedPlans" `
                    -ErrorAction Stop

                $userExists = $true
                $isLicensed = ($mgUser.AssignedLicenses.Count -gt 0)

                # Collect Exchange-related service plans
                $exoPlans = $mgUser.AssignedPlans | Where-Object {
                    $_.Service -eq 'exchange' -and $_.CapabilityStatus -eq 'Enabled'
                }
                $assignedPlans = ($exoPlans | Select-Object -ExpandProperty ServicePlanId) -join ';'
            }
            catch {
                $graphError = $_.Exception.Message
            }

            # Check EXO mailbox
            if ($userExists) {
                try {
                    $mb = Get-Mailbox -Identity $DestAddress -ErrorAction Stop
                    $hasMailbox = ($null -ne $mb)
                }
                catch {
                    $exoError = $_.Exception.Message
                }
            }

            # Determine overall status
            $status = switch ($true) {
                { -not $userExists }            { 'UserNotFound' }
                { $userExists -and -not $isLicensed } { 'NotLicensed' }
                { $isLicensed -and -not $hasMailbox } { 'LicensedNoMailbox' }
                { $isLicensed -and $hasMailbox }      { 'Ready' }
                default                               { 'Unknown' }
            }

            $results.Add([PSCustomObject]@{
                SourceAddress  = $Row.PrimarySmtpAddress
                DestAddress    = $DestAddress
                UserExists     = $userExists
                IsLicensed     = $isLicensed
                HasMailbox     = $hasMailbox
                ExoPlans       = $assignedPlans
                Status         = $status
                GraphError     = $graphError
                EXOError       = $exoError
            })

            if ($graphError -or $exoError) { $errorCount++ } else { $successCount++ }
        }
    }

    end {
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($results.Count) records to: $outputFile" -Level Success

            $ready          = ($results | Where-Object Status -eq 'Ready').Count
            $notLicensed    = ($results | Where-Object Status -eq 'NotLicensed').Count
            $noMailbox      = ($results | Where-Object Status -eq 'LicensedNoMailbox').Count
            $notFound       = ($results | Where-Object Status -eq 'UserNotFound').Count

            Write-Log "Status breakdown | Ready: $ready | NotLicensed: $notLicensed | LicensedNoMailbox: $noMailbox | UserNotFound: $notFound" -Level Info
        }
        else {
            Write-Log "No records were processed." -Level Warning
        }

        Write-Log "Summary | Processed: $successCount | Errors: $errorCount | Total: $($successCount + $errorCount)" -Level Info

        [PSCustomObject]@{
            Function     = 'Get-AllLicensingReport'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            OutputFile   = $outputFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
