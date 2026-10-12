# Build the release zip: tools/package.ps1 -Version 1.0.0
param([string]$Version = '1.0.0')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'gen.ps1')
if ($LASTEXITCODE) { throw 'preflight failed' }
New-Item -ItemType Directory -Force (Join-Path $root 'build') | Out-Null
& C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /optimize /target:winexe /out:"$root\build\MirrorLink.exe" /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll "$root\link\MirrorLink.cs" "$root\link\LinkData.cs"
if ($LASTEXITCODE) { throw 'MirrorLink build failed' }

$flavors = (Get-Content -Raw (Join-Path $root 'sheets\flavors.json') | ConvertFrom-Json).rows
$stage = Join-Path $root 'build\stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
foreach ($fl in $flavors) {
  $d = Join-Path $stage "wow\$($fl.folder)\Interface\AddOns\MirrorPortraits"
  New-Item -ItemType Directory -Force $d | Out-Null
  Get-ChildItem (Join-Path $root 'addon\MirrorPortraits') -File | Where-Object { $_.Extension -in '.lua', '.toc' } | Copy-Item -Destination $d
}
New-Item -ItemType Directory -Force (Join-Path $stage 'link') | Out-Null
Copy-Item "$root\build\MirrorLink.exe", "$root\README.md", "$root\LICENSE" (Join-Path $stage 'link')

$zip = Join-Path $root "build\MirrorPortraits-$Version.zip"
if (Test-Path $zip) { Remove-Item $zip }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::Open($zip, 'Create')
foreach ($f in Get-ChildItem $stage -Recurse -File) {
  $rel = $f.FullName.Substring($stage.Length + 1).Replace('\', '/')
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $f.FullName, $rel, 'Optimal') | Out-Null
}
$z.Dispose()
$z = [IO.Compression.ZipFile]::OpenRead($zip)
$entries = $z.Entries | ForEach-Object { [pscustomobject]@{ path = $_.FullName; size = $_.Length } }
$z.Dispose()
$entries | ConvertTo-Json -Compress | Set-Content -Encoding ascii (Join-Path $root 'build\entries.json')
"zip: $zip  $((Get-Item $zip).Length) bytes  sha256 $((Get-FileHash $zip -Algorithm SHA256).Hash.ToLower())"

# Add-on-only zip for CurseForge (it takes no .exe): the MirrorPortraits folder at the root, as WoW add-on sites expect.
$cf = Join-Path $root "build\MirrorPortraits-$Version-curseforge.zip"
if (Test-Path $cf) { Remove-Item $cf }
$z = [IO.Compression.ZipFile]::Open($cf, 'Create')
foreach ($f in Get-ChildItem (Join-Path $root 'addon\MirrorPortraits') -File | Where-Object { $_.Extension -in '.lua', '.toc' }) {
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $f.FullName, "MirrorPortraits/$($f.Name)", 'Optimal') | Out-Null
}
$z.Dispose()
"curseforge zip: $cf  $((Get-Item $cf).Length) bytes"
