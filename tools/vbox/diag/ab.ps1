param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$ShaXz, [Parameter(Mandatory)][string]$ShaRaw,
      [string]$Tag = 'x', [int]$Settle = 60, [int]$Sec = 15, [int]$Samples = 4, [string]$Serial = '0', [string]$Odb = '1')
# One A/B round on the laptop: stop test VM, fetch image, swapdisk, start headless (VBL_SERIAL=$Serial), ODB up, login, settle,
# then host CPU of the test VM + boss VM (noise) per sample, guest tick_core/idle_pct and TM/NEM rates. Log: C:\Users\justi\vbl\ab-<Tag>.log
# Start it in the background via Invoke-CimMethod Win32_Process Create (survives the helper) and poll the log.
$ErrorActionPreference = 'Continue'
$env:VBL_SERIAL = $Serial; $env:VBL_ODB = $Odb
$R = 'C:\Users\justi\vbl'; $S = "$R\vbtest.ps1"; $L = "$R\ab-$Tag.log"
function Vt { param([string[]]$a) & powershell -NoProfile -ExecutionPolicy Bypass -File $S @a 2>&1 }
function Log($m) { Add-Content $L ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
Remove-Item $L -ErrorAction SilentlyContinue
Log 'start'
Vt @('stop') | Out-Null
Vt @('fetch', $Url, $ShaXz, $ShaRaw) | Select-Object -Last 1 | ForEach-Object { Log $_ }
$st = Vt @('status') | Out-String
if ($st -match 'state=') { } 
Vt @('swapdisk') | ForEach-Object { Log $_ }
Vt @('start', 'headless') | ForEach-Object { Log $_ }
$NoOdb = ($env:VBL_ODB -eq '0')   # no COM2 attached: skip the agent, login by keyboard after a fixed boot wait, classify by host CPU only
if ($NoOdb) { Log 'ODB=0 (no uart2)'; Start-Sleep -Seconds 45 } else { Vt @('odbwait', '60') | ForEach-Object { Log $_ } }
Vt @('login') | ForEach-Object { Log $_ }
$testCpu = @()
Log "settle $Settle s"
Start-Sleep -Seconds $Settle
for ($k = 1; $k -le $Samples; $k++) {
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File "$R\allcpu.ps1" -Sec $Sec 2>&1
  $all = ($o | Where-Object { $_ -match '^pid' } | ForEach-Object { ($_.ToString() -replace ' of one host core over.*','') }) -join ' | '
  Log ("sample $k $all")
  # one sample = the busiest VBoxHeadless pid (helper pids of the same VM show 0 %)
  $v = @($o | Where-Object { $_ -match '^pid \d+ \(VBoxHeadless\): ([\d.,]+) %' } | ForEach-Object { [double]($Matches[1] -replace ',', '.') })
  if ($v.Count) { $testCpu += ($v | Measure-Object -Maximum).Maximum }
}
if ($testCpu.Count) { $m = ($testCpu | Measure-Object -Average).Average; Log ("TESTCPU avg {0:N1} % ({1})" -f $m, ($testCpu -join ' ')); if ($m -ge 90) { Log 'BURN: test VM host CPU >= 90 %' } }
if ($NoOdb) { $idle = @('noodb') } else { $idle = @(Vt @('odbidle', '10000') | Select-String 'idle_pct|tick_core|uptime') }
if (-not $NoOdb) { $idle | ForEach-Object { Log $_.Line } }
if ($NoOdb) { Log 'ODB-N/A' } elseif ($idle.Count -eq 0) {
  # ODB mute = hang state: save vCPU registers + TM/NEM rates for the post-mortem (resolve rip with nm -n osum.mb)
  Log 'HANG: odbidle returned nothing'
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$R\regs.ps1" -N 3 2>&1 | ForEach-Object { Log $_ }
} else { Log 'ODB-OK' }
& powershell -NoProfile -ExecutionPolicy Bypass -File "$R\tm.ps1" -Sec 10 -Top 14 2>&1 | ForEach-Object { Log $_ }
Log 'done'
