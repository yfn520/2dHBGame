# STRUCTURE

## Skill VFX Data Flow

The web `AI 技能特效导演` reads `data/skills.json`, the selected actor manifest, and `combat_actions.json`. It produces a strict phase plan, searches existing VFX libraries, processes chosen/generated frames, and transactionally writes only `res://assets/skill_fx/<bundle_id>/`. Each package owns `skill_fx_bundle.json`, visual atlases, generated Godot effect scenes, and preview metadata.

`addons/game_tools/skill_sequence_editor.gd` is the only importer. It verifies skill/action hashes and all trigger references, backs up `skills.json`, converts package tracks to idempotent `play_effect` nodes, and leaves gameplay nodes unchanged. `scripts/combat/combat_component.gd` executes those nodes with nonblocking delay and applies anchor, follow, facing mirror, lifetime, scale, rotation, tint, and opacity.

## Runtime Scenes

- `res://scenes/game_root.tscn`: persistent runtime root that owns the party controller, current level container, and a single `UIRoot` node as the only UI entry point.
- `res://scenes/player.tscn`: `PartyManager` scene; its exported `Array[int]` is the inspector-configured lineup of character IDs.
- `res://assets/characters/<name>/godot/<name>.tscn`: complete playable-character prefab with body collision, foot-anchored artwork, camera, HitBox, HurtBox, and combat component.
- `res://scenes/*.tscn`: level scenes (auto-generated from `world/stitched/`)
- `res://assets/npcs/<slug>/godot/npc_visual.tscn`: generated standing-NPC visual scene with its own foot anchor, display scale, name label, quest label, and default idle animation.

## Scripts

### Core (`res://scripts/`)

- `game_root.gd`: main scene script, initializes LevelManager, EnemySpawner, and `UIRoot`; delegates B/C/Escape/F3-F6 to UIRoot.
- `player.gd`: reusable playable-character movement, gravity, jump, ladder, and combat-animation controller.
- `game_registry.gd`: AutoLoad singleton, owns all data models, configs, and providers.

### System (`res://scripts/system/`)

- `level_manager.gd`: level loading/unloading, player teleportation, reload support.
- `save_manager.gd`: JSON save/load to user://.
- `enemy_spawner.gd`: loads enemy prefabs from `<asset>/godot/<asset-folder>.tscn` (for example `slimu/godot/slimu.tscn`).
- `party_manager.gd`: exposes the playable lineup as `Array[int]`, instantiates all lineup members, switches the active controller, and keeps inactive members in simple follow/assist AI.
- `enemy.gd`: single-platform AI uses horizontal distance; `attack_range` is the preferred stopping distance, while each skill's `range` controls selection during pursuit.
- `npc_spawner.gd`: spawns only validated `NpcPlacementConfig` records, skips invalid definitions, and retains errors for failed instance IDs.
- `dialogue_service.gd` / `quest_service.gd`: execute strictly authored dialogue conditions/actions and task objectives; ordinary dialogue completion records talk but never auto-delivers a quest.
- `npc_interaction_dispatcher.gd`: resolves `dialogue_id.intent_key` through `npc_interaction_bindings.json` and dispatches explicit `start_quest` / `turn_in_quest` operations.

### Level (`res://scripts/level/`)

- `level_portal.gd`: portal trigger Area2D for level transitions (export: target_level_id, spawn_position).

### Data (`res://scripts/data/`)

- `item_config.gd` - Static config loader for items.json
- `item_instance.gd` - Runtime item instance {uid, item_id, count}
- `skill_config.gd` - Skills.json loader
- `buff_config.gd` - Buffs.json loader
- `level_config.gd` - Levels.json loader
- `npc_config.gd` - Strict `npcs.json` and per-package `npc_asset.json` loader; validates package ownership, metadata types, resources, and dialogue IDs.
- `npc_placement_config.gd` - Sole runtime source for per-level NPC instances from `npc_placements.json`.
- `inventory_data.gd` - Bag data model with add/remove/query, signals, serialization
- `equipment_data.gd` - Equipment slot state with uid+item_id tracking, signals, serialization
- `character_stats.gd` - Character stats with equipment bonus calculation

### Provider (`res://scripts/provider/`)

- `inventory_provider.gd` - Bag operations interface (signal forwarding from InventoryData)
- `equipment_provider.gd` - Equip/unequip logic with auto stat recalculation

### UI (`res://scripts/ui/`)

- `ui_root.gd` - Unified UI manager; owns 5 CanvasLayers (HUD:10, Screen:20, Popup:30, Notification:40, Debug:100) and provides `setup()`, `open_main_menu()`, `toggle_main_menu()`, `toggle_task_drawer()`, `close_top()`, `is_modal_open()`.
- `ui_skin.gd` - Shared `UISkin` resource holding a `Theme` and semantic Icon mapping; first phase uses `StyleBoxFlat` wireframes, later replaced by independent PNGs and then `AtlasTexture` without touching business pages.
- `battle_hud.gd` - Persistent combat HUD (Control in HUDLayer): left-top main/ally cards, top-center enemy info, bottom-center J/K/L/U skill slots, right-top entry buttons; sends semantic requests to UIRoot instead of holding panel references.
- `main_menu.gd` - Unified main menu (Control in ScreenLayer, max ~900x520): left nav with `character`/`equipment`/`skills`/`inventory` tabs, right content area with ScrollContainer; includes equipment popup and item tooltips.
- `task_drawer.gd` - Right-side slide-in task drawer (Control in ScreenLayer); refreshes from real quest state on `quest_updated`.
- `debug_panel.gd` - F3 debug panel (Control in DebugLayer); shows DebugDraw flags, player/party/enemy runtime info.
- `character_panel.gd` - Legacy CanvasLayer panel, retained but no longer mounted on GameRoot; functionality absorbed by `MainMenu`.

### Combat (`res://scripts/combat/`)

- `state_machine.gd` - Generic state machine with enter/update/exit callbacks
- `combat_component.gd` - Combat logic: attack, skills, damage, buffs, cooldowns, and nonblocking imported skill-VFX playback.
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
- `addons/game_tools/plugin.gd` - Editor import entry points keep playable characters under `assets/characters` and enemies under `assets/enemies`; enemy skill lists are filtered against the actions present in each enemy manifest.
- `addons/game_tools/skill_sequence_editor.gd` - Final importer for independent AI skill-VFX bundles; validates bindings/hashes, previews tracks, backs up skills, and creates or updates tagged `play_effect` nodes.

## Assets

- `res://data/excel/items.xlsx`: item configuration table (8 sample items)
- `res://data/excel/skills.xlsx`: skill configuration table (5 skills)
- `res://data/excel/buffs.xlsx`: buff configuration table (7 buffs)
- `res://data/excel/levels.xlsx`: level configuration table (scene paths, spawn points)
- `res://assets/characters/girl/`: imported character sprite frames and animations
- `res://world/stitched/jungle_01/`: imported jungle map art and collision data
- `res://world/stitched/xing/`: imported star map art and collision data
- `res://assets/npcs/<slug>/`: self-contained NPC package (`npc_asset.json`, `portrait.png`, atlas, SpriteFrames, and visual scene).

## NPC Data Flow

`data/npcs.json` selects an NPC package and dialogue. `data/dialogues.json` and `data/quests.json` hold content. `data/npc_interaction_bindings.json` maps stable dialogue intents to explicit quest start/turn-in operations. `data/npc_placements.json` assigns instances to levels. `GameRegistry` loads dialogues before NPC definitions so broken dialogue references fail during configuration, wires the intent dispatcher, and persists quest changes. `GameRoot` asks `NpcSpawner` for the current level only; `LevelConfig` has no NPC API.

The web authoring tool may read `characters.json` and character manifests during conversion, but the resulting package is copied and independent. It may read `levels.json` and referenced scenes to find map art, but never writes either file.

Step 6 sends only the NPC profile and selected target/reward display names to AI. The returned semantic blueprint contains no runtime IDs. Staging allocates IDs, compiles four state entries into a quest-state router, binds the selected enemy/item IDs, resolves placeholder text, and writes authoring templates used by the orchestration editor when targets or counts change.

## Design Notes

- All data flows through Provider layer, not directly to data models
- UI subscribes to Provider signals for automatic refresh
- CharacterStats.recalculate() is called after every equipment change
- Save format includes version number for future compatibility
- Level loading is dynamic via LevelManager, game_root.tscn has no hardcoded level
- First level is determined by the first row in levels.xlsx
- LevelPortal (Area2D) in level scenes triggers transitions
- Player must be in "player" group for portal detection
- Character import generates every character prefab and never rewrites `player.tscn`; lineup selection belongs to `PartyManager`.
- Runtime party selection is prototype-authoritative from `player.tscn` so editor lineup changes override old local save lineup IDs while preserving character progress.
- A playable character's authored foot point is normalized to the bottom center of its body collision inside its own prefab.
- Character `actor_scale` is read from `data/characters.json` at runtime and scales the prefab visual root, body collision, hurt box, and hit boxes together.
- Keyboard polling is used for now so the prototype works without setting up an input map.

## UI Architecture

- GameRoot owns a single `UIRoot` node; no HUD, panel, or DebugLayer is mounted directly on GameRoot.
- `UIRoot` manages five fixed CanvasLayers: HUDLayer(10), ScreenLayer(20), PopupLayer(30), NotificationLayer(40), DebugLayer(100).
- `UISkin` centralizes the shared `Theme` and semantic Icon map; pages reference Icons by name (e.g. `inventory`, `task`, `weapon`) and never hardcode PNG paths.
- Main menu registers four fixed tabs: `character`, `equipment`, `skills`, `inventory`; unimplemented时装 and宠物 are hidden.
- Task drawer slides in from the right; task system is unimplemented so the real empty state is shown.
- Escape closes layers by priority: Popup → TaskDrawer → MainMenu; B/C toggle inventory/equipment tabs directly.
- When a menu is open, the world keeps simulating; movement/jump/Tab-switch remain, but J/K/L/U manual skill input is blocked via `PartyManager.set_manual_skill_input_enabled(bool)`.
- UI is mouse-first; unnecessary buttons disable keyboard focus to avoid arrow-key navigation conflicts with background movement.
- Skin migration path: wireframe StyleBoxFlat → independent transparent PNG with九宫格 StyleBoxTexture → AtlasTexture; only UISkin and margin config change, business pages stay untouched.
