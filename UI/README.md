# Altair's scripted interface

`Build.lua` returns a factory that constructs Altair's complete interface with
`Instance.new`. The main `Altair.lua` now calls this factory instead of loading
an uploaded Roblox model. No UI model needs to be published or made public.
Existing image and font asset IDs are preserved for the original appearance.

## Loading

Normal execution downloads `UI/Build.lua` from this repository. For local
development, place a copy at `Altair/UI/Build.lua` in your executor's filesystem;
Altair prefers that file when it exists. Update or remove that local copy when
you want to use the repository version. The loader does not create a disk cache.

In Roblox Studio, import `Build.lua` as a **ModuleScript** named `Build` inside
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
    └── Build      (ModuleScript: UI/Build.lua)
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
