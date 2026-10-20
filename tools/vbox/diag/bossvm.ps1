param([int]$Cpus = 1, [int]$Boots = 4, [int]$Minutes = 30, [int]$Sec = 15, [string]$Name = 'OrientOS',
      [switch]$NoModify, [switch]$Gui)
# r1268 workaround A: boss VM on 1 vCPU, then measure (laptop, PowerShell 5.1). Touches ONLY the boss VM $Name.
# 1) save config dump, power the VM off cleanly (acpi, fallback poweroff), modifyvm --cpus $Cpus (nothing else changed)
# 2) $Boots short boots: start, login by scancodes, app start (ctrl+shift+t), samples of $Sec s
# 3) one long boot: $Minutes minutes of samples every $Sec s
# Per sample: host CPU % of the VM process (SessionPID via COM), per vCPU "Other" share + TM virtual-sync lag growth
# (debugvm statistics). BURN = other >= 50 % or lag > 200 ms/s or host CPU > 90 % of one core.
# Log: C:\Users\justi\vbl\bossvm.log. Start in the background (Win32_Process Create) and poll the log.
$ErrorActionPreference = 'Continue'
$R = 'C:\Users\justi\vbl'; $LOGF = "$R\bossvm.log"; $VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function Log($m) { Add-Content $LOGF ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Vb { param([string[]]$a) & $VB @a 2>&1 }
function State { $o = Vb @('showvminfo', $Name, '--machinereadable'); foreach ($ln in $o) { if ($ln -match '^VMState="(.+)"') { return $Matches[1] } }; return '?' }
function Snap {
  $h = @{}
  foreach ($ln in (Vb @('debugvm', $Name, 'statistics', '--pattern', '/TM/CPU/*|/TM/VirtualSync/*'))) {
    if ($ln -match 'val="(\d+)".*name="([^"]+)"') { $h[$Matches[2]] = [int64]$Matches[1] } }
  return $h
}
function VmProcess { $v = New-Object -ComObject VirtualBox.VirtualBox; $p = [int]$v.FindMachine($Name).SessionPID; if ($p -le 0) { return $null }; return Get-Process -Id $p -ErrorAction SilentlyContinue }
function Scan([string[]]$c) { Vb (@('controlvm', $Name, 'keyboardputscancode') + $c) | Out-Null }
$MK = @{ a='1E'; e='12'; k='25'; n='31'; o='18'; r='13'; s='1F'; t='14'; w='11' }
function TypeWord([string]$w) { foreach ($ch in $w.ToCharArray()) { $m = $MK["$ch"]; $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80); Scan @($m, $b); Start-Sleep -Milliseconds 200 } }
function Login { TypeWord 'startkennwort'; Start-Sleep -Milliseconds 300; Scan @('1C', '9C') }
function AppStart { Scan @('1D', '2A', '14', '94', 'AA', '9D') }   # ctrl+shift+t release in reverse
function PowerOff {
  $s = State; Log "poweroff: state=$s"
  if ($s -eq 'running' -or $s -eq 'paused') {
    Vb @('controlvm', $Name, 'acpipowerbutton') | Out-Null
    for ($i = 0; $i -lt 30 -and (State) -ne 'poweroff'; $i++) { Start-Sleep -Seconds 2 }
    if ((State) -ne 'poweroff') { Log 'acpi shutdown did not finish -> hard poweroff'; Vb @('controlvm', $Name, 'poweroff') | Out-Null; Start-Sleep -Seconds 5 }
  }
  Log "state now=$(State)"
}
function Run-Phase([string]$tag, [int]$Samples) {
  $type = if ($Gui) { 'gui' } else { 'headless' }
  Log "$tag startvm --type $type"; Vb @('startvm', $Name, '--type', $type) | Select-Object -Last 1 | ForEach-Object { Log "$tag $_" }
  Start-Sleep -Seconds 50
  Login; Log "$tag login typed"; Start-Sleep -Seconds 25
  AppStart; Log "$tag app start (ctrl+shift+t)"; Start-Sleep -Seconds 10
  $a = Snap; $pa = VmProcess; $ta = if ($pa) { $pa.TotalProcessorTime.TotalSeconds } else { 0 }; $burn = 0
  for ($k = 1; $k -le $Samples; $k++) {
    Start-Sleep -Seconds $Sec; $b = Snap; $pb = VmProcess; $tb = if ($pb) { $pb.TotalProcessorTime.TotalSeconds } else { 0 }
    $t = $Sec * 1e9; $parts = @(); $bad = $false
    foreach ($i in 0..($Cpus - 1)) {
      $n = '{0:D2}' -f $i; $ko = "/TM/CPU/$n/cNsOther"; $ke = "/TM/CPU/$n/cNsExecuting"
      if ($b.ContainsKey($ko) -and $a.ContainsKey($ko)) {
        $o = 100 * ($b[$ko] - $a[$ko]) / $t; $e = 100 * ($b[$ke] - $a[$ke]) / $t
        $parts += ("cpu{0} other={1:N0}% exec={2:N0}%" -f $i, $o, $e); if ($o -ge 50) { $bad = $true } } }
    $lag = 0; $co = '/TM/VirtualSync/CurrentOffset'
    if ($b.ContainsKey($co) -and $a.ContainsKey($co)) { $lag = ($b[$co] - $a[$co]) / 1e6 / $Sec }
    $host_ = 100 * ($tb - $ta) / $Sec
    if ($bad -or $lag -gt 200 -or $host_ -gt 90) { $burn++; $flag = '  <== BURN' } else { $flag = '' }
    Log ("{0} s{1} host={2:N0}% lag+{3:N0}ms/s {4}{5}" -f $tag, $k, $host_, $lag, ($parts -join ' | '), $flag)
    $a = $b; $ta = $tb
  }
  $res = if ($burn -ge [Math]::Max(3, [int]($Samples / 5))) { 'BURN' } else { 'OK' }
  Log ("{0} RESULT burn_samples={1}/{2} {3}" -f $tag, $burn, $Samples, $res)
  return $res
}
Log "=== start name=$Name cpus=$Cpus boots=$Boots minutes=$Minutes sec=$Sec nomodify=$NoModify"
Vb @('showvminfo', $Name, '--machinereadable') | Set-Content "$R\bossvm-before-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
PowerOff
if (-not $NoModify) { Log ("modifyvm --cpus $Cpus : " + (Vb @('modifyvm', $Name, '--cpus', "$Cpus") -join ' ')) }
foreach ($ln in (Vb @('showvminfo', $Name, '--machinereadable'))) { if ($ln -match '^(cpus|memory|hpet|x2apic|paravirtprovider|nestedpaging|ioapic)=') { Log "cfg $ln" } }
$res = @()
for ($c = 1; $c -le $Boots; $c++) { $res += (Run-Phase "boot$c" 6); PowerOff }
$long = [int]($Minutes * 60 / $Sec)
$res += (Run-Phase 'long' $long)
Log ("=== SUMMARY " + ($res -join ','))
Log 'ALLDONE (VM left running)'
