# STRUCTURE

## Runtime Scenes

- `res://scenes/game_root.tscn`: persistent runtime root that owns the player and current level container.
- `res://scenes/level_01.tscn`: first playable level scene with the map and a player spawn marker.
- `res://map_stitch_godot.tscn`: imported map scene with background art and collision geometry.
- `res://scenes/player.tscn`: player character scene with collision, animated sprite, and camera.
- `res://scenes/inventory_panel.tscn`: bag UI panel (6x5 grid), toggled with B key.
- `res://scenes/character_panel.tscn`: character stats + equipment slots UI, toggled with C key.

## Scripts

### Core

- `res://scripts/game_root.gd`: places the persistent player at the current level spawn marker, handles B/C keys for UI toggle.
- `res://scripts/player.gd`: movement, gravity, jump handling, ladder climbing, facing direction, and animation switching.
- `res://scripts/game_registry.gd`: AutoLoad singleton, owns all data models and providers.
- `res://scripts/save_manager.gd`: JSON save/load to user://.

### Data Layer (`res://scripts/data/`)

- `item_config.gd` - Static config loader for items.json
- `item_instance.gd` - Runtime item instance {uid, item_id, count}
- `skill_config.gd` - Skills.json loader
- `buff_config.gd` - Buffs.json loader
- `inventory_data.gd` - Bag data model with add/remove/query, signals, serialization
- `equipment_data.gd` - Equipment slot state with uid+item_id tracking, signals, serialization
- `character_stats.gd` - Character stats with equipment bonus calculation

### Provider Layer (`res://scripts/provider/`)

- `inventory_provider.gd` - Bag operations interface (signal forwarding from InventoryData)
- `equipment_provider.gd` - Equip/unequip logic with auto stat recalculation

### UI Layer (`res://scripts/ui/`)

- `inventory_panel.gd` - Bag UI with 30 slots, equip (E) and discard (D) actions
- `character_panel.gd` - Character stats display + equipment slot display

### Combat Layer (`res://scripts/combat/`)

- `state_machine.gd` - Generic state machine with enter/update/exit callbacks
- `combat_component.gd` - Combat logic: attack, skills, damage, buffs, cooldowns
- `hit_box.gd` - Attack detection Area2D
- `hurt_box.gd` - Hit reception Area2D (group "hurt_box")
- `skill_executor.gd` - Skill execution by type (melee/projectile/aoe/fullscreen/self)
- `projectile.gd` - Projectile base with penetration support
- `buff_manager.gd` - Buff lifecycle, DoT ticks, stacking
- `buff_instance.gd` - Single buff instance data

## Assets

- `res://data/excel/items.xlsx`: item configuration table (8 sample items)
- `res://data/excel/skills.xlsx`: skill configuration table (5 skills: melee/projectile/aoe/penetrate/fullscreen)
- `res://data/excel/buffs.xlsx`: buff configuration table (7 buffs: poison/burn/freeze/paralysis/invincible/stun/slow)
- `res://assets/characters/girl/`: imported character sprite frames and animations
- `res://world/stitched/jungle_01/`: imported jungle map art and collision data

## Design Notes

- All data flows through Provider layer, not directly to data models
- UI subscribes to Provider signals for automatic refresh
- CharacterStats.recalculate() is called after every equipment change
- Save format includes version number for future compatibility
- Player uses GameRegistry.character_stats.move_speed instead of hardcoded constant
- Equipment stores both uid and item_id to support returning items to inventory
- The map scene stays isolated so it can be replaced or extended without touching the player logic.
- The player owns the camera so the same player scene can move across levels.
- The game root owns both the player and the active level so later scene switches can reuse the same player instance.
- Keyboard polling is used for now so the prototype works without setting up an input map.
