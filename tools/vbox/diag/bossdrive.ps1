param([string]$Phase = 'a', [string]$Tag = 'r1586')
# Drive the BOSS VM OrientOS (boss said yes, 23.10.2026). Phase a: boot, login, hint 1280x800, start menu -> Taskmgr -> Allow, CPU samples.
# Phase b: from poweroff, boot and shot the limine menu, optional safe-mode entry. Log C:\Users\justi\vbl\boss-<Tag>-<Phase>.log
$ErrorActionPreference = 'Continue'
$R = 'C:\Users\justi\vbl'; $VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'; $N = 'OrientOS'
$L = "$R\boss-$Tag-$Phase.log"
function Log($m) { Add-Content $L ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Vb { param([string[]]$a) & $VB @a 2>&1 }
function State { foreach ($ln in (Vb @('showvminfo', $N, '--machinereadable'))) { if ($ln -match '^VMState="(.+)"') { return $Matches[1] } }; return '?' }
function Scan([string[]]$c) { Vb (@('controlvm', $N, 'keyboardputscancode') + $c) | Out-Null }
function Shot([string]$sn) { Vb @("controlvm", $N, "screenshotpng", "$R\shots\$Tag-$sn.png") | Out-Null; Log "shot $sn" }
$MK = @{ a='1E'; e='12'; k='25'; n='31'; o='18'; r='13'; s='1F'; t='14'; w='11' }
function Login { foreach ($ch in 'startkennwort'.ToCharArray()) { $m = $MK["$ch"]; $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80); Scan @($m, $b); Start-Sleep -Milliseconds 200 }; Start-Sleep -Milliseconds 300; Scan @('1C', '9C') }
function PowerOff {
  if ((State) -in 'running', 'paused') {
    Vb @('controlvm', $N, 'acpipowerbutton') | Out-Null
    for ($i = 0; $i -lt 20 -and (State) -ne 'poweroff'; $i++) { Start-Sleep -Seconds 2 }
    if ((State) -ne 'poweroff') { Log 'acpi poweroff did not finish -> hard poweroff'; Vb @('controlvm', $N, 'poweroff') | Out-Null; Start-Sleep -Seconds 5 }
  }
  Log "state $(State)"
}
function VmProc { $v = New-Object -ComObject VirtualBox.VirtualBox; $p = [int]$v.FindMachine($N).SessionPID; if ($p -le 0) { return $null }; return Get-Process -Id $p -ErrorAction SilentlyContinue }
function Cpu([string]$tag) { $a = VmProc; if (-not $a) { Log "cpu $tag no proc"; return }; $t0 = $a.TotalProcessorTime.TotalSeconds; Start-Sleep -Seconds 8; $b = VmProc; $pct = 100 * ($b.TotalProcessorTime.TotalSeconds - $t0) / 8; Log ("CPU {0} = {1:N1} %" -f $tag, $pct) }
function Mouse([string]$seq) {
  $vbox = New-Object -ComObject VirtualBox.VirtualBox; $session = New-Object -ComObject VirtualBox.Session
  $m = $vbox.FindMachine($N); $m.LockMachine($session, 1)
  try {
    $mouse = $session.Console.Mouse
    function MoveRel([int]$dx, [int]$dy) { while ($dx -ne 0 -or $dy -ne 0) { $sx = [Math]::Max(-100, [Math]::Min(100, $dx)); $sy = [Math]::Max(-100, [Math]::Min(100, $dy)); $mouse.PutMouseEvent($sx, $sy, 0, 0, 0); $dx -= $sx; $dy -= $sy; Start-Sleep -Milliseconds 25 } }
    foreach ($s in $seq.Split(',')) { $p = $s.Split(':')
      switch ($p[0]) {
        'goto' { MoveRel -4000 -4000; Start-Sleep -Milliseconds 100; MoveRel ([int]$p[1]) ([int]$p[2]) }
        'left' { $mouse.PutMouseEvent(0, 0, 0, 0, 1); Start-Sleep -Milliseconds 120; $mouse.PutMouseEvent(0, 0, 0, 0, 0) }
        'sleep' { Start-Sleep -Milliseconds ([int]$p[1]) }
        'shot' { Shot $p[1] } } }
  } finally { try { $session.UnlockMachine() } catch {} }
}
Remove-Item $L -ErrorAction SilentlyContinue
Log "phase $Phase start state $(State)"
if ($Phase -eq 'a') {
  PowerOff
  Remove-Item "$R\boss-$Tag-a-serial.txt" -ErrorAction SilentlyContinue
  Vb @('modifyvm', $N, '--uart1', '0x3F8', '4', '--uart-mode1', 'file', "$R\boss-$Tag-a-serial.txt") | Out-Null
  Vb @('startvm', $N, '--type', 'gui') | Select -Last 1 | % { Log $_ }
  Start-Sleep -Seconds 50; Shot 'boot'; Login; Log 'login typed'; Start-Sleep -Seconds 25
  Vb @('controlvm', $N, 'setvideomodehint', '1280', '800', '32') | Out-Null; Start-Sleep -Seconds 8
  Shot 'desk'; Cpu 'desk'
  Mouse "goto:360:745,sleep:500,left,sleep:2500,shot:menu"
  Mouse "goto:561:430,sleep:500,left,sleep:3500,shot:dlg"
  Cpu 'dialog'
  Mouse "goto:278:309,sleep:500,left,sleep:5000,shot:after"
  Cpu 'after'
  Start-Sleep -Seconds 5; Shot 'after2'
  Log "serial elevate: ready=$((Select-String -Path "$R\boss-$Tag-a-serial.txt" -Pattern 'elevate: ready').Count) allowed=$((Select-String -Path "$R\boss-$Tag-a-serial.txt" -Pattern 'elevate: allowed').Count) start=$((Select-String -Path "$R\boss-$Tag-a-serial.txt" -Pattern 'elevate: start').Count)"
  Log "taskbar lines: $((Select-String -Path "$R\boss-$Tag-a-serial.txt" -Pattern '^taskbar:').Count)"
  Log "panic/stall lines: $((Select-String -Path "$R\boss-$Tag-a-serial.txt" -Pattern 'panic|stall:|watchdog' ).Count)"
}
if ($Phase -eq 'b') {
  PowerOff
  Vb @('startvm', $N, '--type', 'gui') | Select -Last 1 | % { Log $_ }
  foreach ($s in 3, 6, 9) { Start-Sleep -Seconds 3; Shot "limine$s" }
}
if ($Phase -eq 'c') {
  PowerOff
  Vb @('startvm', $N, '--type', 'gui') | Select -Last 1 | % { Log $_ }
  Start-Sleep -Seconds 50; Login; Log 'login typed'
  foreach ($s in 6, 20, 45, 90) { Start-Sleep -Seconds ($s - $(if ($s -eq 6) { 0 } elseif ($s -eq 20) { 6 } elseif ($s -eq 45) { 20 } else { 45 })); Shot "big$s" }
}
Log "phase $Phase done"
