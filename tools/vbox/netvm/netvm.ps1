param(
  [Parameter(Position = 0)][string]$Action = 'status',
  [Parameter(Position = 1)][string]$Arg1 = '',
  [Parameter(Position = 2)][string]$Arg2 = '',
  [string]$Root = 'C:\VBX\mx0j',
  [string]$Vm = 'mx0j-net',
  [string]$Nic = '82540EM',
  [string]$NicType = 'nat',
  [int]$Cpus = 3,
  [int]$Mem = 2048
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $Root | Out-Null
$env:VBOX_USER_HOME = Join-Path $Root 'home'
New-Item -ItemType Directory -Force -Path $env:VBOX_USER_HOME | Out-Null
$VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$Img = Join-Path $Root 'o.img'
$Ser = Join-Path $Root 'serial.txt'
$Shots = Join-Path $Root 'shots'
$OutF = Join-Path $Root 'vb.out'
$ErrF = Join-Path $Root 'vb.err'
New-Item -ItemType Directory -Force -Path $Shots | Out-Null

function Vb([string[]]$a, [int]$to = 60) {
  $p = Start-Process -FilePath $VB -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $OutF -RedirectStandardError $ErrF
  if (-not $p.WaitForExit($to * 1000)) { try { $p.Kill() } catch {}; return 'TIMEOUT' }
  return ("$(Get-Content $OutF -Raw)$(Get-Content $ErrF -Raw)")
}

$SC = @{
  'a'='1E';'b'='30';'c'='2E';'d'='20';'e'='12';'f'='21';'g'='22';'h'='23';'i'='17';'j'='24';'k'='25';'l'='26';'m'='32'
  'n'='31';'o'='18';'p'='19';'q'='10';'r'='13';'s'='1F';'t'='14';'u'='16';'v'='2F';'w'='11';'x'='2D';'y'='2C';'z'='15'
  '1'='02';'2'='03';'3'='04';'4'='05';'5'='06';'6'='07';'7'='08';'8'='09';'9'='0A';'0'='0B'
  ' '='39';'.'='34';'/'='35';'-'='35';'='='0D'
}
function Press([string]$m) {
  $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80)
  Vb (@('controlvm', $Vm, 'keyboardputscancode', $m, $b)) 15 | Out-Null
}
function TypeText([string]$t) {
  foreach ($ch in $t.ToCharArray()) {
    $k = "$ch".ToLower()
    if ($k -eq "`n") { Press '1C'; continue }
    if ($k -eq '/') { Vb @('controlvm', $Vm, 'keyboardputscancode', '2A', '08', '88', 'AA') 15 | Out-Null; continue }
    if ($SC.ContainsKey($k)) { Press $SC[$k] }
  }
}

switch ($Action) {
  'prep' {
    $gz = Join-Path $Root 'o.img.gz'
    & curl.exe -sS -f -o $gz $Arg1
    $in = [IO.File]::OpenRead($gz)
    $gs = New-Object IO.Compression.GZipStream($in, [IO.Compression.CompressionMode]::Decompress)
    $out = [IO.File]::Create($Img)
    $gs.CopyTo($out); $out.Close(); $gs.Close(); $in.Close()
    Remove-Item $gz -Force -ErrorAction SilentlyContinue
    "raw sha256 $((Get-FileHash $Img -Algorithm SHA256).Hash.ToLower())"
  }
  'mkvm' {
    Vb @('controlvm', $Vm, 'poweroff') 20 | Out-Null
    Start-Sleep -Seconds 3
    Vb @('unregistervm', $Vm, '--delete') 60 | Out-Null
    $vmRoot = Join-Path $Root 'vms'
    Vb @('createvm', '--name', $Vm, '--ostype', 'Other_64', '--register', '--basefolder', $vmRoot) 60 | Out-Null
    Remove-Item $Ser -Force -ErrorAction SilentlyContinue
    Vb @('modifyvm', $Vm, '--memory', "$Mem", '--vram', '128', '--cpus', "$Cpus", '--graphicscontroller', 'vmsvga', '--firmware', 'efi', '--ioapic', 'on', '--mouse', 'ps2', '--keyboard', 'ps2', '--audio-driver', 'none', '--usb-xhci', 'off', '--nic1', $NicType, '--nic-type1', $Nic, '--cable-connected1', 'on', '--uart1', '0x3F8', '4', '--uart-mode1', 'file', $Ser) 30
    Vb @('storagectl', $Vm, '--name', 'SATA', '--add', 'sata', '--controller', 'IntelAhci') 30 | Out-Null
    $vdi = Join-Path $Root 'run.vdi'
    Remove-Item $vdi -Force -ErrorAction SilentlyContinue
    Vb @('convertfromraw', $Img, $vdi, '--format', 'VDI') 120 | Out-Null
    Vb @('storageattach', $Vm, '--storagectl', 'SATA', '--port', '0', '--device', '0', '--type', 'hdd', '--medium', $vdi) 30
  }
  'start' { Vb @('startvm', $Vm, '--type', 'headless') 60 }
  'stop' { Vb @('controlvm', $Vm, 'poweroff') 30 }
  'shot' { Vb @('controlvm', $Vm, 'screenshotpng', (Join-Path $Shots "$Arg1.png")) 30; (Get-Item (Join-Path $Shots "$Arg1.png")).Length }
  'type' { TypeText ($Arg1 -replace '\\n', "`n") }
  'key' { Press $Arg1 }
  'raw' { Vb (@('controlvm', $Vm, 'keyboardputscancode') + ($Arg1 -split ',')) 15 | Out-Null }
  'serial' { if (Test-Path $Ser) { Get-Content $Ser -Tail ([int]$(if ($Arg1) { $Arg1 } else { 40 })) } }
  'term' {
    Press '01'; Press '01'
    Vb @('controlvm', $Vm, 'keyboardputscancode', 'E0', '5B', 'E0', 'DB') 15 | Out-Null
    Start-Sleep 2; TypeText 'terminal'; Start-Sleep 2; Press '1C'; Start-Sleep 5
    $i = 0
    foreach ($c in ($Arg1 -split '\|')) {
      TypeText ($c + "`n"); Start-Sleep 5
      Vb @('controlvm', $Vm, 'screenshotpng', (Join-Path $Shots ("{0}{1}.png" -f $Arg2, $i))) 30 | Out-Null
      $i++
    }
    'termdone'
  }
  'cleanup' {
    Vb @('controlvm', $Vm, 'poweroff') 20 | Out-Null
    Start-Sleep -Seconds 3
    Vb @('unregistervm', $Vm, '--delete') 60 | Out-Null
  }
  default { Vb @('list', 'vms', '-l') 20 | Select-String 'Name:|State:' }
}
