# WORLD IMPORT

## Purpose

Convert a raw stitched world package under `res://world/stitched/<name>/` into a playable level scene under `res://scenes/`.

## Expected Input

The source directory must contain:

- `map_stitch_godot.tscn`
- `map_stitch_godot.json`
- `images/`

Example:

- `res://world/stitched/jungle_01/`

## Output

The importer generates a scene that contains:

- `Map` instance of the raw stitched scene
- `PlayerSpawn` marker based on the canvas size from the json

## Usage

```bash
godot --headless --script res://scripts/import_stitched_world.gd -- --source res://world/stitched/jungle_01 --output res://scenes/level_01.tscn --root-name Level01
```

If `--output` is omitted, the importer writes to:

- `res://scenes/<source_folder_name>.tscn`

If `--root-name` is omitted, the importer derives a PascalCase node name from the output file name.

## Workflow

1. Export a raw map package from the external tool.
2. Copy it into `res://world/stitched/<map_name>/`.
3. Run the importer.
4. Open the generated scene under `res://scenes/`.
5. Adjust `PlayerSpawn` and add any level-specific gameplay nodes.
