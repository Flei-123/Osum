param(
  [string]$Dir = 'C:\Users\justi\vbl',
  [string]$TaskName = 'OrientOS-Kickwatch',
  [switch]$Remove
)
$launcher = Join-Path $Dir 'kickwatch-hidden.vbs'
if ($Remove) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  Remove-Item $launcher -Force -ErrorAction SilentlyContinue
  return
}
$script = Join-Path $Dir 'kickwatch.ps1'
if (-not (Test-Path $script)) { throw "missing $script" }
$vbs = 'CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""' + $script + '""", 0, False'
Set-Content -Path $launcher -Value $vbs -Encoding ASCII
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B //Nologo "' + $launcher + '"')
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Get-ScheduledTask -TaskName $TaskName | Select-Object TaskName, State
