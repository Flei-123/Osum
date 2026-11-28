param(
  [string]$Vm = 'OrientOS-aud',
  [int]$Minutes = 60,
  [double]$CpuLimit = 85,
  [int]$ExitLimit = 50,
  [int]$Windows = 2,
  [double]$Step = 1.5,
  [string]$Log = 'C:\Users\justi\vbl\kickwatch.log'
)
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function L($t) { Add-Content $Log ("{0} [{1}] {2}" -f (Get-Date -f HH:mm:ss.fff), $Vm, $t) }
function Vb([string[]]$a, [int]$to = 20) {
  $p = Start-Process -FilePath $VB -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\kwo.txt" -RedirectStandardError "$env:TEMP\kwe.txt"
  if (-not $p.WaitForExit($to * 1000)) { try { $p.Kill() } catch {}; return 'TIMEOUT' }
  return ((Get-Content "$env:TEMP\kwo.txt" -Raw) + (Get-Content "$env:TEMP\kwe.txt" -Raw))
}
function ExitSum {
  $s = Vb @('debugvm', $Vm, 'statistics', '--pattern=/NEM/CPU*/Exit*') 10
  if ($s -eq 'TIMEOUT') { return -1 }
  $sum = 0.0
  foreach ($m in [regex]::Matches($s, 'c="(\d+)"[^>]*name="/NEM/CPU\d+/Exit')) { $sum += [double]$m.Groups[1].Value }
  return $sum
}
$vbox = New-Object -ComObject VirtualBox.VirtualBox
$end = (Get-Date).AddMinutes($Minutes)
$bad = 0; $kicks = 0; $prevCpu = $null; $prevExit = $null; $prevT = $null; $prevPid = 0
L "start cpuLimit=$CpuLimit exitLimit=$ExitLimit windows=$Windows step=$Step"
while ((Get-Date) -lt $end) {
  Start-Sleep -Milliseconds ([int]($Step * 1000))
  $vmPid = 0
  try { $vmPid = [int]$vbox.FindMachine($Vm).SessionPID } catch {}
  if ($vmPid -le 0) { $prevCpu = $null; $bad = 0; continue }
  $p = Get-Process -Id $vmPid -ErrorAction SilentlyContinue
  if (-not $p) { $prevCpu = $null; $bad = 0; continue }
  $cpu = $p.TotalProcessorTime.TotalSeconds; $ex = ExitSum; $now = Get-Date
  if ($vmPid -ne $prevPid -or $null -eq $prevCpu -or $ex -lt 0) { $prevPid = $vmPid; $prevCpu = $cpu; $prevExit = $ex; $prevT = $now; continue }
  $dt = ($now - $prevT).TotalSeconds
  $pct = 100 * ($cpu - $prevCpu) / $dt; $dEx = $ex - $prevExit
  $prevCpu = $cpu; $prevExit = $ex; $prevT = $now
  if ($pct -gt $CpuLimit -and $dEx -lt $ExitLimit) { $bad++ } else { $bad = 0 }
  if ($bad -ge $Windows) {
    $kicks++
    $r = Vb @('debugvm', $Vm, 'info', 'apictimer') 20
    L ("KICK {0} cpu={1:N0}% exits={2} window={3:N1}s result={4}" -f $kicks, $pct, $dEx, $dt, $(if ($r -eq 'TIMEOUT') { 'TIMEOUT' } else { 'ok' }))
    $bad = 0; $prevCpu = $null
  }
}
L "end kicks=$kicks"
