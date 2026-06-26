# PLAN

## Goal

Build a minimal playable 2D side-scroller framework on top of `map_stitch_godot.tscn`.

## Scope

- Use the imported jungle map as the first playable level.
- Add a controllable player with left/right movement.
- Add jump on the space key.
- Add ladder climbing on the map's staircase using up/down input.
- Make the camera follow the player.
- Replace the placeholder player sprite with the imported animated action set.
- Split runtime into a persistent game root, reusable player scene, and level scene.
- Ensure the project starts into a runnable main scene.

## Verification

- Opening the project runs `res://scenes/main.tscn`.
- The player spawns on the map and remains visible.
- Left and right movement works with arrow keys.
- Jump works with the space key.
- The ladder can be climbed with up/down input.
- The player collides with the imported collision polygons.
- The imported `idle` and `run` animations play on the player.
- The project boots through a persistent root scene and places the player at a level spawn marker.

## Next Steps

- Add animations and a more detailed player controller.
- Add checkpoints, hazards, and collectible items.
- Replace the placeholder hero sprite with a production character asset.
