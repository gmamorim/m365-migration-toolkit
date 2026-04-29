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
New-ProjectConfig -ProjectKey "Acme" -CountryCode "ES1" `
    -Domain "acme.com" -DestinationDomain "team.blue" `
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
    -CountryCode "ES1" -Domain "team.blue"
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
│   ├── Get-AllMailUserFwd.ps1
│   ├── Get-AllDomainRecords.ps1
│   ├── Get-AllAcceptedDomains.ps1    ← NEW in V2
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
│   ├── Import-AllMailContacts.ps1    ← NEW in V2
│   ├── Import-AllAcceptedDomains.ps1 ← NEW in V2
│   ├── Update-AllSharedMailboxesAliases.ps1
│   ├── Update-AllDistributionGroupMember.ps1
│   ├── Update-AllDistributionGroupAliases.ps1
│   ├── CSVTranslator.ps1             (function: Convert-CSVForDestination)
│   └── Remove-AllMailboxForwardingEXO.ps1
│
├── DestinationADEnv/                 # Active Directory scripts
│   ├── Remove-AllMailboxForwardingAD.ps1
│   ├── Remove-AllMailboxForwardingByCountryCode.ps1
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
| `Get-AllMailUserFwd.ps1` | `Get-AllMailUserFwd` | `MailUsers_Fwd_<ProjectKey>.csv` |
| `Get-AllDomainRecords.ps1` | `Get-AllDomainRecords` | `DNS_Records_<domain>_<ProjectKey>.csv` |
| `Get-AllAcceptedDomains.ps1` | `Get-AllAcceptedDomains` | `Accepted_Domains_<ProjectKey>.csv` |
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
| `Import-AllMailContacts.ps1` | `Import-AllMailContacts` | import |
| `Import-AllAcceptedDomains.ps1` | `Import-AllAcceptedDomains` | import |
| `Update-AllSharedMailboxesAliases.ps1` | `Update-AllSharedMailboxesAliases` | update |
| `Update-AllDistributionGroupMember.ps1` | `Update-AllDistributionGroupMember` | update |
| `Update-AllDistributionGroupAliases.ps1` | `Update-AllDistributionGroupAliases` | update |
| `CSVTranslator.ps1` | `Convert-CSVForDestination` | *(manual)* |
| `Remove-AllMailboxForwardingEXO.ps1` | `Remove-AllMailboxForwardingEXO` | cleanup |

### DestinationADEnv

| Script | Function | Description |
|---|---|---|
| `Remove-AllMailboxForwardingAD.ps1` | `Remove-AllMailboxForwardingAD` | Clear forwarding attrs by OU |
| `Remove-AllMailboxForwardingByCountryCode.ps1` | `Remove-AllMailboxForwardingByCountryCode` | Clear forwarding attrs by country code |
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
| `$CountryCode` | string | `"ES1"` | Prefix for destination object aliases |
| `$Domain` | string | `"acme.com"` | Source tenant primary domain |
| `$DestDomain` | string | `"team.blue"` | Destination tenant SMTP domain |
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

---

## Alias Naming Convention

All destination objects follow the pattern:

```
<CountryCode>-<sourceLocalPart>@<DestDomain>
```

- Invalid characters (`[^a-zA-Z0-9._-]`) are stripped
- Result is lowercased
- Example: `ES1-invoices@team.blue` (from source `invoices@acme.com` with CountryCode `ES1`)

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
    -CountryCode "ES1" -Company "Acme" -Domain "team.blue" -WhatIf
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
| Forwarding not removed after cleanup phase | `CustomAttribute3` does not match `$CountryCode` | Verify `CustomAttribute3` values in the destination tenant |

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
| `AR-Variables.ps1` / `SEU1-variables.ps1` | `========================` separator — invalid PS1 syntax | Replaced by `New-ProjectConfig.ps1` + template |
| `CSVTranslator.ps1` | Script-mode file; `Convert-Emails` defined inside `ForEach-Object` loop | Converted to function; helper moved to `begin` block |
| `ConvertDLtoShared.ps1` | Raw script with hardcoded `$DGIdentity`; no idempotency; no WhatIf | Converted to parametrized function with idempotency check |

---

## Changelog

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
