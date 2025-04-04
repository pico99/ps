<# sample command line
.\sanitizeLinkfixerScans.ps1 -SourcePath "G:\Shared drives\SATAWAD 2023 2024\File Migration\Regulated LinkFixer Scans\NJHYFS Depts Hackensack NJ\" -fileFilter "Scan Detail*" -OFilePrefix "sanitized-"

#assign params from command line
#>
param(
  [Alias("UNCPath")]
  [Parameter(Mandatory)]
    [string]$SourcePath, #trailing backslash is required
  [Parameter(Mandatory)]
    [string]$fileFilter,
  [Alias("OFilePrefix")]
  [Parameter(Mandatory)]
    [string]$OutputFilePrefix
)

$sanitizeFiles = (Get-ChildItem -Path $SourcePath -Filter $fileFilter).Name #.Name does not include the SourcePath
$mycountdown = $sanitizeFiles.count

if ($mycountdown -eq 0) {
  Write-Host "exiting, no files matching '$fileFilter' in '$SourcePath'" -ForegroundColor Green -backgroundColor DarkGray
  exit
  }
else {
  $begTime = Get-Date
  #$begTime
  $myCounter=0
  foreach ($csvFile in $sanitizeFiles) {
    $myCounter++
    $fullFileName = $SourcePath + $csvFile
      $textToReplace = [System.IO.File]::ReadAllText("$fullFileName") #read the file once
  <#
  #The .Replace() method, when used directly on a string object, is case-sensitive.

  todo: delete the first 4 lines
    regex: starts with "Computer Name:..." ends with "delete these first four rows."
  #>
      $textToReplace = $textToReplace.Replace('LinkTek Support via phone (727-442-1822) or email (Support@LinkTek.com)', 'support')
      $textToReplace = $textToReplace.Replace('LinkTek Support via email at Support@LinkTek.com or call 727-442-1822', 'support')
      $textToReplace = $textToReplace.Replace('Support via email at Support@LinkTek.com or call 727-442-1822', 'support')
      $textToReplace = $textToReplace.Replace('Support@LinkTek.com or call 727-442-1822', 'support')
      $textToReplace = $textToReplace.Replace('Support@LinkTek.com or calling 727-442-1822', 'support')
      $textToReplace = $textToReplace.Replace('Support@LinkTek.com', 'support')
      $textToReplace = $textToReplace.Replace('LinkTek Support', 'support')
      $textToReplace = $textToReplace.Replace('LinkTek support', 'support')
      $textToReplace = $textToReplace.Replace('help at 727-442-1822', 'support')
      $textToReplace = $textToReplace.Replace('LinkFixer Advanced', 'analysis')
      $oFile = $SourcePath + $OutputFilePrefix + $csvFile
    [System.IO.File]::WriteAllText($oFile, $textToReplace)
    Write-Host $csvFile "($myCounter of $myCountdown)"
  }
  $endTime = Get-Date
  #$endTime
  New-TimeSpan -Start $begTime -End $endTime | Select-Object -Property TotalSeconds

  Write-Host "end of script: $myCounter of $myCountdown sanitized"  -ForegroundColor Green  -backgroundColor DarkGray
}