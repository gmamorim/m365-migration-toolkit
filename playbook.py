#!/usr/bin/env python3
"""M365 Migration Playbook — generates HTML and serves on http://localhost:8080"""

import http.server
import threading
import webbrowser
import time

# ---------------------------------------------------------------------------
# HTML CONTENT
# ---------------------------------------------------------------------------

HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>M365 Migration Playbook</title>
<style>
/* ── Reset & Base ── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  font-size: 14px;
  line-height: 1.6;
  color: #172B4D;
  background: #F4F5F7;
  display: flex;
  min-height: 100vh;
}

/* ── Sidebar ── */
#sidebar {
  width: 260px;
  min-width: 260px;
  background: #0052CC;
  color: #fff;
  display: flex;
  flex-direction: column;
  position: fixed;
  top: 0; left: 0; bottom: 0;
  overflow-y: auto;
  z-index: 100;
}
#sidebar-header {
  padding: 20px 16px 12px;
  border-bottom: 1px solid rgba(255,255,255,0.15);
}
#sidebar-header .product { font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; opacity: 0.7; }
#sidebar-header .title { font-size: 15px; font-weight: 600; margin-top: 4px; }
#sidebar-header .version { font-size: 11px; opacity: 0.6; margin-top: 2px; }
#sidebar nav { padding: 8px 0 24px; }
#sidebar nav a {
  display: block;
  padding: 7px 16px 7px 20px;
  color: rgba(255,255,255,0.85);
  text-decoration: none;
  font-size: 13px;
  border-left: 3px solid transparent;
  transition: background 0.15s, color 0.15s, border-color 0.15s;
}
#sidebar nav a:hover { background: rgba(255,255,255,0.1); color: #fff; }
#sidebar nav a.active { background: rgba(255,255,255,0.15); color: #fff; border-left-color: #fff; font-weight: 600; }
#sidebar nav .nav-group { font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em; color: rgba(255,255,255,0.45); padding: 14px 16px 4px; }

/* ── Main content ── */
#main {
  margin-left: 260px;
  flex: 1;
  min-width: 0;
}
#topbar {
  background: #fff;
  border-bottom: 1px solid #DFE1E6;
  padding: 10px 32px;
  font-size: 12px;
  color: #6B778C;
  display: flex;
  align-items: center;
  gap: 6px;
  position: sticky; top: 0; z-index: 50;
}
#topbar span.sep { opacity: 0.5; }
#topbar span.current { color: #172B4D; font-weight: 500; }
#content { padding: 32px 40px 64px; max-width: 960px; }

/* ── Typography ── */
h1 { font-size: 28px; font-weight: 700; color: #172B4D; margin-bottom: 8px; }
h2 { font-size: 20px; font-weight: 600; color: #172B4D; margin: 36px 0 12px; padding-bottom: 6px; border-bottom: 2px solid #DFE1E6; }
h3 { font-size: 16px; font-weight: 600; color: #172B4D; margin: 24px 0 8px; }
h4 { font-size: 14px; font-weight: 600; color: #172B4D; margin: 16px 0 6px; }
p { margin-bottom: 12px; }
ul, ol { margin: 8px 0 12px 20px; }
li { margin-bottom: 4px; }
a { color: #0052CC; text-decoration: none; }
a:hover { text-decoration: underline; }

/* ── Page header ── */
.page-header { margin-bottom: 28px; }
.page-header .meta { font-size: 12px; color: #6B778C; margin-top: 4px; }

/* ── Status lozenges ── */
.lozenge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 3px;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.lozenge-success { background: #E3FCEF; color: #006644; }
.lozenge-warning { background: #FFFAE6; color: #974F0C; }
.lozenge-error   { background: #FFEBE6; color: #BF2600; }
.lozenge-info    { background: #DEEBFF; color: #0747A6; }
.lozenge-neutral { background: #F4F5F7; color: #42526E; border: 1px solid #DFE1E6; }

/* ── Panels ── */
.panel {
  border-radius: 4px;
  padding: 14px 16px;
  margin: 14px 0;
  display: flex;
  gap: 10px;
  align-items: flex-start;
}
.panel-icon { font-size: 16px; flex-shrink: 0; margin-top: 1px; }
.panel-body { flex: 1; }
.panel-body strong { display: block; margin-bottom: 2px; }
.panel-info    { background: #DEEBFF; border-left: 3px solid #0052CC; }
.panel-warning { background: #FFFAE6; border-left: 3px solid #FF991F; }
.panel-success { background: #E3FCEF; border-left: 3px solid #00875A; }
.panel-error   { background: #FFEBE6; border-left: 3px solid #DE350B; }

/* ── Code blocks ── */
pre {
  background: #1B2638;
  color: #CDD5E0;
  border-radius: 6px;
  padding: 16px 18px;
  overflow-x: auto;
  margin: 12px 0;
  font-size: 13px;
  line-height: 1.55;
  font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
}
pre .kw  { color: #79C0FF; }  /* keyword */
pre .fn  { color: #D2A8FF; }  /* function/cmdlet */
pre .str { color: #A5D6FF; }  /* string */
pre .cm  { color: #8B949E; font-style: italic; }  /* comment */
pre .var { color: #FFA657; }  /* variable */
pre .op  { color: #FF7B72; }  /* operator/param flag */
code {
  background: #F4F5F7;
  border: 1px solid #DFE1E6;
  border-radius: 3px;
  padding: 1px 5px;
  font-size: 12.5px;
  font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
  color: #172B4D;
}
pre code { background: none; border: none; padding: 0; color: inherit; font-size: inherit; }

/* ── Tables ── */
table { width: 100%; border-collapse: collapse; margin: 12px 0; font-size: 13px; }
thead th {
  background: #F4F5F7;
  border: 1px solid #DFE1E6;
  padding: 8px 12px;
  text-align: left;
  font-weight: 600;
  color: #42526E;
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.03em;
}
tbody td { border: 1px solid #DFE1E6; padding: 8px 12px; vertical-align: top; }
tbody tr:nth-child(even) td { background: #FAFBFC; }
tbody tr:hover td { background: #F4F5F7; }

/* ── Steps ── */
.step-list { list-style: none; margin: 0; padding: 0; counter-reset: steps; }
.step-list li {
  counter-increment: steps;
  display: flex;
  gap: 14px;
  margin-bottom: 18px;
  align-items: flex-start;
}
.step-list li::before {
  content: counter(steps);
  background: #0052CC;
  color: #fff;
  width: 26px; height: 26px;
  border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: 12px; font-weight: 700;
  flex-shrink: 0; margin-top: 1px;
}
.step-list li .step-body { flex: 1; }
.step-list li .step-body strong { display: block; margin-bottom: 4px; font-size: 14px; }

/* ── Phase timeline ── */
.phase-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
  gap: 10px;
  margin: 16px 0;
}
.phase-card {
  background: #fff;
  border: 1px solid #DFE1E6;
  border-radius: 6px;
  padding: 12px 14px;
  text-align: center;
  cursor: default;
}
.phase-card .phase-num { font-size: 11px; color: #6B778C; text-transform: uppercase; letter-spacing: 0.05em; }
.phase-card .phase-name { font-size: 13px; font-weight: 600; color: #0052CC; margin-top: 4px; }
.phase-card .phase-flag { font-size: 10px; color: #6B778C; margin-top: 4px; }

/* ── Checklist ── */
.checklist { list-style: none; margin: 0; padding: 0; }
.checklist li {
  display: flex; gap: 10px; align-items: flex-start;
  padding: 6px 0; border-bottom: 1px solid #F4F5F7;
}
.checklist li:last-child { border-bottom: none; }
.checklist li .check { color: #00875A; font-size: 15px; flex-shrink: 0; }

/* ── Section divider ── */
.section { margin-top: 8px; }
.section + .section { margin-top: 48px; padding-top: 0; }
hr { border: none; border-top: 1px solid #DFE1E6; margin: 28px 0; }

/* ── Scrollspy ── */
section { scroll-margin-top: 56px; }
</style>
</head>
<body>

<!-- ═══════════════════════════ SIDEBAR ═══════════════════════════ -->
<aside id="sidebar">
  <div id="sidebar-header">
    <div class="product">M365 Migration</div>
    <div class="title">Migration Playbook</div>
    <div class="version">V2 · PowerShell Toolkit</div>
  </div>
  <nav>
    <div class="nav-group">Introduction</div>
    <a href="#overview"      data-section="overview">Overview</a>
    <a href="#prereqs"       data-section="prereqs">Pre-Requisites</a>
    <a href="#architecture"  data-section="architecture">Architecture</a>

    <div class="nav-group">Migration Phases</div>
    <a href="#phase0"  data-section="phase0">Phase 0 — Project Setup</a>
    <a href="#phase1"  data-section="phase1">Phase 1 — Pre-Flight</a>
    <a href="#phase2"  data-section="phase2">Phase 2 — Source Export</a>
    <a href="#phase3"  data-section="phase3">Phase 3 — Data Prep</a>
    <a href="#phase4"  data-section="phase4">Phase 4 — Object Creation</a>
    <a href="#phase5"  data-section="phase5">Phase 5 — Permissions &amp; Aliases</a>
    <a href="#phase6"  data-section="phase6">Phase 6 — Validation</a>
    <a href="#phase7"  data-section="phase7">Phase 7 — Cutover</a>

    <div class="nav-group">Reference</div>
    <a href="#rollback"    data-section="rollback">Rollback</a>
    <a href="#scriptref"   data-section="scriptref">Script Reference</a>
    <a href="#csvformat"   data-section="csvformat">CSV Format</a>
    <a href="#troubleshoot" data-section="troubleshoot">Troubleshooting</a>
  </nav>
</aside>

<!-- ═══════════════════════════ MAIN ═══════════════════════════ -->
<div id="main">
  <div id="topbar">
    <span>M365 Migration</span>
    <span class="sep">›</span>
    <span class="current" id="breadcrumb">Overview</span>
  </div>

  <div id="content">

    <!-- ══ OVERVIEW ══ -->
    <section id="overview" class="section">
      <div class="page-header">
        <h1>M365 Migration Playbook</h1>
        <div class="meta">
          <span class="lozenge lozenge-info">V2</span>&nbsp;
          <span class="lozenge lozenge-neutral">Tenant-to-Tenant</span>&nbsp;
          <span class="lozenge lozenge-success">PowerShell</span>
        </div>
      </div>

      <div class="panel panel-info">
        <span class="panel-icon">ℹ️</span>
        <div class="panel-body">
          <strong>Purpose</strong>
          This playbook guides you through a complete tenant-to-tenant Microsoft 365 migration
          using the V2 PowerShell toolkit. Follow each phase in order. Every phase maps directly
          to scripts in the <code>V2/</code> folder.
        </div>
      </div>

      <h2>Scope</h2>
      <p>This toolkit migrates the following object types from a <strong>source Exchange Online</strong>
      tenant to a <strong>destination Exchange Online / Active Directory</strong> tenant:</p>
      <ul>
        <li>Shared Mailboxes (+ Full Access &amp; Send As permissions)</li>
        <li>Resource Mailboxes (Rooms &amp; Equipment)</li>
        <li>Distribution Groups (+ membership + aliases)</li>
        <li>Mail Contacts</li>
        <li>Accepted Domains</li>
        <li>Mail-user forwarding (source) → removed at cutover</li>
        <li>AD proxy aliases (destination, via RSAT)</li>
      </ul>

      <h2>Toolkit Architecture</h2>
      <p>The workflow is <strong>CSV-driven</strong>. Every <code>Get-*</code> script exports to CSV;
      every <code>Import-*</code> / <code>Update-*</code> script reads from CSV.
      This decouples source and destination access — you can run exports and imports days apart.</p>

      <div class="phase-grid">
        <div class="phase-card"><div class="phase-num">Phase 0</div><div class="phase-name">Setup</div><div class="phase-flag">Config &amp; Load</div></div>
        <div class="phase-card"><div class="phase-num">Phase 1</div><div class="phase-name">Pre-Flight</div><div class="phase-flag">Validation</div></div>
        <div class="phase-card"><div class="phase-num">Phase 2</div><div class="phase-name">Export</div><div class="phase-flag">Source EXO</div></div>
        <div class="phase-card"><div class="phase-num">Phase 3</div><div class="phase-name">Data Prep</div><div class="phase-flag">CSV Review</div></div>
        <div class="phase-card"><div class="phase-num">Phase 4</div><div class="phase-name">Import</div><div class="phase-flag">Dest EXO</div></div>
        <div class="phase-card"><div class="phase-num">Phase 5</div><div class="phase-name">Perms</div><div class="phase-flag">Update</div></div>
        <div class="phase-card"><div class="phase-num">Phase 6</div><div class="phase-name">Validate</div><div class="phase-flag">Report</div></div>
        <div class="phase-card"><div class="phase-num">Phase 7</div><div class="phase-name">Cutover</div><div class="phase-flag">DNS / FWD</div></div>
      </div>
    </section>

    <hr>

    <!-- ══ PRE-REQUISITES ══ -->
    <section id="prereqs" class="section">
      <h1>Pre-Requisites</h1>

      <h2>Software Requirements</h2>
      <table>
        <thead><tr><th>Requirement</th><th>Version</th><th>Notes</th></tr></thead>
        <tbody>
          <tr><td>PowerShell</td><td>5.1 or 7.x</td><td>7.x recommended — supports null-coalescing <code>?.</code> operator</td></tr>
          <tr><td>ExchangeOnlineManagement</td><td>&ge; 3.0</td><td><code>Install-Module ExchangeOnlineManagement</code></td></tr>
          <tr><td>ActiveDirectory (RSAT)</td><td>Any</td><td>Required only for <code>DestinationADEnv</code> scripts</td></tr>
        </tbody>
      </table>

      <h2>Required Roles</h2>
      <table>
        <thead><tr><th>Role</th><th>Where</th><th>Required For</th></tr></thead>
        <tbody>
          <tr><td>Exchange Admin <em>or</em> Global Admin</td><td>Source &amp; Destination tenants</td><td>All <code>Get-*</code>, <code>Import-*</code>, <code>Update-*</code> scripts</td></tr>
          <tr><td>AD Write on target OU</td><td>Destination AD</td><td><code>Remove-AllMailboxForwardingAD</code>, <code>Update-AllMailboxesProxyAliases</code></td></tr>
        </tbody>
      </table>

      <h2>Pre-Migration Checklist</h2>
      <ul class="checklist">
        <li><span class="check">☐</span><span>PowerShell 7.x installed on migration workstation</span></li>
        <li><span class="check">☐</span><span><code>ExchangeOnlineManagement &ge; 3.0</code> installed</span></li>
        <li><span class="check">☐</span><span>Exchange Admin credentials available for <strong>source</strong> tenant</span></li>
        <li><span class="check">☐</span><span>Exchange Admin credentials available for <strong>destination</strong> tenant</span></li>
        <li><span class="check">☐</span><span>CSV output folder created (e.g. <code>C:\CSV</code>) with sufficient disk space</span></li>
        <li><span class="check">☐</span><span>Project key agreed (e.g. <code>Acme</code>) — used in all file names</span></li>
        <li><span class="check">☐</span><span>Alias prefix agreed (e.g. <code>acme</code>) — optional, used as prefix in destination aliases</span></li>
        <li><span class="check">☐</span><span>Destination domain known (e.g. <code>amorim.rocks</code>)</span></li>
        <li><span class="check">☐</span><span>Cutover date agreed with business stakeholders</span></li>
      </ul>

      <div class="panel panel-warning">
        <span class="panel-icon">⚠️</span>
        <div class="panel-body">
          <strong>Important: Run exports before cutover</strong>
          All <code>Get-*</code> export scripts must be run while the source tenant is still active.
          Once DNS is updated, re-running exports will reflect the new state.
        </div>
      </div>
    </section>

    <hr>

    <!-- ══ ARCHITECTURE ══ -->
    <section id="architecture" class="section">
      <h1>Architecture</h1>

      <h2>Data Flow</h2>
<pre>Source Tenant (EXO)          CSV Files (local)          Destination Tenant (EXO / AD)
        │                           │                                  │
   Get-All*  ──────────────►  ProjectKey/                   Import-All*  ──────► New objects
   Get-CSV*  ──────────────►  *.csv files  ◄──  CSVTranslator            Update-All*
                                   │                                  │
                         Test-MigrationPrerequisites          Remove-All*  ─────► Cleanup FWD
                           Get-MigrationReport  ──────────────────────────────► Report CSV</pre>

      <h2>Folder Structure</h2>
<pre>V2/
├── Management/
│   ├── Load-Scripts.ps1              <span class="cm"># Dot-sources all functions into session</span>
│   ├── New-ProjectConfig.ps1         <span class="cm"># Generates project config from template</span>
│   ├── ProjectConfig.TEMPLATE.ps1    <span class="cm"># Token-based config template</span>
│   └── Start-Migration.ps1           <span class="cm"># Phased orchestration entry point</span>
│
├── Validation/
│   ├── Test-MigrationPrerequisites.ps1
│   └── Get-MigrationReport.ps1
│
├── SourceEnv/                        <span class="cm"># Export scripts (read from source EXO)</span>
│   ├── Get-AllMailboxes.ps1
│   ├── Get-AllSharedMailboxes.ps1
│   ├── Get-AllResourceMailboxes.ps1
│   ├── Get-AllDistributionGroups.ps1
│   ├── Get-AllMailEnabledSecurityGroups.ps1
│   ├── Get-AllDynamicDistributionGroups.ps1
│   ├── Get-AllRoomLists.ps1
│   ├── Get-AllUnifiedGroups.ps1      <span class="cm"># export only</span>
│   ├── Get-AllMailUserFwd.ps1
│   ├── Get-AllDomainRecords.ps1
│   ├── Get-AllAcceptedDomains.ps1
│   ├── Get-AllAutoReplyConfig.ps1    <span class="cm"># report only</span>
│   ├── Get-AllSendOnBehalf.ps1       <span class="cm"># report only</span>
│   ├── Get-AllLitigationHold.ps1
│   ├── Get-AllRetentionPolicies.ps1  <span class="cm"># report only</span>
│   ├── Get-AllTransportRules.ps1
│   ├── Get-AllConnectors.ps1
│   ├── Get-AllAntiSpamPolicies.ps1   <span class="cm"># report only</span>
│   ├── Get-AllDkimConfig.ps1         <span class="cm"># report only</span>
│   ├── Get-AllAddressBookPolicies.ps1
│   ├── Get-AllEmailAddressPolicies.ps1 <span class="cm"># report only</span>
│   ├── Get-AllOwaMailboxPolicies.ps1   <span class="cm"># report only</span>
│   ├── Get-CSVMailboxes.ps1
│   ├── Get-CSVSharedMailboxes.ps1
│   ├── Get-CSVResourceMailboxes.ps1
│   └── Get-CSVDistributionGroups.ps1
│
├── DestinationEnv/                   <span class="cm"># Import/Update scripts (write to dest EXO)</span>
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
│   ├── CSVTranslator.ps1
│   └── Remove-AllMailboxForwardingEXO.ps1
│
├── _legacy/                          <span class="cm"># Legacy AD scripts (M&amp;A hybrid scenarios)</span>
│   └── DestinationADEnv/
│   ├── Remove-AllMailboxForwardingAD.ps1
│   ├── Remove-AllMailboxForwardingByPrefix.ps1
│   └── Update-AllMailboxesProxyAliases.ps1
│
└── RegularCmds/
    └── ConvertDLtoShared.ps1</pre>

      <h2>Alias Naming Convention</h2>
      <p>All destination objects are created with a prefixed alias following this pattern:</p>
<pre><span class="var">$sourceLocalPart</span>@<span class="var">$DestDomain</span>

<span class="cm"># Example: source invoices@contoso.com + DestDomain dest.com</span>
invoices@dest.com
<span class="cm"># Collision: john.smith already exists → john.smith2@dest.com</span></pre>
      <p>Invalid characters (<code>[^a-zA-Z0-9._-]</code>) are stripped and the result is lowercased.</p>

      <h2>Logging</h2>
      <p>Every function accepts an optional <code>-LogPath</code> parameter. When provided:</p>
      <ul>
        <li>All console output is mirrored to the file via <code>Add-Content</code></li>
        <li>Log format: <code>[yyyy-MM-dd HH:mm:ss][Level] Message</code></li>
        <li>Levels: <code>Info</code>, <code>Success</code>, <code>Warning</code>, <code>Error</code>, <code>Verbose</code></li>
      </ul>
      <p><code>Start-Migration.ps1</code> automatically creates a timestamped log in <code>$LogFolder</code>:</p>
<pre>$LogFolder\Migration_&lt;ProjectKey&gt;_&lt;yyyyMMdd_HHmm&gt;.log
$LogFolder\Summary_&lt;ProjectKey&gt;_&lt;yyyyMMdd_HHmm&gt;.csv</pre>
    </section>

    <hr>

    <!-- ══ PHASE 0 ══ -->
    <section id="phase0" class="section">
      <h1>Phase 0 — Project Setup</h1>
      <p><span class="lozenge lozenge-neutral">One-time setup</span>&nbsp; Run once per migration project.</p>

      <h2>Step 1 — Load all functions</h2>
      <p>Dot-source <code>Load-Scripts.ps1</code> to bring all V2 functions into your PowerShell session.</p>
<pre><span class="cm"># EXO scripts only (most common)</span>
<span class="op">.</span> <span class="op">.\</span>V2\Management\Load-Scripts.ps1


<span class="cm"># Include utility scripts (ConvertDLtoShared)</span>
<span class="op">.</span> <span class="op">.\</span>V2\Management\Load-Scripts.ps1 <span class="op">-IncludeRegularCmds</span></pre>

      <div class="panel panel-info">
        <span class="panel-icon">ℹ️</span>
        <div class="panel-body">
          You must dot-source Load-Scripts.ps1 in <strong>every new PowerShell session</strong>.
          The functions are not persistent — they live only in the current session.
        </div>
      </div>

      <h2>Step 2 — Create a project config</h2>
      <p>Generate a <code>&lt;ProjectKey&gt;-Config.ps1</code> file from the template. This file stores all
      project variables and is dot-sourced by <code>Start-Migration.ps1</code>.</p>
<pre><span class="fn">New-ProjectConfig</span> <span class="op">-ProjectKey</span> <span class="str">"Contoso"</span> <span class="op">`</span>
    <span class="op">-Domain</span> <span class="str">"contoso.com"</span> <span class="op">-DestinationDomain</span> <span class="str">"dest.com"</span> <span class="op">`</span>
    <span class="op">-CSVFolder</span> <span class="str">"C:\CSV"</span>
<span class="cm"># Creates: .\Acme-Config.ps1</span>

<span class="cm"># To overwrite an existing config:</span>
<span class="fn">New-ProjectConfig</span> <span class="op">-ProjectKey</span> <span class="str">"Acme"</span> <span class="op">...</span> <span class="op">-Force</span></pre>

      <h3>Config variables reference</h3>
      <table>
        <thead><tr><th>Variable</th><th>Example</th><th>Description</th></tr></thead>
        <tbody>
          <tr><td><code>$ProjectKey</code></td><td><code>"Acme"</code></td><td>Unique ID used in all file names</td></tr>
          <tr><td><code>$Prefix</code></td><td><code>""</code></td><td>Optional prefix for destination aliases (leave empty for none)</td></tr>
          <tr><td><code>$Domain</code></td><td><code>"acme.com"</code></td><td>Source tenant primary domain</td></tr>
          <tr><td><code>$DestDomain</code></td><td><code>"dest.com"</code></td><td>Destination tenant SMTP domain</td></tr>
          <tr><td><code>$CSVFolder</code></td><td><code>"C:\CSV"</code></td><td>Base directory for all CSV files</td></tr>
          <tr><td><code>$CSVSource</code></td><td><code>"C:\CSV\Acme"</code></td><td>Project subfolder (auto-set)</td></tr>
          <tr><td><code>$LogFolder</code></td><td><code>"C:\CSV\Acme\Logs"</code></td><td>Log output directory (auto-set)</td></tr>
        </tbody>
      </table>

      <h2>Step 3 — Connect to Exchange Online</h2>
      <p>Connect to the <strong>source</strong> tenant first (for exports), then reconnect to the
      <strong>destination</strong> tenant before running imports.</p>
<pre><span class="cm"># Connect to source tenant</span>
<span class="fn">Connect-ExchangeOnline</span> <span class="op">-UserPrincipalName</span> admin@source.onmicrosoft.com

<span class="cm"># Disconnect when switching tenants</span>
<span class="fn">Disconnect-ExchangeOnline</span> <span class="op">-Confirm:$false</span>

<span class="cm"># Connect to destination tenant</span>
<span class="fn">Connect-ExchangeOnline</span> <span class="op">-UserPrincipalName</span> admin@destination.onmicrosoft.com</pre>
    </section>

    <hr>

    <!-- ══ PHASE 1 ══ -->
    <section id="phase1" class="section">
      <h1>Phase 1 — Pre-Flight Validation</h1>
      <p><span class="lozenge lozenge-warning">Required</span>&nbsp; Run before any exports or imports.</p>

      <h2>Run Test-MigrationPrerequisites</h2>
      <p>This script checks your environment and reports any blockers before the migration starts.</p>
<pre><span class="fn">Test-MigrationPrerequisites</span> <span class="op">-CSVFolder</span> <span class="str">"C:\CSV"</span> <span class="op">-ProjectKey</span> <span class="str">"Acme"</span></pre>

      <h3>What it checks</h3>
      <ul>
        <li>Active Exchange Online session (<code>Get-OrganizationConfig</code>)</li>
        <li>ExchangeOnlineManagement module version (&ge; 3.0)</li>
        <li>CSV output folder exists and is writable</li>
        <li>Sufficient disk space on the CSV drive</li>
        <li>Presence of existing CSV files (warns if stale)</li>
      </ul>

      <h3>Interpreting results</h3>
      <table>
        <thead><tr><th>Status</th><th>Meaning</th><th>Action</th></tr></thead>
        <tbody>
          <tr><td><span class="lozenge lozenge-success">PASS</span></td><td>Check passed</td><td>Continue</td></tr>
          <tr><td><span class="lozenge lozenge-warning">WARN</span></td><td>Non-blocking issue</td><td>Review and decide</td></tr>
          <tr><td><span class="lozenge lozenge-error">FAIL</span></td><td>Blocking issue</td><td>Fix before proceeding</td></tr>
        </tbody>
      </table>

      <div class="panel panel-error">
        <span class="panel-icon">🛑</span>
        <div class="panel-body">
          <strong>Do not proceed if any check shows FAIL.</strong>
          A failed pre-flight check means the migration will encounter errors. Fix all FAILs before moving to Phase 2.
        </div>
      </div>

      <h2>Using Start-Migration (orchestrated)</h2>
      <p>Alternatively, use <code>Start-Migration.ps1</code> with <code>-Phase validate</code>:</p>
<pre><span class="cm"># Validate only</span>
<span class="fn">Start-Migration</span> <span class="op">-ConfigPath</span> <span class="str">".\Acme-Config.ps1"</span> <span class="op">-Phase</span> validate

<span class="cm"># Dry-run the full pipeline (no changes made)</span>
<span class="fn">Start-Migration</span> <span class="op">-ConfigPath</span> <span class="str">".\Acme-Config.ps1"</span> <span class="op">-Phase</span> full <span class="op">-WhatIf</span></pre>
    </section>

    <hr>

    <!-- ══ PHASE 2 ══ -->
    <section id="phase2" class="section">
      <h1>Phase 2 — Source Export</h1>
      <p><span class="lozenge lozenge-info">Source tenant</span>&nbsp; Must be connected to source EXO.</p>

      <div class="panel panel-warning">
        <span class="panel-icon">⚠️</span>
        <div class="panel-body">
          <strong>Connection check</strong>
          Ensure you are connected to the <strong>source</strong> tenant before running any <code>Get-*</code> scripts.
          Running exports against the destination will produce incorrect data.
        </div>
      </div>

      <h2>Export all object types</h2>
      <p>Run each export script in the order shown. All outputs go to <code>$CSVSource</code>
      (<code>C:\CSV\&lt;ProjectKey&gt;\</code>).</p>

      <ul class="step-list">
        <li>
          <div class="step-body">
            <strong>Export regular mailboxes</strong>
<pre><span class="fn">Get-AllMailboxes</span> <span class="op">-OutputCSV</span> <span class="var">$CSVFolder</span> <span class="op">-ProjectKey</span> <span class="var">$ProjectKey</span>
<span class="cm"># Output: Mailboxes_Acme.csv</span></pre>
          </div>
        </li>
        <li>
          <div class="step-body">
            <strong>Export shared mailboxes</strong>
<pre><span class="fn">Get-AllSharedMailboxes</span> <span class="op">-CSVFolder</span> <span class="var">$CSVSource</span> <span class="op">-ProjectKey</span> <span class="var">$ProjectKey</span>
<span class="cm"># Output: Shared_Mailboxes_Acme.csv</span></pre>
          </div>
        </li>
        <li>
          <div class="step-body">
            <strong>Export resource mailboxes</strong>
<pre><span class="fn">Get-AllResourceMailboxes</span> <span class="op">-CSVFolder</span> <span class="var">$CSVSource</span> <span class="op">-ProjectKey</span> <span class="var">$ProjectKey</span>
<span class="cm"># Output: Resource_Mailboxes_Acme.csv</span></pre>
          </div>
        </li>
        <li>
          <div class="step-body">
            <strong>Export distribution groups</strong>
<pre><span class="fn">Get-AllDistributionGroups</span> <span class="op">-CSVFolder</span> <span class="var">$CSVSource</span> <span class="op">-ProjectKey</span> <span class="var">$ProjectKey</span>
<span class="cm"># Output: Distribution_Groups_Acme.csv</span></pre>
          </div>
        </li>
        <li>
          <div class="step-body">
            <strong>Export mail-user forwarding</strong>
<pre><span class="fn">Get-AllMailUserFwd</span> <span class="op">-CSVFolder</span> <span class="var">$CSVSource</span> <span class="op">-ProjectKey</span> <span class="var">$ProjectKey</span>
<span class="cm"># Output: MailUsers_Fwd_Acme.csv</span></pre>
          </div>
        </li>
        <li>
          <div class="step-body">
            <strong>Export accepted domains</strong>
<pre><span class="fn">Get-AllAcceptedDomains</span> <span class="op">-CSVFolder</span> <span class="var">$CSVSource</span> <span class="op">-ProjectKey</span> <span class="var">$ProjectKey</span>
<span class="cm"># Output: Accepted_Domains_Acme.csv</span></pre>
          </div>
        </li>
        <li>
          <div class="step-body">
            <strong>Export DNS records (optional — for reference)</strong>
<pre><span class="fn">Get-AllDomainRecords</span> <span class="op">-Domain</span> <span class="var">$Domain</span> <span class="op">-CSVFolder</span> <span class="var">$CSVSource</span> <span class="op">-ProjectKey</span> <span class="var">$ProjectKey</span>
<span class="cm"># Output: DNS_Records_acme.com_Acme.csv</span></pre>
          </div>
        </li>
      </ul>

      <h2>Or run all exports at once</h2>
<pre><span class="fn">Start-Migration</span> <span class="op">-ConfigPath</span> <span class="str">".\Acme-Config.ps1"</span> <span class="op">-Phase</span> export</pre>

      <h2>CSV outputs summary</h2>
      <table>
        <thead><tr><th>Script</th><th>Output File</th></tr></thead>
        <tbody>
          <tr><td><code>Get-AllMailboxes</code></td><td><code>Mailboxes_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllSharedMailboxes</code></td><td><code>Shared_Mailboxes_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllResourceMailboxes</code></td><td><code>Resource_Mailboxes_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllDistributionGroups</code></td><td><code>Distribution_Groups_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllMailEnabledSecurityGroups</code></td><td><code>Mail_Enabled_Security_Groups_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllDynamicDistributionGroups</code></td><td><code>Dynamic_Distribution_Groups_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllRoomLists</code></td><td><code>Room_Lists_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllUnifiedGroups</code></td><td><code>Unified_Groups_&lt;ProjectKey&gt;.csv</code> <em>(export only)</em></td></tr>
          <tr><td><code>Get-AllMailUserFwd</code></td><td><code>MailUsers_Fwd_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllAcceptedDomains</code></td><td><code>Accepted_Domains_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllDomainRecords</code></td><td><code>DNS_Records_&lt;domain&gt;_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllAutoReplyConfig</code></td><td><code>AutoReply_Config_&lt;ProjectKey&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllSendOnBehalf</code></td><td><code>SendOnBehalf_&lt;ProjectKey&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllLitigationHold</code></td><td><code>Litigation_Hold_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllRetentionPolicies</code></td><td><code>Retention_Policies_&lt;ProjectKey&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllTransportRules</code></td><td><code>Transport_Rules_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllConnectors</code></td><td><code>Inbound/Outbound_Connectors_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllAntiSpamPolicies</code></td><td><code>AntiSpam/AntiPhish_Policies_&lt;ProjectKey&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllDkimConfig</code></td><td><code>DKIM_Config_&lt;ProjectKey&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllAddressBookPolicies</code></td><td><code>Address_Book_Policies_&lt;ProjectKey&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllEmailAddressPolicies</code></td><td><code>Email_Address_Policies_&lt;ProjectKey&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllOwaMailboxPolicies</code></td><td><code>OWA_Mailbox_Policies_&lt;ProjectKey&gt;.csv</code> <em>(report only)</em></td></tr>
        </tbody>
      </table>
    </section>

    <hr>

    <!-- ══ PHASE 3 ══ -->
    <section id="phase3" class="section">
      <h1>Phase 3 — Data Preparation</h1>
      <p><span class="lozenge lozenge-neutral">Offline</span>&nbsp; No EXO connection required.</p>

      <h2>Review exported CSVs</h2>
      <p>Before importing, review each CSV file for data quality issues:</p>
      <ul>
        <li>Missing <code>PrimarySmtpAddress</code> values (required for all object types)</li>
        <li>Special characters in <code>DisplayName</code> that may cause import failures</li>
        <li>Distribution group members that won't exist in the destination</li>
        <li>Forwarding addresses that should be cleared before cutover</li>
        <li>Room/Equipment mailboxes with AddressBookPolicy (ADP) names — these must exist in destination first</li>
      </ul>

      <h2>Cross-tenant address translation (optional)</h2>
      <p>If migrating between two different tenant domains, use <code>Convert-CSVForDestination</code>
      to rewrite SMTP addresses from the source domain to the destination domain using a mapping file.</p>

<pre><span class="cm"># Mapping file format: "Source user email","Destination user email"</span>
<span class="fn">Convert-CSVForDestination</span> <span class="op">`</span>
    <span class="op">-InputCSV</span>       <span class="str">"C:\CSV\Acme\Shared_Mailboxes_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-MappingCSV</span>     <span class="str">"C:\CSV\Acme\Mapping_Mailboxes_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-OutputCSV</span>      <span class="str">"C:\CSV\Acme\Shared_Mailboxes_Acme_Translated.csv"</span> <span class="op">`</span>
    <span class="op">-SourceDomain</span>   <span class="str">"acme.com"</span> <span class="op">`</span>
    <span class="op">-DestDomain</span>     <span class="str">"dest.com"</span></pre>

      <div class="panel panel-info">
        <span class="panel-icon">ℹ️</span>
        <div class="panel-body">
          <strong>Mapping file format</strong>
          The mapping file (<code>Mapping_Mailboxes_&lt;ProjectKey&gt;.csv</code>) must have exactly two columns:
          <code>Source user email</code> and <code>Destination user email</code>. This file is also used by
          <code>Update-AllMailboxesProxyAliases</code> in the AD phase.
        </div>
      </div>

      <h2>Get CSV subsets (optional)</h2>
      <p>If you need to re-export specific objects by reading from an existing CSV filter list,
      use the <code>Get-CSV*</code> variants:</p>
<pre><span class="fn">Get-CSVSharedMailboxes</span> <span class="op">-CSVFile</span> <span class="str">"C:\CSV\Acme\filter.csv"</span> <span class="op">-CSVFolder</span> <span class="var">$CSVSource</span> <span class="op">-ProjectKey</span> <span class="var">$ProjectKey</span></pre>
    </section>

    <hr>

    <!-- ══ PHASE 4 ══ -->
    <section id="phase4" class="section">
      <h1>Phase 4 — Object Creation</h1>
      <p><span class="lozenge lozenge-info">Destination tenant</span>&nbsp; Connect to destination EXO first.</p>

      <div class="panel panel-warning">
        <span class="panel-icon">⚠️</span>
        <div class="panel-body">
          <strong>Order matters</strong>
          Create objects in this order: <strong>Accepted Domains → Address Book Policies → Shared Mailboxes → Resource Mailboxes → Distribution Groups → Mail-Enabled Security Groups → Dynamic Distribution Groups → Room Lists → Mail Contacts → Litigation Hold → Transport Rules → Connectors</strong>.
          Distribution group members must exist before members can be added (Phase 5).
        </div>
      </div>

      <h2>Always dry-run first</h2>
<pre><span class="fn">Start-Migration</span> <span class="op">-ConfigPath</span> <span class="str">".\Acme-Config.ps1"</span> <span class="op">-Phase</span> import <span class="op">-WhatIf</span></pre>

      <h2>Import accepted domains</h2>
<pre><span class="fn">Import-AllAcceptedDomains</span> <span class="op">-CSVFile</span> <span class="str">"C:\CSV\Acme\Accepted_Domains_Acme.csv"</span></pre>

      <h2>Import address book policies</h2>
<pre><span class="fn">Import-AllAddressBookPolicies</span> <span class="op">-CSVFile</span> <span class="str">"C:\CSV\Acme\Address_Book_Policies_Acme.csv"</span></pre>

      <h2>Import shared mailboxes</h2>
<pre><span class="fn">Import-AllSharedMailboxes</span> <span class="op">`</span>
    <span class="op">-CSVFile</span>      <span class="str">"C:\CSV\Acme\Shared_Mailboxes_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-Company</span>      <span class="str">"Acme"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span></pre>

      <h2>Import resource mailboxes</h2>
<pre><span class="fn">Import-AllResourceMailboxes</span> <span class="op">`</span>
    <span class="op">-CSVFile</span>      <span class="str">"C:\CSV\Acme\Resource_Mailboxes_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span></pre>

      <h2>Import distribution groups</h2>
<pre><span class="fn">Import-AllDistributionGroups</span> <span class="op">`</span>
    <span class="op">-CSVFile</span>      <span class="str">"C:\CSV\Acme\Distribution_Groups_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span></pre>

      <h2>Import mail-enabled security groups</h2>
<pre><span class="fn">Import-AllMailEnabledSecurityGroups</span> <span class="op">`</span>
    <span class="op">-CSVFile</span>      <span class="str">"C:\CSV\Acme\Mail_Enabled_Security_Groups_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span></pre>

      <h2>Import dynamic distribution groups</h2>
<pre><span class="fn">Import-AllDynamicDistributionGroups</span> <span class="op">`</span>
    <span class="op">-CSVFile</span>      <span class="str">"C:\CSV\Acme\Dynamic_Distribution_Groups_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span></pre>

      <h2>Import room lists</h2>
<pre><span class="fn">Import-AllRoomLists</span> <span class="op">`</span>
    <span class="op">-CSVFile</span>      <span class="str">"C:\CSV\Acme\Room_Lists_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span></pre>

      <h2>Import mail contacts</h2>
<pre><span class="fn">Import-AllMailContacts</span> <span class="op">`</span>
    <span class="op">-CSVFile</span>      <span class="str">"C:\CSV\Acme\Mail_Contacts_Acme.csv"</span> <span class="op">`</span>
</pre>

      <h2>Apply litigation hold</h2>
<pre><span class="fn">Import-AllLitigationHold</span> <span class="op">-CSVFile</span> <span class="str">"C:\CSV\Acme\Litigation_Hold_Acme.csv"</span></pre>

      <h2>Import transport rules</h2>
      <p>Rules are created <strong>Disabled</strong> by default. Review in EAC before enabling.</p>
<pre><span class="fn">Import-AllTransportRules</span> <span class="op">-CSVFile</span> <span class="str">"C:\CSV\Acme\Transport_Rules_Acme.csv"</span>
<span class="cm"># Add -Enabled to activate on creation</span></pre>

      <h2>Import connectors</h2>
      <p>Connectors are created <strong>Disabled</strong> by default. Review before enabling.</p>
<pre><span class="fn">Import-AllConnectors</span> <span class="op">`</span>
    <span class="op">-InboundCSV</span>   <span class="str">"C:\CSV\Acme\Inbound_Connectors_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-OutboundCSV</span>  <span class="str">"C:\CSV\Acme\Outbound_Connectors_Acme.csv"</span></pre>

      <h2>Or run all imports at once</h2>
<pre><span class="fn">Start-Migration</span> <span class="op">-ConfigPath</span> <span class="str">".\Acme-Config.ps1"</span> <span class="op">-Phase</span> import</pre>
    </section>

    <hr>

    <!-- ══ PHASE 5 ══ -->
    <section id="phase5" class="section">
      <h1>Phase 5 — Permissions &amp; Aliases</h1>
      <p><span class="lozenge lozenge-info">Destination tenant</span>&nbsp; Objects from Phase 4 must exist first.</p>

      <h2>Apply shared mailbox permissions</h2>
      <p>Assigns <strong>Full Access</strong> and <strong>Send As</strong> permissions from the exported CSV.</p>
<pre><span class="fn">Import-AllSharedMailboxPermissions</span> <span class="op">`</span>
    <span class="op">-CSVFile</span>      <span class="str">"C:\CSV\Acme\Shared_Mailboxes_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span></pre>

      <h2>Update shared mailbox aliases</h2>
<pre><span class="fn">Update-AllSharedMailboxesAliases</span> <span class="op">`</span>
    <span class="op">-CSVFile</span>      <span class="str">"C:\CSV\Acme\Shared_Mailboxes_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span></pre>

      <h2>Add distribution group members</h2>
<pre><span class="fn">Update-AllDistributionGroupMember</span> <span class="op">`</span>
    <span class="op">-CSVFile</span>      <span class="str">"C:\CSV\Acme\Distribution_Groups_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span></pre>

      <h2>Update distribution group aliases</h2>
<pre><span class="fn">Update-AllDistributionGroupAliases</span> <span class="op">`</span>
    <span class="op">-CSVFile</span>      <span class="str">"C:\CSV\Acme\Distribution_Groups_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span></pre>

      <h2>Update AD proxy aliases (destination AD only)</h2>
      <p>Requires RSAT and AD write permissions on the target OU. Load AD scripts first.</p>
<pre>
<span class="fn">Update-AllMailboxesProxyAliases</span> <span class="op">`</span>
    <span class="op">-MappingCSV</span>   <span class="str">"C:\CSV\Acme\Mapping_Mailboxes_Acme.csv"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span></pre>

      <h2>Or run all update steps at once</h2>
<pre><span class="fn">Start-Migration</span> <span class="op">-ConfigPath</span> <span class="str">".\Acme-Config.ps1"</span> <span class="op">-Phase</span> update</pre>
    </section>

    <hr>

    <!-- ══ PHASE 6 ══ -->
    <section id="phase6" class="section">
      <h1>Phase 6 — Validation</h1>
      <p><span class="lozenge lozenge-success">Pre-cutover check</span>&nbsp; Run before finalising the cutover date.</p>

      <h2>Run Get-MigrationReport</h2>
      <p>Compares source CSVs against live destination objects and outputs a validation report.</p>
<pre><span class="fn">Get-MigrationReport</span> <span class="op">`</span>
    <span class="op">-CSVFolder</span>    <span class="str">"C:\CSV\Acme"</span> <span class="op">`</span>
    <span class="op">-ProjectKey</span>   <span class="str">"Acme"</span> <span class="op">`</span>
    <span class="op">-Domain</span>       <span class="str">"dest.com"</span>
<span class="cm"># Output: C:\CSV\Acme\Logs\MigrationReport_Acme_&lt;date&gt;.csv</span></pre>

      <h3>Interpreting the report</h3>
      <table>
        <thead><tr><th>Column</th><th>Meaning</th></tr></thead>
        <tbody>
          <tr><td><code>ObjectType</code></td><td>SharedMailbox / ResourceMailbox / DistributionGroup / MailContact</td></tr>
          <tr><td><code>SourceAddress</code></td><td>Primary SMTP from source CSV</td></tr>
          <tr><td><code>DestinationAlias</code></td><td>Expected alias in destination</td></tr>
          <tr><td><code>Status</code></td><td><span class="lozenge lozenge-success">Found</span> or <span class="lozenge lozenge-error">Missing</span></td></tr>
          <tr><td><code>Notes</code></td><td>Additional details (wrong type, permission issues, etc.)</td></tr>
        </tbody>
      </table>

      <div class="panel panel-success">
        <span class="panel-icon">✅</span>
        <div class="panel-body">
          <strong>Validation gate</strong>
          All objects should show <strong>Found</strong> before proceeding to cutover.
          Investigate and resolve any <strong>Missing</strong> entries.
        </div>
      </div>

      <h2>Or run as part of orchestration</h2>
<pre><span class="fn">Start-Migration</span> <span class="op">-ConfigPath</span> <span class="str">".\Acme-Config.ps1"</span> <span class="op">-Phase</span> report</pre>
    </section>

    <hr>

    <!-- ══ PHASE 7 ══ -->
    <section id="phase7" class="section">
      <h1>Phase 7 — Cutover</h1>
      <p><span class="lozenge lozenge-error">Irreversible</span>&nbsp; Coordinate with stakeholders before proceeding.</p>

      <div class="panel panel-error">
        <span class="panel-icon">🛑</span>
        <div class="panel-body">
          <strong>Cutover is business-impacting.</strong>
          Once forwarding is removed and DNS updated, mail delivery switches to the destination tenant.
          Ensure Phase 6 validation shows 100% success before proceeding.
        </div>
      </div>

      <h2>Step 1 — Remove EXO forwarding (source tenant)</h2>
      <p>Connect to the <strong>source</strong> tenant and remove all forwarding attributes.</p>
<pre><span class="cm"># Connect to SOURCE tenant</span>
<span class="fn">Connect-ExchangeOnline</span> <span class="op">-UserPrincipalName</span> admin@source.onmicrosoft.com

<span class="fn">Remove-AllMailboxForwardingEXO</span> <span class="op">`</span>
    <span class="op">-WhatIf</span>       <span class="cm"># dry-run first!</span>

<span class="cm"># Live run:</span>
<span class="fn">Remove-AllMailboxForwardingEXO</span> <span class="op">-CSVFile</span> <span class="var">$mailboxCsv</span> <span class="op">-Domain</span> <span class="var">$DestDomain</span></pre>

      <h2>Step 2 — Remove AD forwarding (destination AD)</h2>
      <p>Requires RSAT. Load AD scripts first.</p>
<pre>
<span class="cm"># By prefix (recommended)</span>
<span class="fn">Remove-AllMailboxForwardingByPrefix</span> <span class="op">`</span>
    <span class="op">-WhatIf</span>

<span class="cm"># By OU (alternative)</span>
<span class="fn">Remove-AllMailboxForwardingAD</span> <span class="op">`</span>
    <span class="op">-OUPath</span>       <span class="str">"OU=Users,DC=contoso,DC=com"</span> <span class="op">`</span>
    <span class="op">-WhatIf</span></pre>

      <h2>Step 3 — Update DNS records</h2>
      <p>Update MX, SPF, Autodiscover, and DKIM records to point to the destination tenant.
      Reference the exported DNS records from Phase 2 for the expected values.</p>
      <table>
        <thead><tr><th>Record type</th><th>Action</th></tr></thead>
        <tbody>
          <tr><td>MX</td><td>Point to destination tenant mail exchanger</td></tr>
          <tr><td>SPF (TXT)</td><td>Update to include destination tenant IP range</td></tr>
          <tr><td>Autodiscover (CNAME)</td><td>Point to <code>autodiscover.outlook.com</code> (destination)</td></tr>
          <tr><td>DKIM (CNAME)</td><td>Add destination tenant DKIM selectors</td></tr>
        </tbody>
      </table>

      <h2>Or run cleanup phase via orchestrator</h2>
<pre><span class="fn">Start-Migration</span> <span class="op">-ConfigPath</span> <span class="str">".\Acme-Config.ps1"</span> <span class="op">-Phase</span> cleanup</pre>
    </section>

    <hr>

    <!-- ══ ROLLBACK ══ -->
    <section id="rollback" class="section">
      <h1>Rollback</h1>
      <p><span class="lozenge lozenge-warning">Emergency use only</span></p>

      <div class="panel panel-warning">
        <span class="panel-icon">⚠️</span>
        <div class="panel-body">
          <strong>Rollback is complex after DNS propagation.</strong>
          If DNS has already been updated and propagated, rolling back requires re-pointing DNS records
          and potentially re-enabling forwarding on the source tenant.
        </div>
      </div>

      <h2>Rollback checklist</h2>
      <ul class="checklist">
        <li><span class="check">☐</span><span>Revert DNS records to point back to source tenant (MX, SPF, Autodiscover)</span></li>
        <li><span class="check">☐</span><span>Re-enable forwarding on source EXO mailboxes if removed</span></li>
        <li><span class="check">☐</span><span>Re-enable AD forwarding attributes if removed</span></li>
        <li><span class="check">☐</span><span>Notify users of temporary disruption</span></li>
        <li><span class="check">☐</span><span>Investigate root cause before rescheduling cutover</span></li>
      </ul>

      <h2>Re-enable AD forwarding (example)</h2>
<pre><span class="cm"># Set targetAddress back on affected AD users</span>
<span class="cm"># See _legacy/DestinationADEnv — AD forwarding scripts are not part of the generic toolkit</span>
    <span class="fn">Set-ADUser</span> <span class="op">-Add</span> @{ targetAddress = <span class="str">"SMTP:user@source.com"</span> }</pre>

      <div class="panel panel-info">
        <span class="panel-icon">ℹ️</span>
        <div class="panel-body">
          The <code>Get-AllMailUserFwd</code> export (Phase 2) captures the original forwarding state.
          Use <code>MailUsers_Fwd_&lt;ProjectKey&gt;.csv</code> as the source of truth for rollback.
        </div>
      </div>
    </section>

    <hr>

    <!-- ══ SCRIPT REFERENCE ══ -->
    <section id="scriptref" class="section">
      <h1>Script Reference</h1>

      <h2>Management</h2>
      <table>
        <thead><tr><th>Script</th><th>Function</th><th>Key Parameters</th><th>Phase</th></tr></thead>
        <tbody>
          <tr><td><code>Load-Scripts.ps1</code></td><td><em>(dot-source)</em></td><td><code>-IncludeRegularCmds</code></td><td>0</td></tr>
          <tr><td><code>New-ProjectConfig.ps1</code></td><td><code>New-ProjectConfig</code></td><td><code>-ProjectKey</code>, <code>-Domain</code>, <code>-DestinationDomain</code>, <code>-CSVFolder</code>, <code>-Prefix</code>, <code>-Force</code></td><td>0</td></tr>
          <tr><td><code>Start-Migration.ps1</code></td><td><em>(orchestrator)</em></td><td><code>-ConfigPath</code>, <code>-Phase</code> (validate/export/import/update/cleanup/report/full), <code>-WhatIf</code></td><td>All</td></tr>
        </tbody>
      </table>

      <h2>Validation</h2>
      <table>
        <thead><tr><th>Script</th><th>Function</th><th>Key Parameters</th><th>Phase</th></tr></thead>
        <tbody>
          <tr><td><code>Test-MigrationPrerequisites.ps1</code></td><td><code>Test-MigrationPrerequisites</code></td><td><code>-CSVFolder</code>, <code>-ProjectKey</code></td><td>1</td></tr>
          <tr><td><code>Get-MigrationReport.ps1</code></td><td><code>Get-MigrationReport</code></td><td><code>-CSVFolder</code>, <code>-ProjectKey</code>, <code>-Domain</code>, <code>-Prefix</code></td><td>6</td></tr>
        </tbody>
      </table>

      <h2>SourceEnv — Export Scripts</h2>
      <table>
        <thead><tr><th>Script</th><th>Function</th><th>Output CSV</th></tr></thead>
        <tbody>
          <tr><td><code>Get-AllMailboxes.ps1</code></td><td><code>Get-AllMailboxes</code></td><td><code>Mailboxes_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllSharedMailboxes.ps1</code></td><td><code>Get-AllSharedMailboxes</code></td><td><code>Shared_Mailboxes_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllResourceMailboxes.ps1</code></td><td><code>Get-AllResourceMailboxes</code></td><td><code>Resource_Mailboxes_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllDistributionGroups.ps1</code></td><td><code>Get-AllDistributionGroups</code></td><td><code>Distribution_Groups_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllMailEnabledSecurityGroups.ps1</code></td><td><code>Get-AllMailEnabledSecurityGroups</code></td><td><code>Mail_Enabled_Security_Groups_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllDynamicDistributionGroups.ps1</code></td><td><code>Get-AllDynamicDistributionGroups</code></td><td><code>Dynamic_Distribution_Groups_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllRoomLists.ps1</code></td><td><code>Get-AllRoomLists</code></td><td><code>Room_Lists_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllUnifiedGroups.ps1</code></td><td><code>Get-AllUnifiedGroups</code></td><td><code>Unified_Groups_&lt;K&gt;.csv</code> <em>(export only)</em></td></tr>
          <tr><td><code>Get-AllMailUserFwd.ps1</code></td><td><code>Get-AllMailUserFwd</code></td><td><code>MailUsers_Fwd_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllDomainRecords.ps1</code></td><td><code>Get-AllDomainRecords</code></td><td><code>DNS_Records_&lt;domain&gt;_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllAcceptedDomains.ps1</code></td><td><code>Get-AllAcceptedDomains</code></td><td><code>Accepted_Domains_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllAutoReplyConfig.ps1</code></td><td><code>Get-AllAutoReplyConfig</code></td><td><code>AutoReply_Config_&lt;K&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllSendOnBehalf.ps1</code></td><td><code>Get-AllSendOnBehalf</code></td><td><code>SendOnBehalf_&lt;K&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllLitigationHold.ps1</code></td><td><code>Get-AllLitigationHold</code></td><td><code>Litigation_Hold_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllRetentionPolicies.ps1</code></td><td><code>Get-AllRetentionPolicies</code></td><td><code>Retention_Policies_&lt;K&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllTransportRules.ps1</code></td><td><code>Get-AllTransportRules</code></td><td><code>Transport_Rules_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllConnectors.ps1</code></td><td><code>Get-AllConnectors</code></td><td><code>Inbound/Outbound_Connectors_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllAntiSpamPolicies.ps1</code></td><td><code>Get-AllAntiSpamPolicies</code></td><td><code>AntiSpam/AntiPhish_Policies_&lt;K&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllDkimConfig.ps1</code></td><td><code>Get-AllDkimConfig</code></td><td><code>DKIM_Config_&lt;K&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllAddressBookPolicies.ps1</code></td><td><code>Get-AllAddressBookPolicies</code></td><td><code>Address_Book_Policies_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-AllEmailAddressPolicies.ps1</code></td><td><code>Get-AllEmailAddressPolicies</code></td><td><code>Email_Address_Policies_&lt;K&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-AllOwaMailboxPolicies.ps1</code></td><td><code>Get-AllOwaMailboxPolicies</code></td><td><code>OWA_Mailbox_Policies_&lt;K&gt;.csv</code> <em>(report only)</em></td></tr>
          <tr><td><code>Get-CSVMailboxes.ps1</code></td><td><code>Get-CSVMailboxes</code></td><td><code>Mailboxes_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-CSVSharedMailboxes.ps1</code></td><td><code>Get-CSVSharedMailboxes</code></td><td><code>Shared_Mailboxes_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-CSVResourceMailboxes.ps1</code></td><td><code>Get-CSVResourceMailboxes</code></td><td><code>Resource_Mailboxes_&lt;K&gt;.csv</code></td></tr>
          <tr><td><code>Get-CSVDistributionGroups.ps1</code></td><td><code>Get-CSVDistributionGroups</code></td><td><code>Distribution_Groups_&lt;K&gt;.csv</code></td></tr>
        </tbody>
      </table>

      <h2>DestinationEnv — Import / Update Scripts</h2>
      <table>
        <thead><tr><th>Script</th><th>Function</th><th>Phase</th><th>WhatIf</th></tr></thead>
        <tbody>
          <tr><td><code>Import-AllSharedMailboxes.ps1</code></td><td><code>Import-AllSharedMailboxes</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Import-AllSharedMailboxPermissions.ps1</code></td><td><code>Import-AllSharedMailboxPermissions</code></td><td>update</td><td>✓</td></tr>
          <tr><td><code>Import-AllResourceMailboxes.ps1</code></td><td><code>Import-AllResourceMailboxes</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Import-AllDistributionGroups.ps1</code></td><td><code>Import-AllDistributionGroups</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Import-AllMailEnabledSecurityGroups.ps1</code></td><td><code>Import-AllMailEnabledSecurityGroups</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Import-AllDynamicDistributionGroups.ps1</code></td><td><code>Import-AllDynamicDistributionGroups</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Import-AllRoomLists.ps1</code></td><td><code>Import-AllRoomLists</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Import-AllMailContacts.ps1</code></td><td><code>Import-AllMailContacts</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Import-AllAcceptedDomains.ps1</code></td><td><code>Import-AllAcceptedDomains</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Import-AllLitigationHold.ps1</code></td><td><code>Import-AllLitigationHold</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Import-AllTransportRules.ps1</code></td><td><code>Import-AllTransportRules</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Import-AllConnectors.ps1</code></td><td><code>Import-AllConnectors</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Import-AllAddressBookPolicies.ps1</code></td><td><code>Import-AllAddressBookPolicies</code></td><td>import</td><td>✓</td></tr>
          <tr><td><code>Update-AllSharedMailboxesAliases.ps1</code></td><td><code>Update-AllSharedMailboxesAliases</code></td><td>update</td><td>✓</td></tr>
          <tr><td><code>Update-AllDistributionGroupMember.ps1</code></td><td><code>Update-AllDistributionGroupMember</code></td><td>update</td><td>✓</td></tr>
          <tr><td><code>Update-AllDistributionGroupAliases.ps1</code></td><td><code>Update-AllDistributionGroupAliases</code></td><td>update</td><td>✓</td></tr>
          <tr><td><code>CSVTranslator.ps1</code></td><td><code>Convert-CSVForDestination</code></td><td>manual</td><td>—</td></tr>
          <tr><td><code>Remove-AllMailboxForwardingEXO.ps1</code></td><td><code>Remove-AllMailboxForwardingEXO</code></td><td>cleanup</td><td>✓</td></tr>
        </tbody>
      </table>

      <h2>_legacy/DestinationADEnv — Active Directory Scripts</h2>
      <table>
        <thead><tr><th>Script</th><th>Function</th><th>Description</th><th>WhatIf</th></tr></thead>
        <tbody>
          <tr><td><code>Remove-AllMailboxForwardingAD.ps1</code></td><td><code>Remove-AllMailboxForwardingAD</code></td><td>Clear forwarding attrs by OU</td><td>✓</td></tr>
          <tr><td><code>Remove-AllMailboxForwardingByPrefix.ps1</code></td><td><code>Remove-AllMailboxForwardingByPrefix</code></td><td>Clear forwarding attrs by prefix</td><td>✓</td></tr>
          <tr><td><code>Update-AllMailboxesProxyAliases.ps1</code></td><td><code>Update-AllMailboxesProxyAliases</code></td><td>Update proxyAddresses in AD</td><td>✓</td></tr>
        </tbody>
      </table>

      <h2>RegularCmds — Utilities</h2>
      <table>
        <thead><tr><th>Script</th><th>Function</th><th>Description</th><th>WhatIf</th></tr></thead>
        <tbody>
          <tr><td><code>ConvertDLtoShared.ps1</code></td><td><code>ConvertDLtoShared</code></td><td>Convert a Distribution List to a Shared Mailbox. Renames original DG with <code>_old</code> suffix, creates shared mailbox with same address.</td><td>✓</td></tr>
        </tbody>
      </table>
    </section>

    <hr>

    <!-- ══ CSV FORMAT ══ -->
    <section id="csvformat" class="section">
      <h1>CSV Format Reference</h1>

      <h2>Shared_Mailboxes_&lt;ProjectKey&gt;.csv</h2>
      <table>
        <thead><tr><th>Column</th><th>Required</th><th>Notes</th></tr></thead>
        <tbody>
          <tr><td><code>DisplayName</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td>Source display name</td></tr>
          <tr><td><code>PrimarySmtpAddress</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td>Source primary SMTP; used to build destination alias</td></tr>
          <tr><td><code>Alias</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td>Source alias</td></tr>
          <tr><td><code>EmailAddresses</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td>Semicolon-separated secondary aliases</td></tr>
          <tr><td><code>FullAccessUsers</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td>Semicolon-separated email addresses</td></tr>
          <tr><td><code>SendAsUsers</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td>Semicolon-separated email addresses</td></tr>
          <tr><td><code>ForwardingAddress</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td>Leave blank if no forwarding</td></tr>
          <tr><td><code>ForwardingSmtpAddress</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td>Leave blank if no forwarding</td></tr>
          <tr><td><code>DeliverToMailboxAndForward</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td><code>True</code> or <code>False</code></td></tr>
        </tbody>
      </table>

      <h2>Distribution_Groups_&lt;ProjectKey&gt;.csv</h2>
      <table>
        <thead><tr><th>Column</th><th>Required</th><th>Notes</th></tr></thead>
        <tbody>
          <tr><td><code>DisplayName</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td></td></tr>
          <tr><td><code>PrimarySmtpAddress</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td></td></tr>
          <tr><td><code>Alias</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td>Semicolon-separated SMTP addresses (used by Update-AllDistributionGroupAliases)</td></tr>
          <tr><td><code>Members</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td>Semicolon-separated primary SMTP addresses</td></tr>
        </tbody>
      </table>

      <h2>Resource_Mailboxes_&lt;ProjectKey&gt;.csv</h2>
      <table>
        <thead><tr><th>Column</th><th>Required</th><th>Notes</th></tr></thead>
        <tbody>
          <tr><td><code>DisplayName</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td></td></tr>
          <tr><td><code>PrimarySmtpAddress</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td></td></tr>
          <tr><td><code>ResourceType</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td><code>Room</code> or <code>Equipment</code></td></tr>
          <tr><td><code>Capacity</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td>Integer; Room mailboxes only</td></tr>
          <tr><td><code>Location</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td>Maps to <code>Office</code> attribute</td></tr>
          <tr><td><code>ADP</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td>AddressBookPolicy name; warned if not found in destination</td></tr>
        </tbody>
      </table>

      <h2>Mail_Contacts_&lt;ProjectKey&gt;.csv</h2>
      <table>
        <thead><tr><th>Column</th><th>Required</th><th>Notes</th></tr></thead>
        <tbody>
          <tr><td><code>DisplayName</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td></td></tr>
          <tr><td><code>ExternalEmailAddress</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td>External email the contact points to</td></tr>
          <tr><td><code>Alias</code></td><td><span class="lozenge lozenge-neutral">No</span></td><td>Auto-derived from ExternalEmailAddress if omitted</td></tr>
        </tbody>
      </table>

      <h2>Mapping_Mailboxes_&lt;ProjectKey&gt;.csv</h2>
      <p>Used by <code>Convert-CSVForDestination</code> and <code>Update-AllMailboxesProxyAliases</code>.</p>
      <table>
        <thead><tr><th>Column</th><th>Required</th><th>Notes</th></tr></thead>
        <tbody>
          <tr><td><code>Source user email</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td>Source tenant UPN or primary SMTP</td></tr>
          <tr><td><code>Destination user email</code></td><td><span class="lozenge lozenge-error">Yes</span></td><td>Destination tenant UPN or primary SMTP</td></tr>
        </tbody>
      </table>

      <div class="panel panel-warning">
        <span class="panel-icon">⚠️</span>
        <div class="panel-body">
          <strong>Multi-value delimiter is semicolon (<code>;</code>)</strong>
          All multi-value fields (EmailAddresses, FullAccessUsers, SendAsUsers, Members, Alias) use
          <code>;</code> as the delimiter — not comma. Commas are reserved for CSV column separation.
        </div>
      </div>
    </section>

    <hr>

    <!-- ══ TROUBLESHOOTING ══ -->
    <section id="troubleshoot" class="section">
      <h1>Troubleshooting</h1>
      <table>
        <thead><tr><th>Error</th><th>Cause</th><th>Resolution</th></tr></thead>
        <tbody>
          <tr>
            <td><code>CSV missing required column: 'PrimarySmtpAddress'</code></td>
            <td>Column name mismatch in CSV</td>
            <td>Verify CSV headers match expected column names exactly (case-sensitive)</td>
          </tr>
          <tr>
            <td><code>The recipient … couldn't be found</code> in <code>Update-AllDistributionGroupMember</code></td>
            <td>Member not yet provisioned in destination</td>
            <td>Run import phase first; all members must exist before being added to groups</td>
          </tr>
          <tr>
            <td><code>No active EXO session</code> in <code>Test-MigrationPrerequisites</code></td>
            <td>Not connected to Exchange Online</td>
            <td>Run <code>Connect-ExchangeOnline -UserPrincipalName admin@tenant.onmicrosoft.com</code></td>
          </tr>
          <tr>
            <td><code>ExchangeOnlineManagement module &ge; 3.0 not found</code></td>
            <td>Module missing or outdated</td>
            <td><code>Install-Module ExchangeOnlineManagement</code> or <code>Update-Module ExchangeOnlineManagement</code></td>
          </tr>
          <tr>
            <td><code>Config file already exists</code> in <code>New-ProjectConfig</code></td>
            <td>Config for this ProjectKey already exists</td>
            <td>Add <code>-Force</code> to overwrite, or use a different <code>-OutputPath</code></td>
          </tr>
          <tr>
            <td><code>'_old' group already exists</code> in <code>ConvertDLtoShared</code></td>
            <td>Script was previously run for this DG</td>
            <td>Manual cleanup required — remove the <code>_old</code> group before re-running</td>
          </tr>
          <tr>
            <td><code>Could not set ADP … may not exist in destination</code></td>
            <td>AddressBookPolicy from source doesn't exist in destination</td>
            <td>Create the ADP in the destination first, or leave blank to skip</td>
          </tr>
          <tr>
            <td>Forwarding not removed after cleanup phase</td>
            <td>Forwarding not removed after cleanup phase</td>
            <td>Verify the CSV file passed to <code>Remove-AllMailboxForwardingEXO</code> contains the correct source addresses</td>
          </tr>
        </tbody>
      </table>
    </section>

  </div><!-- /content -->
</div><!-- /main -->

<script>
// ── Scrollspy ──
const sections = document.querySelectorAll('section[id]');
const navLinks  = document.querySelectorAll('#sidebar nav a[data-section]');
const breadcrumb = document.getElementById('breadcrumb');
const sectionNames = {
  overview: 'Overview', prereqs: 'Pre-Requisites', architecture: 'Architecture',
  phase0: 'Phase 0 — Project Setup', phase1: 'Phase 1 — Pre-Flight',
  phase2: 'Phase 2 — Source Export', phase3: 'Phase 3 — Data Prep',
  phase4: 'Phase 4 — Object Creation', phase5: 'Phase 5 — Permissions & Aliases',
  phase6: 'Phase 6 — Validation', phase7: 'Phase 7 — Cutover',
  rollback: 'Rollback', scriptref: 'Script Reference',
  csvformat: 'CSV Format', troubleshoot: 'Troubleshooting'
};

function setActive(id) {
  navLinks.forEach(a => {
    a.classList.toggle('active', a.dataset.section === id);
  });
  if (breadcrumb && sectionNames[id]) breadcrumb.textContent = sectionNames[id];
}

const observer = new IntersectionObserver(entries => {
  entries.forEach(entry => {
    if (entry.isIntersecting) setActive(entry.target.id);
  });
}, { rootMargin: '-10% 0px -80% 0px' });

sections.forEach(s => observer.observe(s));

// Smooth scroll
navLinks.forEach(a => {
  a.addEventListener('click', e => {
    e.preventDefault();
    const target = document.getElementById(a.dataset.section);
    if (target) target.scrollIntoView({ behavior: 'smooth' });
  });
});
</script>
</body>
</html>"""

# ---------------------------------------------------------------------------
# HTTP SERVER
# ---------------------------------------------------------------------------

class PlaybookHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(HTML.encode("utf-8"))))
        self.end_headers()
        self.wfile.write(HTML.encode("utf-8"))

    def log_message(self, fmt, *args):
        pass  # suppress request logs


def start_server(port=8080):
    server = http.server.HTTPServer(("", port), PlaybookHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


if __name__ == "__main__":
    PORT = 8080
    URL  = f"http://localhost:{PORT}"
    print(f"  M365 Migration Playbook")
    print(f"  Serving at: {URL}")
    print(f"  Press Ctrl+C to stop.\n")
    server = start_server(PORT)
    time.sleep(0.3)
    webbrowser.open(URL)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n  Server stopped.")
        server.shutdown()
