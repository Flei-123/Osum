param([string[]]$Names = @('OrientOS', 'OrientOS-Test'), [int]$Samples = 5, [int]$Sec = 15, [int]$Settle = 60)
$R = 'C:\Users\justi\vbl'; $LOGF = "$R\bench2.log"; $VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function Log($m) { Add-Content $LOGF ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Vb { param([string[]]$a) & $VB @a 2>&1 }
function State([string]$n) { foreach ($ln in (Vb @('showvminfo', $n, '--machinereadable'))) { if ($ln -match '^VMState="(.+)"') { return $Matches[1] } }; return '?' }
function Scan([string]$n, [string[]]$c) { Vb (@('controlvm', $n, 'keyboardputscancode') + $c) | Out-Null }
$MK = @{ a='1E'; e='12'; k='25'; n='31'; o='18'; r='13'; s='1F'; t='14'; w='11' }
function Login([string]$n) { foreach ($ch in 'startkennwort'.ToCharArray()) { $m = $MK["$ch"]; $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80); Scan $n @($m, $b); Start-Sleep -Milliseconds 120 }; Start-Sleep -Milliseconds 300; Scan $n @('1C', '9C') }
function PowerOff([string]$n) {
  if ((State $n) -eq 'running') { Vb @('controlvm', $n, 'poweroff') | Out-Null; Start-Sleep -Seconds 5 }
}
function Snap([string]$n) {
  $h = @{}
  foreach ($ln in (Vb @('debugvm', $n, 'statistics', '--pattern', '/TM/VirtualSync/*'))) { if ($ln -match 'val="(\d+)".*name="([^"]+)"') { $h[$Matches[2]] = [int64]$Matches[1] } }
  return $h
}
function VmProc([string]$n) { $v = New-Object -ComObject VirtualBox.VirtualBox; $p = [int]$v.FindMachine($n).SessionPID; if ($p -le 0) { return $null }; return Get-Process -Id $p -ErrorAction SilentlyContinue }
foreach ($n in $Names) {
  PowerOff $n
  Log "$n startvm headless"
  Vb @('startvm', $n, '--type', 'headless') | Select-Object -Last 1 | ForEach-Object { Log "$n $_" }
  Start-Sleep -Seconds 50; Login $n; Log "$n login typed"; Start-Sleep -Seconds $Settle
  $a = Snap $n; $pa = VmProc $n; $ta = if ($pa) { $pa.TotalProcessorTime.TotalSeconds } else { 0 }
  for ($k = 1; $k -le $Samples; $k++) {
    Start-Sleep -Seconds $Sec; $b = Snap $n; $pb = VmProc $n; $tb = if ($pb) { $pb.TotalProcessorTime.TotalSeconds } else { 0 }
    $lag = 0; $co = '/TM/VirtualSync/CurrentOffset'
    if ($b.ContainsKey($co) -and $a.ContainsKey($co)) { $lag = ($b[$co] - $a[$co]) / 1e6 / $Sec }
    $hc = 100 * ($tb - $ta) / $Sec
    $all = (Get-Process -Name VirtualBoxVM, VBoxHeadless -ErrorAction SilentlyContinue | Measure-Object).Count
    Log ("{0} s{1} host={2:N1}% lag+{3:N1}ms/s vmprocs={4}" -f $n, $k, $hc, $lag, $all)
    $a = $b; $ta = $tb
  }
  PowerOff $n
}
Log 'BENCH2 DONE'
