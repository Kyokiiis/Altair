# Altair UI

`Build.lua` is the only runtime UI file. It contains construction, capsules,
notifications, timers/stopwatch, Settings layout, and official Lucide images.
No uploaded Roblox UI model is required.

```text
UI/
  Build.lua
  README.md
  Development/
    Lucide/     source artwork and license
    Tests/      optional validation scripts
```

Normal execution downloads only `UI/Build.lua`. Local development can override
it with `Altair/UI/Build.lua` in the executor filesystem. The main loader checks
the UI revision and replaces an incompatible local builder with the repository
version. Old local Clock, Capsules, and Notifications files are no longer loaded.

For Studio, import Build as a ModuleScript in a UI folder beside the main
Altair LocalScript in StarterPlayerScripts. No other runtime modules are needed.

```lua
local root, bindings = require(path.To.UI.Build)()
root.Parent = game:GetService("Players").LocalPlayer.PlayerGui
local notifications = bindings.Notifications({Root=root, RequireBuiltUI=true})
local capsules = bindings.Capsules({
    Root=root, RequireBuiltUI=true, Clock=bindings.Clock,
    GetSetting=function(_, fallback) return fallback end,
    Notify=function(...) return notifications:Notify(...) end,
    Notifications=notifications,
})
root.Enabled = true
```

The factory returns a disabled, unparented root. The main script supplies its
settings, HTTP implementation, lifecycle, and Rainbow Mode color. Re-executing
unloads the previous session and removes orphaned Altair roots, including roots
with randomized names. Destroying the root disconnects input, cancels tweens
and pending commands, and stops future polling updates.

## Capsules and value entry

Capsules default to scale 1.25, with a 375px expanded control center on desktop.
The prior oversized saved default of 3 is migrated. Hover expands a pill;
leaving the padded hover area collapses it after 500ms. The hover margin is
24 scaled pixels on every side, with an 18px minimum. Touch uses tapping. Capsules stay near the
top and move below overlapping Altair panels, notifications, and toasts.

Timer setup opens an animated duration panel with a moving, edge-faded ruler,
minute/second selection, snapping, scroll adjustment, and Start/Cancel actions.
Dragging preserves the other unit. Keyboard entry is available by selecting
the displayed duration. Editing stays open while typing, after moving the
pointer away, or losing field focus. Enter starts a valid duration; Escape
cancels. Invalid text restores the previous valid value.

The music pill appears only while Spotify reports active playback with a valid
track duration. Paused, disconnected, and empty states fade it upward while its
slot shrinks over 400ms. Resuming during exit reverses the transition cleanly. The control
center remains available to resume playback. Track art is shared between the
compact pill and both expanded players, fetched from the public Spotify image
CDN without account tokens or bridge keys, and cached in four slots. Seek and
volume drags show immediate feedback and send one command on release.

The music pill measures the complete song title in its actual font and animates
to that width, including space for artwork and padding. The row resizes with it
so long titles are not clipped by a fixed container. Extremely long titles fit
within the viewport by scaling only the compact row, leaving expanded panels unchanged.

## Appearance and performance

Settings uses two columns of compact category cards with descriptions and
subtle tinted borders. Seven categories fit within the existing 613×384 panel.
Capsules reuse the SmartBar's outer charcoal shell, inset back layer, and actual
button gradient palettes. Music uses Home's palette, timer uses Scripts, and
stopwatch uses Playerlist. Outer and compact outlines are 1px at 45% transparency;
inner outlines sit at 65%, keeping the border visible. All borders follow Rainbow
Mode. There is no simulated beat pulse.

Icons are official Lucide SVG artwork rasterized to transparent PNGs for Roblox
ImageLabels. Build.lua embeds losslessly optimized bytes and registers a local
cache using `getcustomasset`/`getsynasset`, `writefile`, and `makefolder`. It does
not redraw icons with Frames or Unicode. Studio LocalScripts cannot register
local PNGs; icon and cover rendering are checked in the actual Volt runtime.
Source artwork and licensing live in `Development/Lucide/`.

Clocks use monotonic elapsed time. Ruler ticks are pooled and updated only while
the picker is visible. Expanded displays render up to 60Hz; compact content and
obstacle layout update at 10Hz. Spotify polls every 1.5s with failure backoff.
Control requests are serialized; pending seek/volume commands are coalesced.
The builder itself binds no events and starts no background polling.

## Development checks

Import optional `Development/Tests` modules under the same Studio UI folder.
Run client-side checks with:

```lua
print(require(path.To.UI.Development.Tests.ValidateCapsules)())
local bindings = require(path.To.UI.Build)({BindingsOnly=true})
require(path.To.UI.Development.Tests["Clock.spec"])(bindings.Clock)
```

`Validate.lua` compares a builder with a matching reference ScreenGui, checking
properties, attributes, independent construction, and timing. Intentional
Settings/capsule changes need a matching reference. The original interface data
remains packed as `v`, `propertyNames`, `propertySets`, and `nodes`.

Companion tests run from the repository root with
`python -m unittest discover -s Companion/tests -v`. They simulate Spotify
responses. Manual checks also cover Volt HTTP requests, official icon loading,
current track art, playback controls, and re-execution.
