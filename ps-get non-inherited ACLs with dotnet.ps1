<#
.SYNOPSIS
    Retrieves the non-inherited Access Control List (ACL) for a specified folder using .NET methods.

.DESCRIPTION
    This script provides a detailed report of permissions set directly on a given folder.
    It uses the System.IO.DirectoryInfo and System.Security.AccessControl classes
    from the .NET Framework to get the DirectorySecurity object and enumerate
    each FileSystemAccessRule that is not inherited from a parent folder.

.PARAMETER FolderPath
    The full path to the folder you want to inspect.

.EXAMPLE
    PS C:\> .\Get-FolderPermissions.ps1 -FolderPath "C:\Users\JohnDoe"
    This will display the explicit permissions for the C:\Users\JohnDoe folder.

.NOTES
    You must run this script with sufficient privileges to read the security
    information of the target folder. Running as an Administrator is recommended.
#>
param (
    [Parameter(Mandatory=$true, HelpMessage="Enter the full path to the folder.")]
    [string]$FolderPath
)

# --- 1. Validate the Folder Path ---
Write-Host "Checking path: $FolderPath" -ForegroundColor Cyan
if (-not (Test-Path -Path $FolderPath -PathType Container)) {
    Write-Error "Error: The specified path '$FolderPath' does not exist or is not a directory."
    # Exit the script gracefully if the path is invalid
    return
}

try {
    # --- 2. Get the DirectoryInfo .NET Object ---
    # Create a .NET object representing the directory.
    $directoryInfo = New-Object System.IO.DirectoryInfo($FolderPath)
    Write-Host "Successfully created DirectoryInfo object for '$($directoryInfo.FullName)'." -ForegroundColor Green

    # --- 3. Get the Access Control (DirectorySecurity) .NET Object ---
    # GetAccessControl() returns the security descriptor for the directory.
    # This can fail if the user running the script lacks permissions.
    Write-Host "Attempting to retrieve Access Control List (ACL)..."
    $directorySecurity = $directoryInfo.GetAccessControl()
    Write-Host "ACL retrieved successfully.`n" -ForegroundColor Green

    # --- 4. Get the Collection of NON-INHERITED Access Rules ---
    # The GetAccessRules() method retrieves the access rules contained in the security object.
    # The parameters specify:
    #   $true  - Include rules explicitly set on the object.
    #   $false - DO NOT include rules inherited from parent objects.
    #   [type] - The type to use for translating the Security Identifier (SID),
    #            e.g., BUILTIN\Administrators instead of S-1-5-32-544.
    $accessRules = $directorySecurity.GetAccessRules($true, $false, [System.Security.Principal.NTAccount])

    # --- 5. Display the Permissions Report ---
    Write-Host "--- Non-Inherited Permissions Report for '$($directoryInfo.FullName)' ---" -ForegroundColor Yellow
    Write-Host ("Found {0} explicit (non-inherited) access rules.`n" -f $accessRules.Count)

    if ($accessRules.Count -eq 0) {
        Write-Host "No explicit permissions found. All permissions are inherited from parent folders." -ForegroundColor Magenta
    }

    # Loop through each access rule and display its properties
    foreach ($rule in $accessRules) {
        Write-Host "Identity           : $($rule.IdentityReference.Value)"
        Write-Host "Permissions        : $($rule.FileSystemRights)"
        Write-Host "Type               : $($rule.AccessControlType)" # Allow or Deny
        # IsInherited is now always false, so we don't need to display it.
        Write-Host "Inheritance Flags  : $($rule.InheritanceFlags)" # How the rule is inherited by child objects/containers
        Write-Host "Propagation Flags  : $($rule.PropagationFlags)" # How the inherited rule is propagated
        Write-Host "--------------------------------------------------"
    }

}
catch {
    # This block will execute if any command in the 'try' block fails,
    # most commonly GetAccessControl() due to insufficient permissions.
    Write-Error "An error occurred: $($_.Exception.Message)"
    Write-Warning "Please ensure you are running PowerShell with sufficient privileges (e.g., 'Run as Administrator')."
}
