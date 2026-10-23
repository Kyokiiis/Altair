# Altair's scripted interface

`Build.lua` returns a factory that constructs Altair's complete interface with
`Instance.new`. The main `Altair.lua` now calls this factory instead of loading
an uploaded Roblox model. No UI model needs to be published or made public.
Existing image and font asset IDs are preserved for the original appearance.

## Loading

Normal execution downloads `UI/Build.lua`, `UI/Notifications.lua`, `UI/Clock.lua`
and `UI/Capsules.lua` from this repository. For local
development, place matching copies in `Altair/UI/` in your executor's filesystem;
Altair prefers that file when it exists. Update or remove that local copy when
you want to use the repository version. The loader does not create a disk cache.

In Roblox Studio, import all four modules as **ModuleScripts** using their filenames without `.lua` inside
a folder named `UI`, beside the Altair **LocalScript**. `UI` can also be a child
of the Altair LocalScript. Run the LocalScript on the client, for example from
`StarterPlayerScripts`. The old ScreenGui is no longer needed by the loader.
Studio previews skip control of Roblox's global master-volume setting because
ordinary LocalScripts cannot access it. Executor-specific features still require
their corresponding runtime capabilities.

```text
StarterPlayerScripts
├── Altair          (LocalScript: Altair.lua)
└── UI             (Folder)
    ├── Build         (ModuleScript: UI/Build.lua)
    ├── Notifications (ModuleScript: UI/Notifications.lua)
    ├── Clock         (ModuleScript: UI/Clock.lua)
    └── Capsules      (ModuleScript: UI/Capsules.lua)
```

To construct an independent preview without running Altair:

```lua
local root = require(path.To.UI.Build)()
root.Parent = game:GetService("StarterGui") -- Studio edit-mode preview
root.Enabled = true
```

The factory returns a fresh, disabled, unparented ScreenGui. Altair takes
ownership, mounts it, positions it, and enables it through its existing startup
and lifecycle logic. The builder does not connect events, start background
tasks, fetch models, or run any other scripts.

## Layout and performance

The authored runtime interface was captured in Studio on 2026-10-23. All 1,451
objects are preserved, including child order, duplicate child names, hidden
templates, gradients, fonts, slices, constraints, and attributes. The hierarchy
is the same one expected by the current main script, including
`SmartBar.Back.Buttons`, `SmartBar.Back.Time`, and `Drag.Interact`.

The builder shares 1,186 immutable values and 722 property tables. Each instance
receives only properties that differ from Roblox's construction defaults: 9,930
assignments rather than copying every serialized property. Configuration occurs
before children are linked, and the completed root is mounted by the caller.
This follows Roblox's guidance to [set Parent last](https://create.roblox.com/docs/reference/engine/datatypes/Instance).
Failed construction destroys all partially created instances before reporting
the error. Separate factory calls never share Instances.

`values` contains shared Roblox datatypes, `propertySets` contains named property
assignments, and `nodes` describes `{parentIndex, classIndex, name, propertySet,
optionalAttributeSet}`. The `classes` table resolves each class index. Edit the
appropriate shared property set carefully: several nodes may use the same set.
For a one-off change, give that node a new property set.

## Validation

`Validate.lua` is an optional Studio regression checker. It is not downloaded or
loaded during normal Altair startup. Keep the original reference ScreenGui
unmodified and run:

```lua
local report = require(path.To.UI.Validate)(require(path.To.UI.Build), original)
print(report.passed, report.objects, report.properties, report.attributes)
for _, failure in ipairs(report.failures) do warn(failure) end
```

The check compares names, classes, child order, writable serialized properties,
and attributes. It also verifies independent factory calls and reports the median
of five construction timings. The disabled root is intentional and is excluded
from the `Enabled` comparison.

The initial Studio validation passed **1,451 objects, 43,167 property checks, and
199 attribute checks**. Median construction was approximately **16 ms** on the
development machine, excluding source download, compilation, image loading,
rendering, and the rest of Altair startup. Timings vary by device. Main code and
UI modules also passed Luau compilation; loader tests cover local/remote source,
Studio modules, diagnostics, and cleanup of incompatible UI hierarchies.
The integrated main script also started in a separate Studio Play session with
the generated UI mounted and enabled; Home, Character, and Settings were checked
through the actual UI. Executor-specific gameplay features were not exercised.

## Notifications and top capsules

`Notifications.lua` replaces the runtime notification renderer with black rounded,
content-sized cards: 300px wide, 20px corners, 8px spacing and a 44px single-line
variant. It measures the actual font, queues bursts, pauses expiry while hovered,
supports click dismissal and bounds the visible stack. The original builder
retains its legacy template for hierarchy compatibility.

`Capsules.lua` owns the top pills, expandable music/control center, countdown
ruler and stopwatch/lap display. Capsules keep a top anchor and move beneath
overlapping Altair panels, bar, toasts and notifications. Settings control scale
and visibility. Clocks use timestamp differences, so pauses and slow frames do
not accumulate countdown drift. One throttled render loop updates visible text;
one request at a time polls the local Spotify companion with failure backoff.
All owned connections and tweens are released on unload.

Expanded surfaces share the SmartBar's flat background and subtle 1px outline,
with a darker base (40% toward black), 4% background transparency and 85% stroke
transparency. Compact pills keep their black finish. Expanded outlines follow
the existing Rainbow Mode hue and restore their neutral color when it is off.
The Spotify backend supplies no live audio amplitude, so no simulated beat pulse
is added.

`Altair.Capsules.clock` exposes `StartTimer(seconds)`, `ToggleTimer()`,
`CancelTimer()`, `ToggleWatch()`, `Lap()` and `ResetWatch()`.
`Altair.Capsules:Open("center" | "music" | "timer" | "watch")` toggles a surface;
`Open(nil)` collapses it. `Altair.Notify(title, description, icon, {Duration=5})`
returns a dismissal handle.

The client-side Studio test `require(path.To.UI.ValidateCapsules)()` exercises
visibility, simulated link/control/unlink/relink, top overlap avoidance and the
single-line notification size. It cleans up its preview and never authorizes
a real Spotify account. Clock model tests run with `luau UI/Clock.spec.luau`.
See [Spotify setup](../Companion/README.md) for connection requirements.
