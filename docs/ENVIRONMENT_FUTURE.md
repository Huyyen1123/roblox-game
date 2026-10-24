# Environment Improvements (documented, not started)

Captured from the look-and-feel review on 2026-10-24. The mountain stays as it is until these are
scheduled (roadmap Phases 3 and 9). Nothing here changes the current course or gameplay.

| # | Area | Today | Target |
|---|---|---|---|
| 1 | **Race gates** | Simple red/blue boards | Real gate pairs: two flexible poles with a printed panel, slightly angled, gently swaying when passed. Panels in Frostpeak colours. Breakaway hinge animation when clipped. |
| 2 | **Fencing** | Continuous red fence along both sides, visually dominant | Mostly orange net only where needed (cliffs, trees, tight corners); elsewhere spaced bamboo/blue edge markers. Lower height, thinner, more transparent so the slope reads first. |
| 3 | **Groomed snow** | One flat snow material | Corduroy groomer texture on the piste (MaterialVariant with fine ridges along the fall line), a softer, brighter powder material off-piste, and a subtle transition band between them. |
| 4 | **Ski tracks** | Riders' trails fade after 2.5 s | Pre-placed faint decal tracks on the piste (older runs) plus longer-lived rider trails on the race course. |
| 5 | **Powder near course edges** | The edge is terrain-shaped only | Wind-blown powder drifts and soft lips along the piste edge; small snow mounds around fence posts and trees. |
| 6 | **Props** | Banners, markers, run sign | Course-side props: timing booth, start hut, snow cannons, piste-basher (parked), safety padding on posts, signage at segment changes, distance boards. Low-poly, reusing a few meshes. |
| 7 | **Frostpeak branding** | Start arch and banners in plain blue/red | A logo and one consistent palette (deep navy, ice blue, signal orange) across arches, gate panels, banners, net, HUD and loading screen. |
| 8 | **Lighting** | Future lighting, one sky, ClockTime 14.6 | A slightly lower sun for longer shadows on the moguls and ridges, a cooler shadow tint, lower bloom on the snow, and an optional golden-hour preset for screenshots and replays. |
| 9 | **Natural course dressing** | Forest and boulders beside the course | Tree clusters framing turns, a few lone trees and rocks near the edge for speed reference, and spectator areas at the jumps and finish (Phase 9). |

## Asset needs

- A gate pole and panel mesh (one mesh, recolourable).
- Net fence and marker pole meshes.
- Groomed-snow and powder MaterialVariants (texture sets, 1–2K).
- A track decal (tileable).
- About 6 prop meshes (booth, hut, snow cannon, padding, sign board, distance board).
- The Frostpeak logo (SVG or PNG), used on decals and the HUD.
