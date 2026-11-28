$ErrorActionPreference = 'Continue'
$features = 'Microsoft-Hyper-V-All','Microsoft-Hyper-V','Microsoft-Hyper-V-Hypervisor','Microsoft-Hyper-V-Services','Microsoft-Hyper-V-Management-Clients','Microsoft-Hyper-V-Management-PowerShell','Microsoft-Hyper-V-Tools-All','VirtualMachinePlatform','HypervisorPlatform','Microsoft-Windows-Subsystem-Linux','Containers-DisposableClientVM'
$stateFile = 'C:\ProgramData\hyperv-features-before.txt'
Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -in $features -and $_.State -eq 'Enabled' } | ForEach-Object { $_.FeatureName } | Set-Content $stateFile
foreach ($name in (Get-Content $stateFile)) { Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart | Out-Null }
bcdedit /set '{default}' hypervisorlaunchtype off
Write-Host "Features disabled. Saved list: $stateFile. Reboot now."
