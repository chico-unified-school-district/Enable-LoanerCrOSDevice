function Import-SomeModule {
 begin {
  $myModules = Get-Module
 }
 process {
  if ($myModules.name -contains $_) { return }
  if (-not(Get-Module -Name $_ -ListAvailable)) {
   Install-Module -Name $_ -Scope CurrentUser -AllowClobber -Confirm:$false -Force
  }
  $modParams = @{
   Name        = $_
   Verbose     = $false
   ErrorAction = 'Stop'
  }
  Import-Module @modParams | Out-Null
  Write-Host ('{0},{1},Module loaded' -f $MyInvocation.MyCommand.Name, $_) -F Green
 }
}