param([switch]$Apply)
$toolId = '{0cb3b571-2f2e-4343-a879-d86a476d7215}'
$espLetter = 'X:'
$steps = @(
 "mountvol $espLetter /s",
 "copy %WINDIR%\System32\SecConfig.efi $espLetter\EFI\Microsoft\Boot\SecConfig.efi /Y",
 "bcdedit /create $toolId /d DebugTool /application osloader",
 "bcdedit /set $toolId path \EFI\Microsoft\Boot\SecConfig.efi",
 "bcdedit /set {bootmgr} bootsequence $toolId",
 "bcdedit /set $toolId loadoptions DISABLE-LSA-ISO,DISABLE-VBS",
 "bcdedit /set $toolId device partition=$espLetter",
 "bcdedit /set {default} vsmlaunchtype off",
 "mountvol $espLetter /d"
)
if (-not $Apply) { $steps; Write-Host 'Dry run only. Use -Apply to execute. Needs physical presence at next boot (confirm prompt).'; return }
foreach ($step in $steps) { cmd /c $step }
Write-Host 'Reboot, then press the key shown by the opt-out tool to confirm.'
