param(
  [string]$Root = 'C:\VBX',
  [string]$Tag = 'base',
  [int]$Boots = 10,
  [string]$Firmware = 'bios',
  [int]$Cpus = 3,
  [int]$Mem = 2048,
  [string]$Extra = '',
  [string]$ExtraData = '',
  [int]$IdleSec = 25,
  [int]$FloodSec = 35,
  [int]$LoginWaitMax = 70,
  [string]$Password = 'startkennwort',
  [string]$VBoxHome = ''
)
$ErrorActionPreference = 'Continue'
if ($VBoxHome) { $env:VBOX_USER_HOME = $VBoxHome }
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$Vm = "abfz-$Tag"
$Log = Join-Path $Root "abfz-$Tag.log"
$Img = Join-Path $Root 'o.img'
$Ser = Join-Path $Root "ser-$Tag.txt"
$VmRoot = Join-Path $Root 'vms'
$CapDir = Join-Path $Root "cap-$Tag"
$OutF = Join-Path $Root "vbo-$Tag.txt"
$ErrF = Join-Path $Root "vbe-$Tag.txt"
$BurnPct = 90
$FreezeRun = 6
$ExitRateLimit = 60
New-Item -ItemType Directory -Force -Path $VmRoot, $CapDir | Out-Null

function L([string]$t) { Add-Content -Path $Log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $t) }

function Vb([string[]]$a, [int]$to = 60) {
  $p = Start-Process -FilePath $VB -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $OutF -RedirectStandardError $ErrF
  if (-not $p.WaitForExit($to * 1000)) { try { $p.Kill() } catch {}; return 'TIMEOUT' }
  return ("$(Get-Content $OutF -Raw)$(Get-Content $ErrF -Raw)")
}

function VmPid {
  try { $v = New-Object -ComObject VirtualBox.VirtualBox; return [int]$v.FindMachine($Vm).SessionPID } catch { return 0 }
}

function Scan([string[]]$codes) { Vb (@('controlvm', $Vm, 'keyboardputscancode') + $codes) 15 | Out-Null }

$MK = @{ a = '1E'; e = '12'; k = '25'; n = '31'; o = '18'; r = '13'; s = '1F'; t = '14'; w = '11' }
function Login {
  foreach ($ch in $Password.ToCharArray()) {
    $m = $MK["$ch"]
    $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80)
    Scan @($m, $b)
  }
  Start-Sleep -Milliseconds 300
  Scan @('1C', '9C')
}

function MakeVm {
  Vb @('controlvm', $Vm, 'poweroff') 20 | Out-Null
  Start-Sleep -Seconds 3
  Vb @('unregistervm', $Vm, '--delete') 60 | Out-Null
  Vb @('createvm', '--name', $Vm, '--ostype', 'Other_64', '--register', '--basefolder', $VmRoot) 60 | Out-Null
  $r = Vb @('modifyvm', $Vm, '--memory', "$Mem", '--vram', '128', '--cpus', "$Cpus", '--graphicscontroller', 'vmsvga', '--chipset', 'piix3', '--firmware', $Firmware, '--ioapic', 'on', '--hpet', 'off', '--mouse', 'ps2', '--keyboard', 'ps2', '--audio-driver', 'none', '--clipboard-mode', 'disabled', '--rtcuseutc', 'off', '--boot1', 'disk', '--boot2', 'none', '--boot3', 'none', '--boot4', 'none', '--usb-ohci', 'off', '--usb-ehci', 'off', '--usb-xhci', 'on', '--nic1', 'nat', '--nic-type1', '82540EM', '--cable-connected1', 'on', '--uart1', '0x3F8', '4', '--uart-mode1', 'file', $Ser) 30
  if ($r -match 'error') { L "modifyvm: $r" }
  Vb @('storagectl', $Vm, '--name', 'IDE', '--add', 'ide', '--controller', 'PIIX4') 30 | Out-Null
  if ($Extra) { $r = Vb (@('modifyvm', $Vm) + ($Extra -split '\s+' | Where-Object { $_ })) 30; L "extra [$Extra] -> $r" }
  if ($ExtraData) {
    foreach ($kv in ($ExtraData -split ';')) {
      $p = $kv -split '=', 2
      if ($p.Count -eq 2) { Vb @('setextradata', $Vm, $p[0], $p[1]) 15 | Out-Null; L "extradata $($p[0])=$($p[1])" }
    }
  }
}

function AttachDisk([int]$n) {
  $vdi = Join-Path $Root "run-$Tag-$n.vdi"
  Remove-Item $vdi -Force -ErrorAction SilentlyContinue
  Vb @('convertfromraw', $Img, $vdi, '--format', 'VDI') 120 | Out-Null
  Vb @('storageattach', $Vm, '--storagectl', 'IDE', '--port', '0', '--device', '0', '--type', 'hdd', '--medium', $vdi) 30 | Out-Null
  return $vdi
}

function DetachDisk([string]$vdi) {
  Vb @('storageattach', $Vm, '--storagectl', 'IDE', '--port', '0', '--device', '0', '--type', 'hdd', '--medium', 'none') 30 | Out-Null
  Vb @('closemedium', 'disk', $vdi, '--delete') 60 | Out-Null
  Remove-Item $vdi -Force -ErrorAction SilentlyContinue
}

function ThreadMap($p) {
  $h = @{}
  try { $p.Refresh(); foreach ($t in $p.Threads) { try { $h[$t.Id] = $t.TotalProcessorTime.TotalSeconds } catch {} } } catch {}
  return $h
}

function ExitSum {
  $s = Vb @('debugvm', $Vm, 'statistics', '--pattern=/PROF/CPU*/EM/RecordedExits') 10
  if ($s -eq 'TIMEOUT') { return -1 }
  $sum = 0.0; $any = $false
  foreach ($m in [regex]::Matches($s, 'c="(\d+)"[^>]*name="/PROF/CPU\d+/EM/RecordedExits"')) { $sum += [double]$m.Groups[1].Value; $any = $true }
  if (-not $any) { return -2 }
  return $sum
}

function ModeOf {
  $f = Join-Path $VmRoot "$Vm\Logs\VBox.log"
  $s = Select-String -Path $f -Pattern 'HM: HMR3Init|NEM: Created partition|HM: Using|NEM: NEMR3Init' -ErrorAction SilentlyContinue | Select-Object -First 3
  $fw = (Vb @('showvminfo', $Vm, '--machinereadable') 20) -split "`n" | Where-Object { $_ -match '^firmware=' } | Select-Object -First 1
  return ((@("$fw".Trim()) + @($s | ForEach-Object { $_.Line.Trim() -replace '^\d+:\d+:\d+\.\d+\s+', '' })) -join ' | ')
}

function Flood($mouse) {
  $mouse.PutMouseEvent(0, 0, 0, 0, 0)
  for ($i = 0; $i -lt 40; $i++) {
    $mouse.PutMouseEvent([int](12 * [math]::Sign([math]::Sin($i / 5.0))), [int](6 * [math]::Sign([math]::Cos($i / 7.0))), 0, 0, 0)
    Start-Sleep -Milliseconds 8
  }
  $mouse.PutMouseEvent(0, 0, 0, 0, 1); Start-Sleep -Milliseconds 80; $mouse.PutMouseEvent(0, 0, 0, 0, 0)
}

function Capture([int]$n, $proc, $deltas) {
  $d = Join-Path $CapDir "b$n"
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  $o = Join-Path $d 'cap.txt'
  Add-Content $o ("freeze capture {0}" -f (Get-Date -Format 'HH:mm:ss.fff'))
  Add-Content $o '--- top threads (cpu % over last second)'
  foreach ($k in ($deltas.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 6)) { Add-Content $o ("tid={0} {1:N0}%" -f $k.Key, $k.Value) }
  Add-Content $o '--- statistics (before wake)'
  Add-Content $o (Vb @('debugvm', $Vm, 'statistics', '--pattern=/NEM/CPU*/Exit*|/HM/CPU*/*Exit*|/TM/CPU/0?/*') 20)
  Vb @('controlvm', $Vm, 'screenshotpng', (Join-Path $d 'screen.png')) 20 | Out-Null
  Copy-Item (Join-Path $VmRoot "$Vm\Logs\VBox.log") (Join-Path $d 'VBox-live.log') -ErrorAction SilentlyContinue
  $t0 = Get-Date
  $r = Vb @('debugvm', $Vm, 'info', 'apictimer') 25
  Add-Content $o ("--- kick info apictimer took {0:N1}s" -f ((Get-Date) - $t0).TotalSeconds)
  Add-Content $o $r
  $a = ThreadMap $proc; Start-Sleep -Seconds 3; $b = ThreadMap $proc
  $mx = 0.0
  foreach ($id in $b.Keys) { if ($a.ContainsKey($id)) { $v = ($b[$id] - $a[$id]) / 3 * 100; if ($v -gt $mx) { $mx = $v } } }
  $heal = if ($mx -lt $BurnPct) { 'yes' } else { 'no' }
  Add-Content $o ("--- after kick max thread {0:N0}% heal={1}" -f $mx, $heal)
  return $heal
}

function RunBoot([int]$n) {
  $res = [ordered]@{ n = $n; result = 'OK'; login = -1; firstBurn = -1; burnSec = 0; maxRun = 0; avgCpu = 0.0; avgMax = 0.0; heal = '-'; exitRate = '-'; bootMaxRun = 0; mode = '' }
  $vdi = AttachDisk $n
  Remove-Item $Ser -Force -ErrorAction SilentlyContinue
  $start = Get-Date
  Vb @('startvm', $Vm, '--type', 'headless') 60 | Out-Null
  $vpid = 0
  for ($i = 0; $i -lt 30 -and $vpid -le 0; $i++) { Start-Sleep -Seconds 1; $vpid = VmPid }
  $proc = if ($vpid -gt 0) { Get-Process -Id $vpid -ErrorAction SilentlyContinue } else { $null }
  if (-not $proc) { $res.result = 'START-FAILED'; DetachDisk $vdi; return $res }
  $prev = ThreadMap $proc; $run = 0; $bootMax = 0; $loginAt = -1
  $sw = [Diagnostics.Stopwatch]::StartNew(); $tPrev = 0.0
  for ($i = 1; $i -le $LoginWaitMax; $i++) {
    Start-Sleep -Milliseconds ([math]::Max(50, [int](($i - $sw.Elapsed.TotalSeconds) * 1000)))
    $now = ThreadMap $proc; $t = $sw.Elapsed.TotalSeconds; $dt = $t - $tPrev
    $mx = 0.0
    foreach ($id in $now.Keys) { if ($prev.ContainsKey($id)) { $v = ($now[$id] - $prev[$id]) / $dt * 100; if ($v -gt $mx) { $mx = $v } } }
    $prev = $now; $tPrev = $t
    if ($mx -ge $BurnPct) { $run++ } else { $run = 0 }
    if ($run -gt $bootMax) { $bootMax = $run }
    if ((Test-Path $Ser) -and (Select-String -Path $Ser -Pattern 'glogin: ready' -Quiet -ErrorAction SilentlyContinue)) { $loginAt = [int]((Get-Date) - $start).TotalSeconds; break }
  }
  $res.bootMaxRun = $bootMax; $res.login = $loginAt
  $res.mode = ModeOf
  if ($loginAt -lt 0) { L "boot ${n}: no login marker in serial after ${LoginWaitMax}s (bootMaxRun=$bootMax), logging in anyway" }
  Start-Sleep -Seconds 2
  Login
  $mouse = $null; $sess = $null
  try { $vbox = New-Object -ComObject VirtualBox.VirtualBox; $sess = New-Object -ComObject VirtualBox.Session; $vbox.FindMachine($Vm).LockMachine($sess, 1); $mouse = $sess.Console.Mouse } catch { L "boot ${n}: mouse lock failed: $_" }
  Start-Sleep -Seconds 8
  $prev = ThreadMap $proc; $sw = [Diagnostics.Stopwatch]::StartNew(); $tPrev = 0.0
  $run = 0; $serAtRun4 = -1; $ticks = 0; $sumCpu = 0.0; $sumMax = 0.0; $e1 = -9; $e1t = 0.0; $frozen = $false
  $total = $IdleSec + $FloodSec
  for ($i = 1; $i -le $total -and -not $frozen; $i++) {
    if ($i -gt $IdleSec -and $mouse) { try { Flood $mouse } catch { L "boot ${n}: flood error: $_" } }
    Start-Sleep -Milliseconds ([math]::Max(50, [int](($i - $sw.Elapsed.TotalSeconds) * 1000)))
    if (-not (Get-Process -Id $vpid -ErrorAction SilentlyContinue)) { $res.result = 'VM-GONE'; break }
    $now = ThreadMap $proc; $t = $sw.Elapsed.TotalSeconds; $dt = $t - $tPrev
    $mx = 0.0; $sum = 0.0; $deltas = @{}
    foreach ($id in $now.Keys) { if ($prev.ContainsKey($id)) { $v = ($now[$id] - $prev[$id]) / $dt * 100; $deltas[$id] = $v; $sum += $v; if ($v -gt $mx) { $mx = $v } } }
    $prev = $now; $tPrev = $t
    $ticks++; $sumCpu += $sum; $sumMax += $mx
    if ($mx -ge $BurnPct) { $run++; $res.burnSec++ } else { $run = 0; $e1 = -9 }
    if ($run -gt $res.maxRun) { $res.maxRun = $run }
    if ($run -ge 4 -and $res.firstBurn -lt 0) { $res.firstBurn = $i }
    if ($run -eq 4) { $e1 = ExitSum; $e1t = $sw.Elapsed.TotalSeconds; $serAtRun4 = (Get-Item $Ser -ErrorAction SilentlyContinue).Length }
    if ($run -ge $FreezeRun) {
      $e2 = ExitSum; $e2t = $sw.Elapsed.TotalSeconds
      if ($e1 -ge 0 -and $e2 -ge 0) { $rate = ($e2 - $e1) / ($e2t - $e1t); $res.exitRate = ('{0:N0}/s' -f $rate); $frozen = ($rate -lt $ExitRateLimit) }
      else { $res.exitRate = 'n/a'; $frozen = ((Get-Item $Ser -ErrorAction SilentlyContinue).Length -eq $serAtRun4) }
      if (-not $frozen) { $run = 0; $e1 = -9 }
    }
    if ($frozen) { $res.result = 'FREEZE'; $res.heal = Capture $n $proc $deltas }
  }
  if ($ticks -gt 0) { $res.avgCpu = [math]::Round($sumCpu / $ticks, 1); $res.avgMax = [math]::Round($sumMax / $ticks, 1) }
  try { if ($sess) { $sess.UnlockMachine() } } catch {}
  Copy-Item (Join-Path $VmRoot "$Vm\Logs\VBox.log") (Join-Path $CapDir "VBox-b$n.log") -ErrorAction SilentlyContinue
  Vb @('controlvm', $Vm, 'poweroff') 25 | Out-Null
  for ($i = 0; $i -lt 15 -and (Get-Process -Id $vpid -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
  if (Get-Process -Id $vpid -ErrorAction SilentlyContinue) { Stop-Process -Id $vpid -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
  Start-Sleep -Seconds 2
  DetachDisk $vdi
  return $res
}

L "=== arm tag=$Tag fw=$Firmware cpus=$Cpus mem=$Mem extra=[$Extra] extradata=[$ExtraData] boots=$Boots idle=$IdleSec flood=$FloodSec vbox=$(Vb @('--version') 10)"
MakeVm
$freezes = 0; $oks = 0
for ($n = 1; $n -le $Boots; $n++) {
  try { $r = RunBoot $n } catch { L "boot ${n}: exception $_"; $r = [ordered]@{ n = $n; result = 'ERROR' } }
  if ($r.result -eq 'FREEZE') { $freezes++ } elseif ($r.result -eq 'OK') { $oks++ }
  L ("BOOT " + (($r.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '))
}
L "SUMMARY tag=$Tag fw=$Firmware cpus=$Cpus extra=[$Extra] extradata=[$ExtraData] boots=$Boots freeze=$freezes ok=$oks"
Vb @('unregistervm', $Vm, '--delete') 60 | Out-Null
L 'ABFZ DONE'
