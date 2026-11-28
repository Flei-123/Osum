param(
  [string]$Root = 'C:\VBX',
  [string]$Url,
  [string]$ShaRaw
)
New-Item -ItemType Directory -Force -Path $Root | Out-Null
$gz = Join-Path $Root 'o.img.gz'
$img = Join-Path $Root 'o.img'
$log = Join-Path $Root 'abprep.log'
function L([string]$t) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $t) }
$have = ''
if (Test-Path $img) { $have = (Get-FileHash $img -Algorithm SHA256).Hash.ToLower() }
if ($have -ne $ShaRaw) {
  L "download $Url"
  & curl.exe -sS -f -o $gz $Url
  L "downloaded $((Get-Item $gz).Length) bytes"
  $in = [IO.File]::OpenRead($gz)
  $gs = New-Object IO.Compression.GZipStream($in, [IO.Compression.CompressionMode]::Decompress)
  $out = [IO.File]::Create($img)
  $gs.CopyTo($out)
  $out.Close(); $gs.Close(); $in.Close()
  Remove-Item $gz -Force -ErrorAction SilentlyContinue
  $have = (Get-FileHash $img -Algorithm SHA256).Hash.ToLower()
}
L "raw sha256 $have expected $ShaRaw match=$($have -eq $ShaRaw)"
L 'ABPREP DONE'
