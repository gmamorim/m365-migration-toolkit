<#
.SYNOPSIS
    Translates a source shared mailbox CSV to destination format using a user mapping file.

.DESCRIPTION
    Reads the source CSV (exported from the source tenant), a user mapping CSV
    (source email -> destination email), and produces a new CSV with:
      - Alias and PrimarySmtpAddress reformatted for the destination tenant
      - DisplayName prefixed with the company name
      - FullAccessUsers, SendAsUsers, and Members remapped to destination addresses
        using the mapping file (falls back to the original address if not found)

    This function is the V2 refactor of CSVTranslator.ps1 (previously a script-mode file).
    The Convert-Emails helper has been moved from the loop scope to the begin block.

.PARAMETER SourceCsv
    Path to the CSV exported from the source tenant (output of Get-AllSharedMailboxes).

.PARAMETER MappingCsv
    Path to the user mapping CSV. Required columns: 'Source user email', 'Destination user email'.

.PARAMETER OutputPath
    Directory (or full file path) for the output CSV. If a directory is given, the file
    is named "Translated_Mailboxes_<Company>_<yyyyMMdd>.csv".

.PARAMETER Prefix
    Optional. Short prefix prepended to the alias (e.g. a department or project code).

.PARAMETER Company
    Optional. Company name used in DisplayName and output file name.

.PARAMETER Domain
    Destination tenant SMTP domain.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Convert-CSVForDestination -SourceCsv "C:\CSV\Contoso\SharedMailbox_acme.com.csv" `
        -MappingCsv "C:\CSV\Contoso\Mapping_Mailboxes_Contoso.csv" `
        -OutputPath "C:\CSV\Contoso\" `
        -Company "Contoso" -Domain "amorim.rocks"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : No external modules (local file operations only)
    CSV In (Source)  : DisplayName, PrimarySmtpAddress, FullAccessUsers, SendAsUsers, Members,
                       ForwardingAddress, ForwardingSmtpAddress, DeliverToMailboxAndForward
    CSV In (Mapping) : 'Source user email', 'Destination user email'
    CSV Out          : Same columns as source, remapped to destination format
#>

function Convert-CSVForDestination {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$SourceCsv,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$MappingCsv,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [string]$Prefix,

        [Parameter(Mandatory = $false)]
        [string]$Company,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

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

        # Validate source CSV columns
        $srcHeaders = (Get-Content $SourceCsv -TotalCount 1) -split ',' | ForEach-Object { $_.Trim('"').Trim() }
        foreach ($col in @('DisplayName', 'PrimarySmtpAddress')) {
            if ($col -notin $srcHeaders) { throw "SourceCsv missing required column: '$col'" }
        }

        # Validate mapping CSV columns
        $mapHeaders = (Get-Content $MappingCsv -TotalCount 1) -split ',' | ForEach-Object { $_.Trim('"').Trim() }
        foreach ($col in @('Source user email', 'Destination user email')) {
            if ($col -notin $mapHeaders) { throw "MappingCsv missing required column: '$col'" }
        }

        # Load mapping into hashtable for O(1) lookup
        $userMap = @{}
        Import-Csv -Path $MappingCsv | ForEach-Object {
            $src = $_.'Source user email'
            $dst = $_.'Destination user email'
            if ($src -and $dst) {
                $userMap[$src.ToLower()] = $dst
            }
        }
        Write-Log "Loaded $($userMap.Count) user mappings from '$MappingCsv'." -Level Info

        # Helper: convert semicolon-separated emails using the mapping
        function Convert-Emails {
            param([string]$rawEmails)
            if (-not $rawEmails) { return '' }
            return ($rawEmails -split ';' | ForEach-Object {
                $trimmed = $_.Trim().ToLower()
                if ($userMap.ContainsKey($trimmed)) { $userMap[$trimmed] } else { $trimmed }
            }) -join ';'
        }

        # Resolve output path
        if ([System.IO.Path]::GetExtension($OutputPath) -eq '') {
            $timestamp  = Get-Date -Format 'yyyyMMdd'
            $OutputPath = Join-Path $OutputPath "Translated_Mailboxes_${Company}_$timestamp.csv"
        }

        $successCount = 0
        $results      = [System.Collections.Generic.List[PSCustomObject]]::new()

        Write-Log "Starting Convert-CSVForDestination. Output: $OutputPath" -Level Info    }

    process {
        $SourceRows = Import-Csv -Path $SourceCsv -Encoding UTF8

        foreach ($row in $SourceRows) {
            Write-Verbose "Translating: $($row.PrimarySmtpAddress)"
            try {
                $localPart             = ($row.PrimarySmtpAddress -split '@')[0]
                $base                  = if ($Prefix) { "$Prefix-$localPart" } else { $localPart }
                $newAlias              = ($base -replace '[^a-zA-Z0-9._-]', '').ToLower()
                $newPrimarySmtpAddress = "$newAlias@$Domain"
                $newDisplayName        = if ($Company) { "$Company - $($row.DisplayName)" } else { $row.DisplayName }

                $results.Add([PSCustomObject]@{
                    DisplayName                = $newDisplayName
                    PrimarySmtpAddress         = $newPrimarySmtpAddress
                    Alias                      = $newAlias
                    EmailAddresses             = $row.EmailAddresses
                    FullAccessUsers            = Convert-Emails $row.FullAccessUsers
                    SendAsUsers                = Convert-Emails $row.SendAsUsers
                    ForwardingAddress          = $row.ForwardingAddress
                    ForwardingSmtpAddress      = $row.ForwardingSmtpAddress
                    DeliverToMailboxAndForward = $row.DeliverToMailboxAndForward
                    Members                    = Convert-Emails $row.Members
                })
                $successCount++
            }
            catch {
                Write-Log "Failed to translate '$($row.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Error
            }
        }
    }

    end {
        $results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Log "Exported $($results.Count) translated rows to: $OutputPath" -Level Success
        Write-Log "Summary | Translated: $successCount | Total input rows: $($results.Count)" -Level Info

        [PSCustomObject]@{
            Function     = 'Convert-CSVForDestination'
            Succeeded    = $successCount
            Failed       = 0
            Total        = $successCount
            OutputFile   = $OutputPath
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
