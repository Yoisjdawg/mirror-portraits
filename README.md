# Mirror Portraits

Any picture as your portrait in World of Warcraft Forever: you, your dog, a screenshot from another game.

**Get it in one click on Melty:** https://melty.gg/m/mirror-portraits. It installs the add-on and the small helper that turns any photo into your portrait. Add-on only (no helper): build with `tools/package.ps1`, then save a 512x512 `Portrait.tga` next to `MirrorPortraits.toc`.

- **Drop a picture in `Pictures\Mirror Portraits`** (PNG, JPG, BMP or GIF). The newest one is used. On your first
  Play the folder opens for you. Drop a new picture in while you play and it comes in too. To find the folder again,
  click the Mirror Portraits icon by the Windows clock, or the "Picture folder" button in your profile (it shows the
  path to copy, since WoW add-ons can't open folders).
- **Your portrait**: the picture replaces your WoW portrait on your player frame, your character sheet, and your
  target frame when you target yourself. "Frame my portrait" lets you drag and zoom the round framing.
- **Your profile**: a panel with the whole picture, your name and a short title
  (e.g. "the Good Boy"). It opens only when you type `/mp`.
- **Seen by other players who have Mirror Portraits**: they see your name and title in your tooltip (through your
  guild, your group, or when they mouse over you). Only the text is sent; the picture stays on your screen.
- Works on your normal WoW Forever realms, alone or in groups.

## How it works
- The add-on installs into WoW Forever's `_classic_beta_/Interface/AddOns/MirrorPortraits`.
- Melty starts `MirrorLink.exe`, which turns your newest picture into the TGA file WoW add-ons can load, then starts
  WoW Forever through the Battle.net app, so you are signed in already (straight `WowB.exe` with its own login screen if
  Battle.net is missing). It never touches the WoW process.

## Commands
`/mp`, `/mp name <name>`, `/mp title <text>`, `/mp portrait on|off`, `/mp folder`, `/mp refresh`, `/mp reset`
(`/mirror` works too).

## Build
`tools/gen.ps1` preflights `sheets/*.json` (every cell, every cross-sheet reference, every row implemented) and
generates `addon/MirrorPortraits/Data.lua` and `link/LinkData.cs`. `tools/package.ps1` builds MirrorLink with the
.NET Framework `csc.exe` and makes the release zip.

Made by @yoisjdawg. MIT license.
