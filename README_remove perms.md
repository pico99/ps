Replace 'C:\admin\Test' with your folder path and rename logpath to the specific folder you are editing

Replace 'DOMAIN\GroupName' with your domain group (e.g., 'unitedwater\whatevergroup')

Run PowerShell as Administrator

Copy and paste the script

You can add multiple groups by modifying the -notmatch condition:
For multiple groups:
$KeepGroups = @("DOMAIN\Group1", "DOMAIN\Group2")
Then in the Where-Object line:
$Acl.Access | Where-Object {$_.IdentityReference -notmatch 'SYSTEM|Administrators|NETWORK SERVICE' -and $_.IdentityReference -notin $KeepGroups}
