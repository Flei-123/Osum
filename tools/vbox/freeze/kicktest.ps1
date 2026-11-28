param(
  [string]$Label = 'A',
  [string]$Mods = '',
  [int]$Minutes = 1,[string]$Flood = 'full',
  [string]$Vm = 'OrientOS-aud',
  [string]$Out = 'C:\Users\justi\vbl\abser5.log',[string]$Ser = 'C:\Users\justi\vbl\aud-serial.txt'
)
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$ser = $Ser
$VmDir = "C:\Users\justi\VirtualBox VMs\$Vm"
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Th4 {
  [DllImport("kernel32.dll")] static extern IntPtr OpenThread(int a, bool i, int id);
  [DllImport("kernel32.dll")] static extern int SuspendThread(IntPtr h);
  [DllImport("kernel32.dll")] static extern int ResumeThread(IntPtr h);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] static extern bool GetThreadContext(IntPtr h, IntPtr ctx);
  [DllImport("kernel32.dll")] static extern int GetThreadDescription(IntPtr h, out IntPtr name);
  public static string Name(int tid) {
    IntPtr h = OpenThread(0x0800, false, tid);
    if (h == IntPtr.Zero) return "?";
    IntPtr p;
    if (GetThreadDescription(h, out p) != 0) return "?";
    return Marshal.PtrToStringUni(p);
  }
  public static ulong[] Sample(int tid) {
    IntPtr h = OpenThread(0x1A, false, tid);
    if (h == IntPtr.Zero) return null;
    IntPtr ctx = Marshal.AllocHGlobal(0x4F0 + 64);
    long p = ((long)ctx + 15) & ~15L;
    for (int i = 0; i < 0x4F0; i++) Marshal.WriteByte((IntPtr)(p + i), 0);
    Marshal.WriteInt32((IntPtr)(p + 0x30), 0x10000F);
    SuspendThread(h);
    bool ok = GetThreadContext(h, (IntPtr)p);
    ulong rip = (ulong)Marshal.ReadInt64((IntPtr)(p + 0xF8));
    ulong rsp = (ulong)Marshal.ReadInt64((IntPtr)(p + 0x98));
    ResumeThread(h);
    CloseHandle(h);
    Marshal.FreeHGlobal(ctx);
    return ok ? new ulong[] { rip, rsp } : null;
  }
}
'@
function L($t) { Add-Content $Out ("{0} [{1}] {2}" -f (Get-Date -f HH:mm:ss), $Label, $t) }
function Vb([string[]]$a, [int]$to = 25) {
  $p = Start-Process -FilePath $VB -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\vbo4.txt" -RedirectStandardError "$env:TEMP\vbe4.txt"
  if (-not $p.WaitForExit($to * 1000)) { try { $p.Kill() } catch {}; return 'TIMEOUT' }
  return ((Get-Content "$env:TEMP\vbo4.txt" -Raw) + (Get-Content "$env:TEMP\vbe4.txt" -Raw))
}
function Scan([string[]]$c) { Vb (@('controlvm', $Vm, 'keyboardputscancode') + $c) 10 | Out-Null }
$MK = @{ a='1E'; e='12'; k='25'; n='31'; o='18'; r='13'; s='1F'; t='14'; w='11' }
function Login { foreach ($ch in 'startkennwort'.ToCharArray()) { $m = $MK["$ch"]; $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80); Scan @($m, $b); Start-Sleep -Milliseconds 120 }; Start-Sleep -Milliseconds 300; Scan @('1C', '9C') }
function VmPid { $v = New-Object -ComObject VirtualBox.VirtualBox; return [int]$v.FindMachine($Vm).SessionPID }
function Stats { $s = Vb @('debugvm', $Vm, 'statistics', '--pattern=/TM/VirtualSync/CurrentOffset') 15; if ($s -eq 'TIMEOUT') { return -1 }; if ($s -match 'val="(\d+)"') { return [double]$Matches[1] / 1e9 }; return -2 }
function SerLen { (Get-Item $ser -ErrorAction SilentlyContinue).Length }
function StatMap($pat) {
  $s = Vb @('debugvm', $Vm, 'statistics', "--pattern=$pat") 20
  $h = @{}
  if ($s -eq 'TIMEOUT') { $h['TIMEOUT'] = 1; return $h }
  foreach ($m in [regex]::Matches($s, '(?:c|val)="(\d+)"[^>]*name="([^"]+)"')) { $h[$m.Groups[2].Value] = [double]$m.Groups[1].Value }
  return $h
}
function ThreadMap($p) { $h = @{}; $p.Refresh(); foreach ($t in $p.Threads) { try { $h[$t.Id] = $t.TotalProcessorTime.TotalSeconds } catch {} }; return $h }

$script:lastLen = -1; $script:lastGrow = Get-Date; $script:cpuT0 = 0.0; $script:cpuW0 = Get-Date; $script:cpuNow = 0.0
$script:freeze = $false; $script:proc = $null; $script:armed = $false; $script:cpuPrev = 0.0
function Watch {
  $sl = SerLen
  if ($sl -ne $script:lastLen) { $script:lastLen = $sl; $script:lastGrow = Get-Date }
  $now = Get-Date
  if (($now - $script:cpuW0).TotalSeconds -ge 3 -and $script:proc) {
    $script:proc.Refresh()
    $cur = $script:proc.TotalProcessorTime.TotalSeconds
    $script:cpuNow = 100 * ($cur - $script:cpuT0) / ($now - $script:cpuW0).TotalSeconds
    $script:cpuT0 = $cur; $script:cpuW0 = $now
  }
  if ($script:armed -and ($now - $script:lastGrow).TotalSeconds -ge 6 -and $script:cpuNow -gt 85) { $script:freeze = $true }
}
function Nap([double]$sec) {
  $e = (Get-Date).AddSeconds($sec)
  while ((Get-Date) -lt $e -and -not $script:freeze) { Start-Sleep -Milliseconds 400; Watch }
}

function LiveCap {
  $d = "C:\Users\justi\vbl\fz5-$Label"
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  $o = "$d\live.txt"
  function W($t) { Add-Content $o ("{0} {1}" -f (Get-Date -f HH:mm:ss.fff), $t) }
  W "freeze detected serlen=$(SerLen) grow-age=$([int]((Get-Date) - $script:lastGrow).TotalSeconds)s hostcpu=$([int]$script:cpuNow)"
  $sl0 = SerLen
  Copy-Item $ser "$d\serial-a.txt" -ErrorAction SilentlyContinue
  $pat = '/NEM/CPU*/Exit*|/NEM/CPU*/Break*|/NEM/CPU*/Import*|/TM/CPU/0?/*'
  $t1 = ThreadMap $script:proc; $s1 = StatMap $pat; $ta = Get-Date
  W "stats A taken"
  Start-Sleep -Seconds 3
  $t2 = ThreadMap $script:proc; $s2 = StatMap $pat; $tb = Get-Date
  $dt = ($tb - $ta).TotalSeconds
  W ("=== stats delta over {0:N1}s (nonzero)" -f $dt)
  foreach ($k in ($s2.Keys | Sort-Object)) { $dv = $s2[$k] - $s1[$k]; if ($dv -ne 0) { W ("{0} {1}" -f $k, $dv) } }
  W '=== thread cpu delta (top 8)'
  $rows = foreach ($id in $t2.Keys) { [pscustomobject]@{ Id = $id; D = $t2[$id] - $t1[$id]; Name = [Th4]::Name($id) } }
  $top = $rows | Sort-Object D -Descending | Select-Object -First 8
  foreach ($r in $top) { W ("tid={0} d={1:N2}s name={2}" -f $r.Id, $r.D, $r.Name) }
  $mods = $script:proc.Modules | Sort-Object { [uint64]$_.BaseAddress }
  foreach ($r in ($top | Select-Object -First 3)) {
    W "=== rip samples tid=$($r.Id) name=$($r.Name)"
    for ($i = 0; $i -lt 6; $i++) {
      $s = [Th4]::Sample([int]$r.Id)
      if ($null -eq $s) { W 'sample failed'; continue }
      $m = $mods | Where-Object { [uint64]$_.BaseAddress -le $s[0] -and ([uint64]$_.BaseAddress + $_.ModuleMemorySize) -gt $s[0] } | Select-Object -First 1
      $nm = if ($m) { $m.ModuleName } else { '?' }; $off = if ($m) { $s[0] - [uint64]$m.BaseAddress } else { 0 }
      W ('rip={0:X} {1}+0x{2:X} rsp={3:X}' -f $s[0], $nm, $off, $s[1])
      Start-Sleep -Milliseconds 120
    }
  }
  W "serial grew during capture so far: $(SerLen) vs $sl0"
  Copy-Item "$VmDir\Logs\VBox.log" "$d\VBox-live.log" -ErrorAction SilentlyContinue
  W 'VBox.log copied (live)'
  Vb @('controlvm', $Vm, 'screenshotpng', "$d\screen.png") 15 | Out-Null
  foreach ($i in 'apic', 'apictimer', 'timers', 'ioapic') {
    W "=== info $i (before this, serial=$(SerLen))"
    $r = Vb @('debugvm', $Vm, 'info', $i) 20
    Add-Content $o $r
  }
  W "serial after info: $(SerLen)"
  Start-Sleep -Seconds 5
  W "serial +5s: $(SerLen)"
  Copy-Item $ser "$d\serial-b.txt" -ErrorAction SilentlyContinue
  Copy-Item "$VmDir\Logs\VBox.log" "$d\VBox-after.log" -ErrorAction SilentlyContinue
  W 'done'
}

$script:kicks = 0
function Kick {
  $script:kicks++
  $n = $script:kicks; $s0 = SerLen; $t0 = Get-Date
  Vb @('debugvm', $Vm, 'info', 'apictimer') 20 | Out-Null
  $ok = $false
  for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 250; if ((SerLen) -gt $s0) { $ok = $true; break } }
  L ("KICK {0} unfroze={1} after={2:N1}s ser {3}->{4} cpu={5:N0}" -f $n, $ok, ((Get-Date) - $t0).TotalSeconds, $s0, (SerLen), $script:cpuNow)
  $script:freeze = $false; $script:lastLen = SerLen; $script:lastGrow = Get-Date
}
L "=== start mods=[$Mods] flood=$Flood minutes=$Minutes"
Vb @('controlvm', $Vm, 'poweroff') 20 | Out-Null
Start-Sleep 4
$vp = VmPid; if ($vp -gt 0) { Stop-Process -Id $vp -Force -ErrorAction SilentlyContinue; Start-Sleep 3 }
Vb @('modifyvm', $Vm, '--audio-driver', 'none', '--cpus', '3', '--graphicscontroller', 'vmsvga', '--vram', '128', '--paravirt-provider', 'default', '--mouse', 'ps2', '--usb-ohci', 'off', '--usb-xhci', 'off', '--nested-hw-virt', 'off', '--hwvirtex', 'on') 15 | Out-Null
if ($Mods) { $r = Vb (@('modifyvm', $Vm) + ($Mods -split ' ')) 15; if ($r -match 'error|Error') { L "modifyvm: $r" } }
Remove-Item $ser -Force -ErrorAction SilentlyContinue
$t0boot = Get-Date
Vb @('startvm', $Vm, '--type', 'headless') 40 | Out-Null
$ok = $false
for ($i = 0; $i -lt 100; $i++) { Start-Sleep 1; if ((Test-Path $ser) -and (Select-String -Path $ser -Pattern 'glogin: first up' -Quiet -ErrorAction SilentlyContinue)) { $ok = $true; break } }
if (-not $ok) { L 'RESULT start-failed (no login)'; exit 1 }
Start-Sleep 2; Login
$q = 0; $prev = -1
for ($i = 0; $i -lt 70; $i++) { Start-Sleep 1; $n = SerLen; if ($n -eq $prev) { $q++ } else { $q = 0 }; $prev = $n; if ($q -ge 5) { break } }
$vp = VmPid
$proc = Get-Process -Id $vp -ErrorAction SilentlyContinue
if (-not $proc) { L 'RESULT start-failed'; exit 1 }
$script:proc = $proc
L "booted pid=$vp ser=$(SerLen) bootsec=$([int]((Get-Date) - $t0boot).TotalSeconds) lag=$(Stats)"

$vbox = New-Object -ComObject VirtualBox.VirtualBox; $s = New-Object -ComObject VirtualBox.Session
$vbox.FindMachine($Vm).LockMachine($s, 1)
$mouse = $s.Console.Mouse
$end = (Get-Date).AddMinutes($Minutes); $cyc = 0
$script:cpuT0 = $proc.TotalProcessorTime.TotalSeconds; $script:cpuW0 = Get-Date
$script:lastLen = SerLen; $script:lastGrow = Get-Date; $script:armed = $true
$doMouse = ($Flood -eq 'full' -or $Flood -eq 'mouse'); $doKeys = ($Flood -eq 'full' -or $Flood -eq 'winesc')
try {
  while ((Get-Date) -lt $end) {
    $cyc++
    if ($doMouse) {
      $mouse.PutMouseEvent(0, 0, 0, 0, 0)
      for ($i = 0; $i -lt 40; $i++) { $mouse.PutMouseEvent([int](12 * [math]::Sign([math]::Sin($i / 5.0))), [int](6 * [math]::Sign([math]::Cos($i / 7.0))), 0, 0, 0); Start-Sleep -Milliseconds 8 }
      $mouse.PutMouseEvent(0, 0, 0, 0, 1); Start-Sleep -Milliseconds 80; $mouse.PutMouseEvent(0, 0, 0, 0, 0)
      Watch
      Nap 0.6
    }
    if ($doKeys) {
      Scan @('5B', 'DB'); Nap 2; Scan @('01', '81'); Nap 1; Scan @('38', '0F', '8F', 'B8'); Nap 2; Scan @('38', '0F', '0F', '8F', '8F', 'B8'); Nap 2
    } elseif (-not $doMouse) { Nap 9 } else { Nap 4 }
    if ($script:freeze) { Kick }
    if ($cyc % 3 -eq 0) { L ("cyc={0} ser={1} cpu={2:N0}% age={3:N0}s" -f $cyc, (SerLen), $script:cpuNow, ((Get-Date) - $script:lastGrow).TotalSeconds) }
  }
} finally { try { $s.UnlockMachine() } catch {} }
if ($script:freeze) { Kick }
$dur = [math]::Round(((Get-Date) - $end.AddMinutes(-$Minutes)).TotalMinutes, 1)
if ($false) {
  L "FREEZE detected cyc=$cyc ser=$(SerLen) cpu=$([int]$script:cpuNow) -> LiveCap"
  LiveCap
  L "RESULT FREEZE after $dur min cyc=$cyc flood=$Flood mods=[$Mods]"
  Copy-Item $ser "C:\Users\justi\vbl\abser4-$Label-freeze-serial.txt" -ErrorAction SilentlyContinue
} else { L "RESULT kicks=$($script:kicks) endser=$(SerLen) $dur min cyc=$cyc flood=$Flood mods=[$Mods]" }
$vp = VmPid
Vb @('controlvm', $Vm, 'poweroff') 20 | Out-Null
Start-Sleep 4
if ($vp -gt 0) { Stop-Process -Id $vp -Force -ErrorAction SilentlyContinue }
L 'END'

