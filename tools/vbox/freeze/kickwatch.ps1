param(
  [string[]]$Vm = @(),
  [double]$CpuLimit = 85,
  [double]$ExitRateLimit = 30,
  [double]$Step = 0.5,
  [double]$SampleSeconds = 0.5,
  [int]$MaxKicks = 6,
  [double]$KickGap = 0.4,
  [double]$Cooldown = 1,
  [double]$GiveupBackoff = 20,
  [double]$Minutes = 0,
  [int]$MaxLogBytes = 2000000,
  [string]$Log = 'C:\Users\justi\vbl\kickwatch.log'
)
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$RunningState = 6
$HeartbeatSeconds = 600
$ListRefreshSeconds = 3

$mutex = New-Object System.Threading.Mutex($false, 'Global\OrientOSKickwatch')
if (-not $mutex.WaitOne(0)) { exit 2 }

function L([string]$name, [string]$text) {
  if ((Test-Path $Log) -and (Get-Item $Log).Length -gt $MaxLogBytes) { Move-Item $Log "$Log.old" -Force }
  Add-Content $Log ("{0} [{1}] {2}" -f (Get-Date -f 'yyyy-MM-dd HH:mm:ss.fff'), $name, $text)
}

function Vb([string[]]$a, [int]$timeout = 15) {
  $psi = New-Object Diagnostics.ProcessStartInfo $VB
  $psi.Arguments = ($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync()
  $e = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($timeout * 1000)) { try { $p.Kill() } catch {}; return 'TIMEOUT' }
  return $o.Result + $e.Result
}

function ExitSum([string]$name) {
  $s = Vb @('debugvm', $name, 'statistics', '--pattern=/NEM/CPU*/Exit*') 10
  if ($s -eq 'TIMEOUT') { return -1 }
  $sum = 0.0
  foreach ($m in [regex]::Matches($s, 'c="(\d+)"[^>]*name="/NEM/CPU\d+/Exit')) { $sum += [double]$m.Groups[1].Value }
  return $sum
}

function CpuSeconds([int]$vmPid) {
  $p = Get-Process -Id $vmPid -ErrorAction SilentlyContinue
  if (-not $p) { return -1 }
  return $p.TotalProcessorTime.TotalSeconds
}

function Sample([string]$name, [int]$vmPid) {
  $c0 = CpuSeconds $vmPid; $e0 = ExitSum $name; $t0 = Get-Date
  Start-Sleep -Milliseconds ([int]($SampleSeconds * 1000))
  $c1 = CpuSeconds $vmPid; $e1 = ExitSum $name; $t1 = Get-Date
  if ($c0 -lt 0 -or $c1 -lt 0 -or $e0 -lt 0 -or $e1 -lt 0) { return $null }
  $dt = ($t1 - $t0).TotalSeconds
  return @{ Cpu = 100 * ($c1 - $c0) / $dt; ExitRate = ($e1 - $e0) / $dt }
}

function IsStalled($s) { return ($null -ne $s) -and ($s.Cpu -gt $CpuLimit) -and ($s.ExitRate -lt $ExitRateLimit) }

function Heal([string]$name, [int]$vmPid, [DateTime]$since) {
  for ($k = 1; $k -le $MaxKicks; $k++) {
    $r = Vb @('debugvm', $name, 'info', 'apictimer') 20
    Start-Sleep -Milliseconds ([int]($KickGap * 1000))
    $s = Sample $name $vmPid
    $state = if ($null -eq $s) { 'gone' } elseif (IsStalled $s) { 'stalled' } else { 'flowing' }
    L $name ("KICK {0} result={1} after={2} cpu={3:N0}% exits/s={4:N0}" -f $k, $(if ($r -eq 'TIMEOUT') { 'TIMEOUT' } else { 'ok' }), $state, $(if ($s) { $s.Cpu } else { 0 }), $(if ($s) { $s.ExitRate } else { 0 }))
    if ($state -ne 'stalled') { L $name ("HEALED kicks={0} total={1:N1}s" -f $k, ((Get-Date) - $since).TotalSeconds); return $true }
  }
  L $name ("GIVEUP kicks={0} total={1:N1}s" -f $MaxKicks, ((Get-Date) - $since).TotalSeconds)
  return $false
}

function RunningVms($vbox) {
  $list = @()
  foreach ($m in $vbox.Machines) {
    if ([int]$m.State -ne $RunningState) { continue }
    if ($Vm.Count -gt 0 -and $Vm -notcontains $m.Name) { continue }
    $list += [pscustomobject]@{ Name = $m.Name; Pid = [int]$m.SessionPID }
  }
  return $list
}

$vbox = New-Object -ComObject VirtualBox.VirtualBox
$end = if ($Minutes -gt 0) { (Get-Date).AddMinutes($Minutes) } else { [DateTime]::MaxValue }
$state = @{}
$lastNames = $null; $vms = @(); $lastList = [DateTime]::MinValue; $lastBeat = Get-Date; $kicksTotal = 0; $healed = 0
L '-' "start vm=[$($Vm -join ',')] cpuLimit=$CpuLimit exitRateLimit=$ExitRateLimit step=$Step sample=$SampleSeconds maxKicks=$MaxKicks"
while ((Get-Date) -lt $end) {
  Start-Sleep -Milliseconds ([int]($Step * 1000))
  if (((Get-Date) - $lastList).TotalSeconds -ge $ListRefreshSeconds) {
    try { $vms = @(RunningVms $vbox) } catch { L '-' "list failed: $($_.Exception.Message)"; try { $vbox = New-Object -ComObject VirtualBox.VirtualBox } catch {} }
    $names = ($vms | ForEach-Object { $_.Name }) -join ','
    if ($names -ne $lastNames) { L '-' "vms=[$names]"; $lastNames = $names }
    $lastList = Get-Date
  }
  foreach ($v in $vms) {
    if ($v.Pid -le 0) { continue }
    $cpu = CpuSeconds $v.Pid
    if ($cpu -lt 0) { $state.Remove($v.Name); continue }
    $now = Get-Date
    $prev = $state[$v.Name]
    $state[$v.Name] = @{ Pid = $v.Pid; Cpu = $cpu; Time = $now; Until = if ($prev) { $prev.Until } else { $now } }
    if (-not $prev -or $prev.Pid -ne $v.Pid) { continue }
    if ($now -lt $prev.Until) { continue }
    $pct = 100 * ($cpu - $prev.Cpu) / ($now - $prev.Time).TotalSeconds
    if ($pct -le $CpuLimit) { continue }
    $since = $prev.Time
    $s = Sample $v.Name $v.Pid
    if (-not (IsStalled $s)) { continue }
    L $v.Name ("STALL detected cpu={0:N0}% exits/s={1:N0}" -f $s.Cpu, $s.ExitRate)
    $wasHealed = Heal $v.Name $v.Pid $since
    if ($wasHealed) { $healed++ }
    $kicksTotal++
    $pause = if ($wasHealed) { $Cooldown } else { $GiveupBackoff }
    $state[$v.Name] = @{ Pid = $v.Pid; Cpu = (CpuSeconds $v.Pid); Time = (Get-Date); Until = (Get-Date).AddSeconds($pause) }
  }
  if (((Get-Date) - $lastBeat).TotalSeconds -ge $HeartbeatSeconds) {
    L '-' ("alive vms=[{0}] stalls={1} healed={2}" -f (($vms | ForEach-Object { $_.Name }) -join ','), $kicksTotal, $healed)
    $lastBeat = Get-Date
  }
}
L '-' "end stalls=$kicksTotal healed=$healed"
