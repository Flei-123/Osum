param([Parameter(Mandatory)][string]$List, [string]$Tag = 'chain')
# Runs ab.ps1 once per line of $List: "<tag> <url> <shaxz> <sharaw> [odb=1|0]" (blank/# lines skipped). Log of the chain: ab-<Tag>.chain.log
$R = 'C:\Users\justi\vbl'; $C = "$R\ab-$Tag.chain.log"
foreach ($l in Get-Content $List) {
  if ($l -match '^\s*(#|$)') { continue }
  $p = $l.Trim() -split '\s+'
  Add-Content $C ("{0} run {1}" -f (Get-Date -Format 'HH:mm:ss'), $p[0])
  & powershell -NoProfile -ExecutionPolicy Bypass -File "$R\ab.ps1" -Url $p[1] -ShaXz $p[2] -ShaRaw $p[3] -Tag $p[0] -Odb $(if ($p.Count -ge 5) { $p[4] } else { '1' }) | Out-Null
  Add-Content $C ("{0} end {1}" -f (Get-Date -Format 'HH:mm:ss'), $p[0])
}
Add-Content $C 'ALLDONE'
