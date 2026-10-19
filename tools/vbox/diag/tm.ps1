param([string]$Pattern = '/TM/CPU/*|/NEM/*|/PDM/*|/EM/*', [int]$Sec = 10, [int]$Top = 30, [string]$Vm = 'OrientOS-Test')
# Two `debugvm statistics` samples of the test VM; prints the biggest per-second deltas (counters: c=, U64/U32: val=).
# /TM/CPU/NN/cNsExecuting|cNsHalted|cNsOther are ns -> shown as percent of wall time. Use it in the 99 % state: halted% high + executing% low = host-side wake cost.
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function Snap { $h = @{}
  foreach ($p in $Pattern.Split('|')) {
    $o = & $vb debugvm $Vm statistics --pattern $p 2>&1 | Out-String
    foreach ($m in [regex]::Matches($o, '<(?:Counter|Profile|ProfileStart)\s+c="(\d+)"[^>]*name="([^"]+)"')) { $h[$m.Groups[2].Value] = [double]$m.Groups[1].Value }
    foreach ($m in [regex]::Matches($o, '<(?:U64|U32)\s+val="(\d+)"[^>]*name="([^"]+)"')) { $h[$m.Groups[2].Value] = [double]$m.Groups[1].Value }
  }
  return ,$h }
$a = Snap; $t1 = Get-Date; Start-Sleep -Seconds $Sec; $b = Snap; $s = ((Get-Date) - $t1).TotalSeconds
"samples: {0} counters, dt={1:N1}s" -f $b.Count, $s
$rows = $b.GetEnumerator() | ForEach-Object { if ($a.ContainsKey($_.Key)) { $d = $_.Value - $a[$_.Key]; if ($d -gt 0) { [pscustomobject]@{ n = $_.Key; r = $d / $s } } } }
$rows | Where-Object { $_.n -match 'cNs(Executing|Halted|Other)$' } | Sort-Object n | ForEach-Object { "{0,7:N1} % wall  {1}" -f ($_.r / 1e7), $_.n }
$rows | Where-Object { $_.n -notmatch 'cNs|/pct' } | Sort-Object r -Descending | Select-Object -First $Top | ForEach-Object { "{0,12:N0}/s  {1}" -f $_.r, $_.n }
