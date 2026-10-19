param([int]$Sec = 5)
# per-thread CPU of the busiest VBoxHeadless process (the headless test VM): which vCPU/EMT/device thread burns the host core
$p = Get-Process VBoxHeadless | Sort-Object CPU -Descending | Select-Object -First 1
$a = @{}; foreach ($t in $p.Threads) { $a[$t.Id] = $t.TotalProcessorTime.TotalSeconds }
$t1 = Get-Date; Start-Sleep -Seconds $Sec; $p.Refresh(); $s = ((Get-Date) - $t1).TotalSeconds
"pid {0} threads {1}" -f $p.Id, $p.Threads.Count
$p.Threads | ForEach-Object { if ($a.ContainsKey($_.Id)) { [pscustomobject]@{ id = $_.Id; pct = 100 * ($_.TotalProcessorTime.TotalSeconds - $a[$_.Id]) / $s } } } | Sort-Object pct -Descending | Select-Object -First 8 | ForEach-Object { "tid {0}: {1:N1} %" -f $_.id, $_.pct }
