# Set-PIM

PowerShell script to enable or disable the Global Administrator and Owner roles in Entra and Azure.

**NOTE:** This is _**bad practice**_ and is shared for example purposes only because Microsoft's documentation is poor for what should be a straightforward task. You should customize it for your specific use case.

You may also prefer [this version](https://github.com/markorr321/PIM-PAM) from [Mark Hunter Orr](https://medium.com/@markhunterorr/activate-your-microsoft-entra-pim-roles-with-powershell-62a0d611659c). It's more robust, but it doesn't handle Azure RBAC roles.

This script is shared under the MIT license with no support or warranty whatsoever. Use at your own risk.

## Requirements

- PowerShell 7+ (the script will work cross-platform)
- Microsoft.Graph PowerShell module (`Install-Module Microsoft.Graph`)
- Az PowerShell module (`Install-Module Az`)

## Usage

A subscription ID and tenant ID are obviously required. You can either provide them as command-line arguments at runtime, or add them to the script for convenience:

```powershell
$subscriptionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
$tenantId = "ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb"
```

The account will be automatically determined based on what you've used authenticate to Graph.

You can run the script with just the mode (`-Enable` or `-Disable`) and no other arguments. For enabling, you'll be prompted for both justification and duration:

```powershell
./Set-PIM.ps1 -Enable
```

Or you can provide a justification and duration directly:

```powershell
./Set-PIM.ps1 -Enable -Reason "Managing user account permissions" -Hours 4
```

You'll be prompted for anything required that you haven't provided.
