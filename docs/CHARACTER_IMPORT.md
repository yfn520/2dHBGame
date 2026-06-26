# CHARACTER IMPORT

## Purpose

Convert an externally exported character package under `res://assets/characters/<name>/` into a project-ready character resource.

## Expected Input

The source directory must contain:

- `manifest.json`
- `godot/character_actions.tscn`
- `godot/spriteframes.tres`
- `godot/all_actions_atlas.png`
- `frames/`

Example:

- `res://assets/characters/girl/`

## What The Importer Does

The importer:

- fixes the atlas path inside `godot/spriteframes.tres`
- fixes the `SpriteFrames` path inside `godot/character_actions.tscn`
- forces `AnimatedSprite2D.centered = true`
- generates `character_config.json` with recommended display scale and offset
- can optionally apply the imported character directly to `res://scenes/player.tscn`

## Usage

```bash
godot --headless --script res://scripts/import_character.gd -- --source res://assets/characters/girl --apply-player res://scenes/player.tscn --target-height 52 --facing left
```

## Generated Config

The importer writes:

- `res://assets/characters/<name>/character_config.json`

This file contains:

- `actions_scene`
- `spriteframes`
- `atlas`
- `default_animation`
- `display_scale`
- `display_offset`
- `faces_right_by_default`
- `available_actions`

## Workflow

1. Export a character package from the external tool.
2. Copy it into `res://assets/characters/<name>/`.
3. Run the importer.
4. If needed, inspect `character_config.json`.
5. If you used `--apply-player`, open `res://scenes/player.tscn` and fine tune the final look.
