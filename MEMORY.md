# MEMORY

## Findings

- The project started nearly empty and only contained the Godot project file and the imported map scene.
- `map_stitch_godot.tscn` already provides three collision polygons, so the prototype can use it directly as the level.
- The level canvas size from `map_stitch_godot.json` is `1376 x 768`, which is used for the initial camera limits.
- The first staircase is on the left side of the map, so a dedicated ladder trigger can cover it reliably.
- The imported action pack includes a ready-to-use `SpriteFrames` resource and a Godot scene, but both exported paths needed to be corrected to the real `res://assets/action/godot/` directory.
- The visual character scene is now nested under `player.tscn`, while `game_root.tscn` keeps the player separate from level scenes for future transitions.

## Decisions

- Player and enemy visible feet share local y=19: with 576px centered cells whose alpha content ends at y=144, `AnimatedSprite2D.position.y=182` under the scene-authored 0.5 wrapper scale yields `(182 + 144 - 288) * 0.5 = 19`. Player runtime must preserve the scene-authored CharacterActionSet transform instead of replacing 0.5 with character_config's 1.0.
- Imported character artwork uses a common local foot baseline at `y = 19` (`COLLISION_BODY_BOTTOM`). A custom body collision may use a different height, but its `position.y + shape_half_height` must still equal 19; slimu's 26px-high body is therefore centered at y=6.
- HurtBox collision geometry is body-local and never mirrored when a sprite turns. Runtime HitBox mirroring is owned exclusively by `HitBox.configure(window, facing)`; player/enemy facing code only flips the sprite. This prevents double mirroring and preserves scene-authored HurtBox offsets.
- An authored `AnimatedSprite2D.position.x` offset must mirror together with `flip_h`; otherwise the artwork shifts relative to the actor root while body-local HitBox/HurtBox geometry remains correct. Facing helpers mirror only the sprite-node X offset, never collision nodes.
- Enemy AI measures detection and combat distance on the X axis only. Enemy `attack_range` is a preferred stopping distance rather than a hit radius. During pursuit, ready skills whose own `range` reaches the player may be selected by weight; after the animation starts, the enemy remains in CHASE and resumes closing distance while that skill is on cooldown. Damage remains driven by HitBox/HurtBox overlap.
- Direct hits enter `HIT` for 0.1 seconds and immediately stop horizontal movement. Periodic DoT damage changes HP without replaying the hurt animation or applying hit stun. Death animations are paused explicitly on their final frame instead of calling `AnimatedSprite2D.stop()`, which resets to frame zero.
- Player movement and facing remain locked while the `hit`/`hurt` combat animation is still playing, even after the minimum 0.1-second HIT state expires, preventing hurt-animation sliding.
- All player combat animations are authoritative movement locks: horizontal velocity is cleared immediately and input/facing remain locked until the non-looping animation finishes, regardless of an earlier timer-based combat-state reset.
- CombatComponent revalidates its pending HitBox window every process tick in addition to `frame_changed`; interrupted, idle and dead actions forcibly deactivate it. Active HitBox debug drawing uses a higher absolute z-index than the always-on HurtBox overlay.
- F6 is only the HitBox debug master switch. Player/enemy root debug drawing additionally requires `HitBox.is_active()` and converts the CollisionShape2D global center back into actor-local coordinates; enemies redraw every frame so opening/closing active windows is reflected immediately.
- Every skill with configured `hit_windows` is synchronized to its animation frame. Melee windows enable HitBox monitoring and damage; projectile/AOE/penetrate windows draw the debug box and execute the skill once without adding duplicate melee collision damage.
- Melee damage is synchronized to `AnimatedSprite2D.frame_changed`. Per-character `combat_actions.json` stores active frame windows and forward-relative HitBox geometry; scene HitBox child offsets remain zero so runtime mirroring cannot double-apply offsets.
- The attack editor scans both `assets/characters` and `assets/enemies`. Its preview reads `AnimatedSprite2D.position`, `offset`, `scale`, and `centered` from `character_actions.tscn`, plus `display_offset` from `character_config.json`, while HitBox coordinates remain relative to the actor root.
- Enemy imports use the asset directory name as both prefab filename and scene root name. For example, `res://assets/enemies/slimu` generates `godot/slimu.tscn` with root node `slimu`; `EnemySpawner` derives this path from the enemy table's existing `asset` field.

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

## 关卡系统

- game_root.tscn 不再硬编码关卡场景，LevelContainer 由 LevelManager 动态加载。
- 首个关卡由 levels.xlsx 配置表中第一行决定，修改 Excel 即可换首关。
- 关卡切换通过 LevelPortal (Area2D) 触发，设置 target_level_id 和 spawn_position。
- Player 需要加入 "player" group，供 portal 检测。
- LevelManager 注册到 GameRegistry.level_manager，全局可访问。
- R 键测试重载当前关卡。

## Follow-up

- If the level size changes, update the camera bounds or drive them from a level metadata node.
- Move from hardcoded keys to Input Map actions once the control scheme stabilizes.
- Consider adding drag-and-drop support for inventory management.
- Add tooltip popups with detailed item information.
