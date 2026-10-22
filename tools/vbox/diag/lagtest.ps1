param([string]$Vm = 'OrientOS', [int]$Flood = 600, [int]$Watch = 15, [string]$Sizes = '1920x1080,1280x720,1024x768', [switch]$NoBoot)
# VirtSync lag after a mouse flood and live resize hints (laptop side, PowerShell 5.1).
# Per phase: VirtualSync CurrentOffset (ns) once per second for $Watch s plus host CPU of the VM process.
# Result per phase: max lag above the baseline (s) and the lag at the end of the window. Log: C:\Users\justi\vbl\lagtest.log (LAGTEST DONE).
# Boots $Vm headless (cold), logs in by scancodes, settles 60 s. Powers the VM off at the end (hard, ACPI does not work in the guest).
$R = 'C:\Users\justi\vbl'; $LOGF = "$R\lagtest.log"; $VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function Log($m) { Add-Content $LOGF ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Vb { param([string[]]$a) & $VB @a 2>&1 }
function State([string]$n) { foreach ($ln in (Vb @('showvminfo', $n, '--machinereadable'))) { if ($ln -match '^VMState="(.+)"') { return $Matches[1] } }; return '?' }
function Scan([string]$n, [string[]]$c) { Vb (@('controlvm', $n, 'keyboardputscancode') + $c) | Out-Null }
$MK = @{ a='1E'; e='12'; k='25'; n='31'; o='18'; r='13'; s='1F'; t='14'; w='11' }
function Login([string]$n) { foreach ($ch in 'startkennwort'.ToCharArray()) { $m = $MK["$ch"]; $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80); Scan $n @($m, $b); Start-Sleep -Milliseconds 120 }; Start-Sleep -Milliseconds 300; Scan $n @('1C', '9C') }
function PowerOff([string]$n) { if ((State $n) -eq 'running') { Vb @('controlvm', $n, 'poweroff') | Out-Null; Start-Sleep -Seconds 5 } }
function Offs([string]$n) {
  foreach ($ln in (Vb @('debugvm', $n, 'statistics', '--pattern', '/TM/VirtualSync/CurrentOffset'))) { if ($ln -match 'val="(\d+)"') { return [double]$Matches[1] } }
  return -1
}
function VmProc([string]$n) { $v = New-Object -ComObject VirtualBox.VirtualBox; $p = [int]$v.FindMachine($n).SessionPID; if ($p -le 0) { return $null }; return Get-Process -Id $p -ErrorAction SilentlyContinue }
$script:base = 0; $script:worst = 0; $script:all = 0
function Watch([string]$phase) {
  $pr = VmProc $Vm; $t0 = if ($pr) { $pr.TotalProcessorTime.TotalSeconds } else { 0 }; $w = 0; $last = 0
  for ($i = 1; $i -le $Watch; $i++) {
    Start-Sleep -Seconds 1
    $o = Offs $Vm; $pr.Refresh(); $t1 = $pr.TotalProcessorTime.TotalSeconds
    $lag = ($o - $script:base) / 1e9; $cpu = 100 * ($t1 - $t0); $t0 = $t1
    if ($lag -gt $w) { $w = $lag }; $last = $lag
    if ($i -eq 1 -or $i -eq 5 -or $i -eq $Watch) { Log ("{0} t+{1}s lag={2:N2}s host={3:N0}%" -f $phase, $i, $lag, $cpu) }
  }
  Log ("{0} RESULT max_lag={1:N2}s end_lag={2:N2}s" -f $phase, $w, $last)
  if ($w -gt $script:worst) { $script:worst = $w }
}
function Flood([int]$n) {
  $vbox = New-Object -ComObject VirtualBox.VirtualBox; $s = New-Object -ComObject VirtualBox.Session
  $vbox.FindMachine($Vm).LockMachine($s, 1)
  try {
    $mouse = $s.Console.Mouse; $sw = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $n; $i++) {
      $dx = 12 * [math]::Sign([math]::Sin($i / 20.0)); $dy = 6 * [math]::Sign([math]::Cos($i / 30.0))
      $mouse.PutMouseEvent($dx, $dy, 0, 0, 0); Start-Sleep -Milliseconds 5
    }
    for ($c = 0; $c -lt 3; $c++) { $mouse.PutMouseEvent(0, 0, 0, 0, 1); Start-Sleep -Milliseconds 80; $mouse.PutMouseEvent(0, 0, 0, 0, 0); Start-Sleep -Milliseconds 400 }
    Log ("flood {0} moves + 3 clicks in {1} ms" -f $n, $sw.ElapsedMilliseconds)
  } finally { $s.UnlockMachine() }
}
Log "== lagtest $Vm flood=$Flood watch=$Watch sizes=$Sizes"
if (-not $NoBoot) {
  PowerOff $Vm
  Vb @('startvm', $Vm, '--type', 'headless') | Select-Object -Last 1 | ForEach-Object { Log "$Vm $_" }
  Start-Sleep -Seconds 50; Login $Vm; Log 'login typed'; Start-Sleep -Seconds 60
}
$script:base = Offs $Vm; Log ("baseline offset {0:N3}s" -f ($script:base / 1e9))
Watch 'idle'
Flood $Flood; Watch 'flood'
foreach ($z in ($Sizes -split ',')) {
  $wh = $z -split 'x'
  Vb @('controlvm', $Vm, 'setvideomodehint', $wh[0], $wh[1], '32') | Out-Null; Log "hint $z"
  Watch "resize_$z"
  Flood 200; Watch "flood_after_$z"
}
Log ("LAGTEST SUMMARY worst_max_lag={0:N2}s (target < 5)" -f $script:worst)
PowerOff $Vm
Log 'LAGTEST DONE'
