param([int]$Sec = 20)
# CPU of every VirtualBoxVM/VBoxHeadless process (percent of one host core) over $Sec seconds; the boss VM shows up as its own pid
$names = 'VirtualBoxVM','VBoxHeadless'
$a = @{}; Get-Process $names -ErrorAction SilentlyContinue | ForEach-Object { $a[$_.Id] = $_.CPU }
$t1 = Get-Date
Start-Sleep -Seconds $Sec
$s = ((Get-Date) - $t1).TotalSeconds
Get-Process $names -ErrorAction SilentlyContinue | ForEach-Object {
  if ($a.ContainsKey($_.Id)) { "pid {0} ({1}): {2:N1} % of one host core over {3:N1}s" -f $_.Id, $_.ProcessName, (100 * ($_.CPU - $a[$_.Id]) / $s), $s }
}
