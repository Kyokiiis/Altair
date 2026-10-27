# Lucide assets

The SVG files are the official Lucide icons from
https://github.com/lucide-icons/lucide/tree/main/icons, retrieved 2026-10-27.
Their path data is unchanged. See `../LUCIDE-LICENSE.txt`.

The matching transparent PNG files are 96px rasterizations made with resvg.
Only `currentColor` is resolved to white so Roblox can tint each ImageLabel.
Build.lua embeds these PNG bytes and registers them through the executor's
local asset API. No geometry is approximated using Roblox Frames or text.

Included icons: chevron-down, eighth-note, pause, play, settings, skip-back,
skip-forward, sun, timer, user, volume-2, volume-x, and x.
