# Equipment Asset Spec (final MeshPart versions)

The skis, snowboard, boots and poles in the game today are **temporary primitive geometry**
built by `src/server/Services/EquipmentService.luau` from the sizes in
`src/shared/Config/SportConfig.luau`. They already have the target proportions. This document
specifies the final MeshPart replacements, so they drop in without changing gameplay.

Visual reference: the style guide image (blocky Roblox look, gear about as wide as the boots).
All sizes are in studs for the default R15 avatar (about 5.6 studs tall, feet 1.0 × 0.3 × 1.0).
1 stud = 0.28 m.

## General rules

- **Format:** FBX or OBJ, Y up, −Z forward (tip/nose toward −Z), origin as noted per item.
- **Budget:** at most 1,500 triangles per ski, 2,000 for the board, 600 per boot, 300 per pole.
  Every rider wears one set, so 20 riders must stay cheap.
- **Materials:** separate surfaces (or a SurfaceAppearance with a mask) for top sheet, base and
  edges, bindings, and graphic. Phase 8 customisation recolours the top sheet and graphic.
- **Collision:** none. All equipment is `CanCollide = false`, `CanQuery = false`, `Massless`.
- **Pivot:** must match the current primitive's centre, so `EquipmentService` only swaps the part.
- **Upload:** to the owner's account. Note the asset IDs in `SportConfig`.

## Skis (pair: one mesh, mirrored)

| Property | Value | Notes |
|---|---|---|
| Overall length | 7.6 | 6.8 flat running length, plus about 0.8 of tip rise |
| Waist width | 0.85 | Under the boot (about 0.8 × boot width, per the style guide) |
| Shovel/tail width | 0.95 / 0.90 | Sidecut: a smooth curve, not steps |
| Thickness | 0.12 at the waist | Tapering to about 0.06 at the tip and tail; chunky enough for the blocky style |
| Tip | Rounded, rising 24° over its last 0.8 | Soft rocker curve, not a hinge |
| Tail | Rounded, rising 10° over its last 0.35 | |
| Mount point | 0.3 behind the ski's centre | The boot centre sits here |
| Origin | Ski centre, on the base plane's mid-height | |
| Bindings | Separate mesh, about 0.9 wide × 0.2–0.26 tall × 1.9 long | Toe piece, heel piece and plate; dark grey and metal |
| Graphic | Top-sheet stripe or graphic area | Recolourable |

## Snowboard

| Property | Value | Notes |
|---|---|---|
| Overall length | 6.6 | Tip to tail |
| Waist / nose and tail width | 1.45 / 1.65 | Slightly wider than the boot is long, so toes and heels don't drag |
| Thickness | 0.12 | |
| Nose and tail | Rounded, rising 16° over 1.1 | Twin shape (same at both ends) |
| Base | Dark base with metal edges visible in profile | |
| Bindings | Two at ±0.9 from centre (1.8 stance), with baseplate, highback on the heel side and ankle/toe straps | Angled about +15° / −6° (a duck stance) in the final version |
| Origin | Board centre | |

## Boots

- **Ski boot:** a hard shell, about 1.08 wide × 0.6 tall × 1.15 long, plus a shin cuff about
  0.65 tall. It welds to the foot (shell) and lower leg (cuff), so it follows the pose.
- **Snowboard boot:** a softer, rounder shape, same footprint, with no separate cuff.
- Both should be rigged as accessories, or welded MeshParts sized from the avatar's foot.

## Poles

| Property | Value |
|---|---|
| Length | 3.8 (about 0.7 × avatar height) |
| Shaft | 0.1 diameter, tapering slightly toward the tip |
| Grip | 0.55 long, 0.24 diameter, with a strap loop |
| Basket | 0.45 diameter disc, 0.35 above the tip |
| Origin | Top of the grip (it welds to the hand) |

## Effect textures (also needed)

| Texture | Use | Notes |
|---|---|---|
| Snow spray flipbook | Carving and braking spray | 4×4 flipbook of small white snow clumps with soft blue-grey shading. The built-in smoke texture used now reads only as a light haze against bright snow. |
| Snow puff | Landing puff | A soft round cloud with a darker underside |
| Trail texture (optional) | Ski and board trails | Compressed-snow groove with slight shading at the edges |

## How to make them

1. **Blender (recommended for skis and board):** the dimensions above are exact. I can write a
   step-by-step for you, or a Python script that generates the meshes in Blender.
2. **Roblox AI mesh generation** (available through this Studio connection): good for boots;
   skis need precise dimensions, which it doesn't always respect.
3. **Creator Store:** acceptable if the model has no scripts and a usable licence. Check before
   inserting.
