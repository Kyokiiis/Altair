# Last Stand

Rayfield Gen2 module for universe 10769802973, place 120293323710237.
Tested with Volt. Load Games/Last Stand.lua directly, or use
Games/Definitions/Last Stand.altair with Altair's custom-script loader.
Re-execution unloads the previous window, labels, connections, and scheduler.
Every automation starts off.

## Quick start

Finish the tutorial and select tools in the normal briefing. **Full autofarm**
starts the solo response, enables equipped-tool actions, and repeats the level.
In an already active match, it begins the response plan immediately.
**F10** stops further automated actions. Existing units, structures, and rescues
continue their normal game behavior.

**Equip Nightmare loadout & start** selects owned tools within the actual slot
limit before starting. Alternatively, select Recon and Vaccine Shell plus
rescue/combat tools yourself.
Gate + Evac Zone enable gated safe zones; Fortification enables roof defenses.
Rooftop Extract is optional. The equipped response plan shows available actions.
Missing tools are skipped; the plan refreshes on loadout changes. No tools,
upgrades, or passes are purchased or unlocked.

## Exact-site rescue assists

Outside full autofarm, **Repeat my evac points** and **Repeat my rooftop extracts**
wait for a rescue the player starts with the game's own tool. Remember that exact
site/building and repeat there when the active extraction ends and the native
cooldown permits it. Record the roof itself, rather than its different boarding
entrance. Wait on burning/destroyed roofs instead of relocating the choice.

Multiple player-started locations rotate. Explicit Rayfield placements and
recorded placement plans also count as player choices. **Forget repeated rescue
locations** clears them and waits for a new extraction. F10 / Stop clears them
too. New matches discard old locations.

Full autofarm chooses its own free sites and accessible, intact rooftops with
healthy civilians. Automatically chosen evac sites avoid visible zombies.
Autonomous placements never silently become player-selected repeat points.
Both modes honor native costs/cooldowns, the budget reserve, and placement
validation. The minimum-civilian slider applies to autonomous selection only.

## S-rank response

The current game's score() requires a win and at least **85% of the starting
population preserved** for S. Evacuated people count as preserved. Match shows
the percentage and S margin; that margin alone does not mean the round is won.

Placement priority:

1. Counter predicted enemy concentrations with an equipped Bombing Run when
   enabled, bounding estimated civilian exposure and avoiding owned HQ teams,
   clinics and depots. Movement during the warning/flight can change the outcome;
   predicted hits are not confirmed kills.
2. In solo full autofarm, use NPC state already held by the local simulation to
   aim normal Recon scans at hidden sources and Vaccine Shell at curable carriers,
   including unrevealed ones. The native scan, shell landing, dose limit, cure
   chance and costs still apply. Uncurable outbreak starters are excluded from
   medical targets. Normal assists and co-op use revealed cases/public reports.
3. Reinforce revealed sources and investigate public reports where needed.
   HQ attack orders still require a revealed zombie; the script does not change
   hidden flags or visibility rules. Adaptive reserves preserve treatment funds.
4. Build bounded vaccination coverage outside active crises and rescue healthy
   people through equipped evac/rooftop tools.
5. Use equipped Monster Hunters, Strike Team or Ghost Patrol, accounting for
   nearby troops and pending deployments. Fortify suitable reachable roofs.

Special priorities include runners, bloaters, screamers, wreckers, brutes,
swimmers, bosses and Weepers. Direct HQ targeting avoids quiet Weepers and
prioritizes angry ones. Native units can still provoke them independently.
Optional existing-base strongpoint use remains experimental.

HQ orders and supply pickups run alongside placements. Owned living HQ squads
prioritize zombies threatening people/rescues, retarget dead enemies, temporarily
skip failed paths, and defend rescue/civilian areas when clear. Revealed humans
are left to treatment instead of explicitly selected as HQ attack targets.
Native units retain their own combat AI. Co-op ownership checks remain intact.
Combat medics receive medical patrol / curable-carrier movement orders rather
than being sent to attack zombies; their native cure and healing rules apply.

Gated safe zones use native street geometry around the HQ area. Build checkpoint
barriers, wait for the planned gates to be observed, check known threats, then
create the safe zone through the native polygon action. Check upkeep and retain
extra rescue funds. Missing/dead gates can be rebuilt. Healthy civilians can
pass checkpoints; impassable wall enclosures are avoided. Gate + Evac Zone must
be equipped.

Reserves and construction adapt to infection, visible threats and preservation.
**S on every Nightmare map is not guaranteed or verified.** Results depend on
loadout, upgrades, map, outbreaks, and native AI. Below the S margin, warn and
continue the normal response and available rewards rather than invent a result.

The public mechanics reference is the [official game description](https://www.roblox.com/games/120293323710237/Last-Stand).
Scoring, costs, geometry, and HQ behavior were also checked against the running
game's methods and tutorial. No reliable public guide proving universal
Nightmare S performance was found.

## Other controls

- **Label visible zombie groups:** pooled labels follow map pan/zoom and clip to
  the viewport. Up to 40 labels; hidden outbreaks need reconnaissance. Rescue
  warnings are rate limited; the other enabled actions determine the response.
- **Supply drops:** normal pickup of existing, unexpired drops, excluding candy.
- **Collect all available candy:** independent normal pickup of real unexpired
  night-time candy. Enabled with full autofarm; candy is checked before supplies.
  Requests are bounded and retried with backoff. Native match/server caps apply.
- **F8 / F9:** mark a map point / queue an equipped point tool. Save/load validated
  plans for the same map. Steps wait for funds/cooldowns, pausing after 90 seconds
  if blocked.
- **Repeat this level:** normal Play Again / Retry and Begin Response. Full
  autofarm enables solo repeat. External map/difficulty/variant changes stop
  automation. Co-op replay stays manual.
- **Equip standard loadout during briefing:** selects the game's preset using
  its normal callback, while the briefing is open.

Solo matches genuinely simulate on the game's client. Multiplayer mirrors
forward the same actions through the existing server codec and ownership path.
**Sent** means submitted, not confirmed server acceptance. Construction waits
for observed gates. RP, reward caps, balances, cooldowns, ownership, and access
remain game controlled. Disconnects, closing the client, or incompatible updates
stop play. Overnight stability is not established.

## Verification

Run luau Tests/LastStand.spec.luau for planner checks and luau-compile on
Games/Last Stand.lua for syntax.

Live solo checks confirmed zero automatic placement before a player-started
rescue, then repeated both the original evac site and original roof, rescuing
over 400 civilians. Full autofarm completed at **S with 95 RP**, built a safe zone
after checkpoint construction, added forts, issued HQ attack/retarget/defend
orders, collected supplies, and replayed the same level. A subsequent Easy round
finished **S with 68 RP, 490 evacuated, and 3 cured** using a loadout with Recon
and Vaccine Shell. This does not establish
co-op acceptance, overnight reliability, or all-map Nightmare S performance.

Nightmare testing remains under development. The baseline lost with 22.4%
preserved; multiple revised runs still ended F or C. A clinic-equipped run won
at C with 49.7% preserved. These results do not establish consistent high-rank
Nightmare farming. Live runs collected actual candy, including five in one
Nightmare round. Manually purchased research used earned RP through the normal
Research Shop; the module contains no automatic RP purchases.

One later Los Angeles Nightmare run at the game's normal 2x speed finished S
with 98.54% preserved, 841 RP and 4 candy. The next repeat finished C with
51.12% preserved and 6 candy, so this is still not consistent. These runs used
11 equipped slots, an owned medical HQ team and substantial research upgrades.
They do not establish the same results on a fresh account or another map.
The third repeat finished B with 56.20% preserved and 7 candy. Later checks
found and fixed combat medics being counted as armed defenders, which could
incorrectly suppress reinforcements. Their orders now prioritize treatment.

Saved candy was independently verified: an automatic pickup increased the
normal profile balance from 47 to 48. Pausing through the game's speed control
also stopped all automated placements and pickups during the pause check.
The public-report-only strategy still failed some repeats despite individual S
results. Solo full mode subsequently gained earlier source scanning and latent
carrier treatment using available NPC state. Later results must be assessed
separately from the earlier public-report-only runs above.
Three consecutive completed runs with this change cleared all infections and
zombies normally on Los Angeles Nightmare at the game's 2x speed:

| Run | Grade | Population preserved | RP | Candy |
| --- | --- | --- | --- | --- |
| 1 | S | 98.90% | 768 | 4 |
| 2 | S | 98.68% | 678 | 4 |
| 3 | S | 99.11% | 818 | 4 |

This is a small sample with the same upgraded account and 11-slot kit. Other
maps, co-op and overnight reliability remain unverified. Native source scanning
and treatment still require equipped tools, sufficient funds and cooldowns.
135 planner checks pass. Re-execution also verified that the previous window
unloaded and its connections disconnected before the new module took over.

Experimental bombing is opt-in and has not been live validated; the S runs
used no bombing calls. It is not automatically enabled by full autofarm.
