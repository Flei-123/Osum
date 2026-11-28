param([string]$Xhci = 'on', [int]$Boots = 4, [string]$Tag = 'x', [string]$Root = 'C:\VBX\nb', [string]$Vm = 'nb-net')
$env:VBOX_USER_HOME = Join-Path $Root 'home'
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$Ser = Join-Path $Root 'serial.txt'
$Log = Join-Path $Root "loop-$Tag.log"
Remove-Item $Log -Force -ErrorAction SilentlyContinue
$mouse = 'ps2'
if ($Xhci -eq 'on') { $mouse = 'usbtablet' }
for ($i = 1; $i -le $Boots; $i++) {
  & $VB controlvm $Vm poweroff 2>$null | Out-Null
  Start-Sleep 4
  Remove-Item $Ser -Force -ErrorAction SilentlyContinue
  & $VB modifyvm $Vm --usb-xhci $Xhci --mouse $mouse | Out-Null
  & $VB startvm $Vm --type headless | Out-Null
  Start-Sleep 70
  $t = ''
  if (Test-Path $Ser) { $t = Get-Content $Ser -Raw }
  $hang = ([regex]::Matches($t, 'hang: detected')).Count
  $ack = ([regex]::Matches($t, 'dhcp: ack ip')).Count
  $safe = ([regex]::Matches($t, 'SAFE MODE')).Count
  $disc = ([regex]::Matches($t, 'dhcp: discover')).Count
  Add-Content $Log "boot $i xhci=$Xhci hang=$hang safe=$safe discover=$disc ack=$ack"
}
Add-Content $Log 'LOOP DONE'
