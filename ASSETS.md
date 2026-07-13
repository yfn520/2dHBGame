# ASSETS

| Asset | Path | Status | Notes |
|---|---|---|---|
| Level art | `res://images/source.png` | Existing | Imported from the stitched map output. |
| Collision mask | `res://images/collision_layer.png` | Existing | Reference image for generated collisions. |
| Player animation atlas | `res://assets/action/godot/all_actions_atlas.png` | Existing | Imported action atlas containing `idle` and `run`. |
| Player sprite frames | `res://assets/action/godot/spriteframes.tres` | Existing | Godot `SpriteFrames` resource used by the player scene. |
| UISkin resource | `res://scripts/ui/ui_skin.gd` | Existing | Holds shared Theme and semantic Icon map; wireframe phase. |

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
