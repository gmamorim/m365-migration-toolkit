<#
.SYNOPSIS
    Converts a Distribution List to a Shared Mailbox while preserving all email addresses and members.

.DESCRIPTION
    Performs the following steps:
      1. Retrieves the original Distribution Group and its members, addresses, and owners
      2. Checks if an '_old' version of the group already exists (idempotency check)
      3. Removes the original DG
      4. Creates a new '_old' DG with all renamed addresses (preserves member history)
      5. Creates a Shared Mailbox with the original DG's addresses
      6. Waits 15 seconds for EXO mailbox provisioning to complete
      7. Grants FullAccess and SendAs to all original DG members

    Run with -WhatIf first to verify the correct group is targeted.

.PARAMETER DGIdentity
    SMTP address or identity of the Distribution Group to convert.
    Example: "sales@acme.com"

.PARAMETER LogPath
    Optional. Full path to a log file.

.EXAMPLE
    ConvertDLtoShared -DGIdentity "sales@acme.com"

.EXAMPLE
    ConvertDLtoShared -DGIdentity "sales@acme.com" -WhatIf

    Shows what would happen without making any changes.

.NOTES
    Author   : Gabriel Amorim
    Version  : 2.0
    Requires : ExchangeOnlineManagement module, active EXO session
    Idempotent: Checks if the '_old' group already exists before proceeding.
#>

function ConvertDLtoShared {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DGIdentity,

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
    }

    process {
        # 1. Retrieve original DG
        try {
            $DG = Get-DistributionGroup -Identity $DGIdentity -ErrorAction Stop
        }
        catch {
            Write-Log "Distribution Group '$DGIdentity' not found: $($_.Exception.Message)" -Level Error
            return
        }

        $DGMembers       = Get-DistributionGroupMember -Identity $DG.Identity
        $DGEmailAddresses = $DG.EmailAddresses
        $DGPrimarySMTP   = $DG.PrimarySmtpAddress.ToString()
        $DGOwners        = $DG.ManagedBy
        $originalName    = $DG.DisplayName

        $oldPrimarySMTP = $DGPrimarySMTP.Replace('@', '_old@')
        $oldDisplayName = "${originalName}_old"

        Write-Log "Starting conversion of '$originalName' ($DGPrimarySMTP) to Shared Mailbox." -Level Info

        # 2. Idempotency: check if _old group already exists
        $existingOld = Get-DistributionGroup -Identity $oldPrimarySMTP -ErrorAction SilentlyContinue
        if ($existingOld) {
            Write-Log "Warning: '_old' group '$oldPrimarySMTP' already exists. Aborting to prevent duplicate conversion." -Level Warning
            return
        }

        if (-not $PSCmdlet.ShouldProcess($DGPrimarySMTP, 'Remove original DG and create Shared Mailbox')) {
            return
        }

        # 3. Remove original DG
        try {
            Remove-DistributionGroup -Identity $DGIdentity -Confirm:$false -ErrorAction Stop
            Write-Log "Removed original Distribution Group '$DGPrimarySMTP'." -Level Success
        }
        catch {
            Write-Log "Failed to remove Distribution Group '$DGPrimarySMTP': $($_.Exception.Message)" -Level Error
            return
        }

        # 4. Create _old DG with renamed addresses
        try {
            $oldEmailAddresses = $DGEmailAddresses | ForEach-Object {
                if ($_.PrefixString -eq 'SMTP') {
                    "SMTP:$($_.SmtpAddress.ToString().Replace('@', '_old@'))"
                } else {
                    $_.ToString().Replace('@', '_old@')
                }
            }

            New-DistributionGroup -Name $oldDisplayName -DisplayName $oldDisplayName `
                -PrimarySmtpAddress $oldPrimarySMTP -ManagedBy $DGOwners -ErrorAction Stop | Out-Null
            Set-DistributionGroup -Identity $oldPrimarySMTP -EmailAddresses $oldEmailAddresses

            foreach ($member in $DGMembers) {
                try {
                    Add-DistributionGroupMember -Identity $oldPrimarySMTP `
                        -Member $member.PrimarySmtpAddress -ErrorAction Stop
                }
                catch {
                    Write-Log "Warning: Could not add '$($member.PrimarySmtpAddress)' to '_old' group: $($_.Exception.Message)" -Level Warning
                }
            }
            Write-Log "Created '_old' group '$oldPrimarySMTP' with all members." -Level Success
        }
        catch {
            Write-Log "Failed to create '_old' group: $($_.Exception.Message)" -Level Error
            return
        }

        # 5. Create Shared Mailbox with original addresses
        try {
            New-Mailbox -Shared -Name $originalName -DisplayName $originalName `
                -PrimarySmtpAddress $DGPrimarySMTP -ErrorAction Stop | Out-Null
            Set-Mailbox -Identity $DGPrimarySMTP -EmailAddresses $DGEmailAddresses
            Write-Log "Created Shared Mailbox '$DGPrimarySMTP'." -Level Success
        }
        catch {
            Write-Log "Failed to create Shared Mailbox: $($_.Exception.Message)" -Level Error
            return
        }

        # 6. Wait for EXO provisioning (required before permission assignment)
        Write-Log "Waiting 15 seconds for mailbox provisioning to complete in EXO..." -Level Info
        Start-Sleep -Seconds 15

        # 7. Grant permissions to all original members
        foreach ($member in $DGMembers) {
            try {
                Add-MailboxPermission -Identity $DGPrimarySMTP -User $member.PrimarySmtpAddress `
                    -AccessRights FullAccess -InheritanceType All -ErrorAction Stop | Out-Null
                Add-RecipientPermission -Identity $DGPrimarySMTP -Trustee $member.PrimarySmtpAddress `
                    -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Log "Granted FullAccess + SendAs to '$($member.PrimarySmtpAddress)'." -Level Success
            }
            catch {
                Write-Log "Failed to assign permissions to '$($member.PrimarySmtpAddress)': $($_.Exception.Message)" -Level Warning
            }
        }
    }

    end {
        Write-Log "Conversion of '$originalName' to Shared Mailbox completed." -Level Success

        [PSCustomObject]@{
            Function        = 'ConvertDLtoShared'
            OriginalDG      = $DGPrimarySMTP
            SharedMailbox   = $DGPrimarySMTP
            OldGroup        = $oldPrimarySMTP
            MembersGranted  = $DGMembers.Count
            TimestampUTC    = (Get-Date).ToUniversalTime()
        }
    }
}
