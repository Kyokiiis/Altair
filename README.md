# Altair

Altair builds its interface in Lua. Start with **Altair.lua** for runtime behavior and **UI/Build.lua** for interface construction, controls and embedded assets.

## Code map

| Path | Responsibility |
| --- | --- |
| `Altair.lua` | Startup, session ownership, settings, navigation, player actions and integration wiring. |
| `UI/Build.lua` | Fresh-instance UI factory, shared controls, motion, capsules, appearance and embedded assets. |
| `Companion/` | Local Spotify service and Windows launcher. |
| `Games/` | Standalone experience integrations; existing filenames remain stable for loaders. |
| `Games/Definitions/` | Custom-script discovery definitions. |

The runtime still uses two Lua files. UI components share private helpers inside Build.lua, so organizing the code does not add module downloads or deployment dependencies. Static asset data is kept separate from the editable implementation within that file.

## Working on the code

- Keep UI construction in Build.lua and runtime/game-service wiring in Altair.lua.
- Preserve instance names, setting IDs and public API names when refactoring; saved preferences and integrations depend on them.
- Keep animation ownership and cleanup with the controller that starts the work. Re-execution must release the previous interface.
- Preserve the original control behavior and accessible text/icon contrast when changing appearance.

See the [UI and integration guide](UI/README.md), [Spotify setup](Companion/README.md), and [third-party notices](THIRD_PARTY_NOTICES.md).

Validation tools and authoring references are maintained outside the release tree. The public package does not include tests or developer implementations.
