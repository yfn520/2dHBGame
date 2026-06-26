# STRUCTURE

## Runtime Scenes

- `res://scenes/game_root.tscn`: persistent runtime root that owns the player and current level container.
- `res://scenes/level_01.tscn`: first playable level scene with the map and a player spawn marker.
- `res://map_stitch_godot.tscn`: imported map scene with background art and collision geometry.
- `res://scenes/player.tscn`: player character scene with collision, animated sprite, and camera.
- `res://map_stitch_godot.tscn`: also contains ladder trigger areas for climbable props.

## Scripts

- `res://scripts/game_root.gd`: places the persistent player at the current level spawn marker.
- `res://scripts/player.gd`: movement, gravity, jump handling, ladder climbing, facing direction, and animation switching.

## Assets

- `res://images/source.png`: level art.
- `res://images/collision_layer.png`: collision reference generated with the map.
- `res://assets/action/godot/spriteframes.tres`: imported `SpriteFrames` resource for `idle` and `run`.
- `res://assets/action/godot/all_actions_atlas.png`: atlas backing the imported player animations.

## Design Notes

- The map scene stays isolated so it can be replaced or extended without touching the player logic.
- The player owns the camera so the same player scene can move across levels.
- The game root owns both the player and the active level so later scene switches can reuse the same player instance.
- Keyboard polling is used for now so the prototype works without setting up an input map.
