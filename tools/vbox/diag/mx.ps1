param([Parameter(Mandatory)][string]$Name, [string]$Extra = '', [string]$Xdata = '', [int]$Cpus = 3, [int]$Cycles = 3,
      [int]$Settle = 30, [int]$Samples = 8, [int]$Sec = 15)
# Burn matrix runner (laptop, PowerShell 5.1). One extra test VM "$Name" (never the boss VM), $Cycles fresh boots.
# Per cycle: mkvm (stage\o.img, VBL_EXTRA = extra modifyvm args, VBL_XDATA = extradata k=v;k=v), start headless, login by keyboard,
# then $Samples samples of $Sec s from `debugvm statistics`: per vCPU share of "Other" time (EMT neither executing nor halted =
# the burn signature, r1268) and growth of the TM virtual-sync lag. Log: C:\Users\justi\vbl\mx-<Name>.log
# Start in the background: Invoke-CimMethod Win32_Process Create (survives the helper), poll the log.
$ErrorActionPreference = 'Continue'
$R = 'C:\Users\justi\vbl'; $L = "$R\mx-$Name.log"; $VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function Log($m) { Add-Content $L ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Vt { param([string[]]$a) & powershell -NoProfile -ExecutionPolicy Bypass -File "$R\vbtest.ps1" @a 2>&1 }
function Snap {
  $h = @{}
  $o = & $VB debugvm $Name statistics --pattern '/TM/CPU/*|/TM/VirtualSync/*' 2>&1
  foreach ($l in $o) { if ($l -match '(?:c|val)="(\d+)".*name="([^"]+)"') { $h[$Matches[2]] = [int64]$Matches[1] } }   # <Counter c=..> or <U64 val=..>
  return $h
}
Log "start name=$Name extra='$Extra' xdata='$Xdata' cpus=$Cpus cycles=$Cycles"
for ($c = 1; $c -le $Cycles; $c++) {
  $env:VBL_VM = $Name; $env:VBL_MEM = '1536'; $env:VBL_ODB = '0'; $env:VBL_SERIAL = '0'; $env:VBL_CPUS = "$Cpus"; $env:VBL_EXTRA = $Extra; $env:VBL_XDATA = $Xdata
  Vt @('mkvm') | Select-Object -Last 1 | ForEach-Object { Log "c$c $_" }
  Vt @('start', 'headless') | Select-Object -Last 1 | ForEach-Object { Log "c$c $_" }
  Start-Sleep -Seconds 45
  Vt @('login') | Select-Object -Last 1 | ForEach-Object { Log "c$c $_" }
  Start-Sleep -Seconds $Settle
  $burn = 0; $a = Snap
  function HostCpu { $q = Get-CimInstance Win32_Process -Filter "Name='VBoxHeadless.exe'" | Where-Object { $_.CommandLine -match "--comment $Name" } | Select-Object -First 1; if ($q) { (Get-Process -Id $q.ProcessId -ErrorAction SilentlyContinue).CPU } else { 0 } }
  $h0 = HostCpu
  for ($k = 1; $k -le $Samples; $k++) {
    Start-Sleep -Seconds $Sec; $b = Snap; $t = $Sec * 1e9
    $parts = @()
    foreach ($i in 0..($Cpus - 1)) {
      $n = '{0:D2}' -f $i; $ko = "/TM/CPU/$n/cNsOther"; $ke = "/TM/CPU/$n/cNsExecuting"
      if ($b.ContainsKey($ko) -and $a.ContainsKey($ko)) { $parts += ("cpu{0} other={1:N0}% exec={2:N0}%" -f $i, (100 * ($b[$ko] - $a[$ko]) / $t), (100 * ($b[$ke] - $a[$ke]) / $t)) }
    }
    $lag = 0; if ($b.ContainsKey('/TM/VirtualSync/CurrentOffset') -and $a.ContainsKey('/TM/VirtualSync/CurrentOffset')) { $lag = ($b['/TM/VirtualSync/CurrentOffset'] - $a['/TM/VirtualSync/CurrentOffset']) / 1e6 / $Sec }
    $h1 = HostCpu; $hp = 100 * ($h1 - $h0) / $Sec; $h0 = $h1; $parts += ('host={0:N0}%' -f $hp)
    $bad = ($hp -ge 85) -or (($parts | Where-Object { $_ -match 'other=(\d+)%' -and [int]$Matches[1] -ge 50 }).Count -gt 0)
    if ($bad -or $lag -gt 200) { $burn++ }
    Log ("c{0} s{1} lag+{2:N0}ms/s {3}{4}" -f $c, $k, $lag, ($parts -join ' | '), $(if ($bad -or $lag -gt 200) { '  <== BURN' } else { '' }))
    $a = $b
  }
  Log ("c{0} RESULT burn_samples={1}/{2} {3}" -f $c, $burn, $Samples, $(if ($burn -ge 3) { 'BURN' } else { 'OK' }))
  & $VB controlvm $Name poweroff 2>&1 | Out-Null; Start-Sleep -Seconds 3
}
Log 'ALLDONE'
