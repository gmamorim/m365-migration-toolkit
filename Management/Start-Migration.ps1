<#
.SYNOPSIS
    Safe, phased orchestration script for M365 tenant-to-tenant migrations.

.DESCRIPTION
    Orchestrates the full migration workflow by loading all function scripts,
    reading the project configuration, running Test-MigrationPrerequisites,
    and executing the requested migration phase(s) in order.

    All function results are aggregated into a master summary that is printed
    to the console and saved as a CSV.

    Supports -WhatIf for a complete dry-run of any phase without making changes.

.PARAMETER ConfigPath
    Full path to the project configuration file (e.g. ".\Contoso-Config.ps1").
    The file must define: $ProjectKey, $Domain, $DestDomain, $CSVFolder, $CSVSource, $LogFolder.
    Optional: $Prefix (alias prefix; defaults to empty string if not set).

.PARAMETER Phase
    Which phase(s) to execute. Valid values:
      validate  - Run Test-MigrationPrerequisites only.
      export    - Export all objects from the source tenant to CSV.
      import    - Create all objects in the destination tenant from CSV.
      update    - Update members, aliases, and permissions in destination.
      cleanup   - Remove forwarding addresses in EXO.
      report    - Run Get-MigrationReport to validate migration completeness.
      full      - Run all phases in sequence (validate, export, import, update, cleanup, report).

.PARAMETER LogPath
    Optional. Full path to the log file. If omitted, a file named
    "Migration_<ProjectKey>_<yyyyMMdd_HHmm>.log" is created in $LogFolder.

.PARAMETER SkipPrerequisites
    Skip the Test-MigrationPrerequisites check.

.EXAMPLE
    Start-Migration -ConfigPath ".\Contoso-Config.ps1" -Phase validate

.EXAMPLE
    Start-Migration -ConfigPath ".\Contoso-Config.ps1" -Phase import -WhatIf -Verbose

    Dry-run of the import phase with verbose per-item output. No objects are created.

.EXAMPLE
    Start-Migration -ConfigPath ".\Contoso-Config.ps1" -Phase full `
        -LogPath "C:\Logs\Contoso_full_migration.log"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : ExchangeOnlineManagement module, active EXO session for most phases.
               Load-Scripts.ps1 is called automatically — do not pre-load manually.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('validate', 'export', 'import', 'update', 'cleanup', 'report', 'full')]
    [string]$Phase,

    [Parameter(Mandatory = $false)]
    [string]$LogPath,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPrerequisites
)

# ---- Bootstrap ----
. (Join-Path $PSScriptRoot 'Load-Scripts.ps1') -IncludeRegularCmds

# ---- Load project config ----
. $ConfigPath

# Prefix defaults to empty string if not defined in config
if (-not (Get-Variable -Name 'Prefix' -ErrorAction SilentlyContinue)) { $Prefix = '' }

# ---- Resolve log path ----
if (-not $LogPath) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmm'
    $LogPath   = Join-Path $LogFolder "Migration_${ProjectKey}_${timestamp}.log"
}

# ---- Internal helpers ----
function Write-Log {
    param([string]$Message, [string]$Level = 'Info')
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][$Level] $Message"
    switch ($Level) {
        'Success' { Write-Host $line -ForegroundColor Green }
        'Warning' { Write-Host $line -ForegroundColor Yellow }
        'Error'   { Write-Host $line -ForegroundColor Red }
        'Header'  { Write-Host "`n$line" -ForegroundColor Magenta }
        default   { Write-Host $line -ForegroundColor Cyan }
    }
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function Invoke-Phase {
    param([string]$Name, [scriptblock]$Block)
    Write-Log "===== PHASE: $Name =====" -Level Header
    try { return (& $Block) }
    catch {
        Write-Log "Phase '$Name' encountered an unhandled error: $($_.Exception.Message)" -Level Error
        return $null
    }
}

$allResults = [System.Collections.Generic.List[PSCustomObject]]::new()

Write-Log "Start-Migration started. Project: $ProjectKey | Phase: $Phase" -Level Info
Write-Log "Log file: $LogPath" -Level Info
if ($WhatIfPreference) { Write-Log "WhatIf mode is ACTIVE — no changes will be made." -Level Warning }

# ---- Prerequisites ----
if (-not $SkipPrerequisites -and $Phase -ne 'export') {
    Write-Log "===== PHASE: validate =====" -Level Header
    $prereqResults = Test-MigrationPrerequisites -CSVFolder $CSVFolder -ProjectKey $ProjectKey -LogPath $LogPath
    $prereqResults | Format-Table Test, Result, Detail -AutoSize

    if ($prereqResults | Where-Object { $_.Result -eq 'Fail' }) {
        Write-Log "Prerequisites check failed. Aborting." -Level Error
        return
    }
    Write-Log "Prerequisites check passed." -Level Success
    if ($Phase -eq 'validate') { return }
}

# ---- Shared params ----
$commonParams = @{ LogPath = $LogPath }
$destParams   = @{ Domain = $DestDomain; LogPath = $LogPath }
if ($Prefix) { $destParams['Prefix'] = $Prefix }

# ---- EXPORT phase ----
if ($Phase -in @('export', 'full')) {
    Invoke-Phase 'Export' {
        $allResults.Add((Get-AllMailboxes         -OutputCSV $CSVFolder -ProjectKey $ProjectKey @commonParams))
        $allResults.Add((Get-AllSharedMailboxes    -OutputCSV $CSVFolder -ProjectKey $ProjectKey @commonParams))
        $allResults.Add((Get-AllResourceMailboxes  -OutputCSV $CSVFolder -ProjectKey $ProjectKey @commonParams))
        $allResults.Add((Get-AllDistributionGroups -OutputCSV $CSVFolder -ProjectKey $ProjectKey @commonParams))
        $allResults.Add((Get-AllMailUserFwd        -OutputCSV $CSVFolder -ProjectKey $ProjectKey @commonParams))
        $allResults.Add((Get-AllAcceptedDomains    -OutputCSV $CSVFolder -ProjectKey $ProjectKey @commonParams))
    }
}

# ---- IMPORT phase ----
if ($Phase -in @('import', 'full')) {
    Invoke-Phase 'Import' {
        $sharedCsv   = Join-Path $CSVSource "Shared_Mailboxes_$ProjectKey.csv"
        $resourceCsv = Join-Path $CSVSource "Resource_Mailboxes_$ProjectKey.csv"
        $groupCsv    = Join-Path $CSVSource "Distribution_Groups_$ProjectKey.csv"
        $contactCsv  = Join-Path $CSVSource "Mail_Contacts_$ProjectKey.csv"
        $domainCsv   = Join-Path $CSVSource "Accepted_Domains_$ProjectKey.csv"

        if (Test-Path $sharedCsv)   { $allResults.Add((Import-AllSharedMailboxes    -CSVFile $sharedCsv   @destParams)) }
        if (Test-Path $resourceCsv) { $allResults.Add((Import-AllResourceMailboxes  -CSVFile $resourceCsv @destParams)) }
        if (Test-Path $groupCsv)    { $allResults.Add((Import-AllDistributionGroups -CSVFile $groupCsv    @destParams)) }
        if (Test-Path $contactCsv)  { $allResults.Add((Import-AllMailContacts       -CSVFile $contactCsv  -LogPath $LogPath)) }
        if (Test-Path $domainCsv)   { $allResults.Add((Import-AllAcceptedDomains    -CSVFile $domainCsv   -LogPath $LogPath)) }
    }
}

# ---- UPDATE phase ----
if ($Phase -in @('update', 'full')) {
    Invoke-Phase 'Update' {
        $sharedCsv = Join-Path $CSVSource "Shared_Mailboxes_$ProjectKey.csv"
        $groupCsv  = Join-Path $CSVSource "Distribution_Groups_$ProjectKey.csv"

        if (Test-Path $sharedCsv) {
            $allResults.Add((Update-AllSharedMailboxesAliases    -CSVFile $sharedCsv @destParams))
            $allResults.Add((Import-AllSharedMailboxPermissions  -CSVFile $sharedCsv @destParams))
        }
        if (Test-Path $groupCsv) {
            $allResults.Add((Update-AllDistributionGroupMember   -CSVFile $groupCsv @destParams))
            $allResults.Add((Update-AllDistributionGroupAliases  -CSVFile $groupCsv @destParams))
        }
    }
}

# ---- CLEANUP phase ----
if ($Phase -in @('cleanup', 'full')) {
    Invoke-Phase 'Cleanup' {
        $mailboxCsv = Join-Path $CSVSource "Mailboxes_$ProjectKey.csv"
        if (Test-Path $mailboxCsv) {
            $allResults.Add((Remove-AllMailboxForwardingEXO -CSVFile $mailboxCsv @destParams))
        }
    }
}

# ---- REPORT phase ----
if ($Phase -in @('report', 'full')) {
    Invoke-Phase 'Report' {
        $allResults.Add((Get-MigrationReport -CSVFolder $CSVFolder -ProjectKey $ProjectKey -Domain $DestDomain -LogPath $LogPath))
    }
}

# ---- Master Summary ----
Write-Log "===== MASTER SUMMARY =====" -Level Header
$allResults | Where-Object { $_ } | Format-Table Function, Succeeded, Failed, Total -AutoSize

$summaryPath = Join-Path $LogFolder "Summary_${ProjectKey}_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
$allResults | Where-Object { $_ } | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8
Write-Log "Summary CSV saved to: $summaryPath" -Level Info
Write-Log "Log file saved to: $LogPath" -Level Info
Write-Log "Start-Migration completed." -Level Success
