function Clear-SessionData {
 Write-Verbose 'Clearing session data'
 Get-PSSession | Remove-PSSession -Confirm:$false
}