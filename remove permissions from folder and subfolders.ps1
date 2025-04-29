# Specify the folder path
$FolderPath = "C:\admin\test"

# Specify log file path
$LogFile = "C:\admin\permissions_cleanup_log.txt"

# Specify the domain group to keep (replace DOMAIN\GroupName with your group)
$KeepGroup = "ADdomain\Backup_Ops"

# Start logging
$TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"Log started at $TimeStamp" | Out-File -FilePath $LogFile
"Target folder: $FolderPath" | Out-File -FilePath $LogFile -Append
"Preserving permissions for: $KeepGroup" | Out-File -FilePath $LogFile -Append

# Get folder and all subfolders
$Folders = Get-ChildItem -Path $FolderPath -Recurse -Directory

# Include the root folder
$Folders = @($FolderPath) + $Folders.FullName

foreach ($Folder in $Folders) {
    try {
        # Get ACL
        $Acl = Get-Acl $Folder

    # Log original permissions
        "\nProcessing folder: $Folder" | Out-File -FilePath $LogFile -Append
        "Original permissions:" | Out-File -FilePath $LogFile -Append
        $Acl.Access | Format-Table IdentityReference, FileSystemRights -AutoSize | Out-File -FilePath $LogFile -Append
   
    # Remove all access rules except for SYSTEM, Administrators, and specified group
        $Acl.Access | Where-Object {$_.IdentityReference -notmatch 'SYSTEM|Administrators|NETWORK SERVICE' -and $_.IdentityReference -ne $KeepGroup} | ForEach-Object {
            $Acl.RemoveAccessRule($_)
            "Removed permission for: $($_.IdentityReference)" | Out-File -FilePath $LogFile -Append
        }
   
    # Apply the changes
    Set-Acl -Path $Folder -AclObject $Acl

     # Log new permissions
        "New permissions:" | Out-File -FilePath $LogFile -Append
        $NewAcl = Get-Acl $Folder
        $NewAcl.Access | Format-Table IdentityReference, FileSystemRights -AutoSize | Out-File -FilePath $LogFile -Append
       
        "Successfully processed: $Folder" | Out-File -FilePath $LogFile -Append
    }
    catch {
        "ERROR processing $Folder : $($_.Exception.Message)" | Out-File -FilePath $LogFile -Append
    }
}

# Log completion
$EndTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"\nOperation completed at $EndTime" | Out-File -FilePath $LogFile -Append
