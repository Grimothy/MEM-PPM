# If we are running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64")
{
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe")
    {
        & "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy bypass -NoProfile -File "$PSCommandPath"
        Exit $lastexitcode
    }
}

# Create a tag file just so Intune knows this was installed
if (-not (Test-Path "$($env:ProgramData)\Microsoft\AutopilotBranding"))
{
    Mkdir "$($env:ProgramData)\Microsoft\AutopilotBranding"
    Mkdir "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts"
    Mkdir "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\PPM"
}
Set-Content -Path "$($env:ProgramData)\Microsoft\AutopilotBranding\AutopilotBranding.ps1.tag" -Value "Installed"

# Start logging
Start-Transcript "$($env:ProgramData)\Microsoft\AutopilotBranding\AutopilotBranding.log"

# PREP: Load the Config.xml
$installFolder = "$PSScriptRoot\"
Write-Host "Install folder: $installFolder"
Write-Host "Loading configuration: $($installFolder)Config.xml"
[Xml]$config = Get-Content "$($installFolder)Config.xml"

#PREP + 1: CUSTOM MJM
<#
write-host "Copying files for Intune scheduled task launch"
Copy-Item "Scripts\Intune\Imesync.ps1" "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\ImeSync.ps1"
$imesyncpath = "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\ImeSync.ps1"
write-host "Copying files for PPM"
Copy-Item -Recurse "Scripts\PPM" "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\" -Force
$initpath = "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\PPM\init.ps1"

#>
write-host "Copying files script files"
Copy-Item -Recurse "Scripts" "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\"
$imesyncpath = "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\ImeSync.ps1"
$initpath = "$($env:ProgramData)\Microsoft\AutopilotBranding\scripts\PPM\init.ps1"




# STEP 1: Apply custom start menu layout
Write-Host "Importing layout: $($installFolder)Layout.xml"
Copy-Item "$($installFolder)Layout.xml" "C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml" -Force
<#
<#
# STEP 2: Configure background
Write-Host "Setting up Autopilot theme"
Mkdir "C:\Windows\Resources\OEM Themes" -Force | Out-Null
Copy-Item "$installFolder\Autopilot.theme" "C:\Windows\Resources\OEM Themes\Autopilot.theme" -Force
Mkdir "C:\Windows\web\wallpaper\Autopilot" -Force | Out-Null
Copy-Item "$installFolder\Autopilot.jpg" "C:\Windows\web\wallpaper\Autopilot\Autopilot.jpg" -Force
Write-Host "Setting Autopilot theme as the new user default"
reg.exe load HKLM\TempUser "C:\Users\Default\NTUSER.DAT" | Out-Host
reg.exe add "HKLM\TempUser\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes" /v InstallTheme /t REG_EXPAND_SZ /d "%SystemRoot%\resources\OEM Themes\Autopilot.theme" /f | Out-Host
reg.exe unload HKLM\TempUser | Out-Host
#>

# STEP 3: Set time zone (if specified)
if ($config.Config.TimeZone) {
	Write-Host "Setting time zone: $($config.Config.TimeZone)"
	Set-Timezone -Id $config.Config.TimeZone
}
else {
	# Enable location services so the time zone will be set automatically (even when skipping the privacy page in OOBE) when an administrator signs in
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Type "String" -Value "Allow" -Force
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "SensorPermissionState" -Type "DWord" -Value 1 -Force
	Start-Service -Name "lfsvc" -ErrorAction SilentlyContinue
}

# STEP 4: Remove specified provisioned apps if they exist
Write-Host "Removing specified in-box provisioned apps"
$apps = Get-AppxProvisionedPackage -online
$config.Config.RemoveApps.App | % {
	$current = $_
	$apps | ? {$_.DisplayName -eq $current} | % {
		Write-Host "Removing provisioned app: $current"
		$_ | Remove-AppxProvisionedPackage -Online | Out-Null
	}
}

<#
# STEP 5: Install OneDrive per machine
if ($config.Config.OneDriveSetup) {
	Write-Host "Downloading OneDriveSetup"
	$dest = "$($env:TEMP)\OneDriveSetup.exe"
	$client = new-object System.Net.WebClient
	$client.DownloadFile($config.Config.OneDriveSetup, $dest)
	Write-Host "Installing: $dest"
	$proc = Start-Process $dest -ArgumentList "/allusers" -WindowStyle Hidden -PassThru
	$proc.WaitForExit()
	Write-Host "OneDriveSetup exit code: $($proc.ExitCode)"
}
#>
# STEP 6: Don't let Edge create a desktop shortcut (roams to OneDrive, creates mess)
Write-Host "Turning off (old) Edge desktop shortcut"
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /v DisableEdgeDesktopShortcutCreation /t REG_DWORD /d 1 /f /reg:64 | Out-Host

<#
# STEP 7: Add language packs
Get-ChildItem "$($installFolder)LPs" -Filter *.cab | % {
	Write-Host "Adding language pack: $($_.FullName)"
	Add-WindowsPackage -Online -NoRestart -PackagePath $_.FullName
}


# STEP 8: Change language
if ($config.Config.Language) {
	Write-Host "Configuring language using: $($config.Config.Language)"
	& $env:SystemRoot\System32\control.exe "intl.cpl,,/f:`"$($installFolder)$($config.Config.Language)`""
}

# STEP 9: Add features on demand
$currentWU = (Get-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ErrorAction Ignore).UseWuServer
if ($currentWU -eq 1)
{
	Write-Host "Turning off WSUS"
	Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"  -Name "UseWuServer" -Value 0
	Restart-Service wuauserv
}
$config.Config.AddFeatures.Feature | % {
	Write-Host "Adding Windows feature: $_"
	Add-WindowsCapability -Online -Name $_
}
if ($currentWU -eq 1)
{
	Write-Host "Turning on WSUS"
	Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"  -Name "UseWuServer" -Value 1
	Restart-Service wuauserv
}

<#
# STEP 10: Customize default apps
if ($config.Config.DefaultApps) {
	Write-Host "Setting default apps: $($config.Config.DefaultApps)"
	& Dism.exe /Online /Import-DefaultAppAssociations:`"$($installFolder)$($config.Config.DefaultApps)`"
}
#>

# STEP 11: Set registered user and organization
Write-Host "Configuring registered user information"
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v RegisteredOwner /t REG_SZ /d "$($config.Config.RegisteredOwner)" /f /reg:64 | Out-Host
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v RegisteredOrganization /t REG_SZ /d "$($config.Config.RegisteredOrganization)" /f /reg:64 | Out-Host

<#

# STEP 12: Configure OEM branding info
if ($config.Config.OEMInfo)
{
	Write-Host "Configuring OEM branding info"

	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v Manufacturer /t REG_SZ /d "$($config.Config.OEMInfo.Manufacturer)" /f /reg:64 | Out-Host
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v Model /t REG_SZ /d "$($config.Config.OEMInfo.Model)" /f /reg:64 | Out-Host
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v SupportPhone /t REG_SZ /d "$($config.Config.OEMInfo.SupportPhone)" /f /reg:64 | Out-Host
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v SupportHours /t REG_SZ /d "$($config.Config.OEMInfo.SupportHours)" /f /reg:64 | Out-Host
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v SupportURL /t REG_SZ /d "$($config.Config.OEMInfo.SupportURL)" /f /reg:64 | Out-Host
	Copy-Item "$installFolder\$($config.Config.OEMInfo.Logo)" "C:\Windows\$($config.Config.OEMInfo.Logo)" -Force
	reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /v Logo /t REG_SZ /d "C:\Windows\$($config.Config.OEMInfo.Logo)" /f /reg:64 | Out-Host
}
#>

<#
# STEP 13: Enable UE-V
Write-Host "Enabling UE-V"
Enable-UEV
Set-UevConfiguration -Computer -SettingsStoragePath "%OneDriveCommercial%\UEV" -SyncMethod External -DisableWaitForSyncOnLogon
Get-ChildItem "$($installFolder)UEV" -Filter *.xml | % {
	Write-Host "Registering template: $($_.FullName)"
	Register-UevTemplate -Path $_.FullName
}

#>
# STEP 14: Disable network location fly-out
Write-Host "Turning off network location fly-out"
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff" /f

# STEP 15: Disable new Edge desktop icon
Write-Host "Turning off Edge desktop icon"
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" /v "CreateDesktopShortcutDefault" /t REG_DWORD /d 0 /f /reg:64 | Out-Host


#STEP 16: Creating folder structure for Microsoft Endpoint Manager Custom Tasks.
$taskfolder = "MEM-Custom"

Write-Host "Init Scheduled task folder named $taskfolder  structure"
$scheduleObject = New-Object -ComObject schedule.service
$scheduleObject.connect()

Write-Host "Checking if the task folder $taskfolder exists"
#$rootFolder = $scheduleObject.GetFolder("\$taskfolder") 

try
{
    $scheduleObject.GetFolder("\$taskfolder")
}
catch
{
    Write-Output "Task folder $taskfolder does not exist and will be created"
    #Write-Output $_
    $rootFolder.CreateFolder("\$taskfolder")
}


#STEP 17: Add Sched Task to increase Intune sync intervals
Write-Host "Create Custome Scheduled tasks For Intune Sync"
$arguments = "-Executionpolicy Bypass $imesyncpath"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "$arguments"
$trigger = New-ScheduledTaskTrigger -Once -At '8 AM' -RepetitionInterval (New-TimeSpan -Minutes 10)
Register-ScheduledTask -Action $action -Trigger $trigger -TaskPath "\$taskfolder" -TaskName IntuneCheckin -User "system" -Description "Increases the interval between Itune sync"


#STEP 18: Add Sched Task for PPM
Write-Host "Create Custome Scheduled tasks For PPM"
#$arguments = "-Executionpolicy Bypass $imesyncpath"
Write-Host "Create Custome Scheduled tasks For PPM"
$arguments = "-Executionpolicy Bypass $initpath"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "$arguments"
$trigger = New-ScheduledTaskTrigger -Once -At '8 AM' -RepetitionInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -Action $action -Trigger $trigger -TaskPath "\$taskfolder" -TaskName PPM -User "system" -Description "Increases the interval between Itune sync"

<#

#STEP 19: Install Bitdefender
Write-Host "running bitdefenderinstall action"

$ProcessTitle = $(Get-Process -Name Installer).MainWindowTitle
$arguments = "/i $installFolder\\Bitdefender\BEST_downloaderWrapper.msi /qn GZ_PACKAGE_ID=aHR0cHM6Ly9jbG91ZC1lY3MuZ3Jhdml0eXpvbmUuYml0ZGVmZW5kZXIuY29tL1BhY2thZ2VzL0JTVFdJTi8wL0l3R2JLbi9pbnN0YWxsZXIueG1sP2xhbmc9ZW4tVVM= REBOOT_IF_NEEDED=0"
Start-Process msiexec.exe -ArgumentList $arguments

    #Start loop for Bitdefender Installation
Do
{
    $status = Get-Process EPConsole -ErrorAction SilentlyContinue
    If (!($status)) { Write-Host 'Waiting for process to start. Will check again in 20 Seconds' ; Start-Sleep -Seconds 20 }
    Else { Write-Host 'Process has started' ; $started = $true }
}
Until ( $started )


Write-Host "Bitdefender install Completed"



Stop-Transcript
#>