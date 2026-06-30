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

## UI System Findings

- EquipmentData stores both uid and item_id per slot to support returning items to inventory on unequip.
- Character panel uses Buttons for equipment slots instead of Labels, enabling click-to-equip/unequip.
- Popup selection list dynamically filters inventory items by slot type (weapon/armor/boots/accessory).
- Slot type colors: weapon=red, armor=blue, boots=green, accessory=gold for visual distinction.
- Stats display includes formatted bonus text (攻+5, 防+3, 血+20, 速+10) for equipped items.

## Excel 配置表

- 配置表统一使用 Excel (.xlsx) 作为源文件，运行时读取 JSON。
- `tools/excel_to_json.py` 支持中文表头自动映射为英文 key。
- stats 子对象字段 (attack, defense, max_hp, move_speed) 自动归入 stats 字典。
- 新增配置表只需在 `data/excel/` 下创建 xlsx，按约定填写表头即可。
- .gitignore 中排除了生成的 JSON 文件，只提交 Excel 源文件。
- `data/excel/.gdignore` 防止 Godot 导入 Excel 文件。

## 战斗系统

- CombatComponent 挂载到角色上，管理攻击、技能、受伤、Buff。
- HitBox (collision_layer=4) 和 HurtBox (collision_layer=8) 通过物理层隔离。
- HurtBox 需要加入 "hurt_box" 组，供全屏/AOE 技能查找目标。
- 弹道(projectile.gd)通过 area_entered 信号检测碰撞，支持穿透(max_pierce=-1 无限)。
- BuffManager 作为子节点挂载，独立处理 DoT 跳伤害和持续时间。
- player.gd 的 play_combat_animation 方法在动画资源到位前用定时器模拟。
- 受击后有 0.3s 硬直 + 0.5s 无敌帧，防止连续受击。

## Follow-up

- If the level size changes, update the camera bounds or drive them from a level metadata node.
- Move from hardcoded keys to Input Map actions once the control scheme stabilizes.
- Consider adding drag-and-drop support for inventory management.
- Add tooltip popups with detailed item information.
