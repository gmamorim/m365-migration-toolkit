<#
.SYNOPSIS
    Validates that the environment is ready for an M365 migration run.

.DESCRIPTION
    Runs a series of pre-flight checks and returns a structured result for each
    test. Tests are categorised as Pass, Fail, or Warning. Start-Migration.ps1
    aborts if any test returns Fail.

    Checks performed:
      - ExchangeOnlineManagement module installed (version >= 3.0)
      - Active Exchange Online session
      - $CSVFolder directory exists and is writable
      - Project CSV subfolder exists (created automatically if missing)
      - Disk space >= 100 MB on the $CSVFolder drive
      - Expected source CSV files present (Warning per missing file)

.PARAMETER CSVFolder
    Base directory for all CSV files. Must exist and be writable.

.PARAMETER ProjectKey
    Project key used to locate the project-specific CSV subfolder.

.PARAMETER LogPath
    Optional. Full path to a log file. Output is appended to this file.

.EXAMPLE
    Test-MigrationPrerequisites -CSVFolder "C:\CSV" -ProjectKey "Acme"

    Runs all prerequisite checks and prints a colour-coded result table.

.EXAMPLE
    $results = Test-MigrationPrerequisites -CSVFolder "C:\CSV" -ProjectKey "Acme"
    $results | Where-Object Result -eq 'Fail'

    Captures results and filters for failures only.

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement >= 3.0
#>

function Test-MigrationPrerequisites {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$CSVFolder,

        [Parameter(Mandatory = $true)]
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

        function New-TestResult {
            param([string]$Test, [string]$Result, [string]$Detail)
            [PSCustomObject]@{ Test = $Test; Result = $Result; Detail = $Detail }
        }

        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
        Write-Log "Starting prerequisite checks for project: $ProjectKey" -Level Info
    }

    process {
        # 1. ExchangeOnlineManagement module
        $exoModule = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
                     Sort-Object Version -Descending | Select-Object -First 1
        if ($exoModule -and [version]$exoModule.Version -ge [version]'3.0') {
            $results.Add((New-TestResult 'EXO Module >= 3.0' 'Pass' "Version $($exoModule.Version) installed"))
        } elseif ($exoModule) {
            $results.Add((New-TestResult 'EXO Module >= 3.0' 'Fail' "Version $($exoModule.Version) is too old. Run: Update-Module ExchangeOnlineManagement"))
        } else {
            $results.Add((New-TestResult 'EXO Module >= 3.0' 'Fail' 'Module not found. Run: Install-Module ExchangeOnlineManagement'))
        }

        # 2. Active EXO session
        try {
            $conn = Get-ConnectionInformation -ErrorAction Stop | Where-Object { $_.State -eq 'Connected' }
            if ($conn) {
                $results.Add((New-TestResult 'EXO Session Active' 'Pass' "Connected to: $($conn.TenantDomain)"))
            } else {
                $results.Add((New-TestResult 'EXO Session Active' 'Fail' 'No active session. Run: Connect-ExchangeOnline'))
            }
        } catch {
            $results.Add((New-TestResult 'EXO Session Active' 'Fail' "Error checking session: $($_.Exception.Message)"))
        }

        # 3. CSVFolder exists and is writable
        if (Test-Path $CSVFolder -PathType Container) {
            try {
                $testFile = Join-Path $CSVFolder ".writetest_$(Get-Random)"
                [System.IO.File]::WriteAllText($testFile, 'test')
                Remove-Item $testFile -Force
                $results.Add((New-TestResult 'CSVFolder Writable' 'Pass' $CSVFolder))
            } catch {
                $results.Add((New-TestResult 'CSVFolder Writable' 'Fail' "Directory exists but is not writable: $CSVFolder"))
            }
        } else {
            $results.Add((New-TestResult 'CSVFolder Exists' 'Fail' "Directory not found: $CSVFolder"))
        }

        # 4. Project subfolder (auto-create)
        $projectFolder = Join-Path $CSVFolder $ProjectKey
        if (Test-Path $projectFolder) {
            $results.Add((New-TestResult 'Project CSV Subfolder' 'Pass' $projectFolder))
        } else {
            try {
                New-Item -ItemType Directory -Path $projectFolder -Force | Out-Null
                $results.Add((New-TestResult 'Project CSV Subfolder' 'Pass' "Created: $projectFolder"))
            } catch {
                $results.Add((New-TestResult 'Project CSV Subfolder' 'Fail' "Could not create: $projectFolder — $($_.Exception.Message)"))
            }
        }

        # 5. Disk space >= 100 MB
        try {
            $drive = Split-Path -Qualifier $CSVFolder
            $disk  = Get-PSDrive -Name ($drive.TrimEnd(':')) -ErrorAction Stop
            $freeMB = [math]::Round($disk.Free / 1MB, 0)
            if ($freeMB -ge 100) {
                $results.Add((New-TestResult 'Disk Space >= 100 MB' 'Pass' "${freeMB} MB free on $drive"))
            } else {
                $results.Add((New-TestResult 'Disk Space >= 100 MB' 'Warning' "Only ${freeMB} MB free on $drive. Consider freeing space."))
            }
        } catch {
            $results.Add((New-TestResult 'Disk Space >= 100 MB' 'Warning' "Could not determine free space: $($_.Exception.Message)"))
        }

        # 6. Expected source CSV files (warnings per missing file)
        $expectedFiles = @(
            "Mailboxes_$ProjectKey.csv"
            "Shared_Mailboxes_$ProjectKey.csv"
            "Resource_Mailboxes_$ProjectKey.csv"
            "Distribution_Groups_$ProjectKey.csv"
        )
        foreach ($file in $expectedFiles) {
            $filePath = Join-Path $projectFolder $file
            if (Test-Path $filePath) {
                $results.Add((New-TestResult "CSV Present: $file" 'Pass' $filePath))
            } else {
                $results.Add((New-TestResult "CSV Present: $file" 'Warning' "Not found: $filePath — run the export phase first."))
            }
        }
    }

    end {
        Write-Log "Prerequisite check complete. Results:" -Level Info
        foreach ($r in $results) {
            $level = switch ($r.Result) { 'Pass' { 'Success' } 'Fail' { 'Error' } default { 'Warning' } }
            Write-Log "  [$($r.Result)] $($r.Test) — $($r.Detail)" -Level $level
        }
        return $results
    }
}
