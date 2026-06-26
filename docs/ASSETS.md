# ASSETS

| Asset | Path | Status | Notes |
|---|---|---|---|
| Level art | `res://images/source.png` | Existing | Imported from the stitched map output. |
| Collision mask | `res://images/collision_layer.png` | Existing | Reference image for generated collisions. |
| Player animation atlas | `res://assets/action/godot/all_actions_atlas.png` | Existing | Imported action atlas containing `idle` and `run`. |
| Player sprite frames | `res://assets/action/godot/spriteframes.tres` | Existing | Godot `SpriteFrames` resource used by the player scene. |

## Notes

- The current player visuals now use the imported animated character resource instead of the temporary SVG.
