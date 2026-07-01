# STRUCTURE

## Runtime Scenes

- `res://scenes/game_root.tscn`: persistent runtime root that owns the player and current level container.
- `res://scenes/player.tscn`: player character scene with collision, animated sprite, and camera.
- `res://scenes/inventory_panel.tscn`: bag UI panel (6x5 grid), toggled with B key.
- `res://scenes/character_panel.tscn`: character stats + equipment slots UI, toggled with C key.
- `res://scenes/*.tscn`: level scenes (auto-generated from `world/stitched/`)

## Scripts

### Core (`res://scripts/`)

- `game_root.gd`: main scene script, initializes LevelManager, handles B/C keys for UI toggle.
- `player.gd`: movement, gravity, jump handling, ladder climbing, combat animation.
- `game_registry.gd`: AutoLoad singleton, owns all data models, configs, and providers.

### System (`res://scripts/system/`)

- `level_manager.gd`: level loading/unloading, player teleportation, reload support.
- `save_manager.gd`: JSON save/load to user://.
- `enemy_spawner.gd`: loads enemy prefabs from `<asset>/godot/<asset-folder>.tscn` (for example `slimu/godot/slimu.tscn`).

### Level (`res://scripts/level/`)

- `level_portal.gd`: portal trigger Area2D for level transitions (export: target_level_id, spawn_position).

### Data (`res://scripts/data/`)

- `item_config.gd` - Static config loader for items.json
- `item_instance.gd` - Runtime item instance {uid, item_id, count}
- `skill_config.gd` - Skills.json loader
- `buff_config.gd` - Buffs.json loader
- `level_config.gd` - Levels.json loader
- `inventory_data.gd` - Bag data model with add/remove/query, signals, serialization
- `equipment_data.gd` - Equipment slot state with uid+item_id tracking, signals, serialization
- `character_stats.gd` - Character stats with equipment bonus calculation

### Provider (`res://scripts/provider/`)

- `inventory_provider.gd` - Bag operations interface (signal forwarding from InventoryData)
- `equipment_provider.gd` - Equip/unequip logic with auto stat recalculation

### UI (`res://scripts/ui/`)

- `inventory_panel.gd` - Bag UI with 30 slots, equip (E) and discard (D) actions
- `character_panel.gd` - Character stats display + equipment slot display

### Combat (`res://scripts/combat/`)

- `state_machine.gd` - Generic state machine with enter/update/exit callbacks
- `combat_component.gd` - Combat logic: attack, skills, damage, buffs, cooldowns
- `hit_box.gd` - Attack detection Area2D
- `hurt_box.gd` - Hit reception Area2D (group "hurt_box")
- `skill_executor.gd` - Skill execution by type (melee/projectile/aoe/fullscreen/self)
- `projectile.gd` - Projectile base with penetration support
- `buff_manager.gd` - Buff lifecycle, DoT ticks, stacking
- `buff_instance.gd` - Single buff instance data
- `assets/<character-or-enemy>/combat_actions.json` - Per-animation active frames and mirrored HitBox geometry; edited for both playable characters and enemies from Game Tools > Configure Attack Hitboxes.

### Editor (`res://scripts/editor/`)

- `import_stitched_world.gd` - CLI tool to import world maps from `world/stitched/`
- `import_character.gd` - CLI tool to import character sprites from `assets/characters/`

## Assets

- `res://data/excel/items.xlsx`: item configuration table (8 sample items)
- `res://data/excel/skills.xlsx`: skill configuration table (5 skills)
- `res://data/excel/buffs.xlsx`: buff configuration table (7 buffs)
- `res://data/excel/levels.xlsx`: level configuration table (scene paths, spawn points)
- `res://assets/characters/girl/`: imported character sprite frames and animations
- `res://world/stitched/jungle_01/`: imported jungle map art and collision data
- `res://world/stitched/xing/`: imported star map art and collision data

## Design Notes

- All data flows through Provider layer, not directly to data models
- UI subscribes to Provider signals for automatic refresh
- CharacterStats.recalculate() is called after every equipment change
- Save format includes version number for future compatibility
- Level loading is dynamic via LevelManager, game_root.tscn has no hardcoded level
- First level is determined by the first row in levels.xlsx
- LevelPortal (Area2D) in level scenes triggers transitions
- Player must be in "player" group for portal detection
- Keyboard polling is used for now so the prototype works without setting up an input map.
