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

## Current Focus: UI System (Inventory & Character Panels)

### Goals

- Build inventory and character equipment UI panels.
- Use B key to open/close inventory, C key for character panel.
- All data operations go through Provider layer for future networking compatibility.
- Items use text display initially, icon support will be added later.

### Status

- [x] Inventory panel scene and script created
- [x] Character panel scene and script created
- [x] Game root updated with B/C key handling
- [x] Equipment panel: clickable slots with type-based filtering
- [x] Equipment panel: popup selection list from inventory
- [x] Equipment panel: color-coded slot types (weapon/armor/boots/accessory)
- [x] Equipment panel: stat bonus display (攻+5, 防+3 etc.)
- [ ] Add sample items for testing
- [ ] Test equip/unequip flow

## Verification

- Press B to open inventory panel, see 30 empty slots
- Press B again or Escape to close inventory
- Press C to open character panel, see stats and 4 equipment slot buttons
- Click empty slot → popup shows compatible items from inventory
- Click item in popup → equips it, slot shows name + stats in color
- Click occupied slot → unequips item back to inventory
- Each slot type has unique color: weapon=red, armor=blue, boots=green, accessory=gold
- Stats update in real-time after equip/unequip

## Next Steps

- Add icon support when asset is ready
- Connect to networking layer when server integration begins
- Add drag-and-drop for item management
- Add item tooltips with detailed stats

## Architecture

### Data Layer (scripts/data/)

- `item_config.gd` - Static config loader for items.json
- `item_instance.gd` - Runtime item instance {uid, item_id, count}
- `inventory_data.gd` - Bag data model with add/remove/query
- `equipment_data.gd` - Equipment slot state with uid tracking
- `character_stats.gd` - Character stats with equipment bonus calculation

### Provider Layer (scripts/provider/)

- `inventory_provider.gd` - Bag operations interface (signal forwarding)
- `equipment_provider.gd` - Equip/unequip logic with auto stat recalculation

### UI Layer (scripts/ui/)

- `inventory_panel.gd` - Bag UI with 6x5 grid, equip/discard actions
- `character_panel.gd` - Character stats and equipment display

### Manager Layer

- `game_registry.gd` - AutoLoad singleton, owns all data models and providers
- `save_manager.gd` - JSON save/load to user://

## Design Notes

- All data flows through Provider layer, not directly to data models
- UI subscribes to Provider signals for automatic refresh
- CharacterStats.recalculate() is called after every equipment change
- Save format includes version number for future compatibility
- Networking migration: Replace Provider implementations with network calls

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
