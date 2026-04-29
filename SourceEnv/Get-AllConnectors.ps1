<#
.SYNOPSIS
    Exports all inbound and outbound connectors from the source tenant to CSV.

.DESCRIPTION
    Retrieves all InboundConnector and OutboundConnector objects and exports their
    key properties to separate CSV files. Used by Import-AllConnectors to recreate
    connectors in the destination tenant.

    Output: <OutputCSV>\<ProjectKey>\Inbound_Connectors_<ProjectKey>.csv
            <OutputCSV>\<ProjectKey>\Outbound_Connectors_<ProjectKey>.csv

.PARAMETER OutputCSV
    Base directory for CSV output.

.PARAMETER ProjectKey
    Project key used to name the output subfolder and file.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Get-AllConnectors -OutputCSV "C:\CSV" -ProjectKey "Acme"

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Get-AllConnectors {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$OutputCSV,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
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

        $folderPath = Join-Path $OutputCSV $ProjectKey
        if (-not (Test-Path $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        }

        $outputInbound  = Join-Path $folderPath "Inbound_Connectors_$ProjectKey.csv"
        $outputOutbound = Join-Path $folderPath "Outbound_Connectors_$ProjectKey.csv"

        Write-Log "Starting Get-AllConnectors." -Level Info
    }

    process {
        # Inbound connectors
        try {
            $inbound = Get-InboundConnector -ErrorAction Stop
            $inboundResults = foreach ($c in $inbound) {
                [PSCustomObject]@{
                    Name                     = $c.Name
                    Enabled                  = $c.Enabled
                    ConnectorType            = $c.ConnectorType
                    ConnectorSource          = $c.ConnectorSource
                    SenderDomains            = $c.SenderDomains -join ';'
                    SenderIPAddresses        = $c.SenderIPAddresses -join ';'
                    RequireTls               = $c.RequireTls
                    RestrictDomainsToCertificate = $c.RestrictDomainsToCertificate
                    TlsSenderCertificateName = $c.TlsSenderCertificateName
                    Comment                  = $c.Comment
                }
            }
            $inboundResults | Export-Csv -Path $outputInbound -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($inbound.Count) inbound connectors to: $outputInbound" -Level Success
        }
        catch {
            Write-Log "Failed to retrieve inbound connectors: $($_.Exception.Message)" -Level Error
        }

        # Outbound connectors
        try {
            $outbound = Get-OutboundConnector -ErrorAction Stop
            $outboundResults = foreach ($c in $outbound) {
                [PSCustomObject]@{
                    Name                     = $c.Name
                    Enabled                  = $c.Enabled
                    ConnectorType            = $c.ConnectorType
                    ConnectorSource          = $c.ConnectorSource
                    RecipientDomains         = $c.RecipientDomains -join ';'
                    SmartHosts               = $c.SmartHosts -join ';'
                    TlsSettings              = $c.TlsSettings
                    TlsDomain                = $c.TlsDomain
                    UseMXRecord              = $c.UseMXRecord
                    IsTransportRuleScoped    = $c.IsTransportRuleScoped
                    Comment                  = $c.Comment
                }
            }
            $outboundResults | Export-Csv -Path $outputOutbound -NoTypeInformation -Encoding UTF8
            Write-Log "Exported $($outbound.Count) outbound connectors to: $outputOutbound" -Level Success
        }
        catch {
            Write-Log "Failed to retrieve outbound connectors: $($_.Exception.Message)" -Level Error
        }
    }

    end {
        [PSCustomObject]@{
            Function     = 'Get-AllConnectors'
            InboundFile  = $outputInbound
            OutboundFile = $outputOutbound
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
