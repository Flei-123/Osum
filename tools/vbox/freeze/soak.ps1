param(
  [string]$Vm = 'OrientOS-aud',
  [string]$Label = 'S',
  [int]$Boots = 10,
  [double]$Minutes = 1,
  [string]$Mods = '',
  [string]$Dir = 'C:\Users\justi\vbl',
  [string]$KickLog = 'C:\Users\justi\vbl\kickwatch.log',
  [int]$BootWait = 55,
  [int]$LoginWait = 40
)
if ($Vm -eq 'OrientOS') { throw 'refusing to touch the boss VM' }
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$Out = Join-Path $Dir 'soak.log'
$Ser = Join-Path $Dir "aud-serial.txt"
function L([string]$t) { Add-Content $Out ("{0} [{1}] {2}" -f (Get-Date -f 'HH:mm:ss'), $Label, $t) }
function Vb([string[]]$a, [int]$to = 25) {
  $psi = New-Object Diagnostics.ProcessStartInfo $VB
  $psi.Arguments = ($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($to * 1000)) { try { $p.Kill() } catch {}; return 'TIMEOUT' }
  return $o.Result + $e.Result
}
function Scan([string[]]$c) { Vb (@('controlvm', $Vm, 'keyboardputscancode') + $c) 10 | Out-Null }
$MK = @{ a='1E'; e='12'; k='25'; n='31'; o='18'; r='13'; s='1F'; t='14'; w='11' }
function Login { foreach ($ch in 'startkennwort'.ToCharArray()) { $m = $MK["$ch"]; $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80); Scan @($m, $b); Start-Sleep -Milliseconds 120 }; Start-Sleep -Milliseconds 300; Scan @('1C', '9C') }
function VmPid { $v = New-Object -ComObject VirtualBox.VirtualBox; return [int]$v.FindMachine($Vm).SessionPID }
function SerLen { (Get-Item $Ser -ErrorAction SilentlyContinue).Length }
function KickLines([DateTime]$since) {
  if (-not (Test-Path $KickLog)) { return @() }
  $cut = $since.ToString('yyyy-MM-dd HH:mm:ss')
  return @(Get-Content $KickLog | Where-Object { $_.Substring(0, 19) -ge $cut -and $_ -like "*[[]$Vm[]]*" })
}

function Boot([int]$n) {
  Vb @('controlvm', $Vm, 'poweroff') 20 | Out-Null
  Start-Sleep 5
  $vp = VmPid; if ($vp -gt 0) { Stop-Process -Id $vp -Force -ErrorAction SilentlyContinue; Start-Sleep 3 }
  Vb @('modifyvm', $Vm, '--audio-driver', 'none', '--cpus', '3', '--graphicscontroller', 'vmsvga', '--vram', '128', '--paravirt-provider', 'default', '--mouse', 'ps2', '--usb-ohci', 'off', '--nested-hw-virt', 'off', '--hwvirtex', 'on') 15 | Out-Null
  if ($Mods) { Vb (@('modifyvm', $Vm) + ($Mods -split ' ')) 15 | Out-Null }
  Remove-Item $Ser -Force -ErrorAction SilentlyContinue
  $t0 = Get-Date
  Vb @('startvm', $Vm, '--type', 'headless') 40 | Out-Null
  Start-Sleep $BootWait; Login; Start-Sleep $LoginWait
  $vp = VmPid
  $proc = Get-Process -Id $vp -ErrorAction SilentlyContinue
  if (-not $proc) { L "boot $n RESULT start-failed"; return 'start-failed' }
  $vbox = New-Object -ComObject VirtualBox.VirtualBox; $s = New-Object -ComObject VirtualBox.Session
  $vbox.FindMachine($Vm).LockMachine($s, 1)
  $mouse = $s.Console.Mouse
  $end = (Get-Date).AddMinutes($Minutes); $cyc = 0; $noGrow = 0; $freeze = $false; $lastSer = SerLen
  $c0 = $proc.TotalProcessorTime.TotalSeconds; $tw = Get-Date
  try {
    while ((Get-Date) -lt $end -and -not $freeze) {
      $cyc++
      $mouse.PutMouseEvent(0, 0, 0, 0, 0)
      for ($i = 0; $i -lt 40; $i++) { $mouse.PutMouseEvent([int](12 * [math]::Sign([math]::Sin($i / 5.0))), [int](6 * [math]::Sign([math]::Cos($i / 7.0))), 0, 0, 0); Start-Sleep -Milliseconds 8 }
      $mouse.PutMouseEvent(0, 0, 0, 0, 1); Start-Sleep -Milliseconds 80; $mouse.PutMouseEvent(0, 0, 0, 0, 0)
      Start-Sleep -Milliseconds 600
      Scan @('5B', 'DB'); Start-Sleep 2; Scan @('01', '81'); Start-Sleep 1; Scan @('38', '0F', '8F', 'B8'); Start-Sleep 2; Scan @('38', '0F', '0F', '8F', '8F', 'B8'); Start-Sleep 2
      $proc.Refresh(); $now = Get-Date
      $cpu = 100 * ($proc.TotalProcessorTime.TotalSeconds - $c0) / ($now - $tw).TotalSeconds
      $c0 = $proc.TotalProcessorTime.TotalSeconds; $tw = $now
      $sl = SerLen
      if ($sl -eq $lastSer) { $noGrow++ } else { $noGrow = 0 }
      $lastSer = $sl
      if ($noGrow -ge 4 -and $cpu -gt 70) { $freeze = $true }
      if ($noGrow -ge 8) { $freeze = $true }
    }
  } finally { try { $s.UnlockMachine() } catch {} }
  $lines = KickLines $t0
  $stalls = @($lines | Where-Object { $_ -like '*STALL detected*' }).Count
  $healed = @($lines | Where-Object { $_ -like '*HEALED*' })
  $giveup = @($lines | Where-Object { $_ -like '*GIVEUP*' }).Count
  $times = @($healed | ForEach-Object { if ($_ -match 'total=([\d.,]+)s') { [double]($Matches[1] -replace ',', '.') } })
  $maxHeal = if ($times.Count) { ($times | Measure-Object -Maximum).Maximum } else { 0 }
  $res = if ($freeze) { 'FREEZE' } else { 'OK' }
  L ("boot {0} RESULT {1} cyc={2} stalls={3} healed={4} giveup={5} maxHealSec={6:N1} mods=[{7}]" -f $n, $res, $cyc, $stalls, $healed.Count, $giveup, $maxHeal, $Mods)
  if ($freeze) { Copy-Item $Ser (Join-Path $Dir "soak-$Label-$n-freeze-serial.txt") -ErrorAction SilentlyContinue }
  return $res
}

L "=== start vm=$Vm boots=$Boots minutes=$Minutes mods=[$Mods]"
for ($n = 1; $n -le $Boots; $n++) { [void](Boot $n) }
Vb @('controlvm', $Vm, 'poweroff') 20 | Out-Null
L '=== done'
