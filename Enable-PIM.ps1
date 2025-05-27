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

.EXAMPLE
    ./Enable-PIM.ps1
    Activates both roles with the default duration, prompting for justification.

.EXAMPLE
    ./Enable-PIM.ps1 "Investigating security alert"
    Activates both roles with the provided justification for the default duration.

.EXAMPLE
    ./Enable-PIM.ps1 -Reason "Emergency access required" -Hours 4
    Activates both roles for 4 hours with the specified justification.

.NOTES
    File Name      : Enable-PIM.ps1
    Author         : Danny Stewart
    Version        : 1.1.0
    Prerequisite   : PowerShell 7+, Microsoft.Graph and Az PowerShell modules
    License        : MIT License

    This script requires you to be eligible for both the Global Administrator
    role in Entra ID and the Owner role in Azure. It will use your current
    identity for authentication.

    You must edit the script to update the subscription and tenant IDs
    before using it in your environment.

.LINK
    https://github.com/dannystewart/Enable-PIM
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Reason,

    [Parameter(Mandatory = $false)]
    [int]$Hours = 8
)

# Your subscription and tenant IDs
$subscriptionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
$tenantId = "ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb"

# Azure role assignment ID (this is for the Owner role)
$roleDefinitionId = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"

# Calculate duration based on input and max hours
$startDate = Get-Date
$maxHours = 8
$durationHours = if ($Hours -gt $maxHours) { $maxHours } else { $Hours }
$duration = "PT${durationHours}H"

# Prompt for reason if not supplied
if ([string]::IsNullOrWhiteSpace($Reason)) {
    Write-Host -NoNewline "Enter reason for PIM activation: " -ForegroundColor Cyan
    $Reason = Read-Host
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
