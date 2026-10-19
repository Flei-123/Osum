param([int]$N = 4, [int]$Ms = 300)
# rip/rsp/cr3/rflags of every vCPU of OrientOS-Test (debugvm getregisters), N rounds. Resolve rip with `nm -n osum.mb` (tools/vbox/diag/README).
$vb = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
for ($k = 0; $k -lt $N; $k++) {
  $line = @()
  foreach ($c in 0..2) {
    $o = & $vb debugvm OrientOS-Test getregisters --cpu $c rip rsp cr3 rflags 2>&1 | Out-String
    $m = [regex]::Matches($o, '(rip|rsp|cr3|rflags)\s*=\s*(0x[0-9a-fA-F]+)')
    $line += ('cpu' + $c + ' ' + (($m | ForEach-Object { $_.Groups[1].Value + '=' + $_.Groups[2].Value }) -join ' '))
  }
  $line -join ' | '
  Start-Sleep -Milliseconds $Ms
}
