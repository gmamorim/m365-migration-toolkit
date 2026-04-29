<#
.SYNOPSIS
    Creates resource mailboxes (Room and Equipment) in the destination tenant from a source CSV.

.DESCRIPTION
    For each row, resolves a unique destination alias using Resolve-UniqueAlias and creates
    a Room or Equipment mailbox. After creation, sets user attributes (Office, Phone,
    Department, etc.) and optionally sets an AddressBookPolicy. ADP failures are logged
    as warnings and do not abort.

.PARAMETER CSVFile
    Full path to the input CSV.
    Required columns: DisplayName, PrimarySmtpAddress, ResourceType.

.PARAMETER Domain
    Destination tenant SMTP domain (e.g. "contoso.com").

.PARAMETER Company
    Optional. Company name prepended to DisplayName.

.PARAMETER Prefix
    Optional. Short prefix prepended to the alias.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Import-AllResourceMailboxes -CSVFile "C:\CSV\Contoso\Resource_Mailboxes_Contoso.csv" `
        -Domain "dest.com"

.EXAMPLE
    Import-AllResourceMailboxes -CSVFile "C:\CSV\Contoso\Resource_Mailboxes_Contoso.csv" `
        -Domain "dest.com" -Company "Contoso" -WhatIf

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.1
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : DisplayName (req), PrimarySmtpAddress (req), ResourceType (req: Room|Equipment),
               Capacity, Location, Telephone, Department, Company, ADP,
               Street, City, StateProvince, Zip, Country
#>

function Import-AllResourceMailboxes {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CSVFile,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

        [Parameter(Mandatory = $false)]
        [string]$Company,

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

        $headers = (Get-Content $CSVFile -TotalCount 1) -split ',' | ForEach-Object { $_.Trim('"').Trim() }
        foreach ($col in @('DisplayName', 'PrimarySmtpAddress', 'ResourceType')) {
            if ($col -notin $headers) { throw "CSV missing required column: '$col'" }
        }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Import-AllResourceMailboxes. CSV: $CSVFile" -Level Info
    }

    process {
        $Resources = Import-Csv -Path $CSVFile -Encoding UTF8

        foreach ($Resource in $Resources) {
            $resolveParams = @{ SourceAddress = $Resource.PrimarySmtpAddress; Domain = $Domain }
            if ($Prefix) { $resolveParams['Prefix'] = $Prefix }

            $PrimarySmtpAddress   = Resolve-UniqueAlias @resolveParams
            $Alias                = ($PrimarySmtpAddress -split '@')[0]
            $FormattedDisplayName = if ($Company) { "$Company - $($Resource.DisplayName)" } else { $Resource.DisplayName }

            Write-Verbose "Processing: $FormattedDisplayName -> $PrimarySmtpAddress"

            if ($PSCmdlet.ShouldProcess($PrimarySmtpAddress, "Create $($Resource.ResourceType) mailbox")) {
                try {
                    switch ($Resource.ResourceType) {
                        'Room' {
                            $newParams = @{
                                Room               = $true
                                Name               = $FormattedDisplayName
                                DisplayName        = $FormattedDisplayName
                                Alias              = $Alias
                                PrimarySmtpAddress = $PrimarySmtpAddress
                                ErrorAction        = 'Stop'
                                Confirm            = $false
                            }
                            if ($Resource.Capacity -and $Resource.Capacity -ne '') {
                                $newParams['ResourceCapacity'] = [int]$Resource.Capacity
                            }
                            New-Mailbox @newParams
                        }
                        'Equipment' {
                            New-Mailbox -Equipment -Name $FormattedDisplayName -DisplayName $FormattedDisplayName `
                                -Alias $Alias -PrimarySmtpAddress $PrimarySmtpAddress -ErrorAction Stop -Confirm:$false
                        }
                        default {
                            Write-Log "Unknown ResourceType '$($Resource.ResourceType)' for '$($Resource.DisplayName)'. Skipping." -Level Warning
                            continue
                        }
                    }

                    Write-Log "Created $($Resource.ResourceType) mailbox '$FormattedDisplayName'." -Level Success
                    $successCount++

                    $setUserParams = @{}
                    if ($Resource.Location)      { $setUserParams['Office']          = $Resource.Location }
                    if ($Resource.Telephone)     { $setUserParams['Phone']           = $Resource.Telephone }
                    if ($Resource.Department)    { $setUserParams['Department']      = $Resource.Department }
                    if ($Resource.Company)       { $setUserParams['Company']         = $Resource.Company }
                    if ($Resource.Street)        { $setUserParams['StreetAddress']   = $Resource.Street }
                    if ($Resource.City)          { $setUserParams['City']            = $Resource.City }
                    if ($Resource.StateProvince) { $setUserParams['StateOrProvince'] = $Resource.StateProvince }
                    if ($Resource.Zip)           { $setUserParams['PostalCode']      = $Resource.Zip }
                    if ($Resource.Country)       { $setUserParams['CountryOrRegion'] = $Resource.Country }

                    if ($setUserParams.Count -gt 0) {
                        Set-User -Identity $PrimarySmtpAddress @setUserParams -ErrorAction Stop -Confirm:$false
                    }

                    if ($Resource.ADP -and $Resource.ADP -ne '') {
                        try {
                            Set-Mailbox -Identity $PrimarySmtpAddress -AddressBookPolicy $Resource.ADP -ErrorAction Stop -Confirm:$false
                        }
                        catch {
                            Write-Log "Warning: Could not set ADP '$($Resource.ADP)' for '$FormattedDisplayName'. It may not exist in the destination tenant." -Level Warning
                        }
                    }
                }
                catch {
                    Write-Log "Failed to create '$FormattedDisplayName': $($_.Exception.Message)" -Level Error
                    $errorCount++
                }
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Import-AllResourceMailboxes'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
