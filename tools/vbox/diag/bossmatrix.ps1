param([int]$Boots = 3, [int]$Samples = 4, [int]$Sec = 15, [string]$Name = 'OrientOS', [string]$Only = '', [switch]$Gui)
# r1268 step 3: VM-setting matrix on the boss VM $Name (laptop, PowerShell 5.1). Unattended; start in background
# (Invoke-CimMethod Win32_Process Create) and poll C:\Users\justi\vbl\bossmatrix.log.
# For every config: power off, reset to BASE, apply the config's modifyvm/extradata args, $Boots boots x $Samples samples of $Sec s.
# Per sample: host CPU % of the VM process (SessionPID) -> BURN if > 90 % of one core. Result per config: burn boots / boots.
# Only the VM $Name is touched. At the end the ORIGINAL settings (bossmatrix-orig-*.txt dump) are restored via BASE + --cpus 1.
# Hyper-V on the host is never touched.
$ErrorActionPreference = 'Continue'
$R = 'C:\Users\justi\vbl'; $LOGF = "$R\bossmatrix.log"; $VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function Log($m) { Add-Content $LOGF ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Vb { param([string[]]$a) & $VB @a 2>&1 }
function State { $o = Vb @('showvminfo', $Name, '--machinereadable'); foreach ($ln in $o) { if ($ln -match '^VMState="(.+)"') { return $Matches[1] } }; return '?' }
function VmProcess { $v = New-Object -ComObject VirtualBox.VirtualBox; $p = [int]$v.FindMachine($Name).SessionPID; if ($p -le 0) { return $null }; return Get-Process -Id $p -ErrorAction SilentlyContinue }
function Scan([string[]]$c) { Vb (@('controlvm', $Name, 'keyboardputscancode') + $c) | Out-Null }
$MK = @{ a='1E'; e='12'; k='25'; n='31'; o='18'; r='13'; s='1F'; t='14'; w='11' }
function TypeWord([string]$w) { foreach ($ch in $w.ToCharArray()) { $m = $MK["$ch"]; $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80); Scan @($m, $b); Start-Sleep -Milliseconds 200 } }
function Login { TypeWord 'startkennwort'; Start-Sleep -Milliseconds 300; Scan @('1C', '9C') }
function AppStart { Scan @('1D', '2A', '14', '94', 'AA', '9D') }
function PowerOff {
  $s = State
  if ($s -eq 'running' -or $s -eq 'paused') {
    Vb @('controlvm', $Name, 'acpipowerbutton') | Out-Null
    for ($i = 0; $i -lt 15 -and (State) -ne 'poweroff'; $i++) { Start-Sleep -Seconds 2 }
    if ((State) -ne 'poweroff') { Vb @('controlvm', $Name, 'poweroff') | Out-Null; Start-Sleep -Seconds 5 }
  }
}
# BASE = known neutral state; configs then change ONE thing (or a few) against it
$BASE = @('--cpus', '1', '--paravirt-provider', 'default', '--x2apic', 'off', '--ioapic', 'on', '--hpet', 'off', '--nested-paging', 'on', '--large-pages', 'on')
$BASEX = @('VBoxInternal/NEM/UseRing0Runloop')   # extradata keys reset (deleted) per config
# name -> @{ m = modifyvm args; x = @(key,value,...) extradata }
$CFG = [ordered]@{
  'base'       = @{ m = @() }
  'pv_none'    = @{ m = @('--paravirt-provider', 'none') }
  'pv_kvm'     = @{ m = @('--paravirt-provider', 'kvm') }
  'pv_hyperv'  = @{ m = @('--paravirt-provider', 'hyperv') }
  'pv_minimal' = @{ m = @('--paravirt-provider', 'minimal') }
  'runloop0'   = @{ m = @(); x = @('VBoxInternal/NEM/UseRing0Runloop', '0') }
  'runloop1'   = @{ m = @(); x = @('VBoxInternal/NEM/UseRing0Runloop', '1') }
  'x2apic'     = @{ m = @('--x2apic', 'on') }
  'hpet_on'    = @{ m = @('--hpet', 'on') }
  'audio_off'  = @{ m = @('--audio-enabled', 'off') }
  'gfx_vboxvga'= @{ m = @('--graphicscontroller', 'vboxvga') }
  'chipset_ich9'= @{ m = @('--chipset', 'ich9') }
  'np_off'     = @{ m = @('--nested-paging', 'off') }
  'lp_off'     = @{ m = @('--large-pages', 'off') }
  'cpus2'      = @{ m = @('--cpus', '2') }
}
function Apply([string]$k) {
  $c = $CFG[$k]
  Log ("modifyvm base : " + ((Vb (@('modifyvm', $Name) + $BASE)) -join ' '))
  foreach ($key in $BASEX) { Vb @('setextradata', $Name, $key) | Out-Null }
  if ($c.m.Count -gt 0) { Log ("modifyvm $k : " + ((Vb (@('modifyvm', $Name) + $c.m)) -join ' ')) }
  if ($c.x) { for ($i = 0; $i -lt $c.x.Count; $i += 2) { Vb @('setextradata', $Name, $c.x[$i], $c.x[$i + 1]) | Out-Null; Log ("extradata " + $c.x[$i] + "=" + $c.x[$i + 1]) } }
}
function Boot-Measure([string]$tag) {
  $type = if ($Gui) { 'gui' } else { 'headless' }
  Vb @('startvm', $Name, '--type', $type) | Select-Object -Last 1 | ForEach-Object { Log "$tag $_" }
  Start-Sleep -Seconds 50; Login; Start-Sleep -Seconds 25; AppStart; Start-Sleep -Seconds 10
  $pa = VmProcess; $ta = if ($pa) { $pa.TotalProcessorTime.TotalSeconds } else { 0 }; $hot = 0; $vals = @()
  for ($k = 1; $k -le $Samples; $k++) {
    Start-Sleep -Seconds $Sec; $pb = VmProcess; $tb = if ($pb) { $pb.TotalProcessorTime.TotalSeconds } else { 0 }
    $h = 100 * ($tb - $ta) / $Sec; $ta = $tb; $vals += ('{0:N0}' -f $h); if ($h -gt 90) { $hot++ }
  }
  $res = if ($hot -ge [Math]::Max(2, [int]($Samples / 2))) { 'BURN' } else { 'OK' }
  Log ("{0} host%={1} {2}" -f $tag, ($vals -join ','), $res)
  return $res
}
Log "=== start boots=$Boots samples=$Samples sec=$Sec only='$Only'"
Vb @('showvminfo', $Name, '--machinereadable') | Set-Content "$R\bossmatrix-orig-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
$sum = @()
foreach ($k in $CFG.Keys) {
  if ($Only -and (($Only -split ',') -notcontains $k)) { continue }
  PowerOff; Apply $k
  $b = 0; $n = 0
  for ($i = 1; $i -le $Boots; $i++) { $r = Boot-Measure "$k#$i"; $n++; if ($r -eq 'BURN') { $b++ }; PowerOff }
  Log ("RESULT $k burn_boots=$b/$n"); $sum += "$k=$b/$n"
}
PowerOff; Apply 'base'
Log ("=== SUMMARY " + ($sum -join ' '))
Log 'ALLDONE (VM off, settings = BASE with 1 vCPU)'
