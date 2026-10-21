param([string]$VM = 'OrientOS-Test', [switch]$NoLogin, [switch]$Keep, [int]$WaitSec = 120)
# ODB-UP (laptop, PowerShell 5.1): cold boot one VM headless with uart1 -> file and uart2 -> server pipe, start the
# odbc relay on tcp:127.0.0.1:4710, wait for the agent, type the password by scancodes (DEU layout).
# Then use: python -I odbc\odbc.py --port tcp:127.0.0.1:4710 --token-file odb.token exec <cmd>
# Log: C:\Users\justi\vbl\odbup.log. The VM stays running (stop it with odbdown.ps1 or controlvm poweroff).
$ErrorActionPreference = 'Continue'
$R = 'C:\Users\justi\vbl'; $LOGF = "$R\odbup.log"; $VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$PIPE = '\\.\pipe\odb-' + $VM.ToLower(); $PROXY = 'tcp:127.0.0.1:4710'; $PY = 'C:\Python312\python.exe'
if (-not (Test-Path $PY)) { $PY = 'python' }
function Log($m) { Add-Content $LOGF ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Vb { param([string[]]$a) & $VB @a 2>&1 }
function State([string]$n) { foreach ($ln in (Vb @('showvminfo', $n, '--machinereadable'))) { if ($ln -match '^VMState="(.+)"') { return $Matches[1] } }; return '?' }
function Scan([string]$n, [string[]]$c) { Vb (@('controlvm', $n, 'keyboardputscancode') + $c) | Out-Null }
$MK = @{ a='1E'; e='12'; k='25'; n='31'; o='18'; r='13'; s='1F'; t='14'; w='11' }
function TypeWord([string]$n, [string]$w) {
  foreach ($ch in $w.ToCharArray()) { $m = $MK["$ch"]; $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80); Scan $n @($m, $b); Start-Sleep -Milliseconds 120 } }
$tag = ($VM.ToLower() -replace '[^a-z0-9]+', '-')
Log "== odbup $VM"
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'odbc.py.*serve' } | ForEach-Object { Log "kill old relay $($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force }
if ((State $VM) -eq 'running') { Vb @('controlvm', $VM, 'poweroff') | Out-Null; Start-Sleep -Seconds 5 }
$out = "$R\odbup-$tag.txt"; Remove-Item $out -ErrorAction SilentlyContinue
Vb @('modifyvm', $VM, '--uart1', '0x3F8', '4', '--uart-mode1', 'file', $out) | Out-Null
Vb @('modifyvm', $VM, '--uart2', '0x2F8', '3', '--uart-mode2', 'server', $PIPE) | Out-Null
Vb @('startvm', $VM, '--type', 'headless') | Select-Object -Last 1 | ForEach-Object { Log $_ }
$cl = '"' + $PY + '" -I "' + "$R\odbc\odbc.py" + '" --port pipe:' + $PIPE + ' --wait 60 serve --listen ' + $PROXY
$cr = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cl }
Log "relay rc=$($cr.ReturnValue) pid=$($cr.ProcessId)"
Start-Sleep -Seconds 20
$o = & $PY -I "$R\odbc\odbc.py" --port $PROXY --token-file "$R\odb.token" -t 15 wait $WaitSec 2>&1 | Out-String
Log "odb wait: $($o.Trim())"
if (-not $NoLogin) {
  TypeWord $VM 'startkennwort'; Start-Sleep -Milliseconds 300; Scan $VM @('1C', '9C'); Log 'login typed'
  Start-Sleep -Seconds 25
}
$o = & $PY -I "$R\odbc\odbc.py" --port $PROXY --token-file "$R\odb.token" -t 20 exec ps 2>&1 | Out-String
Log ("exec ps: " + ($o -replace '\s+', ' ').Substring(0, [Math]::Min(400, $o.Length)))
Log 'ODBUP DONE'
