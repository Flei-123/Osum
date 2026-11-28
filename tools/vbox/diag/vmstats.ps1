param([string]$Vm = 'OrientOS', [string]$Pattern = '/NEM/*', [double]$Sec = 5, [int]$Top = 40)
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function Snap {
  $o = & $VB debugvm $Vm statistics --pattern $Pattern | Out-String
  $h = @{}
  foreach ($m in [regex]::Matches($o, '<(Counter|Profile|ProfileInstance)\b([^>]*)/?>')) {
    $at = $m.Groups[2].Value
    $n = [regex]::Match($at, 'name="([^"]+)"').Groups[1].Value
    $c = [regex]::Match($at, '\bc="(\d+)"').Groups[1].Value
    if ($n -and $c) { $h[$n] = [double]$c }
  }
  $h
}
$t0 = Get-Date; $a = Snap
Start-Sleep -Milliseconds ([int]($Sec * 1000))
$b = Snap; $dt = ((Get-Date) - $t0).TotalSeconds
$rows = foreach ($k in $b.Keys) { if ($a.ContainsKey($k)) { [pscustomobject]@{ Name = $k; Total = $b[$k]; PerSec = [math]::Round(($b[$k] - $a[$k]) / $dt, 1) } } }
$rows | Where-Object { $_.PerSec -ne 0 } | Sort-Object { -[math]::Abs($_.PerSec) } | Select-Object -First $Top | Format-Table -AutoSize | Out-String -Width 200
"window=" + [math]::Round($dt, 2) + "s counters=" + $b.Count
