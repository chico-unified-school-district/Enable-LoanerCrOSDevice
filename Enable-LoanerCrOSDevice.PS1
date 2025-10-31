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
 [string]$StopTime = '6:00 PM',
 [Alias('wi')]
 [switch]$WhatIf
)

function Get-Data ($params) {
 begin { $sql = Get-Content -Path '.\sql\reenable.sql' -Raw }
 process {
  $data = New-SqlOperation @params -Query $sql
  Write-Verbose ('{0},Count {1}' -f $MyInvocation.MyCommand.Name, @($data).count)
  $data
 }
}

function Enable-GDevice {
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.barCode, $_.sn
  if ($_.status -eq 'ACTIVE') { return (Write-Verbose ('{0},{1},{2},Device already active' -f $msg)), $_ }
  Write-Host ('{0},{1},{2}' -f $msg) -F Blue
  Write-Verbose "& $gam update cros $($_.id) action reenable"
  if (!$WhatIf) {
   $ErrorActionPreference = 'Continue'
   (& $gam update cros $_.id action reenable) *>$null
   $ErrorActionPreference = 'Stop'
  }
  $_
 }
}

function Get-CrosDev {
 begin { $crosFields = 'annotatedAssetID,deviceId,status,serialNumber' }
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.barCode, $_.sn
  Write-Verbose ('{0},{1},{2}' -f $msg)
  Write-Verbose "& $gam print cros query `"asset_id: $($_.barCode)`" fields $crosFields"
  $ErrorActionPreference = 'Continue'
  ($dev = & $gam print cros query "asset_id: $($_.barCode)" fields $crosFields | ConvertFrom-Csv) *>$null
  $ErrorActionPreference = 'Stop'
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

function Update-SqlDate ($params) {
 begin { $updateSql = Get-Content -Path '.\sql\Update-DRA-DD.sql' -Raw }
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.barCode, $_.sn
  $sqlVars = "serialNumber=$($_.sn)"
  Write-Host ('{0},{1},{2}' -f $msg) -F Blue
  Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, ($sqlVars -join ','))
  if (!$WhatIf) { New-SqlOperation @params -Query $updateSql -Parameters $sqlVars }
 }
}

$gam = 'C:\GAM7\gam.exe'

if ($WhatIf) { Show-TestRun }

Import-Module CommonScriptFunctions -Cmdlet Show-BlockInfo, New-SqlOperation, Show-TestRun
Import-Module -Name dbatools -Cmdlet Invoke-DbaQuery, Set-DbatoolsConfig, Connect-DbaInstance, Disconnect-DbaInstance

$sqlInstance = Connect-DbaInstance -SqlInstance $SQLServer -Database $SQLDatabase -SqlCredential $SQLCredential

Show-BlockInfo 'Runs every 5 minutes'

do {
 Get-Data $sqlInstance |
  Get-CrosDev |
   Enable-GDevice |
    Update-SqlDate $sqlInstance
 if (!$WhatIf) { Start-Sleep -Seconds 300 }
} until ( $WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)) )

if ($WhatIf) { Show-TestRun }