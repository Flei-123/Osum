param([string]$Vm = 'OrientOS', [int]$Boots = 3, [int]$Settle = 45)
# Taskbar presence check (STAB-1, laptop side, PowerShell 5.1): N cold headless boots, login by scancodes, screenshot,
# then per screenshot: share of non-background pixels in the middle third (pins) and the right third (tray, clock) of the bottom 48 px strip
# (empty bar ~ 0 %; the left third is empty by design, the pins are centered). Log C:\Users\justi\vbl\barcheck.log (BARCHECK DONE), shots barcheck-<n>.png. Hard poweroff at the end of each boot.
Add-Type -AssemblyName System.Drawing
$R = 'C:\Users\justi\vbl'; $LOGF = "$R\barcheck.log"; $VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function Log($m) { Add-Content $LOGF ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Vb { param([string[]]$a) & $VB @a 2>&1 }
function State([string]$n) { foreach ($ln in (Vb @('showvminfo', $n, '--machinereadable'))) { if ($ln -match '^VMState="(.+)"') { return $Matches[1] } }; return '?' }
function Scan([string]$n, [string[]]$c) { Vb (@('controlvm', $n, 'keyboardputscancode') + $c) | Out-Null }
$MK = @{ a='1E'; e='12'; k='25'; n='31'; o='18'; r='13'; s='1F'; t='14'; w='11' }
function Login([string]$n) { foreach ($ch in 'startkennwort'.ToCharArray()) { $m = $MK["$ch"]; $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80); Scan $n @($m, $b); Start-Sleep -Milliseconds 120 }; Start-Sleep -Milliseconds 300; Scan $n @('1C', '9C') }
function PowerOff([string]$n) { if ((State $n) -eq 'running') { Vb @('controlvm', $n, 'poweroff') | Out-Null; Start-Sleep -Seconds 5 } }
function Strip([string]$png, [double]$x0, [double]$x1) {
  $b = New-Object System.Drawing.Bitmap $png; $h = $b.Height; $w = $b.Width
  $ref = $b.GetPixel([int]($w * $x0) + 2, $h - 3); $n = 0; $d = 0
  for ($y = $h - 44; $y -lt $h - 4; $y += 2) { for ($x = [int]($w * $x0); $x -lt [int]($w * $x1); $x += 2) {
    $p = $b.GetPixel($x, $y); $n++
    if ([math]::Abs($p.R - $ref.R) + [math]::Abs($p.G - $ref.G) + [math]::Abs($p.B - $ref.B) -gt 60) { $d++ } } }
  $b.Dispose(); return [math]::Round(100.0 * $d / $n, 1)
}
Log "== barcheck $Vm boots=$Boots settle=$Settle"
for ($i = 1; $i -le $Boots; $i++) {
  PowerOff $Vm
  Vb @('startvm', $Vm, '--type', 'headless') | Select-Object -Last 1 | ForEach-Object { Log "boot $i $_" }
  Start-Sleep -Seconds 50; Login $Vm; Start-Sleep -Seconds $Settle
  $png = "$R\barcheck-$i.png"; Remove-Item $png -ErrorAction SilentlyContinue
  Vb @('controlvm', $Vm, 'screenshotpng', $png) | Out-Null
  if (Test-Path $png) {
    $bm = New-Object System.Drawing.Bitmap $png; $sz = "{0}x{1}" -f $bm.Width, $bm.Height; $bm.Dispose()
    $l = Strip $png 0.33 0.67; $r = Strip $png 0.67 1.0
    $v = if ($l -gt 2 -and $r -gt 2) { 'BAR_OK' } else { 'BAR_EMPTY_OR_PARTIAL' }
    Log ("boot {0} size={1} png={2}B mid_diff={3}% right_diff={4}% -> {5}" -f $i, $sz, (Get-Item $png).Length, $l, $r, $v)
  } else { Log "boot $i NO SCREENSHOT" }
}
PowerOff $Vm
Log 'BARCHECK DONE'
