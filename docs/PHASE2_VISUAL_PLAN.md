# Phase 2 Plan: Rider Presentation (not started; waiting for Phase 1 approval)

Goal: riding looks and feels like a winter sports game, not a Roblox prototype. Following the
roadmap, Phase 2 focuses on **the rider and the camera**: posture, animation, equipment and
camera. It also includes the two pieces of visual feedback that most affect how fast and smooth
riding feels (snow spray and a cleaner speedometer). The environment redesign stays in later
phases.

## What looks wrong today, and why

| Problem | Cause in the current build |
|---|---|
| Character stiff and upright | The Humanoid is in the Physics state with no animation playing, so the avatar holds its default standing pose. Only the whole body tilts (lean). |
| No skiing posture | Nothing bends the knees, hips or arms |
| Skis are red rectangles | `EquipmentService` welds placeholder Parts |
| Snowboard looks wrong | Same placeholder approach, and the rider faces forward instead of standing sideways |
| Speedometer looks like a placeholder | A flat rectangle with a bar (`HudUI`) |
| Riding lacks feedback | No snow spray, trails, speed lines or sound |

## 1. Riding poses and leaning (R15)

**Approach: procedural posing first, authored clips layered on top.**

- **Procedural base pose (code only, no assets):** every frame, set `Motor6D.Transform` on the
  R15 joints from the movement state.
  - Knees and hips flex: deeper when tucking, slightly deeper at speed, briefly compressed on
    landing.
  - The torso leans forward and the hips counter-rotate into turns (angulation), as real
    carving looks.
  - Arms are forward with hands low (ski poles) or out for balance (snowboard).
  - The head looks along the direction of travel.
  - The whole-body lean already in the controller stays; the joints add the shape.
- **States driven:** idle/start stance, riding, carving left/right, tuck, brake (skis: wedge or
  skid; snowboard: heel-side skid), jump crouch → takeoff → air → landing compression, stumble
  wobble, wipeout (down on one side), getting back up.
- **Smooth transitions:** every joint target is eased (critically damped), so states blend
  instead of snapping.
- **Snowboard stance:** the body rotates about 80° sideways on the board, with regular/goofy
  options (a per-player setting, saved later with progression). Turns use toe-side and heel-side
  leans instead of ski angulation.
- **Authored clips (manual work):** short accent animations such as pole push-off at the start,
  grabs and the finish celebration are best made in the Roblox Animation Editor and uploaded to
  your account. Procedural code can't produce those convincingly. I'll script the playback
  slots. You (or I, guided step by step) author the clips. Most of them belong to Phase 4
  tricks.
- **Works with every avatar:** pose offsets are relative, so different R15 body types and scales
  all work. R6 avatars fall back to the current lean only.

## 2. Equipment models

| Item | Approach |
|---|---|
| Skis (pair) | Proper MeshParts: tapered, side-cut shape, tip and tail rocker, bindings. Options: (a) Roblox AI mesh generation (available in this Studio connection), (b) a trusted Creator Store model checked for scripts, (c) a Blender model you or I spec. Recommended: try (a) and (b), keep the best, and fall back to (c). |
| Poles | Thin MeshPart or a cylinder with a basket and grip, held in the hands |
| Snowboard | MeshPart with rounded nose and tail, bindings with straps, camber |
| Helmet and goggles | Optional accessories, fitted to the head attachment. A big win for the "premium" look. |
| Materials | Base colour, graphic, edges and bindings as separate surfaces or SurfaceAppearance, so Phase 8 customisation can recolour them |

Equipment attaches to the feet (skis) or both feet (board), so it follows the knee and ankle
posing instead of floating under the root.

## 3. Third-person camera

- A lower, closer default framing (about 12–14 studs back, focus at hip height, slight downward
  pitch), so the slope ahead and the rider's posture both read clearly.
- Speed-based FOV, retuned for 0–70 km/h: subtle at cruising, opening up when tucked.
- Turn anticipation: the camera yaws slightly into the turn ahead of the rider.
- Subtle landing dip and small high-speed vibration, both with a "reduce camera motion"
  setting.
- No camera roll during air rotations (preparing for Phase 4 flips).
- First person stays, gaining the knee-bend bob and the new FOV curve.

## 4. Snow spray and trails (riding feedback)

- **Carving spray:** a ParticleEmitter at the downhill edge, rate scaled with
  speed × turn sharpness. Small soft snow sprites, lit by the scene.
- **Braking spray:** a bigger fan of snow thrown forward and sideways.
- **Landing puff:** a short burst scaled by impact.
- **Ski and board trails:** Trail objects between attachments on the equipment edges, fading
  over about 2–3 s. Two thin lines for skis, one wide line for a board.
- **Speed feel:** faint wind streaks at the screen edges above about 50 km/h (optional, with the
  reduce-motion setting).
- All client-side and per-rider, with particle budgets (limited emitters for distant riders).
  This doesn't affect physics.

## 5. Speedometer and HUD

- Phase 2 replaces the speedometer with a **minimal circular gauge**: an arc fill, large km/h
  number, small tuck and jump-charge indicators, frosted-glass panel, white/blue palette. It's
  responsive for mobile.
- The full race HUD (timer, placement, checkpoints, minimap) comes with racing in Phase 4,
  styled the same way.

## 6. Snow materials and lighting (light touch only)

Phase 2 only adjusts what affects the rider: exposure so white ski gear and snow aren't blown
out, and a rim light so the rider stands out from the snow. The environment redesign stays in
later phases.

## What needs your involvement

| Item | Why |
|---|---|
| Choosing the equipment look | I'll show 2–3 options per item from Studio screenshots |
| Authored animation clips (later) | Animation Editor work, uploaded to your Roblox account |
| Regular/goofy default | A small decision (default: regular) |

## Phase 2 deliverables and order

1. Procedural R15 skiing pose, carving angulation and tuck/brake/jump/landing poses
2. Snowboard sideways stance with regular/goofy
3. Equipment meshes (skis + poles, board, helmet and goggles) attached to the feet and hands
4. Camera framing, FOV and turn anticipation, plus a reduce-motion setting
5. Snow spray, trails and landing puffs
6. Circular speedometer
7. Before/after screenshots and a test checklist

**Out of scope:** trick animations (Phase 4), the course and environment redesign (Phases 3
and 9), audio (Phase 10).
