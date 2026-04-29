<#
.SYNOPSIS
    Dot-sources all V2 migration functions into the current PowerShell session.

.DESCRIPTION
    Imports all function definitions from the V2 script library using paths
    relative to this file's location ($PSScriptRoot). No environment-specific
    variable files are required — just dot-source this loader before calling
    any migration function.

    Use -IncludeRegularCmds to load utility functions such as ConvertDLtoShared.

.PARAMETER IncludeRegularCmds
    Also loads RegularCmds utility scripts (e.g. ConvertDLtoShared).

.EXAMPLE
    . .\V2\Management\Load-Scripts.ps1

    Loads all core migration functions (SourceEnv + DestinationEnv).

.EXAMPLE
    . .\V2\Management\Load-Scripts.ps1 -IncludeRegularCmds

    Loads all scripts including utility functions.

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : ExchangeOnlineManagement module
#>

param (
    [switch]$IncludeRegularCmds
)

$root = $PSScriptRoot | Split-Path   # V2 root

# ---- Management helpers (load first — other scripts depend on Resolve-UniqueAlias) ----
. (Join-Path $PSScriptRoot 'Resolve-UniqueAlias.ps1')
. (Join-Path $PSScriptRoot 'New-ProjectConfig.ps1')

# ---- SourceEnv ----
$sourceScripts = @(
    'Get-AllMailboxes.ps1'
    'Get-AllSharedMailboxes.ps1'
    'Get-AllResourceMailboxes.ps1'
    'Get-AllDistributionGroups.ps1'
    'Get-AllMailUserFwd.ps1'
    'Get-AllDomainRecords.ps1'
    'Get-AllAcceptedDomains.ps1'
    'Get-CSVMailboxes.ps1'
    'Get-CSVSharedMailboxes.ps1'
    'Get-CSVResourceMailboxes.ps1'
    'Get-CSVDistributionGroups.ps1'
)
foreach ($s in $sourceScripts) {
    . (Join-Path $root "SourceEnv\$s")
}

# ---- DestinationEnv ----
$destScripts = @(
    'Import-AllSharedMailboxes.ps1'
    'Import-AllSharedMailboxPermissions.ps1'
    'Import-AllResourceMailboxes.ps1'
    'Import-AllDistributionGroups.ps1'
    'Import-AllMailContacts.ps1'
    'Import-AllAcceptedDomains.ps1'
    'Update-AllSharedMailboxesAliases.ps1'
    'Update-AllDistributionGroupMember.ps1'
    'Update-AllDistributionGroupAliases.ps1'
    'CSVTranslator.ps1'
    'Remove-AllMailboxForwardingEXO.ps1'
)
foreach ($s in $destScripts) {
    . (Join-Path $root "DestinationEnv\$s")
}

# ---- Validation ----
. (Join-Path $root 'Validation\Test-MigrationPrerequisites.ps1')
. (Join-Path $root 'Validation\Get-MigrationReport.ps1')

# ---- RegularCmds (optional) ----
if ($IncludeRegularCmds) {
    . (Join-Path $root 'RegularCmds\ConvertDLtoShared.ps1')
}

Write-Host "[Load-Scripts] All V2 migration functions loaded." -ForegroundColor DarkGray
