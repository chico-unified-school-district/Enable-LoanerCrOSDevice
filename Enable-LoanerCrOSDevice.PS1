#Requires -Version 5.0
<# 
.SYNOPSIS
 Queries Aeries for Chromebooks marked as loaners and enables them throoughout the school day
.DESCRIPTION
 Run with Test and/or Log switches as well as common parameters
.EXAMPLE
 Enable-LoanerCrOSDevice.ps1 -SISCOnnection server\database -SISCredential $sisCredObject
.EXAMPLE
 Enable-LoanerCrOSDevice.ps1 -SISCOnnection server\database -SISCredential $sisCredObject -WhatIf -Verbose -Debug
.INPUTS
.OUTPUTS
 Log Files, email messages
.NOTES
 Thanks Wendy Kwo for the nice SQL Statements!
#>

[cmdletbinding()]
param ( 
 # SQL server name
 [Parameter(Mandatory = $True)]
 [Alias('SISServer')]
 [string]$SQLServer,
 # SQL database name
 [Parameter(Mandatory = $True)]
 [Alias('SISDatabase', 'SISDB')]
 [string]$SQLDatabase,
 # Aeries SQL user account with SELECT permission to STU table 
 [Parameter(Mandatory = $True)]
 [Alias('SISCred')]
 [System.Management.Automation.PSCredential]$SQLCredential,
 [switch]$OneLoop,
 [switch]$WhatIf
)

# Variables
$gamExe = '.\lib\gam-64\gam.exe'
$crosFields = "annotatedAssetID,deviceId,status,serialNumber"

# Imported Functions
. .\lib\Add-Log.ps1 # Format Log entries
. .\lib\Invoke-SqlCommand.ps1 # Useful function for querying SQL and returning results


$reenableQuery = Get-Content -Path '.\sql\reenable.sql' -Raw
$updateCmdSql = Get-Content -Path '.\sql\Update-DRA-DD.sql' -Raw
$stopTime = '6:00pm'
$waitTime = 600 # Seconds
Add-Log script "Running Until $stopTime"
Add-Log script "Runs every $($waitTime/60) minutes"
Add-Log info 'Checking for devices to Re-Enable'
do {
 $reenableLoaners = Invoke-SqlCommand -Server $SQLServer -Database $SQLDatabase -Cred $SQLCredential -Query $reenableQuery
 # $reenableLoaners = @{SerialNumber="5CD71312K0"} # For Testing purposes

 foreach ($device in $reenableLoaners) {
  $sn = $device.serialNumber
  Write-Debug "Process $sn"

  ($crosDev = & $gamExe print cros query "id: $sn" fields $crosFields | ConvertFrom-CSV) *>$null # *>$null suppresses noisy gam.exe output 
  $id = $crosDev.deviceId

  Write-Verbose ($crosDev | Out-String)
  if ($crosDev.status -eq "DISABLED") {
   Add-Log enable $sn
   if (!$WhatIf) { & $gamExe update cros $id action reenable *>$null } # *>$null hides gam.exe output
  }
  else { Write-Verbose "$sn, Skipping. Already 'ACTIVE'" }
  # Update database to indicate device has been checked.
  $updateCmd = $updateCmdSql -f $sn
  Invoke-SqlCommand -Server $SQLServer -Database $SQLDatabase -Cred $SQLCredential -SQLCommand $updateCmd -WhatIf:$WhatIf
 }
 if ($WhatIf -or $OneLoop) { BREAK }
 else {
  #  Wait x seconds and run again until $stopTime
  Start-Sleep -Seconds $waitTime
 }
} until ( (Get-Date) -ge (Get-Date $stopTime) )