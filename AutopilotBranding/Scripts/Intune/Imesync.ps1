Start-Transcript "$($env:ProgramData)\Microsoft\AutopilotBranding\IMEScript.log"
Write-Host "Running Sync tasks"
Write-Host "------------------"
$Shell = New-Object -ComObject Shell.Application
$Shell.open("intunemanagementextension://syncapp")
Write-Host "------------------"
Write-Host "Sync Tasks Completed"

Stop-Transcript