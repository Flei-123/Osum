param([string]$Url = '', [string]$ShaXz = '', [string]$Tag = '', [string]$Rollback = '', [switch]$Prune)
# Swap the disk of the boss VM `OrientOS` for a fresh image (VM must be powered off), or roll back (laptop, PowerShell 5.1).
#   bossswap.ps1 -Url <url> -ShaXz <sha256 of the .xz> -Tag <tag>     tag defaults to the 6 hex chars after the host in the URL
#   bossswap.ps1 -Rollback <tag|file name|full path>                   re-attach an older disk (os-<tag>.vdi)
#   bossswap.ps1 -Prune                                                 list the disks, keep the 4 newest + the attached one (dry run only prints)
# Safety (UPD-5): the OLD disk is never touched. Before the swap its path, size and free space are logged and a one-line
# rollback command is printed. The swap needs free space >= 3x the raw image (xz + raw + vdi); otherwise it stops BEFORE
# any change. Timing per step goes to the log. Own stage dir (vbl\bossstage), log vbl\bossswap.log.
$ErrorActionPreference = 'Continue'
$R = 'C:\Users\justi\vbl'; $S = "$R\bossstage"; $VB = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'; $N = 'OrientOS'
$DIR = 'C:\Users\justi\VirtualBox VMs\OrientOS'; $LOG = "$R\bossswap.log"
function Log($m) { Add-Content $LOG ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m); Write-Output $m }
function Vb { param([string[]]$a) & $VB @a 2>&1 }
function Attached { foreach ($ln in (Vb @('showvminfo', $N, '--machinereadable'))) { if ($ln -match '^"IDE-0-0"="(.+)"') { return $Matches[1] -replace '\\\\', '\' } }; return '' }
function State { foreach ($ln in (Vb @('showvminfo', $N, '--machinereadable'))) { if ($ln -match '^VMState="(.+)"') { return $Matches[1] } }; return '?' }
function FreeGB { return [Math]::Round((Get-PSDrive C).Free / 1GB, 2) }
function Attach([string]$vdi) { Vb @('storageattach', $N, '--storagectl', 'IDE', '--port', '0', '--device', '0', '--type', 'hdd', '--medium', $vdi) | Out-Null }
$t0 = Get-Date
try {
  if ($Prune) {
    $cur = Attached
    Get-ChildItem $DIR -Filter 'os*.vdi' | Sort-Object LastWriteTime -Descending | ForEach-Object { '{0}  {1} MB  {2}{3}' -f $_.Name, [Math]::Round($_.Length / 1MB), $_.LastWriteTime.ToString('dd.MM HH:mm'), $(if ($_.FullName -eq $cur) { '  <- attached' } else { '' }) }
    Log ("prune: dry run only, free {0} GB. Delete old ones by hand: Remove-Item '<file>'" -f (FreeGB))
    return
  }
  $st = State
  if ($st -ne 'poweroff') { throw "VM state $st, need poweroff" }
  $old = Attached
  if ($Rollback) {
    $p = $Rollback
    if (-not (Test-Path $p)) { $p = Join-Path $DIR $Rollback }
    if (-not (Test-Path $p)) { $p = Join-Path $DIR "os-$Rollback.vdi" }
    if (-not (Test-Path $p)) { throw "rollback target not found: $Rollback" }
    Attach $p
    Log "ROLLBACK -> $p (was: $old)"
    return
  }
  if (-not $Url -or -not $ShaXz) { throw 'need -Url and -ShaXz' }
  if (-not $Tag) { if ($Url -match '/t-([0-9a-f]{6})') { $Tag = $Matches[1] } else { $Tag = (Get-Date -Format 'MMddHHmm') } }
  $oldSize = 0; if ($old -and (Test-Path $old)) { $oldSize = [Math]::Round((Get-Item $old).Length / 1MB) }
  Log ("OLD disk: {0} ({1} MB) - stays on disk. Rollback: bossswap.ps1 -Rollback '{0}'" -f $old, $oldSize)
  Log ("free before: {0} GB, tag {1}" -f (FreeGB), $Tag)
  New-Item -ItemType Directory -Force $S | Out-Null
  $t1 = Get-Date
  Log "fetch $Url"
  curl.exe -sS -f -o "$S\o.xz" $Url
  if (-not (Test-Path "$S\o.xz")) { throw 'download failed' }
  $xzMB = [Math]::Round((Get-Item "$S\o.xz").Length / 1MB, 1)
  if ((FreeGB) * 1024 -lt $xzMB * 20) { Remove-Item "$S\o.xz" -Force; throw ("not enough free space: {0} GB for a {1} MB xz" -f (FreeGB), $xzMB) }
  $h = (Get-FileHash "$S\o.xz" -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $ShaXz.ToLower()) { Remove-Item "$S\o.xz" -Force; throw "sha mismatch $h" }
  $t2 = Get-Date
  Log ("sha ok ({0} MB xz, {1:N1} s), decompress" -f $xzMB, ($t2 - $t1).TotalSeconds)
  python -c "import lzma,shutil; shutil.copyfileobj(lzma.open(r'$S\o.xz','rb'), open(r'$S\o.img','wb'))"
  $t3 = Get-Date
  $rawMB = [Math]::Round((Get-Item "$S\o.img").Length / 1MB)
  Log ("raw {0} MB ({1:N1} s)" -f $rawMB, ($t3 - $t2).TotalSeconds)
  $vdi = Join-Path $DIR "os-$Tag.vdi"
  if ($vdi -eq $old) { throw "tag $Tag is the attached disk; pick another tag" }
  if (Test-Path $vdi) { Remove-Item $vdi -Force }
  Vb @('convertfromraw', "$S\o.img", $vdi, '--format', 'VDI') | Out-Null
  if (-not (Test-Path $vdi) -or (Get-Item $vdi).Length -lt 1MB) { throw 'convert failed' }
  $t4 = Get-Date
  Attach $vdi
  if ((Attached) -ne $vdi) { Log 'WARN: attach not confirmed by showvminfo' }
  Remove-Item "$S\o.xz", "$S\o.img" -Force
  Log ("SWAPPED -> {0} ({1} MB vdi, convert {2:N1} s, total {3:N1} s, free after {4} GB)" -f $vdi, [Math]::Round((Get-Item $vdi).Length / 1MB), ($t4 - $t3).TotalSeconds, ((Get-Date) - $t0).TotalSeconds, (FreeGB))
  Log 'DONE'
} catch { Log "FAIL: $_" }
