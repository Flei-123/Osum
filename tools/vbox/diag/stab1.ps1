param([string[]]$Names = @('OrientOS', 'OrientOS-Test'), [int]$Boots = 1, [int]$Settle = 90, [switch]$Gui, [switch]$NoLogin, [switch]$Trace)
# STAB-1 laptop side (PowerShell 5.1): cold boot each VM, UART1 -> file, bring the files back for
# tools/stab/report.py (server side: python3 tools/stab/report.py --boss <boss> --test <test>).
# Per VM and boot: acpi poweroff (hard fallback) -> uart1 = file -> startvm -> login by scancodes
# -> $Settle s -> acpi poweroff. Output: C:\Users\justi\vbl\stab1-<vm>-<n>.txt (serial, taskbar:/desk: lines).
# Touches ONLY the uart1 setting of the named VMs (it stays "file" afterwards; the old mode is logged).
# Start in the background (Invoke-CimMethod Win32_Process Create) and poll C:\Users\justi\vbl\stab1.log.
# Boss VM = OrientOS (keep bossvm.ps1 rules: no host load while it runs).
# The guest keyboard layout is DEU: '-' is scancode 35, '/' is shift+7; taskbar output needs /etc/uitrace (-Trace creates it).
$ErrorActionPreference = 'Continue'
$R = 'C:\Users\justi\vbl'; $LOGF = "$R\stab1.log"; $VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
function Log($m) { Add-Content $LOGF ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }
function Vb { param([string[]]$a) & $VB @a 2>&1 }
function State([string]$n) { foreach ($ln in (Vb @('showvminfo', $n, '--machinereadable'))) { if ($ln -match '^VMState="(.+)"') { return $Matches[1] } }; return '?' }
function Scan([string]$n, [string[]]$c) { Vb (@('controlvm', $n, 'keyboardputscancode') + $c) | Out-Null }
$MK = @{ a='1E'; c='2E'; e='12'; h='23'; i='17'; k='25'; n='31'; o='18'; r='13'; s='1F'; t='14'; u='16'; w='11'; y='2C'; ' '='39'; '-'='35' }
function TypeWord([string]$n, [string]$w) {
  foreach ($ch in $w.ToCharArray()) { if ($ch -eq [char]47) { Scan $n @('2A', '08', '88', 'AA'); Start-Sleep -Milliseconds 120; continue }; $m = $MK["$ch"]; $b = '{0:X2}' -f ([Convert]::ToInt32($m, 16) + 0x80); Scan $n @($m, $b); Start-Sleep -Milliseconds 120 } }
function Login([string]$n) { TypeWord $n 'startkennwort'; Start-Sleep -Milliseconds 300; Scan $n @('1C', '9C') }
function PowerOff([string]$n) {
  $s = State $n
  if ($s -eq 'running' -or $s -eq 'paused') {
    Vb @('controlvm', $n, 'acpipowerbutton') | Out-Null
    for ($i = 0; $i -lt 30 -and (State $n) -ne 'poweroff'; $i++) { Start-Sleep -Seconds 2 }
    if ((State $n) -ne 'poweroff') { Log "$n acpi shutdown did not finish -> hard poweroff"; Vb @('controlvm', $n, 'poweroff') | Out-Null; Start-Sleep -Seconds 5 }
  }
}
function Enter([string]$n) { Scan $n @('1C', '9C') }
function Prime([string]$n) {
  PowerOff $n
  Log "$n prime boot: touch /etc/uitrace (taskbar output is OFF without that file)"
  Vb @('startvm', $n, '--type', 'headless') | Select-Object -Last 1 | ForEach-Object { Log "$n $_" }
  Start-Sleep -Seconds 50
  Login $n; Start-Sleep -Seconds 40
  Scan $n @('1D', '2A', '14', '94', 'AA', '9D'); Start-Sleep -Seconds 10
  TypeWord $n 'touch /etc/uitrace'; Enter $n; Start-Sleep -Seconds 4
  TypeWord $n 'sync'; Enter $n; Start-Sleep -Seconds 6
  PowerOff $n
  Log "$n prime done"
}
function Uart1Old([string]$n) {
  $m = ''; foreach ($ln in (Vb @('showvminfo', $n, '--machinereadable'))) { if ($ln -match '^uartmode1="(.*)"') { $m = $Matches[1] } }
  return $m
}
foreach ($n in $Names) {
  $tag = ($n.ToLower() -replace '[^a-z0-9]+', '-')
  $old = Uart1Old $n
  Log "$n uartmode1 before: $old"
  if ($Trace) { Prime $n }
  for ($b = 1; $b -le $Boots; $b++) {
    $out = "$R\stab1-$tag-$b.txt"
    PowerOff $n
    Remove-Item $out -ErrorAction SilentlyContinue
    Vb @('modifyvm', $n, '--uart1', '0x3F8', '4', '--uart-mode1', 'file', $out) | Out-Null
    $type = if ($Gui) { 'gui' } else { 'headless' }
    Log "$n boot $b startvm --type $type"
    Vb @('startvm', $n, '--type', $type) | Select-Object -Last 1 | ForEach-Object { Log "$n $_" }
    Start-Sleep -Seconds 50
    if (-not $NoLogin) { Login $n; Log "$n login typed" }
    Start-Sleep -Seconds $Settle
    PowerOff $n
    $lines = 0; if (Test-Path $out) { $lines = (Select-String -Path $out -Pattern '^(taskbar|desk): ' -SimpleMatch:$false | Measure-Object).Count }
    Log "$n boot $b done: $out taskbar/desk lines=$lines"
  }
  if ($old -and $old -ne 'file') { Log "$n note: uart1 was '$old' before, now 'file' (set it back by hand if needed)" }
}
Log 'STAB1 DONE'
