# M365 Migration V2 — PowerShell Toolkit

A structured PowerShell toolkit for tenant-to-tenant Microsoft 365 migrations. This is V2, a complete rewrite of the original scripts applying a uniform standard, persistent logging, pre-flight validation, and a safe orchestration workflow.

---

## Architecture Overview

```
Source Tenant (EXO)         CSV Files (local)         Destination Tenant (EXO/AD)
        │                        │                              │
   Get-All* ──────────────► ProjectKey/              Import-All* ───────► New objects
   Get-CSV* ──────────────► *.csv files   ◄──────── CSVTranslator        Update-All*
                                │                              │
                           Validation/                  Remove-All* ─────► Cleanup FWD
                     Test-MigrationPrerequisites
                       Get-MigrationReport ─────────────────────────────► Report CSV
```

The workflow is driven entirely by CSV files. Every `Get-*` script exports to CSV; every `Import-*`/`Update-*` script reads from CSV. `Start-Migration.ps1` orchestrates the full pipeline from a single command.

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| PowerShell | 5.1 or 7.x | 7.x recommended for null-coalescing `?.` operator |
| ExchangeOnlineManagement | >= 3.0 | `Install-Module ExchangeOnlineManagement` |
| ActiveDirectory (RSAT) | Any | Required only for `DestinationADEnv` scripts |
| Exchange Online role | Exchange Admin or Global Admin | Required to create/modify mailboxes |
| AD Write permissions | Target OU | Required for AD forwarding removal and proxy updates |

---

## Quick Start

### 1. Load all functions
```powershell
. .\V2\Management\Load-Scripts.ps1
# Include AD scripts if needed:
. .\V2\Management\Load-Scripts.ps1 -IncludeADScripts -IncludeRegularCmds
```

### 2. Create a project config
```powershell
New-ProjectConfig -ProjectKey "Acme" `
    -Domain "acme.com" -DestinationDomain "amorim.rocks" `
    -CSVFolder "C:\CSV"
# Creates: .\Acme-Config.ps1
```

### 3. Connect to Exchange Online
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@yourtenant.onmicrosoft.com
```

### 4. Run a pre-flight check
```powershell
Test-MigrationPrerequisites -CSVFolder "C:\CSV" -ProjectKey "Acme"
```

### 5. Run the full migration (dry-run first)
```powershell
# Dry-run:
Start-Migration -ConfigPath ".\Acme-Config.ps1" -Phase full -WhatIf

# Live run:
Start-Migration -ConfigPath ".\Acme-Config.ps1" -Phase full
```

### 6. Validate results
```powershell
Get-MigrationReport -CSVFolder "C:\CSV" -ProjectKey "Acme" `
    -Domain "amorim.rocks"
```

---

## Folder Structure

```
V2/
├── Management/
│   ├── Load-Scripts.ps1              # Dot-sources all functions
│   ├── New-ProjectConfig.ps1         # Generates project config from template
│   ├── ProjectConfig.TEMPLATE.ps1    # Config file template (tokens replaced at runtime)
│   └── Start-Migration.ps1           # Safe phased orchestration
│
├── Validation/
│   ├── Test-MigrationPrerequisites.ps1  # Pre-flight environment checks
│   └── Get-MigrationReport.ps1         # Post-migration validation report
│
├── SourceEnv/                        # Export scripts (read from source EXO)
│   ├── Get-AllMailboxes.ps1
│   ├── Get-AllSharedMailboxes.ps1
│   ├── Get-AllResourceMailboxes.ps1
│   ├── Get-AllDistributionGroups.ps1
│   ├── Get-AllMailEnabledSecurityGroups.ps1
│   ├── Get-AllDynamicDistributionGroups.ps1
│   ├── Get-AllRoomLists.ps1
│   ├── Get-AllUnifiedGroups.ps1      # export only (no import — use migration tool)
│   ├── Get-AllMailUserFwd.ps1
│   ├── Get-AllDomainRecords.ps1
│   ├── Get-AllAcceptedDomains.ps1
│   ├── Get-AllAutoReplyConfig.ps1    # report only
│   ├── Get-AllSendOnBehalf.ps1       # report only
│   ├── Get-AllLitigationHold.ps1
│   ├── Get-AllRetentionPolicies.ps1  # report only
│   ├── Get-AllTransportRules.ps1
│   ├── Get-AllConnectors.ps1
│   ├── Get-AllAntiSpamPolicies.ps1   # report only
│   ├── Get-AllDkimConfig.ps1         # report only
│   ├── Get-AllAddressBookPolicies.ps1
│   ├── Get-AllEmailAddressPolicies.ps1 # report only
│   ├── Get-AllOwaMailboxPolicies.ps1   # report only
│   ├── Get-CSVMailboxes.ps1
│   ├── Get-CSVSharedMailboxes.ps1
│   ├── Get-CSVResourceMailboxes.ps1
│   └── Get-CSVDistributionGroups.ps1
│
├── DestinationEnv/                   # Import/Update scripts (write to destination EXO)
│   ├── Import-AllSharedMailboxes.ps1
│   ├── Import-AllSharedMailboxPermissions.ps1
│   ├── Import-AllResourceMailboxes.ps1
│   ├── Import-AllDistributionGroups.ps1
│   ├── Import-AllMailEnabledSecurityGroups.ps1
│   ├── Import-AllDynamicDistributionGroups.ps1
│   ├── Import-AllRoomLists.ps1
│   ├── Import-AllMailContacts.ps1
│   ├── Import-AllAcceptedDomains.ps1
│   ├── Import-AllLitigationHold.ps1
│   ├── Import-AllTransportRules.ps1
│   ├── Import-AllConnectors.ps1
│   ├── Import-AllAddressBookPolicies.ps1
│   ├── Update-AllSharedMailboxesAliases.ps1
│   ├── Update-AllDistributionGroupMember.ps1
│   ├── Update-AllDistributionGroupAliases.ps1
│   ├── CSVTranslator.ps1             (function: Convert-CSVForDestination)
│   └── Remove-AllMailboxForwardingEXO.ps1
│
├── DestinationADEnv/                 # Active Directory scripts
│   ├── Remove-AllMailboxForwardingAD.ps1
│   ├── Remove-AllMailboxForwardingByPrefix.ps1
│   └── Update-AllMailboxesProxyAliases.ps1
│
├── RegularCmds/                      # Utility scripts
│   └── ConvertDLtoShared.ps1
│
└── README.md
```

---

## Script Reference

### Management

| Script | Function | Description |
|---|---|---|
| `Load-Scripts.ps1` | *(dot-source)* | Loads all V2 functions into session |
| `New-ProjectConfig.ps1` | `New-ProjectConfig` | Creates `<ProjectKey>-Config.ps1` from template |
| `Start-Migration.ps1` | *(orchestrator)* | Runs phases: validate, export, import, update, cleanup, report, full |

### Validation

| Script | Function | Description |
|---|---|---|
| `Test-MigrationPrerequisites.ps1` | `Test-MigrationPrerequisites` | Checks EXO connection, modules, disk space, CSV presence |
| `Get-MigrationReport.ps1` | `Get-MigrationReport` | Compares source CSVs vs destination objects, outputs report CSV |

### SourceEnv

| Script | Function | Outputs |
|---|---|---|
| `Get-AllMailboxes.ps1` | `Get-AllMailboxes` | `Mailboxes_<ProjectKey>.csv` |
| `Get-AllSharedMailboxes.ps1` | `Get-AllSharedMailboxes` | `Shared_Mailboxes_<ProjectKey>.csv` |
| `Get-AllResourceMailboxes.ps1` | `Get-AllResourceMailboxes` | `Resource_Mailboxes_<ProjectKey>.csv` |
| `Get-AllDistributionGroups.ps1` | `Get-AllDistributionGroups` | `Distribution_Groups_<ProjectKey>.csv` |
| `Get-AllMailEnabledSecurityGroups.ps1` | `Get-AllMailEnabledSecurityGroups` | `Mail_Enabled_Security_Groups_<ProjectKey>.csv` |
| `Get-AllDynamicDistributionGroups.ps1` | `Get-AllDynamicDistributionGroups` | `Dynamic_Distribution_Groups_<ProjectKey>.csv` |
| `Get-AllRoomLists.ps1` | `Get-AllRoomLists` | `Room_Lists_<ProjectKey>.csv` |
| `Get-AllUnifiedGroups.ps1` | `Get-AllUnifiedGroups` | `Unified_Groups_<ProjectKey>.csv` *(export only)* |
| `Get-AllMailUserFwd.ps1` | `Get-AllMailUserFwd` | `MailUsers_Fwd_<ProjectKey>.csv` |
| `Get-AllDomainRecords.ps1` | `Get-AllDomainRecords` | `DNS_Records_<domain>_<ProjectKey>.csv` |
| `Get-AllAcceptedDomains.ps1` | `Get-AllAcceptedDomains` | `Accepted_Domains_<ProjectKey>.csv` |
| `Get-AllAutoReplyConfig.ps1` | `Get-AllAutoReplyConfig` | `AutoReply_Config_<ProjectKey>.csv` *(report only)* |
| `Get-AllSendOnBehalf.ps1` | `Get-AllSendOnBehalf` | `SendOnBehalf_<ProjectKey>.csv` *(report only)* |
| `Get-AllLitigationHold.ps1` | `Get-AllLitigationHold` | `Litigation_Hold_<ProjectKey>.csv` |
| `Get-AllRetentionPolicies.ps1` | `Get-AllRetentionPolicies` | `Retention_Policies_<ProjectKey>.csv` *(report only)* |
| `Get-AllTransportRules.ps1` | `Get-AllTransportRules` | `Transport_Rules_<ProjectKey>.csv` |
| `Get-AllConnectors.ps1` | `Get-AllConnectors` | `Inbound_Connectors_<ProjectKey>.csv`, `Outbound_Connectors_<ProjectKey>.csv` |
| `Get-AllAntiSpamPolicies.ps1` | `Get-AllAntiSpamPolicies` | `AntiSpam_Policies_<ProjectKey>.csv`, `AntiPhish_Policies_<ProjectKey>.csv` *(report only)* |
| `Get-AllDkimConfig.ps1` | `Get-AllDkimConfig` | `DKIM_Config_<ProjectKey>.csv` *(report only)* |
| `Get-AllAddressBookPolicies.ps1` | `Get-AllAddressBookPolicies` | `Address_Book_Policies_<ProjectKey>.csv` |
| `Get-AllEmailAddressPolicies.ps1` | `Get-AllEmailAddressPolicies` | `Email_Address_Policies_<ProjectKey>.csv` *(report only)* |
| `Get-AllOwaMailboxPolicies.ps1` | `Get-AllOwaMailboxPolicies` | `OWA_Mailbox_Policies_<ProjectKey>.csv` *(report only)* |
| `Get-CSVMailboxes.ps1` | `Get-CSVMailboxes` | `Mailboxes_<ProjectKey>.csv` |
| `Get-CSVSharedMailboxes.ps1` | `Get-CSVSharedMailboxes` | `Shared_Mailboxes_<ProjectKey>.csv` |
| `Get-CSVResourceMailboxes.ps1` | `Get-CSVResourceMailboxes` | `Resource_Mailboxes_<ProjectKey>.csv` |
| `Get-CSVDistributionGroups.ps1` | `Get-CSVDistributionGroups` | `Distribution_Groups_<ProjectKey>.csv` |

### DestinationEnv

| Script | Function | Phase |
|---|---|---|
| `Import-AllSharedMailboxes.ps1` | `Import-AllSharedMailboxes` | import |
| `Import-AllSharedMailboxPermissions.ps1` | `Import-AllSharedMailboxPermissions` | update |
| `Import-AllResourceMailboxes.ps1` | `Import-AllResourceMailboxes` | import |
| `Import-AllDistributionGroups.ps1` | `Import-AllDistributionGroups` | import |
| `Import-AllMailEnabledSecurityGroups.ps1` | `Import-AllMailEnabledSecurityGroups` | import |
| `Import-AllDynamicDistributionGroups.ps1` | `Import-AllDynamicDistributionGroups` | import |
| `Import-AllRoomLists.ps1` | `Import-AllRoomLists` | import |
| `Import-AllMailContacts.ps1` | `Import-AllMailContacts` | import |
| `Import-AllAcceptedDomains.ps1` | `Import-AllAcceptedDomains` | import |
| `Import-AllLitigationHold.ps1` | `Import-AllLitigationHold` | import |
| `Import-AllTransportRules.ps1` | `Import-AllTransportRules` | import |
| `Import-AllConnectors.ps1` | `Import-AllConnectors` | import |
| `Import-AllAddressBookPolicies.ps1` | `Import-AllAddressBookPolicies` | import |
| `Update-AllSharedMailboxesAliases.ps1` | `Update-AllSharedMailboxesAliases` | update |
| `Update-AllDistributionGroupMember.ps1` | `Update-AllDistributionGroupMember` | update |
| `Update-AllDistributionGroupAliases.ps1` | `Update-AllDistributionGroupAliases` | update |
| `CSVTranslator.ps1` | `Convert-CSVForDestination` | *(manual)* |
| `Remove-AllMailboxForwardingEXO.ps1` | `Remove-AllMailboxForwardingEXO` | cleanup |

### DestinationADEnv

| Script | Function | Description |
|---|---|---|
| `Remove-AllMailboxForwardingAD.ps1` | `Remove-AllMailboxForwardingAD` | Clear forwarding attrs by OU |
| `Remove-AllMailboxForwardingByPrefix.ps1` | `Remove-AllMailboxForwardingByPrefix` | Clear forwarding attrs by prefix |
| `Update-AllMailboxesProxyAliases.ps1` | `Update-AllMailboxesProxyAliases` | Update proxyAddresses in AD using mapping file |

### RegularCmds

| Script | Function | Description |
|---|---|---|
| `ConvertDLtoShared.ps1` | `ConvertDLtoShared` | Convert a Distribution List to a Shared Mailbox |

---

## Configuration File Reference

Variables set by `<ProjectKey>-Config.ps1` (generated by `New-ProjectConfig`):

| Variable | Type | Example | Description |
|---|---|---|---|
| `$ProjectKey` | string | `"Acme"` | Unique identifier; used in file names and folder names |
| `$Prefix` | string | `""` | Optional prefix for destination object aliases |
| `$Domain` | string | `"acme.com"` | Source tenant primary domain |
| `$DestDomain` | string | `"amorim.rocks"` | Destination tenant SMTP domain |
| `$CSVFolder` | string | `"C:\CSV"` | Base directory for all CSV files |
| `$CSVSource` | string | `"C:\CSV\Acme"` | Project-specific subfolder (auto-set) |
| `$LogFolder` | string | `"C:\CSV\Acme\Logs"` | Log file output directory (auto-set) |

---

## CSV Format Reference

### `Shared_Mailboxes_<ProjectKey>.csv`

| Column | Required | Notes |
|---|---|---|
| `DisplayName` | Yes | Source display name |
| `PrimarySmtpAddress` | Yes | Source primary SMTP; used to build destination alias |
| `Alias` | No | Source alias |
| `EmailAddresses` | No | Semicolon-separated; added as secondary aliases in destination |
| `FullAccessUsers` | No | Semicolon-separated email addresses |
| `SendAsUsers` | No | Semicolon-separated email addresses |
| `ForwardingAddress` | No | Leave blank if no forwarding |
| `ForwardingSmtpAddress` | No | Leave blank if no forwarding |
| `DeliverToMailboxAndForward` | No | `True` or `False` |

### `Resource_Mailboxes_<ProjectKey>.csv`

| Column | Required | Notes |
|---|---|---|
| `DisplayName` | Yes | Source display name |
| `PrimarySmtpAddress` | Yes | Source primary SMTP |
| `ResourceType` | Yes | `Room` or `Equipment` |
| `Capacity` | No | Integer; applied only to Room mailboxes |
| `Location` | No | Maps to `Office` attribute |
| `Telephone` | No | Maps to `Phone` attribute |
| `Department` | No | |
| `Company` | No | |
| `ADP` | No | AddressBookPolicy name (warning if not found in destination) |
| `Street`, `City`, `StateProvince`, `Zip`, `Country` | No | Address fields |

### `Distribution_Groups_<ProjectKey>.csv`

| Column | Required | Notes |
|---|---|---|
| `DisplayName` | Yes | |
| `PrimarySmtpAddress` | Yes | |
| `Alias` | Yes | Semicolon-separated list of all SMTP addresses (used by Update-AllDistributionGroupAliases) |
| `Members` | No | Semicolon-separated primary SMTP addresses |

### `Mail_Contacts_<ProjectKey>.csv`

| Column | Required | Notes |
|---|---|---|
| `DisplayName` | Yes | |
| `ExternalEmailAddress` | Yes | External email the contact points to |
| `Alias` | No | Auto-derived from ExternalEmailAddress if omitted |

### `Accepted_Domains_<ProjectKey>.csv`

| Column | Required | Notes |
|---|---|---|
| `DomainName` | Yes | FQDN of the domain to add |
| `DomainType` | No | Defaults to `Authoritative` |

### Mapping file (`Mapping_Mailboxes_<ProjectKey>.csv`)

Used by `Convert-CSVForDestination` and `Update-AllMailboxesProxyAliases`.

| Column | Required | Notes |
|---|---|---|
| `Source user email` | Yes | Source tenant UPN or primary SMTP |
| `Destination user email` | Yes | Destination tenant UPN or primary SMTP |

### `Dynamic_Distribution_Groups_<ProjectKey>.csv`

| Column | Required | Notes |
|---|---|---|
| `DisplayName` | Yes | |
| `PrimarySmtpAddress` | Yes | |
| `Alias` | No | Semicolon-separated SMTP addresses |
| `RecipientFilter` | No | Custom OPATH filter — review after import |
| `IncludedRecipients` | No | Used when no custom filter; defaults to `AllRecipients` |
| `ConditionalDept` | No | Semicolon-separated department values |
| `ConditionalCompany` | No | Semicolon-separated company values |

### `Litigation_Hold_<ProjectKey>.csv`

| Column | Required | Notes |
|---|---|---|
| `PrimarySmtpAddress` | Yes | Must match destination mailbox |
| `LitigationHoldEnabled` | Yes | `True` or `False` |
| `LitigationHoldDuration` | No | Days or `Unlimited` |
| `LitigationHoldOwner` | No | Free-text owner label |

### `Transport_Rules_<ProjectKey>.csv`

| Column | Required | Notes |
|---|---|---|
| `Name` | Yes | |
| `Priority` | No | |
| `State` | No | `Enabled` or `Disabled` (import always creates Disabled unless `-Enabled` flag used) |
| `Comments` | No | |
| `SubjectContainsWords`, `SenderDomainIs`, etc. | No | Semicolon-separated values |
| `ApplyHtmlDisclaimerText` | No | HTML string |

### `Inbound_Connectors_<ProjectKey>.csv` / `Outbound_Connectors_<ProjectKey>.csv`

| Column | Required | Notes |
|---|---|---|
| `Name` | Yes | |
| `ConnectorType` | No | `OnPremises` or `Partner` |
| `SenderDomains` / `RecipientDomains` | No | Semicolon-separated |
| `SenderIPAddresses` / `SmartHosts` | No | Semicolon-separated |
| `RequireTls` / `TlsSettings` | No | `True`/`False` or TLS mode string |

---

## Alias Naming Convention

All destination objects follow the pattern:

```
<Prefix>-<sourceLocalPart>@<DestDomain>
```

- Invalid characters (`[^a-zA-Z0-9._-]`) are stripped
- Result is lowercased
- Example: `invoices@amorim.rocks` (from source `invoices@acme.com` with no prefix)
- Example with prefix: `acme-invoices@amorim.rocks` (from source `invoices@acme.com` with `-Prefix "acme"`)

---

## Logging

Every function accepts an optional `-LogPath` parameter. When provided:
- All console output is mirrored to the file using `Add-Content`
- Log format: `[yyyy-MM-dd HH:mm:ss][Level] Message`
- Levels: `Info`, `Success`, `Warning`, `Error`, `Verbose`

`Start-Migration.ps1` automatically creates a log file in `$LogFolder` if `-LogPath` is not specified:
```
$LogFolder\Migration_<ProjectKey>_<yyyyMMdd_HHmm>.log
```

A summary CSV is also written after each run:
```
$LogFolder\Summary_<ProjectKey>_<yyyyMMdd_HHmm>.csv
```

---

## WhatIf / Dry-Run

All scripts that create, modify, or delete objects support `-WhatIf`. This prints what would happen without making any changes.

Run a complete dry-run of any phase:
```powershell
Start-Migration -ConfigPath ".\Acme-Config.ps1" -Phase import -WhatIf
Start-Migration -ConfigPath ".\Acme-Config.ps1" -Phase full -WhatIf
```

Run an individual function in dry-run:
```powershell
Import-AllSharedMailboxes -CSVFile "C:\CSV\Acme\Shared_Mailboxes_Acme.csv" `
    -Company "Acme" -Domain "amorim.rocks" -WhatIf
```

---

## Troubleshooting

| Error | Cause | Resolution |
|---|---|---|
| `CSV missing required column: 'PrimarySmtpAddress'` | Column name mismatch in CSV | Verify CSV headers match the expected column names exactly |
| `The recipient ... couldn't be found` in `Update-AllDistributionGroupMember` | Member not yet provisioned in destination | Run the import phase first; members must exist before being added to groups |
| `No active EXO session` in `Test-MigrationPrerequisites` | Not connected to Exchange Online | Run `Connect-ExchangeOnline -UserPrincipalName admin@tenant.onmicrosoft.com` |
| `ExchangeOnlineManagement module >= 3.0 not found` | Module missing or outdated | Run `Install-Module ExchangeOnlineManagement` or `Update-Module ExchangeOnlineManagement` |
| `Config file already exists` in `New-ProjectConfig` | Config for this ProjectKey exists | Add `-Force` to overwrite, or use a different `$OutputPath` |
| `'_old' group already exists` in `ConvertDLtoShared` | Script was previously run for this DG | Manual cleanup required — remove the `_old` group before re-running |
| `Could not set ADP ... may not exist in destination` | AddressBookPolicy from source doesn't exist in destination | Create the ADP in the destination first, or leave blank to skip |
| Forwarding not removed after cleanup phase | `CustomAttribute3` does not match `$Prefix` | Verify `CustomAttribute3` values in the destination tenant |
| `Failed to set hold for '...'` in `Import-AllLitigationHold` | Mailbox not licensed for Litigation Hold | Assign E3/E5 or equivalent license to the destination mailbox |
| Transport rule created but not active | Rules are created Disabled by default | Review the rule in EAC, then enable manually or re-run with `-Enabled` |
| `Using custom RecipientFilter` warning in `Import-AllDynamicDistributionGroups` | Source filter references source-tenant attributes | Review and update the filter in the destination tenant after import |

---

## Bugs Fixed in V2

| Script | Bug | Fix |
|---|---|---|
| `Import-AllDistributionGroups` | `"$_.Exception.Message"` — broken string interpolation | `"$($_.Exception.Message)"` |
| `Update-AllDistributionGroupAliases` | Same interpolation bug on group address | Fixed |
| `Update-AllDistributionGroupAliases` | Selects column `Aliases` — export produces `Alias` | Column name corrected to `Alias` |
| `Update-AllDistributionGroupMember` | Members split on `,` — exports join on `;` | Split delimiter corrected to `;` |
| `Get-AllMailUserFwd` | `Split-Path` applied to `$outputCSV` then write path used `$outputCSV` as dir | `Split-Path` removed; `$OutputCSV` is now validated as a directory |
| `Remove-AllMailboxForwardingEXO` | Raw script with inline `Connect-ExchangeOnline` and hardcoded country codes | Refactored into parametrized function |
| `<ProjectKey>-Variables.ps1` | `========================` separator — invalid PS1 syntax | Replaced by `New-ProjectConfig.ps1` + template |
| `CSVTranslator.ps1` | Script-mode file; `Convert-Emails` defined inside `ForEach-Object` loop | Converted to function; helper moved to `begin` block |
| `ConvertDLtoShared.ps1` | Raw script with hardcoded `$DGIdentity`; no idempotency; no WhatIf | Converted to parametrized function with idempotency check |

---

## Changelog

### V2.1 — 2026
- Added 15 new SourceEnv scripts: `Get-AllMailEnabledSecurityGroups`, `Get-AllDynamicDistributionGroups`, `Get-AllRoomLists`, `Get-AllUnifiedGroups`, `Get-AllAutoReplyConfig`, `Get-AllSendOnBehalf`, `Get-AllLitigationHold`, `Get-AllRetentionPolicies`, `Get-AllTransportRules`, `Get-AllConnectors`, `Get-AllAntiSpamPolicies`, `Get-AllDkimConfig`, `Get-AllAddressBookPolicies`, `Get-AllEmailAddressPolicies`, `Get-AllOwaMailboxPolicies`
- Added 7 new DestinationEnv scripts: `Import-AllMailEnabledSecurityGroups`, `Import-AllDynamicDistributionGroups`, `Import-AllRoomLists`, `Import-AllLitigationHold`, `Import-AllTransportRules`, `Import-AllConnectors`, `Import-AllAddressBookPolicies`
- Transport rules and connectors created in Disabled state by default; use `-Enabled` to activate on creation
- Dynamic distribution groups with custom `RecipientFilter` emit a warning to review after import
- `Load-Scripts.ps1` updated to include all new scripts

### V2.0 — 2025
- Complete rewrite applying a uniform standard across all 34 scripts
- Added comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`) to every function
- Added `[CmdletBinding(SupportsShouldProcess)]` to all write/modify/delete functions
- Added `begin/process/end` structure with `$successCount`/`$errorCount` tracking
- Added `Write-Log` helper with optional `$LogPath` file mirroring to every function
- Added CSV column validation in `begin` block for all reader functions
- Added `Write-Verbose` for per-item progress messages
- All functions return a `[PSCustomObject]` summary for pipeline composition
- Fixed all bugs listed in the Bugs Fixed section above
- New scripts: `Get-AllAcceptedDomains`, `Import-AllMailContacts`, `Import-AllAcceptedDomains`, `Test-MigrationPrerequisites`, `Get-MigrationReport`, `New-ProjectConfig`, `Start-Migration`
- `Load-Scripts.ps1` now uses `$PSScriptRoot`-relative paths instead of hardcoded environment paths

### V1.0 — 2025-02-24 to 2025-04-14
- Initial implementation of migration scripts
- Basic error handling with `Write-Host` colour coding
- Functional coverage: shared mailboxes, resource mailboxes, distribution groups, forwarding removal, proxy alias updates
