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
 [string]$StopTime = "6:00 PM",
 [Alias('wi')]
 [switch]$WhatIf
)

function Get-Data ($params) {
 begin { $sql = Get-Content -Path '.\sql\reenable.sql' -Raw }
 process {
  $data = Invoke-SqlCmd @params -Query $sql
  Write-Verbose ('{0},Count {1}' -f $MyInvocation.MyCommand.Name, $data.count)
  $data
 }
}

function Enable-GDevice {
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.barCode, $_.sn
  if ($_.status -eq "ACTIVE") { return (Write-Verbose ('{0},{1},{2},Device already active' -f $msg)), $_ }
  Write-Host ('{0},{1},{2}' -f $msg) -F Blue
  Write-Verbose "& $gam update cros $($_.id) action reenable"
  if (!$WhatIf) { (& $gam update cros $_.id action reenable) *>$null }
  $_
 }
}

function Get-CrosDev {
 begin { $crosFields = "annotatedAssetID,deviceId,status,serialNumber" }
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.barCode, $_.sn
  Write-Verbose ('{0},{1},{2}' -f $msg)
  Write-Verbose "& $gam print cros query `"asset_id: $($_.barCode)`" fields $crosFields"
  ($dev = & $gam print cros query "asset_id: $($_.barCode)" fields $crosFields | ConvertFrom-CSV) *>$null
  if (!$dev) { return (Write-Verbose ('{0},{1},{2}, CrOS device not found' -f $msg)) }
  $obj = [PSCustomObject]@{
   sn      = $_.sn
   barCode = $_.barCode
   dts     = $_.dts
   flag    = $_.reEnabledFlag
   id      = $dev.deviceId
   status  = $dev.status
  }
  $obj
  Write-Verbose ($obj | Out-String)
 }
}

function Update-SqlDate {
 begin { $baseSql = Get-Content -Path '.\sql\Update-DRA-DD.sql' -Raw }
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.barCode, $_.sn
  $sql = $baseSql -f $_.sn
  Write-Host ('{0},{1},{2}' -f $msg) -F Blue
  Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $sql)
  if (!$WhatIf) { Invoke-SqlCmd @params -Query $sql }
 }
}

$gam = '.\bin\gam.exe'

# Imported Functions
. .\lib\Import-SomeModule.ps1
. .\lib\Show-TestRun.ps1

Show-TestRun

'SqlServer' | Import-SomeModule

$sqlParams = @{
 Server                 = $SQLServer
 Database               = $SQLDatabase
 Credential             = $SQLCredential
 TrustServerCertificate = $true
}
'==== Runs every 5 minutes ==== '
do {
 Get-Data $sqlParams | Get-CrosDev | Enable-GDevice | Update-SqlDate
 if (!$WhatIf) { Start-Sleep -Seconds (60 * 5) }
} until ( $WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)) )