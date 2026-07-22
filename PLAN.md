# PLAN

## Current Focus: AI skill VFX director V1

### Goal

Create 2D skill visuals without professional VFX software: the web workbench reads the real skill/action timing, draws one structured AI proposal at a time, retains proposal history, reuses or generates assets per phase, previews the composite, and exports one independent bundle. The Godot skill editor is the only place that imports the bundle into `skills.json`.

### Status

- [x] Strict AI planning API with event, hit-window, node-index, anchor, timing, and path validation.
- [x] Unified Spine/Unity/sequence/single-image library index and scored search.
- [x] Per-phase generation, transparent/additive processing, normalized atlas assembly, and isolated regeneration.
- [x] Web director for project/actor/skill selection, single-proposal draw history, material confirmation, timeline preview, mirror preview, and nontechnical adjustments.
- [x] Transactional independent package export under `assets/skill_fx/<bundle_id>/` without editing `skills.json`.
- [x] Godot Skill Sequence Editor import with package/hash validation, mandatory backup, idempotent `play_effect` updates, and gameplay-node preservation.
- [x] Runtime nonblocking delay, anchor/follow/mirror/lifetime/scale/rotation/tint/opacity support.
- [x] Backend, frontend, Godot importer, headless parse, production build, and visible browser smoke tests.
- [ ] Run one final provider-backed skill through asset generation and approve its art in-game.

### Acceptance

- Web export never modifies `data/skills.json`.
- Reimporting the same bundle updates its generated nodes instead of duplicating them.
- Import does not change damage, buff, movement, cost, cooldown, or existing wait nodes.
- Missing events, nodes, assets, hash matches, or package-local paths block import with a concrete error.
- VFX delay is scheduled independently and never stalls the skill executor.

## Current Focus: NPC one-stop authoring hard cut

### Goal

Use the web NPC workshop as the only NPC creation and placement entry. Runtime data is split into `npcs.json`, `dialogues.json`, `quests.json`, and `npc_placements.json`; `levels.json` and `characters.json` are never NPC runtime sources.

### Status

- [x] Standard self-contained packages under `res://assets/npcs/<slug>/`.
- [x] AI mother image, idle generation/background removal, independent portrait, manual replacement, foot anchor preview, and character-manifest conversion.
- [x] Strict `/api/npc-generation/draft` schema with one repair attempt and project-reference validation.
- [x] Pending in-memory resources and one final transaction for resources plus four JSON files.
- [x] Hash conflict detection, mandatory backup, sequential writes, rollback, and unchanged hashes after failure.
- [x] Recursive `.tscn` map-scene resolution to the referenced `source.png` and slug-based unique placement IDs.
- [x] Godot hard-cut config, placement loader, visual-scene instantiation, strict package ownership, dialogue validation, and spawn error retention.
- [x] NPC-focused frontend, backend, and Godot tests plus headless editor parsing.
- [ ] Produce and approve final village-elder artwork through the configured AI provider, then save it to the selected forest map through the workshop.

### Acceptance

- A staged NPC does not touch project files until **统一提交**.
- Saving never modifies `data/levels.json` or `data/characters.json`.
- Every referenced visual resource stays under its own NPC package.
- The actor root is the foot position; `npc_visual.tscn` owns the art anchor, display scale, and labels.
- Invalid packages/dialogues are rejected and invalid placements never create placeholder actors.

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

- [x] Generate enemy prefabs using each asset directory name and resolve them from the enemy table's `asset` path.
- [x] Drive melee HitBox activation from per-character animation frame windows and provide a visual editor.
- [x] Let enemies cast eligible skills while pursuing, then resume closing distance during cooldown; use X-axis-only combat distance.
- [x] Generate independent playable-character prefabs and configure the active lineup through PartyManager.

- Add animations and a more detailed player controller.
- Add checkpoints, hazards, and collectible items.
- Replace the placeholder hero sprite with a production character asset.

## Current Focus: UI 统一管理、布局重构与可换肤资产方案

### Goals

- 新增统一 `UIRoot`，GameRoot 只保留一个 UI 入口，不再直接挂载 HUD、角色面板、旧背包和动态 DebugLayer。
- 第一阶段完成正式的信息架构、布局、响应式尺寸、输入规则和数据绑定，仅使用功能线框皮肤。
- UI 背景、边框和 Icon 全部经过可换肤资源层接入；后续先替换为独立 PNG 与九宫格，再无业务改动地迁移到图集。
- 角色、装备、技能、背包使用统一主菜单；任务为右侧抽屉；未实现的时装和宠物隐藏。

### Status

- [x] `UIRoot` 统一管理 5 层 CanvasLayer (HUD/Screen/Popup/Notification/Debug)
- [x] `UISkin` 资源持有共享 Theme 和语义化 Icon 映射
- [x] `BattleHud` 重构：移除 CharacterPanel 引用，通过 UIRoot 发送语义化请求
- [x] `MainMenu` 统一主菜单：character/equipment/skills/inventory 四页
- [x] `TaskDrawer` 右侧抽屉，任务系统未实现时展示真实空状态
- [x] `DebugPanel` 迁入 DebugLayer，F3 调试
- [x] `game_root.gd` 使用 UIRoot 作为唯一 UI 入口
- [x] `game_root.tscn` 移除旧面板，添加 UIRoot 节点
- [x] 移除旧 InventoryPanel (scene + script)
- [x] Escape 按优先级关闭：弹窗 → 任务抽屉 → 主菜单
- [x] 菜单打开时 J/K/L/U 施法被屏蔽，移动/跳跃/Tab 切人保留
- [x] `PartyManager.set_manual_skill_input_enabled(bool)` 转发给 CombatComponent
- [x] Godot 无头加载和脚本解析通过
- [ ] 替换独立 PNG 与九宫格验证皮肤迁移
- [ ] 使用 AtlasTexture 替换独立 PNG 验证图集迁移
- [ ] 在 960×540、1152×648、1376×768 和 1920×1080 下布局验收

## Verification

- GameRoot 下只存在一个 UIRoot，旧面板和动态 DebugLayer 无残留引用
- B/C、HUD 入口、任务入口和 Escape 的打开、切页、互斥及关闭优先级正确
- 菜单打开时移动、跳跃、Tab 和世界模拟正常；J/K/L/U 不施法；关闭后立即恢复
- 切换角色、升级、装备变更、背包增删和技能冷却能实时刷新
- Godot 无头加载和 `git diff --check` 通过

## Next Steps

- 切图到位后替换 UISkin 中的 StyleBoxFlat 为独立透明 PNG 与九宫格 StyleBoxTexture
- 将独立 PNG 打包为图集，UISkin 引用切换到 AtlasTexture
- 连接网络层时替换 Provider 实现
- 添加战斗动画 (attack, hit, skill1, skill2, skill3, dead)
- 添加弹道/特效场景 (fireball, frost_arrow, etc.)
- 添加 Buff 特效场景 (poison_fx, burn_fx, freeze_fx, etc.)

## Architecture

### Data Layer (scripts/data/)

- `item_config.gd` - Static config loader for items.json
- `item_instance.gd` - Runtime item instance {uid, item_id, count}
- `skill_config.gd` - Skills.json loader (5 skills: melee/projectile/aoe/penetrate/fullscreen)
- `buff_config.gd` - Buffs.json loader (7 buffs: poison/burn/freeze/paralysis/invincible/stun/slow)
- `inventory_data.gd` - Bag data model with add/remove/query
- `equipment_data.gd` - Equipment slot state with uid tracking
- `character_stats.gd` - Character stats with equipment bonus calculation

### Provider Layer (scripts/provider/)

- `inventory_provider.gd` - Bag operations interface (signal forwarding)
- `equipment_provider.gd` - Equip/unequip logic with auto stat recalculation

### UI Layer (scripts/ui/)

- `ui_root.gd` - Unified UI manager; owns 5 CanvasLayers (HUD/Screen/Popup/Notification/Debug) and exposes open/toggle/close APIs
- `ui_skin.gd` - Shared UISkin resource with Theme and semantic Icon mapping
- `battle_hud.gd` - Persistent combat HUD in HUDLayer; skill slots, cards, entry buttons
- `main_menu.gd` - Unified main menu in ScreenLayer; character/equipment/skills/inventory tabs
- `task_drawer.gd` - Right-side slide-in task drawer in ScreenLayer
- `debug_panel.gd` - F3 debug panel in DebugLayer

### Combat Layer (scripts/combat/)

- `state_machine.gd` - Generic state machine with enter/update/exit callbacks
- `combat_component.gd` - Combat logic: attack, skills, damage, buffs, cooldowns
- `hit_box.gd` - Attack detection Area2D (collision_layer=4)
- `hurt_box.gd` - Hit reception Area2D (collision_layer=8, group "hurt_box")
- `skill_executor.gd` - Skill execution by type (melee/projectile/aoe/fullscreen/self)
- `projectile.gd` - Projectile base with penetration support
- `buff_manager.gd` - Buff lifecycle, DoT ticks, stacking, state checks
- `buff_instance.gd` - Single buff instance data

### Manager Layer

- `game_registry.gd` - AutoLoad singleton, owns all data models and providers
- `save_manager.gd` - JSON save/load to user://

## Design Notes

- All data flows through Provider layer, not directly to data models
- UI subscribes to Provider signals for automatic refresh
- CharacterStats.recalculate() is called after every equipment change
- Save format includes version number for future compatibility
- Networking migration: Replace Provider implementations with network calls
- GameRoot owns a single UIRoot node; no UI is mounted directly on GameRoot
- UIRoot manages five fixed CanvasLayers with strict z-index: HUD(10), Screen(20), Popup(30), Notification(40), Debug(100)
- UISkin abstracts asset references so skin migration (wireframe → PNG → atlas) never touches business code
- When menus are open, manual skill input (J/K/L/U) is blocked while movement/jump/Tab remain active

## Excel 配置表工作流

配置表统一使用 Excel 管理，运行时读取 JSON。

### 目录结构

```
data/excel/          ← 源文件 (.xlsx)，手动编辑
data/items.json      ← 自动生成，不要手动修改
tools/create_items_excel.py  ← 初始化 Excel 文件
tools/excel_to_json.py       ← Excel → JSON 转换工具
```

### 工作流程

1. 用 Excel 打开 `data/excel/items.xlsx` 编辑数据
2. 运行 `python tools/excel_to_json.py` 生成 JSON
3. Godot 运行时自动读取 JSON

### 新增配置表

1. 在 `data/excel/` 下创建 `新表名.xlsx`
2. 第一行为表头（支持中文），第一列必须是 `ID`
3. 运行 `python tools/excel_to_json.py 新表名`
4. 在 GDScript 中读取对应的 JSON

### 表头映射

中文表头自动映射为英文 key：
- ID → id, 名称 → name, 类型 → type, 描述 → description
- 可堆叠 → stackable, 最大数量 → max_count
- 攻击力 → attack, 防御力 → defense, 最大生命 → max_hp, 移动速度 → move_speed
- 回复量 → heal_amount

新增字段只需在 `excel_to_json.py` 的 `HEADER_MAP` 中添加映射。
