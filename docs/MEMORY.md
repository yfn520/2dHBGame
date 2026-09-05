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

## Follow-up

- If the level size changes, update the camera bounds or drive them from a level metadata node.
- Move from hardcoded keys to Input Map actions once the control scheme stabilizes.

## BGM 发布与运行时

- `data/music.json` 由网页音乐编排台作为唯一写入方发布；运行时只通过 `MusicConfig` 读取。首次发布前文件可缺失，不能在 Godot 侧手工补写。
- 关卡 BGM 的权威优先级是 `music.json.tracks["level:<id>"].path`，旧 `levels.json.bgm` 只保留兼容回退。`LevelManager` 在关卡实例加载完成后切曲，缺轨会淡出旧曲。
- `AudioManager` 使用两个独立 `AudioStreamPlayer` 交叉淡入淡出，不能把 BGM 放回 SFX 池；否则长音频会被池复用和多音节限制打断。
- `tools/validate_data.py` 对发布后的 music.json 校验格式、资源路径及 derived 轨的 `derived_from`/`init_noise_level`，对应 headless 守卫为 `tests/music_config.gd`。
- 战斗曲不能在刷怪时触发：`Enemy` 只在实际进入 CHASE/ATTACK 时上报交战，`EnemySpawner` 聚合同屏敌人并按 Boss 优先发出 `combat_started`；全部脱战/死亡后由 `LevelManager.restore_level_bgm()` 恢复关卡曲。Boss 轨缺失时回退 battle，二者都缺失时保持关卡曲。

## 章节回响可重刷

- `data/echo_spawns.json` 与回响敌人配置由发布脚本 `tools/gen_echo_data.py` 生成；运行时只读取，修改数据结构后必须同步 `tools/validate_data.py` 与 `tests/echo_spawns.gd`。
- 回响怪不能带 `spawn_key`，否则会继承剧情怪的永久击杀记录；但 `EnemySpawner.spawn_enemy()` 仍必须无条件将实例 `add_child` 到关卡容器，不能把挂树逻辑误放进 `spawn_key` 条件块。
- 群怪的 `respawn_s` 是每组被清空后的完整重生延迟。回响全图首轮通关只计一次 `echo_clears:<chapter_id>`，之后群怪仍持续波次重生；精英/Boss 本次进图不重生，Boss 击杀另记 `echo_boss_kills:<chapter_id>`。
- 回响 Boss 的 `drop_items` 保留原来 chance=1 的唯一装备，首杀保证；`echo_drop_items` 是日常 farming 表，并仅对这些原有唯一装备追加 0.08 概率。原 Boss 没有唯一装备时不应凭空添加该规则。

## NPC 地图摆放

- `data/npc_placements.json` 的权威坐标来自 `正式剧情/六章主线任务设计案.md` 附录 A，经 `frontend/scripts/sync-npc-placements-to-godot.ts` 备份后发布，禁止只改运行时 JSON。
- 余晖城是约 4147 像素宽的三段拼接街区，常驻 NPC 不能全部塞进一个 1456 像素视口。商人应落在左街摊位，会馆/守卫/铁匠保留中央剧情锚点，进度彩蛋 NPC 分散到左右居民区；`npcPlacementImporter.test.ts` 守住全体横向最小间距 220 像素。

## 任务世界内容表现（2026-09-05）

- `runtime_world_content.json` 的 `area_event`、`named_event`、`pickup` 是工作台发布的任务实体来源；触发器/交互逻辑仍分别由 `WorldAreaTrigger`、`WorldInteractable` 处理。
- 这些条目必须经 `WorldTaskVisual` 生成可见关卡物件：区域事件提供路线与边界桩，护送粮车、信标、营地、机关、证物等依名称/事件语义生成不同轮廓。不得退回只显示调试矩形或菱形占位。
- 回归守卫：`tests/world_task_visuals.gd` 会实例化全部任务区域、命名交互和拾取物，并要求粮种车事件拥有完整可见模型。
- 地面拾取物优先读取 `items.json` 中实际存在的 PNG；仅有路径声明、但文件尚未生成时才回退到语义占位物。网页物品图标工作台的“选择任务缺图”会从 `runtime_world_content.json` 交叉出这批条目并只选择缺少真实文件的物品。

## 剧情招募后的相机重绑（2026-09-05）

- 剧情的 `set_second_hero` / `recruit_hero` 会触发 `PartyManager` 重建队伍；新主控的 Camera2D 会回到角色预制体默认偏移。每次 `switch_character` 后必须调用 `LevelManager.refresh_active_camera()`，重新应用当前关卡边界和 `ground_line_y`，否则对话/招募后会露出地图底部，像地图整体向上移。
- 回归守卫：`tests/party_camera_rebind.gd` 验证每次主控切换都会刷新当前关卡相机。
