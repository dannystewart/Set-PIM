# Enable-PIM

Quick and dirty PowerShell script to enable the Global Administrator role in Entra as well as the Owner role for an Azure tenant.

**NOTE:** This is _**very bad practice**_, and is shared for example purposes only. You should customize it for your use case. I may refine it for greater flexibility, but since Microsoft's documentation is poor for what should be a straightforward task, I wanted to share this basic version in case it helps somebody.

You may also prefer the version from [Mark Hunter Orr](https://medium.com/@markhunterorr/activate-your-microsoft-entra-pim-roles-with-powershell-62a0d611659c) available [here](https://github.com/markorr321/PIM-PAM). It's more robust, but it doesn't handle Azure RBAC roles.

This script is shared under the MIT license, and is provided with no support or warranty whatsoever. Use at your own risk.

## Requirements

- PowerShell 7+ (the script will work cross-platform)
- Microsoft.Graph PowerShell module (`Install-Module Microsoft.Graph`)
- Az PowerShell module (`Install-Module Az`)

## Usage

Be sure to edit the script with your subscription and tenant IDs:

```powershell
# Your subscription and tenant IDs
$subscriptionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
$tenantId = "ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb"
```

The account will be automatically determined based on what you've used authenticate to Graph.

You can run the script with only a justification:

```powershell
./Enable-PIM.ps1 "Managing user account permissions"
```

This will default to a duration of 8 hours. You can also specify the time:

```powershell
./Enable-PIM.ps1 -Reason "Managing user account permissions" -Hours 2
```
