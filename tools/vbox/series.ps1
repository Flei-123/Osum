# series.ps1 - W-L3b measurement helpers (runs on the LAPTOP, PowerShell 5.1, started as a hidden background process).
#   series.ps1 modes <n> <log>     n live mode switches 1920x1080 -> 1280x720 -> 2400x1350 (cycle), per switch: hang seconds
#   series.ps1 boot <n> <log> <headless|gui> <img-label>   n cold boots: login, white-desktop share, host CPU after login
# Output lines go to <log> (poll it). A "hang" = VM process above 85 % of one host core for the sample window after a switch.
param([string]$Mode, [int]$N, [string]$Log, [string]$Arg3 = 'headless', [string]$Label = '')
$ErrorActionPreference = 'Continue'
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$S  = 'C:\Users\justi\vbl\vbtest.ps1'
$VM = 'OrientOS-Test'
function Out-L([string]$t) { Add-Content -Path $Log -Value ("{0} {1}" -f (Get-Date -Format HH:mm:ss), $t) }
function Vbt { & powershell -NoProfile -ExecutionPolicy Bypass -File $S @args 2>&1 | Out-String }
function VmPid {
  $o = & $VB showvminfo $VM --machinereadable 2>$null
  foreach ($l in $o) { if ($l -match '^SessionPID="?(\d+)"?') { return [int]$Matches[1] } }
  # fallback: newest VirtualBoxVM / VBoxHeadless
  $p = Get-Process VBoxHeadless, VirtualBoxVM -ErrorAction SilentlyContinue | Sort-Object StartTime | Select-Object -Last 1
  if ($p) { return $p.Id }
  return 0
}
function CpuSample([int]$procId, [double]$sec) {
  $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
  if (-not $p) { return -1 }
  $c1 = $p.CPU; $t1 = Get-Date; Start-Sleep -Milliseconds ([int]($sec * 1000)); $p.Refresh()
  return [math]::Round(100 * ($p.CPU - $c1) / ((Get-Date) - $t1).TotalSeconds, 0)
}
function LogDir { $d = Get-ChildItem 'C:\Users\justi\VirtualBox VMs\OrientOS-Test\Logs\VBox.log' -ErrorAction SilentlyContinue; return $d }
function CatchUps { $f = 'C:\Users\justi\VirtualBox VMs\OrientOS-Test\Logs\VBox.log'; if (Test-Path $f) { return @(Select-String -Path $f -Pattern 'Giving up catch-up' -ErrorAction SilentlyContinue).Count } return 0 }
function WhiteShare([string]$png) {
  Add-Type -AssemblyName System.Drawing
  $b = New-Object System.Drawing.Bitmap $png; $w = $b.Width; $h = $b.Height; $white = 0; $n = 0
  for ($y = 0; $y -lt $h; $y += 16) { for ($x = 0; $x -lt $w; $x += 16) { $c = $b.GetPixel($x, $y); $n++; if ($c.R -gt 235 -and $c.G -gt 235 -and $c.B -gt 235) { $white++ } } }
  $b.Dispose(); return [math]::Round(100 * $white / [math]::Max(1, $n), 0)
}

if ($Mode -eq 'modes') {
  $pid1 = VmPid; Out-L "START modes n=$N pid=$pid1 catchups=$(CatchUps)"
  $sizes = @(@(1920, 1080), @(1280, 720), @(2400, 1350)); $hang = 0; $secsTot = 0
  for ($i = 0; $i -lt $N; $i++) {
    $sz = $sizes[$i % 3]
    & $VB controlvm $VM setvideomodehint $sz[0] $sz[1] 32 | Out-Null
    Start-Sleep -Seconds 4
    $t0 = Get-Date; $vals = @()
    for ($k = 0; $k -lt 3; $k++) { $vals += (CpuSample $pid1 2.0) }
    $isHang = (($vals | Where-Object { $_ -gt 85 }).Count -ge 2)
    $dur = 0
    if ($isHang) {
      $hang++
      $deadline = (Get-Date).AddSeconds(240)
      while ((Get-Date) -lt $deadline) { $v = CpuSample $pid1 3.0; if ($v -lt 60) { break } }
      $dur = [int]((Get-Date) - $t0).TotalSeconds
      $secsTot += $dur
    }
    $vm = (& $VB showvminfo $VM --machinereadable 2>$null | Where-Object { $_ -match '^VideoMode' }) -join ''
    Out-L ("sw {0} {1}x{2} cpu=[{3}] hang={4} dur={5}s {6} catchups={7}" -f ($i + 1), $sz[0], $sz[1], ($vals -join ','), $isHang, $dur, $vm, (CatchUps))
  }
  Out-L "DONE modes n=$N hangs=$hang hangsec=$secsTot catchups=$(CatchUps)"
}
elseif ($Mode -eq 'boot') {
  $white = 0; $hot = 0
  for ($i = 0; $i -lt $N; $i++) {
    Vbt swapdisk | Out-Null
    $env:VBL_SERIAL = '1'
    if ($Arg3 -eq 'gui') { Vbt start | Out-Null } else { Vbt start headless | Out-Null }
    Start-Sleep -Seconds 40
    Vbt login | Out-Null
    Start-Sleep -Seconds 20
    $pid1 = VmPid
    $vals = @(); for ($k = 0; $k -lt 4; $k++) { $vals += (CpuSample $pid1 3.0) }
    Vbt shot ("b$i") | Out-Null
    $ws = WhiteShare ("C:\Users\justi\vbl\shots\b$i.png")
    $isHot = (($vals | Where-Object { $_ -gt 85 }).Count -ge 3)
    if ($isHot) { $hot++ }; if ($ws -gt 60) { $white++ }
    $ser = ''; $sf = 'C:\Users\justi\vbl\serial.txt'
    if (Test-Path $sf) { $ser = (Get-Content $sf -Tail 1 -ErrorAction SilentlyContinue) -join '' ; if ($ser.Length -gt 60) { $ser = $ser.Substring(0, 60) } }
    Out-L ("boot {0} {1} {2} cpu=[{3}] hot={4} white={5}% catchups={6} lastser='{7}'" -f ($i + 1), $Label, $Arg3, ($vals -join ','), $isHot, $ws, (CatchUps), $ser)
  }
  Out-L "DONE boot $Label $Arg3 n=$N hot=$hot white=$white"
}
