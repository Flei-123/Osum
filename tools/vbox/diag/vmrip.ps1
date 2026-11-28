param([string]$Vm = 'OrientOS', [int]$N = 40, [string]$Out = 'C:\Users\justi\vbl\vlag\rip.txt')
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$sb = New-Object System.Text.StringBuilder
for ($i = 0; $i -lt $N; $i++) {
  foreach ($c in 0..2) {
    $r = & $VB debugvm $Vm getregisters --cpu=$c rip cs rflags cr3 2>&1 | Out-String
    $v = @{}
    foreach ($m in [regex]::Matches($r, '(\w+)\s*=\s*(0x[0-9a-fA-F]+)')) { $v[$m.Groups[1].Value] = $m.Groups[2].Value }
    [void]$sb.AppendLine(("{0} {1} {2} {3} {4} {5}" -f (Get-Date -f 'HH:mm:ss.fff'), $c, $v['rip'], $v['cs'], $v['rflags'], $v['cr3']))
  }
}
[IO.File]::WriteAllText($Out, $sb.ToString())
"done " + $N
