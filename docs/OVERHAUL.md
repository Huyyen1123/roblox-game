# Mountain & gameplay overhaul — how to test

Course: **Summit Ridge** (default). Press Play, pick a sport, and you start at the summit.

## Controls
| Key | On the snow | In the air |
|---|---|---|
| A / D | steer | spin |
| W | push (slow speeds) | frontflip (hold; release to stop rotating) |
| S | — | backflip |
| Q E F G | — | grabs. Board: indy, melon, method, tail. Skis: safety, mute, japan, tail |
| Z / X | — | board nose / tail tweak |
| Shift | tuck | |
| Ctrl | brake | |
| Space | hold to charge a jump | |
| V | camera | |
| R | restart (summit, or the trick park when you're practising there) | |
| T | go to the trick park | |

Nothing finishes a rotation for you: land within ~30° of level and straight for a clean landing, up to ~55° for a sketchy one, beyond that (or upside down) you wipe out.

## Race
- The clock starts at the START banner. Six orange beams mark the checkpoints. You can take any route between them; the arrow and distance under the clock point to the nearest beam of the next one.
- The FINISH arch is in the basin. Finish times and best times are kept by the server.
- Routes:
  - **Left:** trick park in the upper bowl, then gentle powder and a dense pine forest.
  - **Centre:** fast rollers, two kickers, a cave tunnel.
  - **Right:** steep pitches, a narrow rock passage, a rock drop, the frozen waterfall.
  - **Bottom:** all routes rejoin for the big air above the finish, past the frozen lake.

## Trick park
Press **T** (or the TRICK PARK button). It has four kickers, S, M, L and XL, each marked with orange-tipped poles at the lip. Approximate natural airtime:

| Kicker | Natural air |
|---|---|
| S | 0.3 s |
| M | 0.6 s |
| L | 0.65 s |
| XL | 1.0 s (about 1.6 s with a charged jump) |

A single flip needs about 0.85 s of rotation. Press **R** to go back to the top of the park.

## Studio-only helpers
- **K:** throws the rider straight up (~1.3 s of air) to try tricks anywhere.
- **F8 / F9:** Summit Ridge / Frostpeak.
- Landing details are written to `HumanoidRootPart.DebugLastLanding`.

## Rebaking terrain after changing kickers or the lake
Bump `World.TerrainVersion` in `Config/Courses/SummitRidge.luau`, then either:
- run `CourseService.Init()` in Edit mode with fresh modules, or
- press Play once and the server regenerates it, though that bake is not saved.

Then save the place.

## Known limits
- **Powder wake:** the EditableMesh wake needs "Allow Mesh & Image APIs" (owner ID verification) on the published place. Until then the snow tracks use the texture-trail fallback.
- **Multiplayer:** only tested with one client in Studio. Remote riders use the same replicated attributes as before, plus flip rate and four grabs.
