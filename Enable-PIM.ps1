param(
    [Parameter(Mandatory = $true)]
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

Write-Host "Starting PIM role activation...`n" -ForegroundColor Cyan

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -NoWelcome
$context = Get-MgContext
Write-Host "✓ Connected as $($context.Account)" -ForegroundColor Green

Write-Host "`nFetching user information..." -ForegroundColor Cyan
$currentUser = (Get-MgUser -UserId $context.Account).Id

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
