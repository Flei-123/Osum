param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$ShaXz, [Parameter(Mandatory)][string]$ShaRaw,
      [string]$Tag = 'x', [int]$Settle = 60, [int]$Sec = 15, [int]$Samples = 4, [string]$Serial = '0')
# One A/B round on the laptop: stop test VM, fetch image, swapdisk, start headless (VBL_SERIAL=$Serial), ODB up, login, settle,
# then host CPU of the test VM + boss VM (noise) per sample, guest tick_core/idle_pct and TM/NEM rates. Log: C:\Users\justi\vbl\ab-<Tag>.log
# Start it in the background via Invoke-CimMethod Win32_Process Create (survives the helper) and poll the log.
$ErrorActionPreference = 'Continue'
$env:VBL_SERIAL = $Serial
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
Vt @('odbwait', '60') | ForEach-Object { Log $_ }
Vt @('login') | ForEach-Object { Log $_ }
Log "settle $Settle s"
Start-Sleep -Seconds $Settle
for ($k = 1; $k -le $Samples; $k++) {
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File "$R\allcpu.ps1" -Sec $Sec 2>&1
  $all = ($o | Where-Object { $_ -match '^pid' } | ForEach-Object { ($_.ToString() -replace ' of one host core over.*','') }) -join ' | '
  Log ("sample $k $all")
}
$idle = @(Vt @('odbidle', '10000') | Select-String 'idle_pct|tick_core|uptime')
$idle | ForEach-Object { Log $_.Line }
if ($idle.Count -eq 0) {
  # ODB mute = hang state: save vCPU registers + TM/NEM rates for the post-mortem (resolve rip with nm -n osum.mb)
  Log 'HANG: odbidle returned nothing'
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$R\regs.ps1" -N 3 2>&1 | ForEach-Object { Log $_ }
} else { Log 'ODB-OK' }
& powershell -NoProfile -ExecutionPolicy Bypass -File "$R\tm.ps1" -Sec 10 -Top 14 2>&1 | ForEach-Object { Log $_ }
Log 'done'
