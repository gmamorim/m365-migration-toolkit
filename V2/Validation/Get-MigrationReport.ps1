<#
.SYNOPSIS
    Generates a post-migration validation report comparing source CSVs with destination objects.

.DESCRIPTION
    For each object type (SharedMailbox, ResourceMailbox, DistributionGroup), compares:
      - Total count in the source CSV vs. objects found in the destination EXO tenant
      - Whether each source object has a matching object at the expected destination alias
      - Whether permissions/members were correctly assigned (SharedMailbox and DistributionGroup)

    Produces:
      - A CSV report file: MigrationReport_<ProjectKey>_<yyyyMMdd_HHmm>.csv
      - A summary table printed to the console
      - Aggregated pass/fail counts returned as a PSCustomObject

.PARAMETER CSVFolder
    Base directory containing the project CSV subfolder.

.PARAMETER ProjectKey
    Project key used to locate CSV files and build destination alias patterns.

.PARAMETER Domain
    Destination tenant SMTP domain (e.g. "dest.com").

.PARAMETER Prefix
    Optional. Prefix used when objects were created (must match what was used in Import-*).

.PARAMETER ReportPath
    Optional. Directory to write the report CSV. Defaults to the project CSV subfolder.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-MigrationReport -CSVFolder "C:\CSV" -ProjectKey "Contoso" -Domain "dest.com"

    Validates the Contoso migration and saves a report to C:\CSV\Contoso\.

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-MigrationReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$CSVFolder,

        [Parameter(Mandatory = $true)]
        [string]$ProjectKey,

        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $false)]
        [string]$Prefix,

        [Parameter(Mandatory = $false)]
        [string]$ReportPath,

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

        $projectFolder = Join-Path $CSVFolder $ProjectKey
        if (-not $ReportPath) { $ReportPath = $projectFolder }

        $reportFile = Join-Path $ReportPath "MigrationReport_${ProjectKey}_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
        $reportRows = [System.Collections.Generic.List[PSCustomObject]]::new()

        $totalChecked  = 0
        $totalMissing  = 0
        $totalMismatch = 0

        Write-Log "Starting migration report for project: $ProjectKey" -Level Info

        # Helper: build destination alias from source PrimarySmtpAddress
        function Get-DestAlias {
            param([string]$PrimarySmtpAddress)
            $local = ($PrimarySmtpAddress -split '@')[0]
            $base  = if ($Prefix) { "$Prefix-$local" } else { $local }
            return ($base -replace '[^a-zA-Z0-9._-]', '').ToLower()
        }
    }

    process {
        # ---- Shared Mailboxes ----
        $sharedCsv = Join-Path $projectFolder "Shared_Mailboxes_$ProjectKey.csv"
        if (Test-Path $sharedCsv) {
            Write-Log "Checking Shared Mailboxes..." -Level Info
            $sourceRows = Import-Csv $sharedCsv -Encoding UTF8
            foreach ($row in $sourceRows) {
                $totalChecked++
                $destAlias   = Get-DestAlias $row.PrimarySmtpAddress
                $destAddress = "$destAlias@$Domain"

                try {
                    $destMailbox = Get-Mailbox -Identity $destAddress -ErrorAction Stop
                    $found = $true

                    # Check FullAccess permissions
                    $permMatch = 'N/A'
                    if ($row.FullAccessUsers) {
                        $currentPerms  = (Get-MailboxPermission -Identity $destAddress |
                            Where-Object { $_.IsInherited -eq $false -and $_.User -ne 'NT AUTHORITY\SELF' }).User -join ';'
                        $expectedPerms = ($row.FullAccessUsers -split ';' | Where-Object { $_ -match '@' }) -join ';'
                        $permMatch     = if ($currentPerms -eq $expectedPerms) { 'Match' } else { 'Mismatch' }
                        if ($permMatch -eq 'Mismatch') { $totalMismatch++ }
                    }

                    $reportRows.Add([PSCustomObject]@{
                        ObjectType              = 'SharedMailbox'
                        SourceIdentity          = $row.PrimarySmtpAddress
                        ExpectedDestAlias       = $destAddress
                        FoundInDestination      = $found
                        PermissionsOrMembership = $permMatch
                        Notes                   = ''
                    })
                    Write-Verbose "Found: $destAddress"
                }
                catch {
                    $totalMissing++
                    $reportRows.Add([PSCustomObject]@{
                        ObjectType              = 'SharedMailbox'
                        SourceIdentity          = $row.PrimarySmtpAddress
                        ExpectedDestAlias       = $destAddress
                        FoundInDestination      = $false
                        PermissionsOrMembership = 'N/A'
                        Notes                   = 'Not found in destination'
                    })
                    Write-Log "Missing SharedMailbox: $destAddress (source: $($row.PrimarySmtpAddress))" -Level Warning
                }
            }
        }

        # ---- Resource Mailboxes ----
        $resourceCsv = Join-Path $projectFolder "Resource_Mailboxes_$ProjectKey.csv"
        if (Test-Path $resourceCsv) {
            Write-Log "Checking Resource Mailboxes..." -Level Info
            $sourceRows = Import-Csv $resourceCsv -Encoding UTF8
            foreach ($row in $sourceRows) {
                $totalChecked++
                $destAlias   = Get-DestAlias $row.PrimarySmtpAddress
                $destAddress = "$destAlias@$Domain"

                try {
                    Get-Mailbox -Identity $destAddress -ErrorAction Stop | Out-Null
                    $reportRows.Add([PSCustomObject]@{
                        ObjectType              = 'ResourceMailbox'
                        SourceIdentity          = $row.PrimarySmtpAddress
                        ExpectedDestAlias       = $destAddress
                        FoundInDestination      = $true
                        PermissionsOrMembership = 'N/A'
                        Notes                   = ''
                    })
                }
                catch {
                    $totalMissing++
                    $reportRows.Add([PSCustomObject]@{
                        ObjectType              = 'ResourceMailbox'
                        SourceIdentity          = $row.PrimarySmtpAddress
                        ExpectedDestAlias       = $destAddress
                        FoundInDestination      = $false
                        PermissionsOrMembership = 'N/A'
                        Notes                   = 'Not found in destination'
                    })
                    Write-Log "Missing ResourceMailbox: $destAddress" -Level Warning
                }
            }
        }

        # ---- Distribution Groups ----
        $groupCsv = Join-Path $projectFolder "Distribution_Groups_$ProjectKey.csv"
        if (Test-Path $groupCsv) {
            Write-Log "Checking Distribution Groups..." -Level Info
            $sourceRows = Import-Csv $groupCsv -Encoding UTF8
            foreach ($row in $sourceRows) {
                $totalChecked++
                $srcLocal    = ($row.PrimarySmtpAddress -split '@')[0]
                $base        = if ($Prefix) { "$Prefix-$srcLocal" } else { $srcLocal }
                $destAlias   = ($base -replace '[^a-zA-Z0-9._-]', '').ToLower()
                $destAddress = "$destAlias@$Domain"

                try {
                    Get-DistributionGroup -Identity $destAddress -ErrorAction Stop | Out-Null
                    $memberMatch = 'N/A'
                    if ($row.Members) {
                        $currentMembers  = (Get-DistributionGroupMember -Identity $destAddress | Select-Object -ExpandProperty PrimarySmtpAddress) -join ';'
                        $expectedMembers = ($row.Members -split ';' | Where-Object { $_ -match '@' }) -join ';'
                        $memberMatch     = if ($currentMembers -eq $expectedMembers) { 'Match' } else { 'Mismatch' }
                        if ($memberMatch -eq 'Mismatch') { $totalMismatch++ }
                    }

                    $reportRows.Add([PSCustomObject]@{
                        ObjectType              = 'DistributionGroup'
                        SourceIdentity          = $row.PrimarySmtpAddress
                        ExpectedDestAlias       = $destAddress
                        FoundInDestination      = $true
                        PermissionsOrMembership = $memberMatch
                        Notes                   = ''
                    })
                }
                catch {
                    $totalMissing++
                    $reportRows.Add([PSCustomObject]@{
                        ObjectType              = 'DistributionGroup'
                        SourceIdentity          = $row.PrimarySmtpAddress
                        ExpectedDestAlias       = $destAddress
                        FoundInDestination      = $false
                        PermissionsOrMembership = 'N/A'
                        Notes                   = 'Not found in destination'
                    })
                    Write-Log "Missing DistributionGroup: $destAddress" -Level Warning
                }
            }
        }
    }

    end {
        # Export CSV report
        $reportRows | Export-Csv -Path $reportFile -NoTypeInformation -Encoding UTF8
        Write-Log "Report saved to: $reportFile" -Level Info

        # Console summary table
        $summary = $reportRows | Group-Object ObjectType | ForEach-Object {
            $grp = $_.Group
            [PSCustomObject]@{
                ObjectType   = $_.Name
                Total        = $grp.Count
                Found        = ($grp | Where-Object FoundInDestination -eq $true).Count
                Missing      = ($grp | Where-Object FoundInDestination -eq $false).Count
                Mismatch     = ($grp | Where-Object PermissionsOrMembership -eq 'Mismatch').Count
            }
        }

        Write-Host "`n===== Migration Report Summary =====" -ForegroundColor Magenta
        $summary | Format-Table ObjectType, Total, Found, Missing, Mismatch -AutoSize

        [PSCustomObject]@{
            Function     = 'Get-MigrationReport'
            Succeeded    = $totalChecked - $totalMissing - $totalMismatch
            Failed       = $totalMissing
            Total        = $totalChecked
            Mismatches   = $totalMismatch
            ReportFile   = $reportFile
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
