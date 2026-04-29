<#
.SYNOPSIS
    Resolves a unique alias for a destination object, avoiding collisions with existing recipients.

.DESCRIPTION
    Builds a candidate alias from the source PrimarySmtpAddress local part, sanitises it,
    then checks the destination Exchange Online tenant via Get-Recipient. If the candidate
    already exists, appends an incrementing numeric suffix (2, 3, ...) until a free alias
    is found.

    Alias format: <sanitisedLocalPart>@<Domain>
    Example: invoices@contoso.com -> invoices@dest.com (free)
             john.smith@contoso.com -> john.smith@dest.com (taken) -> john.smith2@dest.com

.PARAMETER SourceAddress
    The source PrimarySmtpAddress. The local part is used as the alias base.

.PARAMETER Domain
    Destination tenant SMTP domain.

.PARAMETER Prefix
    Optional. A prefix to prepend to the alias (e.g. a department code).
    When provided, the alias becomes: <Prefix>-<localPart>@<Domain>

.EXAMPLE
    Resolve-UniqueAlias -SourceAddress "invoices@contoso.com" -Domain "dest.com"
    # Returns: invoices@dest.com  (or invoices2@dest.com if taken)

.EXAMPLE
    Resolve-UniqueAlias -SourceAddress "john.smith@contoso.com" -Domain "dest.com" -Prefix "sales"
    # Returns: sales-john.smith@dest.com  (or sales-john.smith2@dest.com if taken)

.OUTPUTS
    [string] The resolved unique alias (full SMTP address).

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
#>

function Resolve-UniqueAlias {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceAddress,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

        [Parameter(Mandatory = $false)]
        [string]$Prefix
    )

    $localPart = ($SourceAddress -split '@')[0]
    $base      = if ($Prefix) { "$Prefix-$localPart" } else { $localPart }
    $base      = ($base -replace '[^a-zA-Z0-9._-]', '').ToLower()

    $candidate = "$base@$Domain"
    $suffix    = 2

    while ($true) {
        $exists = Get-Recipient -Identity $candidate -ErrorAction SilentlyContinue
        if (-not $exists) { return $candidate }
        $candidate = "$base$suffix@$Domain"
        $suffix++
    }
}
