# tools/vbox/resizewatch.ps1 -- r1297/r1299 resize gate for the VirtualBox test VM (PowerShell 5.1, runs on the laptop).
# For each size: `controlvm setvideomodehint`, then a screenshot every ~2 s. Two times are measured:
#   t_mode  = until the screenshot has the new size (hint picked up and followed), t_paint = until the picture is a real desktop
#   (PNG > 60 KB; the dark compositor background #10141A is a flat colour, ~4 KB).
# FAIL when t_mode > $MaxMode or t_paint > $MaxPaint seconds, or a step never finishes. Needs the running test VM (vbtest.ps1 start,
# logged in). Usage: powershell -File resizewatch.ps1 [-Sizes '1280x720,1024x768,2340x1476'] [-MaxMode 20] [-MaxPaint 40]
param([string]$Sizes = '1280x720,1024x768,2340x1476,1920x1080', [int]$MaxMode = 20, [int]$MaxPaint = 40, [int]$Limit = 120)
$s = 'C:\Users\justi\vbl\vbtest.ps1'
$png = 'C:\Users\justi\vbl\shots\rw.png'
function V { & powershell -NoProfile -ExecutionPolicy Bypass -File $s @args }
$bad = 0
V shot rw | Out-Null
$prevw = [regex]::Match(((V shotstat rw) -join ' '), 'size=(\d+)x').Groups[1].Value
foreach ($z in ($Sizes -split ',')) {
  $wh = $z -split 'x'
  $t0 = Get-Date
  V hint $wh[0] $wh[1] | Out-Null
  $tm = -1; $tp = -1
  while ((Get-Date) -lt $t0.AddSeconds($Limit)) {
    V shot rw | Out-Null
    $st = (V shotstat rw) -join ' '
    $t = [int]((Get-Date) - $t0).TotalSeconds
    $m = [regex]::Match($st, 'size=(\d+)x(\d+)')
    $w = [int]$m.Groups[1].Value
    $sz = (Get-Item $png).Length
    # the kernel may shrink the request (15/16 steps): a changed size that is not the old one counts as followed
    if ($tm -lt 0 -and $w -gt 0 -and "$w" -ne $prevw) { $tm = $t }
    if ($tm -ge 0 -and $sz -gt 60000) { $tp = $t; break }
    Start-Sleep 1
  }
  $prevw = "$w"
  $line = "{0}: t_mode={1}s t_paint={2}s (png {3} B)" -f $z, $tm, $tp, $sz
  if ($tm -lt 0 -or $tm -gt $MaxMode -or $tp -lt 0 -or $tp -gt $MaxPaint) { "FAIL: $line"; $bad++ } else { "OK: $line" }
}
if ($bad -eq 0) { 'OK: resizewatch all steps' } else { "FAIL: resizewatch $bad step(s)"; exit 1 }
