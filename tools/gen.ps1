# Preflight every sheet, then generate addon/MirrorPortraits/Data.lua and link/LinkData.cs from them.
# Usage: powershell -ExecutionPolicy Bypass -File tools/gen.ps1 [-PreflightOnly]
param([switch]$PreflightOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$addon = Join-Path $root 'addon\MirrorPortraits'
$names = 'media', 'crops', 'surfaces', 'settings', 'share', 'commands', 'flavors', 'link', 'hooks', 'checks'
$SH = @{}
foreach ($n in $names) { $SH[$n] = Get-Content -Raw -Encoding UTF8 (Join-Path $root "sheets\$n.json") | ConvertFrom-Json }
$P = New-Object System.Collections.Generic.List[string]
function Ids($n) { @($SH[$n].rows | ForEach-Object { $_.($SH[$n].columns[0]) }) }
function Src($file) { $p = Join-Path $addon $file; if (Test-Path $p) { Get-Content -Raw $p } else { '' } }

# 1. Every row x column crossing is filled (settings: a string default may be "").
foreach ($n in $names) {
  $sheet = $SH[$n]; $i = 0
  foreach ($r in $sheet.rows) {
    $i++
    foreach ($c in $sheet.columns) {
      $v = $r.$c
      $okEmpty = ($n -eq 'settings' -and $c -eq 'default' -and $r.type -eq 'string')
      if ($null -eq $v) { $P.Add("$n row $i ($($r.($sheet.columns[0]))): '$c' missing"); continue }
      if ($v -is [string] -and $v.Trim() -eq '' -and -not $okEmpty) { $P.Add("$n row $i ($($r.($sheet.columns[0]))): '$c' is empty") }
      if ($v -is [array] -and $v.Count -eq 0) { $P.Add("$n row $i ($($r.($sheet.columns[0]))): '$c' is an empty list") }
    }
    foreach ($extra in $r.PSObject.Properties.Name) { if ($extra -notin $sheet.columns) { $P.Add("$n row ${i}: '$extra' is not a column") } }
  }
  $dup = Ids $n | Group-Object | Where-Object Count -gt 1
  foreach ($d in $dup) { $P.Add("$n id '$($d.Name)' appears $($d.Count) times") }
}

# 2. Cross-sheet references resolve.
$settingKeys = Ids 'settings'
$sharedKeys = @($SH.settings.rows | Where-Object shared | ForEach-Object key)
foreach ($r in $SH.crops.rows) {
  if ($r.media -notin (Ids 'media')) { $P.Add("crops $($r.id): media '$($r.media)' not in media") }
  foreach ($k in 'x', 'y', 'w', 'h') { if ($r.$k -lt 0 -or $r.$k -gt 1) { $P.Add("crops $($r.id): $k outside 0-1") } }
  if ($r.x + $r.w -gt 1.0001 -or $r.y + $r.h -gt 1.0001) { $P.Add("crops $($r.id): runs past the image") }
}
foreach ($r in $SH.surfaces.rows) {
  if ($r.crop -notin (Ids 'crops')) { $P.Add("surfaces $($r.id): crop '$($r.crop)' not in crops") }
  if ($r.when -notin 'always', 'self-target') { $P.Add("surfaces $($r.id): unknown when '$($r.when)'") }
}
foreach ($r in $SH.settings.rows) {
  if ($r.type -notin 'string', 'number', 'bool') { $P.Add("settings $($r.key): unknown type '$($r.type)'") }
  if ($r.type -eq 'bool' -and $r.default -isnot [bool]) { $P.Add("settings $($r.key): default is not true/false") }
  if ($r.type -eq 'string' -and $r.max -lt 1) { $P.Add("settings $($r.key): max length must be positive") }
}
$face = $SH.crops.rows | Where-Object id -eq 'face'
$def = @{}; foreach ($r in $SH.settings.rows) { $def[$r.key] = $r.default }
if ($face.x -ne $def.faceX -or $face.y -ne $def.faceY -or $face.w -ne $def.faceS -or $face.h -ne $def.faceS) { $P.Add("crops face and settings faceX/faceY/faceS defaults disagree") }
foreach ($r in $SH.share.rows) {
  foreach ($f in $r.fields) { if ($f -ne 'ver' -and $f -notin $sharedKeys) { $P.Add("share $($r.id): field '$f' is not a shared setting") } }
  foreach ($c in $r.channels) { if ($c -notin 'GUILD', 'PARTY', 'RAID', 'WHISPER') { $P.Add("share $($r.id): channel '$c' not allowed") } }
  if ($r.code.Length -ne 1) { $P.Add("share $($r.id): code must be one letter") }
}
foreach ($r in $SH.commands.rows) { if ($r.setting -ne 'none' -and $r.setting -notin $settingKeys) { $P.Add("commands $($r.id): setting '$($r.setting)' not in settings") } }
foreach ($r in $SH.link.rows) {
  if ($r.target -match '^(\w+):(.+)$' -and $Matches[1] -in $names) {
    if ($Matches[2] -notin (Ids $Matches[1])) { $P.Add("link $($r.id): $($r.target) does not resolve") }
  } elseif ($r.target -in $names) { } elseif ($r.target -notmatch '^(Generated/|Pictures/)') { $P.Add("link $($r.id): target '$($r.target)' is neither a sheet row nor a known literal") }
  foreach ($m in [regex]::Matches($r.condition, 'settings:(\w+)')) { if ($m.Groups[1].Value -notin $settingKeys) { $P.Add("link $($r.id): condition names unknown setting $($m.Groups[1].Value)") } }
}
foreach ($r in $SH.checks.rows) { foreach ($src in ($r.source -split ',')) { if ($src -notin $names) { $P.Add("checks $($r.id): source sheet '$src' does not exist") } } }

# 3. The code implements every row (verified against the sources, not assumed).
$toc = Src 'MirrorPortraits.toc'
foreach ($f in Get-ChildItem $addon -Filter *.lua -File) { if ($toc -notmatch [regex]::Escape($f.Name)) { $P.Add("toc does not load $($f.Name)") } }
foreach ($r in $SH.hooks.rows) {
  $src = Src $r.file
  if (-not $src) { $P.Add("hooks $($r.id): file $($r.file) missing"); continue }
  $needle = ($r.target -split '[ /]')[0] -replace '^C_ChatInfo\.', '' -replace '^Texture:', ''
  if ($src -notmatch [regex]::Escape($needle)) { $P.Add("hooks $($r.id): $needle not found in $($r.file)") }
}
$test = Src 'Test.lua'
foreach ($r in $SH.checks.rows) { if ($test -notmatch ('"' + [regex]::Escape($r.id) + '"')) { $P.Add("checks $($r.id): not implemented in Test.lua") } }
$cmd = Src 'Profile.lua'
foreach ($r in $SH.commands.rows) { if ($r.id -ne 'toggle' -and $cmd -notmatch ('"' + [regex]::Escape($r.id) + '"')) { $P.Add("commands $($r.id): not handled in Profile.lua") } }
$cs = if (Test-Path (Join-Path $root 'link\MirrorLink.cs')) { Get-Content -Raw (Join-Path $root 'link\MirrorLink.cs') } else { '' }
foreach ($r in $SH.link.rows) { if ($cs -notmatch ('"' + [regex]::Escape($r.id) + '"')) { $P.Add("link $($r.id): step not in MirrorLink.cs") } }

# 4. The sheets match this PC's WoW (when it is here).
$wow = 'C:\Program Files (x86)\World of Warcraft'
if (Test-Path $wow) { foreach ($r in $SH.flavors.rows) { if (-not (Test-Path (Join-Path $wow "$($r.folder)\$($r.exe)"))) { $P.Add("flavors $($r.id): $($r.folder)\$($r.exe) not in this PC's WoW") } } }

if ($P.Count) { "PREFLIGHT FAILED ($($P.Count))"; $P | ForEach-Object { " - $_" }; exit 1 }
"PREFLIGHT CLEAN: " + (($names | ForEach-Object { "$_=$(@($SH[$_].rows).Count)x$(@($SH[$_].columns).Count)" }) -join ', ')
if ($PreflightOnly) { exit 0 }

# 5. Generate: one Lua table / one C# object per sheet row, built from that row's columns.
function LuaVal($v) {
  if ($null -eq $v) { return 'nil' }
  if ($v -is [bool]) { return $v.ToString().ToLower() }
  if ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) { return ([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $v)) }
  if ($v -is [array]) { return '{' + ((@($v) | ForEach-Object { LuaVal $_ }) -join ', ') + '}' }
  return '"' + ($v -replace '\\', '\\' -replace '"', '\"') + '"'
}
$lua = @('-- GENERATED by tools/gen.ps1 from sheets/*.json. Edit the sheets, not this file.', 'local _, ns = ...', 'ns.Data = {}')
foreach ($n in 'media', 'crops', 'surfaces', 'settings', 'share', 'commands', 'flavors', 'checks') {
  $sheet = $SH[$n]; $key = $sheet.columns[0]
  $lua += "ns.Data.$n = {"
  foreach ($r in $sheet.rows) { $lua += '  {' + (($sheet.columns | ForEach-Object { "$_ = $(LuaVal $r.$_)" }) -join ', ') + '},' }
  $lua += '}'
  $lua += "for _, row in ipairs(ns.Data.$n) do ns.Data.$n[row.$key] = row end"
}
[IO.File]::WriteAllText((Join-Path $addon 'Data.lua'), ($lua -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))

function CsVal($v) {
  if ($v -is [bool]) { return $v.ToString().ToLower() }
  if ($v -is [int] -or $v -is [long]) { return "$v" }
  if ($v -is [double] -or $v -is [decimal]) { return ([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $v)) }
  return '"' + ($v -replace '\\', '\\' -replace '"', '\"') + '"'
}
$cs = @('// GENERATED by tools/gen.ps1 from sheets/*.json. Edit the sheets, not this file.',
  'class MediaRow { public string id, file, source, from, placeholder; public int width, height; }',
  'class FlavorRow { public string id, label, folder, exe, uid, family; public int @interface; }',
  'class LinkRow { public string id, action, target, condition; public int order; }',
  'static class LinkData {')
$cs += '  public static readonly MediaRow[] Media = {'
foreach ($r in $SH.media.rows) { $cs += "    new MediaRow { id = $(CsVal $r.id), file = $(CsVal $r.file), source = $(CsVal $r.source), from = $(CsVal $r.from), width = $($r.width), height = $($r.height), placeholder = $(CsVal $r.placeholder) }," }
$cs += '  };'
$cs += '  public static readonly FlavorRow[] Flavors = {'
foreach ($r in $SH.flavors.rows) { $cs += "    new FlavorRow { id = $(CsVal $r.id), label = $(CsVal $r.label), folder = $(CsVal $r.folder), exe = $(CsVal $r.exe), uid = $(CsVal $r.uid), family = $(CsVal $r.family), @interface = $($r.interface) }," }
$cs += '  };'
$cs += '  public static readonly LinkRow[] Steps = {'
foreach ($r in $SH.link.rows | Sort-Object order) { $cs += "    new LinkRow { id = $(CsVal $r.id), order = $($r.order), action = $(CsVal $r.action), target = $(CsVal $r.target), condition = $(CsVal $r.condition) }," }
$cs += '  };'
$cs += "  public static readonly string[] Checks = { $((Ids 'checks' | ForEach-Object { CsVal $_ }) -join ', ') };"
$cs += '}'
[IO.File]::WriteAllText((Join-Path $root 'link\LinkData.cs'), ($cs -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
"wrote Data.lua and LinkData.cs"
