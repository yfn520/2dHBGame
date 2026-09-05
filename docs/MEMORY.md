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
