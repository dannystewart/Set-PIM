<#
.SYNOPSIS
    Activates Entra Global Administrator and Azure Owner PIM roles.

.DESCRIPTION
    This script activates Privileged Identity Management (PIM) roles for both
    Microsoft Entra ID (Global Administrator) and Azure RBAC (Owner) using
    the Microsoft Graph and Azure PowerShell modules.

    NOTE: Elevating to Global Administrator and Owner roles should be done
    sparingly and only when necessary. This script is provided as an example
    and should be customized for your specific environment.

.PARAMETER Reason
    A justification for why the privileged roles are being activated.
    This is required and will be prompted for if not supplied.

.PARAMETER Hours
    The duration in hours for which the roles should be activated.
    Defaults to 8 hours. Will be capped at configurable max allowed value.

.PARAMETER SubscriptionId
    The Azure subscription ID. If not provided, will use the default value
    set in the script variables.

.PARAMETER TenantId
    The Azure tenant ID. If not provided, will use the default value
    set in the script variables.

.EXAMPLE
    ./Enable-PIM.ps1
    Activates both roles with the default duration, prompting for justification.

.EXAMPLE
    ./Enable-PIM.ps1 "Investigating security alert"
    Activates both roles with the provided justification for the default duration.

.EXAMPLE
    ./Enable-PIM.ps1 -Reason "Emergency access required" -Hours 4
    Activates both roles for 4 hours with the specified justification.

.EXAMPLE
    ./Enable-PIM.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -TenantId "87654321-4321-4321-4321-210987654321"
    Activates both roles using the specified subscription and tenant IDs.

.NOTES
    File Name      : Enable-PIM.ps1
    Author         : Danny Stewart
    Version        : 1.3.0
    Prerequisite   : PowerShell 7+, Microsoft.Graph and Az PowerShell modules
    License        : MIT License

    This script requires you to be eligible for both the Global Administrator
    role in Entra ID and the Owner role in Azure. It will use your current
    identity for authentication.

    You can either edit the script to update the subscription and tenant IDs
    or provide them as command-line arguments when running the script.

.LINK
    https://github.com/dannystewart/Enable-PIM
#>

param(
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

# Begin activation process
Write-Host "Starting PIM role activation..." -ForegroundColor Cyan

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -NoWelcome
$context = Get-MgContext
Write-Host "✓ Connected as $($context.Account)" -ForegroundColor Green

# Get user and role info
Write-Host "`nFetching user and role info..." -ForegroundColor Cyan
$currentUser = (Get-MgUser -UserId $context.Account).Id
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

# Connect to Azure
Write-Host "`nConnecting to Azure (authenticate in browser if prompted)..." -ForegroundColor Cyan
Connect-AzAccount -TenantId $tenantId
Write-Host "✓ Connected to Azure successfully!" -ForegroundColor Green

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
