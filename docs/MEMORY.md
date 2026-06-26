# MEMORY

## Findings

- The project started nearly empty and only contained the Godot project file and the imported map scene.
- `map_stitch_godot.tscn` already provides three collision polygons, so the prototype can use it directly as the level.
- The level canvas size from `map_stitch_godot.json` is `1376 x 768`, which is used for the initial camera limits.
- The first staircase is on the left side of the map, so a dedicated ladder trigger can cover it reliably.
- The imported action pack includes a ready-to-use `SpriteFrames` resource and a Godot scene, but both exported paths needed to be corrected to the real `res://assets/action/godot/` directory.
- The visual character scene is now nested under `player.tscn`, while `game_root.tscn` keeps the player separate from level scenes for future transitions.

## Decisions

- Use a `CharacterBody2D` player controller for the initial platformer loop.
- Keep controls hardcoded to arrow keys plus `A` and `D` for movement and `Space` for jump.
- Use `Up/Down` plus `W/S` for ladder climbing while inside a ladder `Area2D`.
- Reuse the imported `idle` and `run` animation atlas instead of the temporary SVG placeholder.
- Use a persistent root scene with a level container and a reusable player scene instead of placing the player directly inside each level.

## Follow-up

- If the level size changes, update the camera bounds or drive them from a level metadata node.
- Move from hardcoded keys to Input Map actions once the control scheme stabilizes.
