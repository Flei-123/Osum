# SPDX-License-Identifier: GPL-2.0-only
# tools/bench/vbench.ps1 -- laptop half of the OrientOS VirtualBox benchmark (PowerShell 5.1, device HOLO-LAPTOP-3).
# Needs: vbtest.ps1 installed, the image already fetched (`vbtest.ps1 fetch ...`), odb token + odbc client installed (see tools/vbox/README.md).
# Only ever touches the VM `OrientOS-Test` (vbtest.ps1 refuses the boss VM). Run it in the BACKGROUND (CIM create), the run takes minutes:
#   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\justi\vbl\vbench.ps1 -Out C:\Users\justi\vbl\bench.out'}
# Prints lines `BENCHVBOX {json}` (one per round) to -Out; the server side (tools/bench/vbox.sh parse) merges them to the median.
param([int]$Rounds = 1, [int]$Settle = 20, [int]$IdleMs = 20000, [string]$Out = 'C:\Users\justi\vbl\bench.out')
$ErrorActionPreference = 'Continue'
$vt = 'C:\Users\justi\vbl\vbtest.ps1'
function V([string[]]$a) { (& powershell -NoProfile -ExecutionPolicy Bypass -File $vt @a 2>&1 | Out-String) }
function Log([string]$m) { Add-Content -Path $Out -Value $m }
Set-Content -Path $Out -Value ("INFO: vbench start " + (Get-Date -Format s))
for ($r = 1; $r -le $Rounds; $r++) {
    $res = [ordered]@{}
    V @('mkvm') | Out-Null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    V @('start', 'headless') | Out-Null
    $o = V @('odbwait', '240')
    if ($o -notmatch 'OK: odb agent up') { Log "FAIL: round $r agent never answered"; V @('cleanup') | Out-Null; continue }
    $res['vbox.boot_agent_ms'] = [int]$sw.ElapsedMilliseconds
    $sw.Restart()
    $o = V @('odblogin', '120')
    if ($o -match 'OK: odb login') { $res['vbox.login_to_desktop_ms'] = [int]$sw.ElapsedMilliseconds } else { Log "INFO: round $r login failed" }
    Start-Sleep -Seconds $Settle
    $o = V @('odbidle', "$IdleMs")
    $m = [regex]::Match($o, 'idle_pct=(\d+)'); if ($m.Success) { $res['idle.cpu_pct'] = 100 - [int]$m.Groups[1].Value }
    $mt = [regex]::Match($o, 'mem_total_kb=(\d+)'); $mf = [regex]::Match($o, 'mem_free_kb=(\d+)')
    if ($mt.Success -and $mf.Success) { $res['mem.total_mb'] = [math]::Round([int64]$mt.Groups[1].Value / 1024, 1); $res['mem.idle_used_mb'] = [math]::Round(([int64]$mt.Groups[1].Value - [int64]$mf.Groups[1].Value) / 1024, 1) }
    $o = V @('idle', '20', '3')
    $mi = [regex]::Match($o, 'idle min ([\d.,]+) %'); if ($mi.Success) { $res['vbox.host_cpu_pct'] = [double]($mi.Groups[1].Value -replace ',', '.') }
    $o = V @('odb', 'exec', 'bench', '--json')
    $b = [regex]::Match($o, 'BENCHJSON (\{.*\})'); if ($b.Success) { $res['_guest'] = $b.Groups[1].Value }
    V @('cleanup') | Out-Null
    $json = ($res.GetEnumerator() | Where-Object { $_.Key -ne '_guest' } | ForEach-Object { '"' + $_.Key + '":' + ([string]$_.Value -replace ',', '.') }) -join ','
    Log ('BENCHVBOX {' + $json + '}')
    if ($res.Contains('_guest')) { Log ('BENCHJSON ' + $res['_guest']) }
}
Log ("INFO: vbench done " + (Get-Date -Format s))
