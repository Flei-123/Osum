bcdedit /set '{default}' hypervisorlaunchtype auto
bcdedit /set '{default}' vsmlaunchtype auto
bcdedit /set '{default}' isolatedcontext Yes
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled -Value 1
Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name EnableVirtualizationBasedSecurity -ErrorAction SilentlyContinue
Remove-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard' -Recurse -ErrorAction SilentlyContinue
bcdedit /delete '{0cb3b571-2f2e-4343-a879-d86a476d7215}' 2>$null
$stateFile = 'C:\ProgramData\hyperv-features-before.txt'
if (Test-Path $stateFile) { foreach ($name in (Get-Content $stateFile)) { Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart | Out-Null } }
Write-Host 'Restored. Reboot now.'
