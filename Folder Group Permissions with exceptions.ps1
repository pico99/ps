<#
.SYNOPSIS
    Lists groups and users with permissions on folders, excluding specified default identities.
.DESCRIPTION
    This script recursively scans a specified folder path, identifies all security principals (users or groups)
    that have permissions, and lists those whose names are not in a predefined exclusion list.
    The exclusion list targets common administrative, system, and broad access accounts.
.PARAMETER Path
    The root folder path to scan for permissions. This parameter is mandatory.
.EXAMPLE
    .\Get-FolderPermissionsExcludingDefaults.ps1 -Path "C:\Shares\DepartmentX"

    This command will scan the "C:\Shares\DepartmentX" folder and its subfolders,
    displaying security principals (groups or users) with their permissions,
    excluding the predefined system/admin/common groups.
.EXAMPLE
    Get-ChildItem -Path "C:\Projects" -Directory | .\Get-FolderPermissionsExcludingDefaults.ps1

    This command gets all subdirectories of "C:\Projects" and pipes them to the script
    to analyze permissions for each.
.OUTPUTS
    PSCustomObject
    Outputs objects with the following properties:
    - FolderPath: The full path to the folder.
    - Identity: The security principal (e.g., "DOMAIN\GroupName" or "BUILTIN\Users").
    - Permissions: The file system rights granted to the security principal (e.g., "ReadAndExecute, Synchronize").
    - AccessControlType: Specifies whether the rights are "Allow" or "Deny".
    - IsInherited: Indicates if the permission is inherited from a parent folder (True/False).
.NOTES
    Author: Gemini
    Date: 2025-05-09
    The script filters identities based on the name part of the IdentityReference (e.g., "GroupName" from "DOMAIN\GroupName").
    The exclusion list matching is case-insensitive.
    If you need to exclude "Backup Operators" (the built-in group), ensure "Backup Operators" is in the $ExcludedIdentities list.
    The script requires appropriate permissions to read ACLs of the target folders.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [string]$Path
)

begin {
    # List of identity names to exclude (case-insensitive matching will be used)
    # These are the "name parts" after any domain or "BUILTIN\" prefix.
    $Global:ExcludedIdentities = @(
        "Domain Admins",
        "Backup_OPs",      # This is per user request. The built-in group is "Backup Operators".
                           # Add "Backup Operators" to this list if you want to exclude the built-in group.
        "Administrators",  # Matches BUILTIN\Administrators
        "SYSTEM",          # Matches NT AUTHORITY\SYSTEM
        "Domain Users",
        "CREATOR OWNER",   # Matches special identity
        "Authenticated Users", # Matches well-known group
        "Users"            # Matches BUILTIN\Users
    )

    Write-Verbose "Script initialized. Excluded identities (case-insensitive): $($Global:ExcludedIdentities -join ', ')"
    $Global:Results = [System.Collections.Generic.List[PSCustomObject]]::new()
}

process {
    # Validate the path
    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Error "The path '$Path' does not exist or is not a folder. Please provide a valid folder path. Skipping this item."
        return # Changed from 'continue' to 'return' as process block handles one item from pipeline
    }

    Write-Verbose "Starting permission scan for base folder: $Path"

    # Create a list of folders to process: the root path itself and all its subdirectories
    $FoldersToProcess = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    try {
        $RootFolderItem = Get-Item -Path $Path -ErrorAction Stop
        $FoldersToProcess.Add($RootFolderItem)

        $SubFolders = Get-ChildItem -Path $Path -Directory -Recurse -ErrorAction SilentlyContinue # Continue if some subfolders are inaccessible
        if ($null -ne $SubFolders) {
            $FoldersToProcess.AddRange($SubFolders)
        }
    }
    catch {
        Write-Error "Error accessing folder structure for '$Path': $($_.Exception.Message)"
        return
    }

    foreach ($Folder in $FoldersToProcess) {
        Write-Verbose "Processing folder: $($Folder.FullName)"
        try {
            # Get-Acl can be slow; ensure errors don't stop the whole script for one folder.
            $Acl = Get-Acl -Path $Folder.FullName -ErrorAction SilentlyContinue
            if (-not $Acl) {
                Write-Warning "Could not retrieve ACL for $($Folder.FullName). Skipping."
                continue
            }

            foreach ($Ace in $Acl.Access) {
                $IdentityName = $Ace.IdentityReference.Value
                # Extract the name part, e.g., "Administrators" from "BUILTIN\Administrators" or "SalesUsers" from "CONTOSO\SalesUsers"
                $IdentityNamePart = $IdentityName.Split('\')[-1]

                # Check if the identity name part is in the exclusion list (PowerShell -eq is case-insensitive for strings)
                $IsExcluded = $false
                foreach ($ExcludedItem in $Global:ExcludedIdentities) {
                    if ($IdentityNamePart -eq $ExcludedItem) {
                        $IsExcluded = $true
                        Write-Verbose "Excluding '$IdentityName' because '$IdentityNamePart' is in the exclusion list."
                        break
                    }
                }

                if (-not $IsExcluded) {
                    $OutputObject = [PSCustomObject]@{
                        FolderPath        = $Folder.FullName
                        Identity          = $IdentityName
                        Permissions       = $Ace.FileSystemRights.ToString() # Convert FileSystemRights enum to string
                        AccessControlType = $Ace.AccessControlType.ToString()
                        IsInherited       = $Ace.IsInherited
                    }
                    $Global:Results.Add($OutputObject)
                }
            }
        }
        catch {
            # Catch errors specific to processing a single folder's ACL
            Write-Warning "Error processing ACL for folder '$($Folder.FullName)': $($_.Exception.Message)"
        }
    }
}

end {
    if ($Global:Results.Count -eq 0) {
        Write-Host "No non-excluded identities with permissions found in the processed path(s)."
    } else {
        Write-Output $Global:Results
    }
    Write-Verbose "Script finished. Total matching ACEs found: $($Global:Results.Count)"
}
