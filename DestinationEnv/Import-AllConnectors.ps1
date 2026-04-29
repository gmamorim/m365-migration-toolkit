<#
.SYNOPSIS
    Creates inbound and outbound connectors in the destination tenant from source CSVs.

.DESCRIPTION
    Reads the inbound and outbound connector CSV files exported by Get-AllConnectors
    and recreates them in the destination tenant. Connectors are created in disabled
    state by default to allow review before activation.

.PARAMETER InboundCSV
    Full path to the inbound connectors CSV. If omitted, inbound connectors are skipped.

.PARAMETER OutboundCSV
    Full path to the outbound connectors CSV. If omitted, outbound connectors are skipped.

.PARAMETER Enabled
    If specified, creates connectors in Enabled state. Default is Disabled.

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    Import-AllConnectors -InboundCSV "C:\CSV\Acme\Inbound_Connectors_Acme.csv" `
        -OutboundCSV "C:\CSV\Acme\Outbound_Connectors_Acme.csv"

.EXAMPLE
    Import-AllConnectors -InboundCSV "C:\CSV\Acme\Inbound_Connectors_Acme.csv" -Enabled -WhatIf

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    CSV In   : Name (req) — all other columns optional
#>

function Import-AllConnectors {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$InboundCSV,

        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$OutboundCSV,

        [Parameter(Mandatory = $false)]
        [switch]$Enabled,

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

        if (-not $InboundCSV -and -not $OutboundCSV) {
            throw "At least one of -InboundCSV or -OutboundCSV must be provided."
        }

        $successCount = 0
        $errorCount   = 0
        Write-Log "Starting Import-AllConnectors." -Level Info
        if (-not $Enabled) { Write-Log "Connectors will be created in Disabled state. Use -Enabled to activate on creation." -Level Warning }
    }

    process {
        # Inbound connectors
        if ($InboundCSV) {
            try {
                $inbound = Import-Csv -Path $InboundCSV -Encoding UTF8 -ErrorAction Stop
            }
            catch {
                Write-Log "Failed to import inbound CSV: $($_.Exception.Message)" -Level Error
                $inbound = @()
            }

            foreach ($c in $inbound) {
                Write-Verbose "Processing inbound: $($c.Name)"
                if ($PSCmdlet.ShouldProcess($c.Name, 'Create inbound connector')) {
                    try {
                        $params = @{ Name = $c.Name; Enabled = $Enabled.IsPresent; ErrorAction = 'Stop' }
                        if ($c.ConnectorType -and $c.ConnectorType -ne '')         { $params['ConnectorType']            = $c.ConnectorType }
                        if ($c.SenderDomains -and $c.SenderDomains -ne '')         { $params['SenderDomains']            = $c.SenderDomains -split ';' }
                        if ($c.SenderIPAddresses -and $c.SenderIPAddresses -ne '') { $params['SenderIPAddresses']        = $c.SenderIPAddresses -split ';' }
                        if ($c.RequireTls -eq 'True')                              { $params['RequireTls']               = $true }
                        if ($c.RestrictDomainsToCertificate -eq 'True')            { $params['RestrictDomainsToCertificate'] = $true }
                        if ($c.TlsSenderCertificateName -and $c.TlsSenderCertificateName -ne '') { $params['TlsSenderCertificateName'] = $c.TlsSenderCertificateName }
                        if ($c.Comment -and $c.Comment -ne '')                     { $params['Comment']                  = $c.Comment }

                        New-InboundConnector @params
                        Write-Log "Created inbound connector '$($c.Name)'." -Level Success
                        $successCount++
                    }
                    catch {
                        Write-Log "Failed to create inbound connector '$($c.Name)': $($_.Exception.Message)" -Level Error
                        $errorCount++
                    }
                }
            }
        }

        # Outbound connectors
        if ($OutboundCSV) {
            try {
                $outbound = Import-Csv -Path $OutboundCSV -Encoding UTF8 -ErrorAction Stop
            }
            catch {
                Write-Log "Failed to import outbound CSV: $($_.Exception.Message)" -Level Error
                $outbound = @()
            }

            foreach ($c in $outbound) {
                Write-Verbose "Processing outbound: $($c.Name)"
                if ($PSCmdlet.ShouldProcess($c.Name, 'Create outbound connector')) {
                    try {
                        $params = @{ Name = $c.Name; Enabled = $Enabled.IsPresent; ErrorAction = 'Stop' }
                        if ($c.ConnectorType -and $c.ConnectorType -ne '')     { $params['ConnectorType']     = $c.ConnectorType }
                        if ($c.RecipientDomains -and $c.RecipientDomains -ne '') { $params['RecipientDomains'] = $c.RecipientDomains -split ';' }
                        if ($c.SmartHosts -and $c.SmartHosts -ne '')           { $params['SmartHosts']        = $c.SmartHosts -split ';' }
                        if ($c.TlsSettings -and $c.TlsSettings -ne '')         { $params['TlsSettings']       = $c.TlsSettings }
                        if ($c.TlsDomain -and $c.TlsDomain -ne '')             { $params['TlsDomain']         = $c.TlsDomain }
                        if ($c.UseMXRecord -eq 'True')                         { $params['UseMXRecord']       = $true }
                        if ($c.Comment -and $c.Comment -ne '')                 { $params['Comment']           = $c.Comment }

                        New-OutboundConnector @params
                        Write-Log "Created outbound connector '$($c.Name)'." -Level Success
                        $successCount++
                    }
                    catch {
                        Write-Log "Failed to create outbound connector '$($c.Name)': $($_.Exception.Message)" -Level Error
                        $errorCount++
                    }
                }
            }
        }
    }

    end {
        Write-Log "Summary | Succeeded: $successCount | Failed: $errorCount | Total: $($successCount + $errorCount)" -Level Info
        [PSCustomObject]@{
            Function     = 'Import-AllConnectors'
            Succeeded    = $successCount
            Failed       = $errorCount
            Total        = $successCount + $errorCount
            TimestampUTC = (Get-Date).ToUniversalTime()
        }
    }
}
