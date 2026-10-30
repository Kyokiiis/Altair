# Last Stand

Rayfield Gen2 module for universe `10769802973`, main place `120293323710237`.
Requires connection/upvalue inspection (tested with Volt). Runs independently;
when Altair is loaded, notifications use Altair's notification cards.

Load `Games/Last Stand.lua`, or copy `Games/Definitions/Last Stand.altair` to
the executor's `Altair/Custom Scripts` folder and use Altair's Reprompt button.
Only one instance of this module stays active after re-execution.

## Gameplay controls

- **Automatic evacuation:** select free green sites with nearby healthy civilians,
  skipping active boats and nearby visible zombies. It honors the money reserve,
  equipped tool, cooldown, and the game's placement validation.
- **Recon:** investigate reported outbreak sites without an active nearby drone.
- **Treatment:** use Vaccine Shell on clusters of infected that recon has revealed.
- **Reinforcement:** deploy Strike Team near visible zombie clusters.
- **HQ teams:** send existing owned squads toward visible threats, retaining
  co-op ownership checks.
- **Supply drops:** collect existing unexpired supply drops through the game's
  pickup action. Candy crates are excluded.
- **Placement plans:** F8 marks the cursor's map position; F9 queues the selected
  point tool. Plans can be saved and loaded for the same map. The queue waits for
  money and cooldowns and pauses after 90 seconds on a blocked step.
- **Repeat this level:** opt in to the ordinary single-player Play Again/Retry
  result flow and Begin Response. External map/difficulty changes stop automation.
- **F10:** stop everything. Closing/unloading disconnects the module's input
  handlers and update loop.

All automation starts disabled. Finish the tutorial, select your equipped tools,
start the response, then enable the actions you want and choose a budget reserve.
The standard loadout includes Recon, Vaccine Shell, Evac Point, and Strike Team;
the module can select that existing preset while the level briefing is open.
The enable button skips tools missing from the equipped loadout.
For unattended play, enable normal level repeat as well. The script cannot continue
through a disconnect, client closure, or incompatible game update. Repeat handling
does not guarantee wins, a particular Research Point rate, or overnight stability.

Single-player levels are simulated by the game's client. Multiplayer mirrors
forward the same game actions to the server using the game's existing codec and
ownership checks. A multiplayer action logged as **Sent** means it was submitted,
not that server acceptance has been confirmed. Multiplayer replay is manual.

There are no direct balance/profile edits, invented grant remotes, cooldown
overrides, game-pass unlocks, or modified research caps. Costs and rewards are
resolved by ordinary gameplay.

## Development checks

`luau Tests/LastStand.spec.luau` runs the deterministic planner checks outside
Roblox. `luau-compile "Games/Last Stand.lua"` checks the complete script's syntax.
Live single-player checks exercise the normal game methods; multiplayer behavior
requires a separate active co-op match.

The live check completed all 11 tutorial lessons, including an 80-person evac.
An automated normal-level check made four evac placements and rescued 268 people
in 50 seconds. A later check completed the ordinary replay/start transition and
resumed evacuation in the next round. These checks do not establish overnight
stability or verify co-op server acceptance.
