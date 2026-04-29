<#
.SYNOPSIS
    Dot-sources all migration functions into the current PowerShell session.

.DESCRIPTION
    Imports all function definitions from the script library using paths
    relative to this file's location ($PSScriptRoot). No environment-specific
    variable files are required — just dot-source this loader before calling
    any migration function.

    Use -IncludeRegularCmds to load utility functions such as ConvertDLtoShared.

.PARAMETER IncludeRegularCmds
    Also loads RegularCmds utility scripts (e.g. ConvertDLtoShared).

.EXAMPLE
    . .\Management\Load-Scripts.ps1

    Loads all core migration functions (SourceEnv + DestinationEnv).

.EXAMPLE
    . .\Management\Load-Scripts.ps1 -IncludeRegularCmds

    Loads all scripts including utility functions.

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : ExchangeOnlineManagement module
#>

param (
    [switch]$IncludeRegularCmds
)

$root = $PSScriptRoot | Split-Path   # toolkit root

# ---- Management helpers (load first — other scripts depend on Resolve-UniqueAlias) ----
. (Join-Path $PSScriptRoot 'Resolve-UniqueAlias.ps1')
. (Join-Path $PSScriptRoot 'New-ProjectConfig.ps1')

# ---- SourceEnv ----
$sourceScripts = @(
    'Get-AllMailboxes.ps1'
    'Get-AllSharedMailboxes.ps1'
    'Get-AllResourceMailboxes.ps1'
    'Get-AllDistributionGroups.ps1'
    'Get-AllMailEnabledSecurityGroups.ps1'
    'Get-AllDynamicDistributionGroups.ps1'
    'Get-AllRoomLists.ps1'
    'Get-AllUnifiedGroups.ps1'
    'Get-AllMailUserFwd.ps1'
    'Get-AllDomainRecords.ps1'
    'Get-AllAcceptedDomains.ps1'
    'Get-AllAutoReplyConfig.ps1'
    'Get-AllSendOnBehalf.ps1'
    'Get-AllLitigationHold.ps1'
    'Get-AllRetentionPolicies.ps1'
    'Get-AllTransportRules.ps1'
    'Get-AllConnectors.ps1'
    'Get-AllAntiSpamPolicies.ps1'
    'Get-AllDkimConfig.ps1'
    'Get-AllAddressBookPolicies.ps1'
    'Get-AllEmailAddressPolicies.ps1'
    'Get-AllOwaMailboxPolicies.ps1'
    'Set-AllMailboxForwardingEXO.ps1'
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
    'Import-AllMailEnabledSecurityGroups.ps1'
    'Import-AllDynamicDistributionGroups.ps1'
    'Import-AllRoomLists.ps1'
    'Import-AllMailContacts.ps1'
    'Import-AllAcceptedDomains.ps1'
    'Import-AllLitigationHold.ps1'
    'Import-AllTransportRules.ps1'
    'Import-AllConnectors.ps1'
    'Import-AllAddressBookPolicies.ps1'
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
. (Join-Path $root 'Validation\Get-AllLicensingReport.ps1')

# ---- RegularCmds (optional) ----
if ($IncludeRegularCmds) {
    . (Join-Path $root 'RegularCmds\ConvertDLtoShared.ps1')
}

Write-Host "[Load-Scripts] All migration functions loaded." -ForegroundColor DarkGray
