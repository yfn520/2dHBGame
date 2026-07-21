# ASSETS

| Asset | Path | Status | Notes |
|---|---|---|---|
| Level art | `res://images/source.png` | Existing | Imported from the stitched map output. |
| Collision mask | `res://images/collision_layer.png` | Existing | Reference image for generated collisions. |
| Player animation atlas | `res://assets/action/godot/all_actions_atlas.png` | Existing | Imported action atlas containing `idle` and `run`. |
| Player sprite frames | `res://assets/action/godot/spriteframes.tres` | Existing | Godot `SpriteFrames` resource used by the player scene. |
| UISkin resource | `res://scripts/ui/ui_skin.gd` | Existing | Holds shared Theme and semantic Icon map; wireframe phase. |
| NPC package | `res://assets/npcs/<slug>/` | Generated | Self-contained runtime resource; no character-table dependency. |

## NPC Asset Contract

```text
assets/npcs/<slug>/
  npc_asset.json
  portrait.png
  godot/
    all_actions_atlas.png
    spriteframes.tres
    npc_visual.tscn
```

- `npc_asset.json` version is exactly `1`; `id` equals `<slug>`.
- Required metadata: `display_name`, `default_animation`, `spriteframes`, `visual_scene`, `portrait`, `frame_size`, `foot_center`, and positive `display_scale`.
- Resource paths must stay under the same NPC package and must exist.
- The atlas is horizontal and contains the complete authored idle sequence. AI creation produces four frames; conversion preserves every idle frame declared by the source character manifest.
- `npc_visual.tscn` is generated with the foot anchor and labels already positioned. Runtime code only instantiates it.
- `portrait.png` is generated independently from the mother image or replaced manually; it is not cropped from the first idle frame.

## UI Asset Contract

- All UI backgrounds, borders, and icons are accessed through `UISkin`; business pages never hardcode PNG paths.
- Semantic icon names (examples): `inventory`, `task`, `character`, `equipment`, `skills`, `weapon`, `armor`, `boots`, `accessory`, `close`, `debug`.
- Skin migration path (phase-by-phase):
  1. **Wireframe**: `StyleBoxFlat` with flat colors and borders (current phase).
  2. **Independent PNG**: replace `StyleBoxFlat` with `StyleBoxTexture` using九宫格 (`expand_margin_*` + `axis_stretch_mode = AXIS_STRETCH_MODE_TILE_FRACTIONAL`); icons replaced by transparent PNGs.
  3. **AtlasTexture**: pack PNGs into atlases; UISkin references switch to `AtlasTexture` regions; business pages stay unchanged.
- When adding a new semantic icon, only extend the `_icon_map` in `UISkin`; pages that already call `skin.get_icon(StringName(name))` pick it up automatically.

## Notes

- The current player visuals now use the imported animated character resource instead of the temporary SVG.
- UI visuals are currently wireframe `StyleBoxFlat`; they are not the final look. Replace via `UISkin` when cut assets arrive.
