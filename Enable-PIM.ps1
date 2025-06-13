<#
.SYNOPSIS
    Activates or deactivates Entra Global Administrator and Azure Owner PIM roles.

.DESCRIPTION
    This script activates or deactivates Privileged Identity Management (PIM) roles for Entra ID
    (Global Administrator) and Azure RBAC (Owner) using the Graph and Azure PowerShell modules.

    NOTE: Elevating to Global Administrator and Owner roles should be done sparingly and only when
    necessary. This script is an example and should be customized for your specific environment.

.PARAMETER Enable
    Activates the PIM roles. Cannot be used with -Disable.

.PARAMETER Disable
    Deactivates the PIM roles. Cannot be used with -Enable.

.PARAMETER Reason
    A justification for why the roles are being activated or deactivated. For activation, this is
    required and will be prompted for if not supplied. For deactivation, this is optional.

.PARAMETER Hours
    The duration in hours for which the roles should be activated. Only used with -Enable. Defaults
    to 8 hours. Will be capped at configurable max allowed value.

.PARAMETER SubscriptionId
    The Azure subscription ID. If not provided, will use the default value set in the script variables.

.PARAMETER TenantId
    The Azure tenant ID. If not provided, will use the default value set in the script variables.

.EXAMPLE
    ./Enable-PIM.ps1 -Enable
    Activates both roles with the default duration, prompting for justification.

.EXAMPLE
    ./Enable-PIM.ps1 -Enable -Reason "Investigating security alert"
    Activates both roles with the provided justification for the default duration.

.EXAMPLE
    ./Enable-PIM.ps1 -Enable -Reason "Emergency access required" -Hours 4
    Activates both roles for 4 hours with the specified justification.

.EXAMPLE
    ./Enable-PIM.ps1 -Disable
    Deactivates both roles with the default reason.

.EXAMPLE
    ./Enable-PIM.ps1 -Disable -Reason "Finished administrative tasks"
    Deactivates both roles with a custom reason.

.EXAMPLE
    ./Enable-PIM.ps1 -Enable -SubscriptionId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321"
    Activates both roles using the specified subscription and tenant IDs.

.NOTES
    File Name      : Enable-PIM.ps1
    Author         : Danny Stewart
    Version        : 2.0.0
    Prerequisite   : PowerShell 7+, Microsoft.Graph and Az PowerShell modules
    License        : MIT License

    This script requires you to be eligible for both the Global Administrator role in Entra ID and
    the Owner role in Azure. It will use your current identity for authentication.

    You can either edit the script to update the subscription and tenant IDs or provide them as
    command-line arguments when running the script.

.LINK
    https://github.com/dannystewart/Enable-PIM
#>

param(
    [Parameter(Mandatory = $true, ParameterSetName = "Enable")]
    [switch]$Enable,

    [Parameter(Mandatory = $true, ParameterSetName = "Disable")]
    [switch]$Disable,

    [Parameter(Mandatory = $false)]
    [string]$Reason,

    [Parameter(Mandatory = $false)]
    [int]$Hours = 8,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId
)

# Default subscription and tenant IDs (can be edited for easier repeat usage)
$defaultSubscriptionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
$defaultTenantId = "ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb"

# Use provided parameters or fall back to default values
$subscriptionId = if ($SubscriptionId) { $SubscriptionId } else { $defaultSubscriptionId }
$tenantId = if ($TenantId) { $TenantId } else { $defaultTenantId }

# Validate that we have valid subscription and tenant IDs
if ($subscriptionId -eq $defaultSubscriptionId -or $tenantId -eq $defaultTenantId) {
    Write-Host "Warning: Using default placeholder IDs. Please provide valid subscription and tenant IDs either:" -ForegroundColor Yellow
    Write-Host "  1. As parameters: -SubscriptionId 'your-sub-id' -TenantId 'your-tenant-id'" -ForegroundColor Yellow
    Write-Host "  2. By editing the default values in this script" -ForegroundColor Yellow
    Write-Host ""
}

# Azure role assignment ID (this is for the Owner role)
$roleDefinitionId = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"

if ($Enable) {
    # Calculate duration based on input and max hours
    $startDate = Get-Date
    $maxHours = 8
    $durationHours = if ($Hours -gt $maxHours) { $maxHours } else { $Hours }
    $duration = "PT${durationHours}H"

    # Prompt for hours if not supplied as an argument
    if (-not $PSBoundParameters.ContainsKey('Hours')) {
        Write-Host -NoNewline "Enter duration in hours (hit Enter for max of $maxHours): " -ForegroundColor Cyan
        $inputHours = Read-Host
        if ([string]::IsNullOrWhiteSpace($inputHours)) {
            $Hours = $maxHours
        }
        elseif ($inputHours -as [int]) {
            $Hours = [int]$inputHours
        }
        else {
            Write-Host "Invalid input. Defaulting to max hours: $maxHours" -ForegroundColor Yellow
            $Hours = $maxHours
        }

        $durationHours = if ($Hours -gt $maxHours) { $maxHours } else { $Hours }
        $duration = "PT${durationHours}H"
    }

    # Prompt for reason if not supplied as an argument
    if (-not $PSBoundParameters.ContainsKey('Reason')) {
        Write-Host -NoNewline "Enter reason for PIM activation: " -ForegroundColor Cyan
        $Reason = Read-Host
        if ([string]::IsNullOrWhiteSpace($Reason)) {
            Write-Host "Error: A reason is required to activate PIM. Exiting." -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "`nStarting PIM role activation..." -ForegroundColor Cyan
}
else {
    if (-not $PSBoundParameters.ContainsKey('Reason')) {
        Write-Host -NoNewline "Enter reason for PIM deactivation (or hit Enter for default): " -ForegroundColor Cyan
        $inputReason = Read-Host
        if ([string]::IsNullOrWhiteSpace($inputReason)) {
            $Reason = "End of work session"
        }
        else {
            $Reason = $inputReason
        }
    }

    Write-Host "`nStarting PIM role deactivation..." -ForegroundColor Cyan
}

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -NoWelcome
$context = Get-MgContext
Write-Host "✓ Connected as $($context.Account)" -ForegroundColor Green

# Get user info
Write-Host "`nFetching user info..." -ForegroundColor Cyan
$currentUser = (Get-MgUser -UserId $context.Account).Id

if ($Enable) {
    # Get eligible roles
    $myRoles = Get-MgRoleManagementDirectoryRoleEligibilitySchedule -ExpandProperty RoleDefinition -All -Filter "principalId eq '$currentUser'"

    # Verify eligibility for Global Administrator
    $myRole = $myRoles | Where-Object { $_.RoleDefinition.DisplayName -eq "Global Administrator" }
    if (-not $myRole) {
        Write-Host "Global Administrator not found as eligible role." -ForegroundColor Red
        exit
    }

    # Setup parameters for activation
    $params = @{
        Action           = "selfActivate"
        PrincipalId      = $myRole.PrincipalId
        RoleDefinitionId = $myRole.RoleDefinitionId
        DirectoryScopeId = $myRole.DirectoryScopeId
        Justification    = $Reason
        ScheduleInfo     = @{
            StartDateTime = $startDate
            Expiration    = @{
                Type     = "AfterDuration"
                Duration = $duration
            }
        }
    }

    # Activate the Entra role
    Write-Host "Activating Global Administrator role (this will take a minute)..." -ForegroundColor Cyan
    $entraError = $null
    New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $params -ErrorVariable entraError -ErrorAction SilentlyContinue

    if ($entraError) {
        if ($entraError.Exception.Message -match "RoleAssignmentExists") {
            Write-Host "✓ Global Administrator is already active." -ForegroundColor Green
        }
        else {
            Write-Host "Error activating Entra role: $($entraError.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "`n✓ Global Administrator activation request submitted!" -ForegroundColor Green
    }
}
else {
    # Get active Entra role assignments
    Write-Host "Checking for active Global Administrator role..." -ForegroundColor Cyan
    $activeEntraRoles = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -ExpandProperty RoleDefinition -All -Filter "principalId eq '$currentUser'"
    $activeGlobalAdmin = $activeEntraRoles | Where-Object { $_.RoleDefinition.DisplayName -eq "Global Administrator" -and $_.AssignmentType -eq "Activated" }

    if ($activeGlobalAdmin) {
        Write-Host "Found active Global Administrator role. Deactivating..." -ForegroundColor Yellow

        # Setup parameters for deactivation
        $params = @{
            Action           = "selfDeactivate"
            PrincipalId      = $activeGlobalAdmin.PrincipalId
            RoleDefinitionId = $activeGlobalAdmin.RoleDefinitionId
            DirectoryScopeId = $activeGlobalAdmin.DirectoryScopeId
            Justification    = $Reason
        }

        # Deactivate the Entra role
        $entraError = $null
        New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $params -ErrorVariable entraError -ErrorAction SilentlyContinue

        if ($entraError) {
            Write-Host "Error deactivating Entra role: $($entraError.Exception.Message)" -ForegroundColor Red
        }
        else {
            Write-Host "`n✓ Global Administrator deactivation request submitted!" -ForegroundColor Green
        }
    }
    else {
        Write-Host "`n✓ Global Administrator role is not currently active." -ForegroundColor Green
    }
}

# Connect to Azure
Write-Host "`nConnecting to Azure (authenticate in browser if prompted)..." -ForegroundColor Cyan
Connect-AzAccount -TenantId $tenantId
Write-Host "✓ Connected to Azure successfully!" -ForegroundColor Green

if ($Enable) {
    # Activate the Azure RBAC role
    Write-Host "`nActivating Owner role (this will take a minute)..." -ForegroundColor Cyan
    $azureError = $null
    New-AzRoleAssignmentScheduleRequest -Name (New-Guid).Guid `
        -Scope "/subscriptions/${subscriptionId}" `
        -PrincipalId $currentUser `
        -RoleDefinitionId "/subscriptions/${subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/${roleDefinitionId}" `
        -RequestType SelfActivate `
        -Justification $Reason `
        -ScheduleInfoStartDateTime $startDate.ToString("o") `
        -ExpirationDuration $duration `
        -ExpirationType AfterDuration `
        -ErrorVariable azureError `
        -ErrorAction SilentlyContinue

    if ($azureError) {
        if ($azureError.Exception.Message -match "Role assignment already exists") {
            Write-Host "✓ Owner role is already active." -ForegroundColor Green
        }
        else {
            Write-Host "Error activating Azure RBAC role: $($azureError.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "`n✓ Owner activation request submitted!" -ForegroundColor Green
    }

    Write-Host "`nPIM activation complete!`n" -ForegroundColor Cyan
}
else {
    # Get active Azure RBAC role assignments
    Write-Host "`nChecking for active Owner role..." -ForegroundColor Cyan
    $activeAzureRoles = Get-AzRoleAssignmentScheduleInstance -Scope "/subscriptions/${subscriptionId}" -Filter "principalId eq '$currentUser'"
    $activeOwner = $activeAzureRoles | Where-Object {
        $_.RoleDefinitionId -eq "/subscriptions/${subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/${roleDefinitionId}" -and
        $_.AssignmentType -eq "Activated"
    }

    if ($activeOwner) {
        Write-Host "Found active Owner role. Deactivating..." -ForegroundColor Yellow

        # Deactivate the Azure RBAC role
        $azureError = $null
        New-AzRoleAssignmentScheduleRequest -Name (New-Guid).Guid `
            -Scope "/subscriptions/${subscriptionId}" `
            -PrincipalId $currentUser `
            -RoleDefinitionId "/subscriptions/${subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/${roleDefinitionId}" `
            -RequestType SelfDeactivate `
            -Justification $Reason `
            -ErrorVariable azureError `
            -ErrorAction SilentlyContinue

        if ($azureError) {
            Write-Host "Error deactivating Azure RBAC role: $($azureError.Exception.Message)" -ForegroundColor Red
        }
        else {
            Write-Host "`n✓ Owner deactivation request submitted!" -ForegroundColor Green
        }
    }
    else {
        Write-Host "`n✓ Owner role is not currently active." -ForegroundColor Green
    }

    Write-Host "`nPIM deactivation complete!`n" -ForegroundColor Cyan
}
