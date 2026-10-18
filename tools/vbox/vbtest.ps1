# vbtest.ps1 - VirtualBox test loop helper for OrientOS (runs on the LAPTOP, Windows PowerShell 5.1).
# Install: remote_write to C:\Users\justi\vbl\vbtest.ps1 (see tools/vbox/README.md).
# Run:     powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\justi\vbl\vbtest.ps1 <cmd> [args]
# SAFETY: this script only ever touches the VM named 'OrientOS-Test'. The boss VM 'OrientOS'
#         ({0ee259f6-...}) is refused everywhere. Only ONE test VM exists at a time.
# Output: every line is plain text; results start with OK / FAIL / INFO so workers can grep them.
param(
  [Parameter(Position = 0)][string]$Cmd = 'help',
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$A
)
$ErrorActionPreference = 'Stop'
$VM        = 'OrientOS-Test'
$BOSS_UUID = '0ee259f6-4232-4c00-b855-ae407ee6bb2d'
$VB        = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$ROOT      = 'C:\Users\justi\vbl'
$STAGE     = Join-Path $ROOT 'stage'
$SHOTS     = Join-Path $ROOT 'shots'
$SERIAL    = Join-Path $ROOT 'serial.txt'
$VMDIR     = 'C:\Users\justi\VirtualBox VMs\OrientOS-Test'
$LAYOUT    = if ($env:VBL_LAYOUT) { $env:VBL_LAYOUT } else { 'de' }   # guest keyboard layout for 'type:' (de swaps y/z)

function Say([string]$s) { Write-Output $s }
function Vb([string[]]$vargs, [switch]$Soft) {
  # run VBoxManage; on failure either throw (default) or return $false (-Soft)
  $ErrorActionPreference = 'Continue'   # PS 5.1: native stderr must not become a terminating error
  $out = & $VB @vargs 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    if ($Soft) { return $false }
    throw ("VBoxManage " + ($vargs -join ' ') + " failed: " + $out.Trim())
  }
  if (-not $Soft) { return $out.Trim() }
  return $true
}
function VmInfo { # machine-readable showvminfo as hashtable, $null when the VM does not exist
  $ErrorActionPreference = 'Continue'
  $o = & $VB showvminfo $VM --machinereadable 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  $h = @{}
  foreach ($l in $o) { $i = $l.IndexOf('='); if ($i -gt 0) { $h[$l.Substring(0, $i).Trim('"')] = $l.Substring($i + 1).Trim('"') } }
  return $h
}
function Guard { # never operate on the boss VM
  $i = VmInfo
  if ($i -and $i['UUID'] -eq $BOSS_UUID) { throw 'REFUSED: test VM resolves to the boss VM' }
  return $i
}
function State { $i = Guard; if ($null -eq $i) { return 'none' } return $i['VMState'] }
function NeedRunning { if ((State) -ne 'running') { throw "VM $VM is not running (state: $(State))" } }
function EnsureDirs { foreach ($d in $ROOT, $STAGE, $SHOTS) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } } }
function Sha([string]$p) { (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() }
function Elapsed($sw) { '{0:N1}s' -f $sw.Elapsed.TotalSeconds }

# ---------- scancodes (set 1) ----------
$SC = @{}
$c = 0x10; foreach ($ch in 'qwertyuiop'.ToCharArray()) { $SC[[string]$ch] = @($c); $c++ }
$c = 0x1E; foreach ($ch in 'asdfghjkl'.ToCharArray())  { $SC[[string]$ch] = @($c); $c++ }
$c = 0x2C; foreach ($ch in 'zxcvbnm'.ToCharArray())    { $SC[[string]$ch] = @($c); $c++ }
$c = 0x02; foreach ($ch in '1234567890'.ToCharArray()) { $SC[[string]$ch] = @($c); $c++ }
if ($LAYOUT -eq 'de') { $t = $SC['y']; $SC['y'] = $SC['z']; $SC['z'] = $t }
$NAMED = @{
  'enter' = @(0x1C); 'esc' = @(0x01); 'tab' = @(0x0F); 'bs' = @(0x0E); 'space' = @(0x39)
  'ctrl' = @(0x1D); 'shift' = @(0x2A); 'alt' = @(0x38); 'win' = @(0xE0, 0x5B); 'altgr' = @(0xE0, 0x38)
  'up' = @(0xE0, 0x48); 'down' = @(0xE0, 0x50); 'left' = @(0xE0, 0x4B); 'right' = @(0xE0, 0x4D)
  'del' = @(0xE0, 0x53); 'home' = @(0xE0, 0x47); 'end' = @(0xE0, 0x4F); 'pgup' = @(0xE0, 0x49); 'pgdn' = @(0xE0, 0x51)
  'f1' = @(0x3B); 'f2' = @(0x3C); 'f3' = @(0x3D); 'f4' = @(0x3E); 'f5' = @(0x3F); 'f6' = @(0x40)
  'f7' = @(0x41); 'f8' = @(0x42); 'f9' = @(0x43); 'f10' = @(0x44); 'f11' = @(0x57); 'f12' = @(0x58)
}
function KeyCodes([string]$name) { # -> int[] make code (with optional E0 prefix)
  $n = $name.ToLower()
  if ($NAMED.ContainsKey($n)) { return $NAMED[$n] }
  if ($SC.ContainsKey($n)) { return $SC[$n] }
  throw "unknown key '$name'"
}
function MakeBreak([int[]]$code) { # -> (make bytes, break bytes) as hex strings
  $m = @(); $b = @()
  if ($code.Count -eq 2) { $m = @('E0', ('{0:X2}' -f $code[1])); $b = @('E0', ('{0:X2}' -f ($code[1] -bor 0x80))) }
  else { $m = @('{0:X2}' -f $code[0]); $b = @('{0:X2}' -f ($code[0] -bor 0x80)) }
  return ,@($m, $b)
}
function SendScan([string[]]$codes) { Vb (@('controlvm', $VM, 'keyboardputscancode') + $codes) | Out-Null }
function Combo([string]$spec) { # "ctrl+shift+t"
  $parts = $spec.Split('+'); $mk = @(); $br = @()
  foreach ($p in $parts) { $mb = MakeBreak (KeyCodes $p); $mk += $mb[0]; $br = $mb[1] + $br }   # release in reverse order
  SendScan ($mk + $br)
}
function TypeText([string]$text, [int]$pause) {
  foreach ($ch in $text.ToCharArray()) {
    $k = [string]$ch; $shift = $false; $code = $null
    switch -CaseSensitive ($k) {
      ' ' { $code = @(0x39) } '.' { $code = @(0x34) } ',' { $code = @(0x33) } '-' { $code = @(0x35) }
      '/' { $code = @(0x08); $shift = $true } '_' { $code = @(0x35); $shift = $true } ':' { $code = @(0x34); $shift = $true }
      ';' { $code = @(0x33); $shift = $true } '=' { $code = @(0x0B); $shift = $true } '"' { $code = @(0x03); $shift = $true }
      default {
        $lk = $k.ToLower()
        if ($SC.ContainsKey($lk)) { $code = $SC[$lk]; if ($k -cne $lk) { $shift = $true } }
        else { throw "type: no scancode for '$k'" }
      }
    }
    $mb = MakeBreak $code
    if ($shift) { SendScan (@('2A') + $mb[0] + $mb[1] + @('AA')) } else { SendScan ($mb[0] + $mb[1]) }
    Start-Sleep -Milliseconds $pause
  }
}
function KeysSeq([string]$seq) {
  # tokens split by ';': type:<text> | key:<name> | combo:ctrl+shift+t | k:<raw hex scancodes> | sleep:<ms> | shot:<name>
  foreach ($t in $seq.Split(';')) {
    if ($t.Trim() -eq '') { continue }
    $i = $t.IndexOf(':'); if ($i -lt 0) { $c = $t; $a = '' } else { $c = $t.Substring(0, $i); $a = $t.Substring($i + 1) }
    switch ($c) {
      'type'  { TypeText $a 120 }
      'key'   { $mb = MakeBreak (KeyCodes $a); SendScan ($mb[0] + $mb[1]); Start-Sleep -Milliseconds 200 }
      'combo' { Combo $a; Start-Sleep -Milliseconds 300 }
      'k'     { SendScan $a.Split(' '); Start-Sleep -Milliseconds 200 }
      'sleep' { Start-Sleep -Milliseconds ([int]$a) }
      'shot'  { Shot $a }
      default { throw "unknown token '$t'" }
    }
  }
}

# ---------- screenshots ----------
function Shot([string]$name) {
  EnsureDirs; NeedRunning
  $p = Join-Path $SHOTS ($name + '.png')
  Vb @('controlvm', $VM, 'screenshotpng', $p) | Out-Null
  Say ("OK: shot " + $p + " (" + (Get-Item $p).Length + " bytes)")
}
function ShotStat([string]$name) {
  Add-Type -AssemblyName System.Drawing
  $p = if (Test-Path $name) { $name } else { Join-Path $SHOTS ($name + '.png') }
  $bmp = New-Object System.Drawing.Bitmap $p
  try {
    $w = $bmp.Width; $h = $bmp.Height; $step = 4
    $nb = 0; $n = 0; $lum = 0.0
    for ($y = 0; $y -lt $h; $y += $step) { for ($x = 0; $x -lt $w; $x += $step) {
      $px = $bmp.GetPixel($x, $y); $l = 0.299 * $px.R + 0.587 * $px.G + 0.114 * $px.B
      $n++; $lum += $l; if ($l -gt 12) { $nb++ } } }
    Say ("INFO: shotstat {0} size={1}x{2} nonblack={3:P1} meanluma={4:N1}" -f $name, $w, $h, ($nb / $n), ($lum / $n))
    # bottom strip (taskbar): last 56 px; count pixels that differ from the strip background (most common colour)
    $y0 = [Math]::Max(0, $h - 56); $cnt = @{}
    for ($y = $y0; $y -lt $h; $y += 2) { for ($x = 0; $x -lt $w; $x += 4) { $k = $bmp.GetPixel($x, $y).ToArgb(); if ($cnt.ContainsKey($k)) { $cnt[$k]++ } else { $cnt[$k] = 1 } } }
    $bg = ($cnt.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
    $left = 0; $right = 0; $lt = 0; $rt = 0; $mid = 0
    for ($y = $y0; $y -lt $h; $y += 2) { for ($x = 0; $x -lt $w; $x += 4) {
      $diff = ($bmp.GetPixel($x, $y).ToArgb() -ne $bg)
      if ($x -lt $w / 3) { $lt++; if ($diff) { $left++ } } elseif ($x -ge 2 * $w / 3) { $rt++; if ($diff) { $right++ } } else { if ($diff) { $mid++ } } } }
    Say ("INFO: shotstat {0} taskbar_strip bgcolor=0x{1:X8} diff_left={2:P1} diff_right={3:P1} diff_mid_px={4}" -f $name, $bg, ($left / [Math]::Max(1, $lt)), ($right / [Math]::Max(1, $rt)), $mid)
    if (($nb / $n) -gt 0.05) { Say "OK: shotstat $name not black" } else { Say "FAIL: shotstat $name (almost) black" }
  } finally { $bmp.Dispose() }
}

# ---------- mouse (COM, PS/2 relative) ----------
function MouseSeq([string]$seq) {
  $vbox = New-Object -ComObject VirtualBox.VirtualBox
  $session = New-Object -ComObject VirtualBox.Session
  $m = $vbox.FindMachine($VM)
  if ($m.Id -eq $BOSS_UUID) { throw 'REFUSED: boss VM' }
  $m.LockMachine($session, 1)
  try {
    $mouse = $session.Console.Mouse
    $script:btn = 0
    function MoveRel([int]$dx, [int]$dy) {
      while ($dx -ne 0 -or $dy -ne 0) {
        $sx = [Math]::Max(-100, [Math]::Min(100, $dx)); $sy = [Math]::Max(-100, [Math]::Min(100, $dy))
        $mouse.PutMouseEvent($sx, $sy, 0, 0, $script:btn); $dx -= $sx; $dy -= $sy; Start-Sleep -Milliseconds 25
      }
    }
    foreach ($s in $seq.Split(',')) {
      $p = $s.Split(':')
      switch ($p[0]) {
        'goto'  { MoveRel -4000 -4000; Start-Sleep -Milliseconds 100; MoveRel ([int]$p[1]) ([int]$p[2]) }   # absolute from top-left
        'rel'   { MoveRel ([int]$p[1]) ([int]$p[2]) }
        'left'  { $mouse.PutMouseEvent(0, 0, 0, 0, 1); Start-Sleep -Milliseconds 120; $mouse.PutMouseEvent(0, 0, 0, 0, 0) }
        'dbl'   { 1..2 | ForEach-Object { $mouse.PutMouseEvent(0, 0, 0, 0, 1); Start-Sleep -Milliseconds 60; $mouse.PutMouseEvent(0, 0, 0, 0, 0); Start-Sleep -Milliseconds 80 } }
        'right' { $mouse.PutMouseEvent(0, 0, 0, 0, 2); Start-Sleep -Milliseconds 120; $mouse.PutMouseEvent(0, 0, 0, 0, 0) }
        'mid'   { $mouse.PutMouseEvent(0, 0, 0, 0, 4); Start-Sleep -Milliseconds 120; $mouse.PutMouseEvent(0, 0, 0, 0, 0) }
        'ldown' { $script:btn = 1; $mouse.PutMouseEvent(0, 0, 0, 0, 1) }
        'lup'   { $script:btn = 0; $mouse.PutMouseEvent(0, 0, 0, 0, 0) }
        'wheel' { $n = [int]$p[1]; $d = [Math]::Sign($n); 1..[Math]::Abs($n) | ForEach-Object { $mouse.PutMouseEvent(0, 0, $d, 0, 0); Start-Sleep -Milliseconds 200 } }
        'sleep' { Start-Sleep -Milliseconds ([int]$p[1]) }
        'shot'  { Shot $p[1] }
        default { throw "unknown mouse token '$s'" }
      }
      Start-Sleep -Milliseconds 250
    }
  } finally { $session.UnlockMachine() }
  Say 'OK: mouse done'
}

# ---------- serial ----------
function SerialText([int]$maxBytes = 400000) {
  if (-not (Test-Path $SERIAL)) { return '' }
  $fs = [System.IO.File]::Open($SERIAL, 'Open', 'Read', 'ReadWrite')
  try {
    $len = $fs.Length; $start = [Math]::Max(0, $len - $maxBytes); [void]$fs.Seek($start, 'Begin')
    $buf = New-Object byte[] ($len - $start); [void]$fs.Read($buf, 0, $buf.Length)
    return [System.Text.Encoding]::GetEncoding(28591).GetString($buf)
  } finally { $fs.Close() }
}

# ---------- host CPU of the test VM process ----------
function VmProc {
  # the VM process id comes from COM (IMachine.SessionPID); process command lines are not readable for the helper
  $i = Guard; if ($null -eq $i) { throw 'no test VM' }
  $vbox = New-Object -ComObject VirtualBox.VirtualBox
  $m = $vbox.FindMachine($VM)
  if ($m.Id -eq $BOSS_UUID) { throw 'REFUSED: boss VM' }
  $procId = [int]$m.SessionPID
  if ($procId -le 0) { throw 'VM process not found (SessionPID 0)' }
  return Get-Process -Id $procId
}

# ---------- commands ----------
function CmdFetch {
  $ErrorActionPreference = 'Continue'
  if ($A.Count -lt 2) { throw 'usage: fetch <url> <sha256-of-xz> [sha256-of-raw]' }
  EnsureDirs
  $url = $A[0]; $shaXz = $A[1].ToLower(); $shaRaw = if ($A.Count -ge 3) { $A[2].ToLower() } else { '' }
  $xz = Join-Path $STAGE 'o.xz'; $img = Join-Path $STAGE 'o.img'
  Remove-Item $xz, $img -ErrorAction SilentlyContinue
  $sw = [Diagnostics.Stopwatch]::StartNew()
  & curl.exe -sS -f -L --connect-timeout 20 -o $xz $url
  if ($LASTEXITCODE -ne 0) { throw "curl failed ($LASTEXITCODE)" }
  $sz = (Get-Item $xz).Length; $tDl = Elapsed $sw
  Say ("INFO: download {0} bytes in {1} ({2:N1} MB/s)" -f $sz, $tDl, ($sz / 1MB / [Math]::Max(0.01, $sw.Elapsed.TotalSeconds)))
  $sw.Restart(); $got = Sha $xz
  if ($got -ne $shaXz) { throw "xz sha mismatch: got $got" }
  Say ("OK: xz sha256 ({0})" -f (Elapsed $sw))
  $sw.Restart()
  $py = "import lzma,shutil,sys; shutil.copyfileobj(lzma.open(sys.argv[1]), open(sys.argv[2], 'wb'))"   # single quotes inside: PS 5.1 strips double quotes in native args
  & python -I -c $py $xz $img
  if ($LASTEXITCODE -ne 0) { throw 'python lzma failed' }
  Say ("INFO: unxz {0} bytes in {1}" -f (Get-Item $img).Length, (Elapsed $sw))
  if ($shaRaw) { $sw.Restart(); $g = Sha $img; if ($g -ne $shaRaw) { throw "raw sha mismatch: got $g" }; Say ("OK: raw sha256 ({0})" -f (Elapsed $sw)) }
  Say "OK: fetch done -> $img"
}
function CmdMkvm {
  EnsureDirs
  $img = Join-Path $STAGE 'o.img'
  if (-not (Test-Path $img)) { throw "no $img (run fetch first)" }
  $mem = if ($env:VBL_MEM) { [int]$env:VBL_MEM } else { 3072 }; if ($mem -gt 4096) { $mem = 4096 }
  $cpus = if ($env:VBL_CPUS) { [int]$env:VBL_CPUS } else { 3 }
  $useSerial = ($env:VBL_SERIAL -ne '0')   # NB: PowerShell names are case-insensitive, never call this $serial ($SERIAL is the file path)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $i = Guard
  if ($i) {
    if ($i['VMState'] -ne 'poweroff') { Vb @('controlvm', $VM, 'poweroff') -Soft | Out-Null; Start-Sleep -Seconds 3 }
    Vb @('unregistervm', $VM, '--delete') -Soft | Out-Null
  }
  if (Test-Path $VMDIR) { Remove-Item $VMDIR -Recurse -Force -ErrorAction SilentlyContinue }
  Vb @('createvm', '--name', $VM, '--ostype', 'Other', '--register') | Out-Null
  $i = Guard
  if ($i['UUID'] -eq $BOSS_UUID) { throw 'REFUSED: boss VM' }
  Vb @('modifyvm', $VM, '--memory', "$mem", '--vram', '128', '--cpus', "$cpus", '--graphicscontroller', 'vmsvga', '--chipset', 'piix3',
       '--ioapic', 'on', '--hpet', 'off', '--pae', 'off', '--boot1', 'disk', '--boot2', 'none', '--boot3', 'none', '--boot4', 'none',
       '--rtcuseutc', 'off', '--nic1', 'nat', '--nic-type1', '82540EM', '--cable-connected1', 'on', '--mouse', 'ps2', '--keyboard', 'ps2',
       '--audio-driver', 'none', '--clipboard-mode', 'disabled', '--usb-ohci', 'off') | Out-Null
  Vb @('modifyvm', $VM, '--usb-ehci', 'off', '--usb-xhci', 'on') -Soft | Out-Null     # xHCI like the boss VM; non-fatal if unsupported
  if ($useSerial) { Vb @('modifyvm', $VM, '--uart1', '0x3F8', '4', '--uart-mode1', 'file', $SERIAL) | Out-Null; Remove-Item $SERIAL -ErrorAction SilentlyContinue }
  Vb @('storagectl', $VM, '--name', 'IDE', '--add', 'ide', '--controller', 'PIIX4') | Out-Null
  $vdi = Join-Path $VMDIR 'os.vdi'
  Vb @('convertfromraw', $img, $vdi, '--format', 'VDI') | Out-Null
  Vb @('storageattach', $VM, '--storagectl', 'IDE', '--port', '0', '--device', '0', '--type', 'hdd', '--medium', $vdi) | Out-Null
  Vb @('setextradata', $VM, 'GUI/ScaleFactor', '1') | Out-Null
  Say ("OK: mkvm {0} mem={1} cpus={2} serial={3} in {4}" -f $VM, $mem, $cpus, $useSerial, (Elapsed $sw))
}
function CmdSwapDisk { # replace the disk of an existing test VM by stage\o.img (VM is powered off first)
  $img = Join-Path $STAGE 'o.img'; if (-not (Test-Path $img)) { throw 'no stage\o.img' }
  $i = Guard; if ($null -eq $i) { throw 'no test VM (use mkvm)' }
  if ($i['VMState'] -ne 'poweroff') { Vb @('controlvm', $VM, 'poweroff') -Soft | Out-Null; Start-Sleep -Seconds 3 }
  $vdi = Join-Path $VMDIR 'os.vdi'
  Vb @('storageattach', $VM, '--storagectl', 'IDE', '--port', '0', '--device', '0', '--type', 'hdd', '--medium', 'none') | Out-Null
  Vb @('closemedium', 'disk', $vdi, '--delete') -Soft | Out-Null
  Vb @('convertfromraw', $img, $vdi, '--format', 'VDI') | Out-Null
  Vb @('storageattach', $VM, '--storagectl', 'IDE', '--port', '0', '--device', '0', '--type', 'hdd', '--medium', $vdi) | Out-Null
  Remove-Item $SERIAL -ErrorAction SilentlyContinue
  Say 'OK: swapdisk done'
}
function CmdStart {
  $s = State; if ($s -eq 'none') { throw 'no test VM (mkvm first)' }
  if ($s -eq 'running') { Say 'INFO: already running'; return }
  $type = if ($A -contains 'headless') { 'headless' } else { 'gui' }
  Vb @('startvm', $VM, '--type', $type) | Out-Null
  Say "OK: started ($type)"
}
function CmdStop {
  if ((State) -eq 'running') { Vb @('controlvm', $VM, 'poweroff') -Soft | Out-Null; Start-Sleep -Seconds 2 }
  Say ("OK: state=" + (State))
}
function CmdCleanup {
  $i = Guard
  if ($i) {
    if ($i['VMState'] -ne 'poweroff') { Vb @('controlvm', $VM, 'poweroff') -Soft | Out-Null; Start-Sleep -Seconds 3 }
    Vb @('unregistervm', $VM, '--delete') -Soft | Out-Null
  }
  if (Test-Path $VMDIR) { Remove-Item $VMDIR -Recurse -Force -ErrorAction SilentlyContinue }
  Remove-Item (Join-Path $STAGE '*') -Force -ErrorAction SilentlyContinue
  Remove-Item $SERIAL -ErrorAction SilentlyContinue
  if (-not ($A -contains 'keepshots')) { Remove-Item (Join-Path $SHOTS '*') -Force -ErrorAction SilentlyContinue }
  Say ("OK: cleanup done, VM exists=" + [bool](VmInfo))
}
function CmdIdle {
  NeedRunning
  $sec = if ($A.Count -ge 1) { [int]$A[0] } else { 30 }; $n = if ($A.Count -ge 2) { [int]$A[1] } else { 1 }
  $p = VmProc; $vals = @()
  for ($k = 0; $k -lt $n; $k++) {
    $p.Refresh(); $c1 = $p.CPU; $t1 = Get-Date; Start-Sleep -Seconds $sec; $p.Refresh()
    $s = ((Get-Date) - $t1).TotalSeconds; $v = 100 * ($p.CPU - $c1) / $s; $vals += $v
    Say ("INFO: idle sample {0}: {1:N1} % of one host core over {2:N1}s (pid {3}, {4})" -f ($k + 1), $v, $s, $p.Id, $p.ProcessName)
  }
  $avg = ($vals | Measure-Object -Average).Average
  $min = ($vals | Measure-Object -Minimum).Minimum
  if ($min -lt 30) { Say ("OK: idle min {0:N1} % avg {1:N1} % (target < 30)" -f $min, $avg) } else { Say ("FAIL: idle min {0:N1} % avg {1:N1} % (target < 30)" -f $min, $avg) }
}
function CmdStatus {
  $ErrorActionPreference = 'Continue'
  $i = Guard
  if ($null -eq $i) { Say 'INFO: no test VM' } else { Say ("INFO: {0} state={1} mem={2} cpus={3} uart1={4} VideoMode={5}" -f $VM, $i['VMState'], $i['memory'], $i['cpus'], $i['uart1'], $i['VideoMode']) }
  Say ("INFO: running VMs: " + ((& $VB list runningvms) -join ' '))
  if (Test-Path $SERIAL) { Say ("INFO: serial.txt {0} bytes" -f (Get-Item $SERIAL).Length) }
  if (Test-Path $STAGE) { Get-ChildItem $STAGE | ForEach-Object { Say ("INFO: stage {0} {1}" -f $_.Name, $_.Length) } }
}

try {
  switch ($Cmd) {
    'fetch'    { CmdFetch }
    'mkvm'     { CmdMkvm }
    'swapdisk' { CmdSwapDisk }
    'start'    { CmdStart }
    'stop'     { CmdStop }
    'cleanup'  { CmdCleanup }
    'status'   { CmdStatus }
    'shot'     { Shot $A[0] }
    'shotstat' { ShotStat $A[0] }
    'keys'     { NeedRunning; KeysSeq ($A -join ' '); Say 'OK: keys done' }
    'mouse'    { NeedRunning; MouseSeq ($A -join ' ') }
    'hint'     { NeedRunning; Vb @('controlvm', $VM, 'setvideomodehint', $A[0], $A[1], '32') | Out-Null; Say "OK: hint $($A[0])x$($A[1])" }
    'wait'     { Start-Sleep -Seconds ([int]$A[0]); Say "OK: waited $($A[0])s" }
    'idle'     { CmdIdle }
    'serial'   {
      $mode = if ($A.Count -ge 1) { $A[0] } else { 'tail' }
      switch ($mode) {
        'tail'  { $n = if ($A.Count -ge 2) { [int]$A[1] } else { 30 }; (SerialText) -split "`r?`n" | Select-Object -Last $n }
        'grep'  { $m = (SerialText) -split "`r?`n" | Select-String -Pattern $A[1]; $m | Select-Object -Last 40 | ForEach-Object { $_.Line } }
        'count' { $m = (SerialText 4000000) -split "`r?`n" | Select-String -Pattern $A[1]; Say ("INFO: serial count '{0}' = {1}" -f $A[1], @($m).Count) }
        'wait'  { # serial wait <regex> <timeout-sec>
                  $to = if ($A.Count -ge 3) { [int]$A[2] } else { 60 }; $sw = [Diagnostics.Stopwatch]::StartNew(); $hit = $false
                  while ($sw.Elapsed.TotalSeconds -lt $to) { if ((SerialText) -match $A[1]) { $hit = $true; break }; Start-Sleep -Seconds 2 }
                  if ($hit) { Say ("OK: serial matched '{0}' after {1}" -f $A[1], (Elapsed $sw)) } else { Say ("FAIL: serial no match for '{0}' in {1}s" -f $A[1], $to) } }
        'size'  { Say ("INFO: serial {0} bytes" -f $(if (Test-Path $SERIAL) { (Get-Item $SERIAL).Length } else { 0 })) }
        default { throw "serial: unknown mode $mode" }
      }
    }
    'login'    { # type the password at the sign-in screen: login [password]
                 NeedRunning; $pw = if ($A.Count -ge 1) { $A[0] } else { 'startkennwort' }
                 TypeText $pw 200; Start-Sleep -Milliseconds 300; KeysSeq 'key:enter'; Say 'OK: login typed' }
    default {
      Say 'vbtest.ps1 commands (VM name is fixed: OrientOS-Test):'
      Say '  fetch <url> <sha-xz> [sha-raw] | mkvm | swapdisk | start [headless] | stop | cleanup [keepshots] | status'
      Say '  shot <name> | shotstat <name> | hint <w> <h> | wait <sec> | idle <sec> [samples]'
      Say '  keys "type:abc;key:enter;combo:ctrl+shift+t;k:1D 2A;sleep:500;shot:x" | login [password]'
      Say '  mouse "goto:430:250,left,dbl,right,rel:10:0,ldown,lup,wheel:-3,sleep:300,shot:x"'
      Say '  serial tail [n] | grep <re> | count <re> | wait <re> <timeout-sec> | size'
      Say 'env: VBL_MEM (MB, max 4096) VBL_CPUS VBL_SERIAL=0 VBL_LAYOUT=de|us'
    }
  }
} catch {
  Say ("FAIL: " + $_.Exception.Message)
  exit 1
}
