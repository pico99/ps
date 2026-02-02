#assign params from command line
param(
  [Alias("UNCPath")]
  [Parameter(Mandatory)]
    [string]$SourcePath,
  [Alias("OFilePath")]
  [Parameter(Mandatory)]
    [string]$OutputFilePath,
  [Parameter()]
    [switch] $processAllACLs
)

begin {
  if ($processAllACLs.IsPresent) {
    write-host "initializing FoldersArray (all ACLs)..." -ForegroundColor green -backgroundColor DarkGray  
  } else {
    write-host "initializing FoldersArray (excluding common ACLs)..." -ForegroundColor green -backgroundColor DarkGray  
    }
  
  Import-Module Microsoft.PowerShell.Security #PowerShell 7 moved ACLs... 
  $startTime = Get-Date

  #create arrayLists to hold output from 3 tasks: 1) count, 2) get ACLs, 3) expand group membership
  #$arrayListFolderCountResults = [System.Collections.ArrayList]@()
  #$arrayListACLs = [System.Collections.ArrayList]@()
  #$arrayListGroupsToExpand = [System.Collections.ArrayList]@()

  #.net List (for performance and mutability) of identity/group names to exclude (case-insensitive matching will be used)
  #These are the "name parts" after any domain or "BUILTIN\" prefix.
  $listExcludedGroups = [System.Collections.Generic.List[string]]@()
    $listExcludedGroups.Add("Administrators")      # Matches BUILTIN\Administrators
    $listExcludedGroups.Add("Authenticated Users") # Matches well-known group
    $listExcludedGroups.Add("Backup_OPs")
    $listExcludedGroups.Add("Domain Admins")       # Matches well-known group
    $listExcludedGroups.Add("Domain Users")        # Matches well-known group
    $listExcludedGroups.Add("NETWORK SERVICE")     # Matches well-known group
    $listExcludedGroups.Add("SYSTEM")              # Matches NT AUTHORITY\SYSTEM
    $listExcludedGroups.Add("CREATOR OWNER")       # Matches special identity
    $listExcludedGroups.Add("Users")               # Matches BUILTIN\Users
    $listExcludedGroups.Add("Everyone")            # Matches BUILTIN\Users
  
  #get [only] folders (-Directory) under the source path for file counts and sizes
  #**  ACLs uses -Recurse: need to account for this
  #**   trying to avoid the perf hit of scanning the folders twice

  #long paths
  #$longpath = '\\?\'
  #$SourcePath = "B:\Customer Support Return Mail HM LEAD Daily Count\Health Monitor Daily Count\Customer Support Team Ebill\Customer Support Team Direct Debit\Customer Support Team CC&B Health Monitors FO\CSODISSUES\CSODISSUEOCT\6754pa_files\Options_split_files"
  #$longpath + $SourcePath
  #"b:\Customer Support Return Mail HM LEAD Daily Count\Health Monitor Daily Count\Customer Support Team Ebill\Customer Support Team Direct Debit\Daily Direct Debit Log"
  #$SourcePath #**debug

  $FoldersArray = @(Get-ChildItem $SourcePath -Directory -Recurse)# -Recurse) #**debug recurse is later
  
  #new [pcustomobject] array for ACL results which will be the input to expand group members
  $ACLOutInfo = @()

  #Write-Verbose "Script initialized. Excluded identities (case-insensitive): $($Global:ExcludedIdentities -join ', ')" -Verbose
} #end "begin block"

process {
  $loopstart = Get-Date -DisplayHint Time
  $elapsedtimeFoldersArray = New-TimeSpan -Start $startTime -End $loopstart | Select-Object -Property TotalSeconds, TotalMinutes
  
  #loop through the folders for ACLs + file counts; write separate CSVs for each
  $Foldercount = 0
  ForEach ($currentFolder in $FoldersArray) {
    $Foldercount++
    #display the current path being evaluated (top level only for file counts)
    "$Foldercount of $($FoldersArray.count) $($currentFolder.FullName)"
      #write-host "$Foldercount of $($FoldersArray.count) $($currentFolder.FullName)" -ForegroundColor Yellow -backgroundColor DarkGray

    #extract the ACLs for each folder in this loop

    #create a FolderInfo object (.net for speed)
      #$objCurrentFolderInfo = New-Object System.IO.DirectoryInfo($currentFolder.FullName) #must use "FullName" for the complete UNC path
      #$ACLs = $objCurrentFolderInfo.GetAccessControl()
      $directoryInfo = [System.IO.DirectoryInfo]$currentFolder
      #$directoryInfo = New-Object System.IO.DirectoryInfo($FolderPath)

    #get the Access Control (DirectorySecurity) .NET Object
    # GetAccessControl() returns the security descriptor for the directory.
    # This can fail if the user running the script lacks permissions.
    $directorySecurity = $directoryInfo.GetAccessControl()
    $ACLs = $directorySecurity.GetAccessRules($true, $false, [System.Security.Principal.NTAccount])
    <# The parameters specify:
    #   $true  - Include rules explicitly set on the object.
    # ** $false - DO NOT include rules inherited from parent objects. **
    #   [type] - The type to use for translating the Security Identifier (SID),
    #            e.g., BUILTIN\Administrators instead of S-1-5-32-544.
    #>
    #$ACLs = (get-acl $currentFolder.fullname).Access

    #exclude ACLs in the ExcludedGroups array (see "begin {}" section above)
    #ForEach ($accessRule in $ACLs.Access) {
    ForEach ($accessRule in $ACLs) {
      #$ACLs.Access | Format-Table
      $thisGroupName = $accessRule.IdentityReference.Value
        #Write-host "thisGroupName = $thisGroupName" -ForegroundColor Green -backgroundColor DarkGray #**debug

      #only ACLs that are not inherited
      #if (-not $accessRule.IsInherited) { #-eq $false
        #$accessRule.IsInherited #**debug
        #Extract the GroupName, e.g., "Administrators" from "BUILTIN\Administrators" or "SalesUsers" from "CONTOSO\SalesUsers"
        $thisShortGroupName = $thisGroupName.Split('\')[-1]
        
        #save this group for group member expansion
        #Write-host "$thisGroupName not inherited" -ForegroundColor Yellow -backgroundColor DarkBlue #**debug
        
        if ($processAllACLs) {
          $ACLOutInfo += [pscustomobject]@{
            FolderPath = $currentFolder.FullName
            IdentityReference = $thisGroupName
            FileSystemRights = $accessRule.FileSystemRights
            AccessControlType = $accessRule.AccessControlType
            IsInherited = $accessRule.IsInherited
            InheritanceFlags = $accessRule.InheritanceFlags
            PropagationFlags = $accessRule.PropagationFlags# Check if the ShortGroupName is in the exclusion list (PowerShell -eq is case-insensitive for strings)
          }
        } else {
            $IsExcluded = $false
            ForEach ($ExcludedItem in $listExcludedGroups) {
              #test for exclusion
              if ($thisShortGroupName -eq $ExcludedItem) {
                $IsExcluded = $true
                #Write-host "Excluding '$thisGroupName' because '$ExcludedItem' is in the exclusion list." -ForegroundColor Yellow -backgroundColor DarkBlue
                break #match
              } #end excluded groups loop
            }
            if (-not $IsExcluded) {
              #abbreviated output (fewer columns)
                $ACLOutInfo += [pscustomobject]@{
                FolderPath = $currentFolder.FullName
                IdentityReference = $thisGroupName
                FileSystemRights = $accessRule.FileSystemRights
              }
            } #endif Excluded
          } #endif processAllACLs
      <#} else { 
          #$accessRule.IsInherited #**debug
          #Write-Host "     inherited: skipping rule for $thisGroupName" -ForegroundColor Yellow -BackgroundColor DarkRed
      #  } #endif IsInherited
      #>
      #Write-host "looping for next access rule in $($currentFolder.FullName)" -ForegroundColor Green -backgroundColor DarkGray
    } #end access rules loop
  } #end currentFolder loop
  Write-host "`nelapsed time to retrieve the folders: $elapsedtimeFoldersArray" -ForegroundColor Green -backgroundColor DarkGray
} #end "process block"

end {

  #create OutFile (ACLs)
  $OutFile = $OutputFilePath + "-acls-" + $((Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')) + ".csv"
  #Save results to csv file
#  $ACLOutInfo | Export-Csv -Path "G:\My Drive\tmp\myarrayList.csv" -NoTypeInformation
  $ACLOutInfo | Export-Csv $OutFile -NoTypeInformation
  Write-host "saving $OutFile..." -ForegroundColor Green -backgroundColor DarkBlue

  $endTime = Get-Date
  New-TimeSpan -Start $startTime -End $endTime | Select-Object -Property TotalSeconds, TotalMinutes
  
  Write-Host "end of script" -ForegroundColor Green -backgroundColor DarkGray

}
