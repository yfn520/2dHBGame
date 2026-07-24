# MEMORY

## Findings

- The project started nearly empty and only contained the Godot project file and the imported map scene.
- `map_stitch_godot.tscn` already provides three collision polygons, so the prototype can use it directly as the level.
- The level canvas size from `map_stitch_godot.json` is `1376 x 768`, which is used for the initial camera limits.
- The first staircase is on the left side of the map, so a dedicated ladder trigger can cover it reliably.
- The imported action pack includes a ready-to-use `SpriteFrames` resource and a Godot scene, but both exported paths needed to be corrected to the real `res://assets/action/godot/` directory.
- The visual character scene is now nested under `player.tscn`, while `game_root.tscn` keeps the player separate from level scenes for future transitions.

## Decisions

- Skill VFX authoring uses one exchange contract: `assets/skill_fx/<bundle_id>/skill_fx_bundle.json`. The web tool may create packages but never writes `skills.json`; the Godot Skill Sequence Editor is the only importer.
- A VFX plan may trigger only from `skill_start`, a real action event, a real hit-window start, or a real skill-node index. Package paths must remain inside their own bundle and all references are rejected before export/import when stale.
- Imported `play_effect` nodes carry `source_bundle_id` and `source_track_id`. Import first removes nodes from the previously active generated package and then inserts the selected package, so one skill has one active VFX package and repeated imports stay idempotent.
- The importer preserves gameplay and existing wait nodes. When a matching wait node is absent, event/window timing becomes `delay_ms` on the effect rather than a new blocking skill-sequence wait.
- `CombatComponent` schedules delayed effects independently. Result-target effects subscribe before the hit and apply delay only after a real result, preventing missed hits and avoiding changes to skill execution timing.
- VFX visuals support package scene, anchor, local/world/fullscreen space, follow behavior, facing mirror, lifetime, scale, rotation, tint, opacity, layer, and additive/screen/normal blend authored by the generated scene.
- The optional user VFX brief defaults to empty. The director displays every action frame and sends only the frames explicitly selected by the user. `智能选择` preselects start/end, action-event, hit-window, and a few motion-spread frames; full-select and clear are also available. The selection is saved with the editing state.
- Per-track AI generation is user-driven draw-card generation: one click makes exactly one image-model request using the full marked action storyboard. The returned 2x2 card contains start/peak/dissolve keys, is processed into the atlas, and is retained with its exact prompt for later reselection.
- VFX planning is also a draw-card flow: one click requests exactly one structured proposal, automatically selects it, and retains up to 20 prior proposal cards for later switching. The three-proposal comparison flow is removed.
- Proposal generation exposes elapsed seconds and cancellation in the page, keeps failures in a persistent alert, aborts the browser wait at 80 seconds, and enforces a 75-second backend timeout. Backend code changes require restarting the non-reloading local Uvicorn process.
- Effect Workbench save/load includes director proposals, per-proposal prompts, up to 20 draw-card results per track, and currently selected atlases. Browser directory permissions cannot be serialized, so a loaded session reconnects the Godot folder before export.
- Verification for the V1 contract includes five backend schema/package tests, three frontend transaction tests, a Godot importer idempotence/gameplay-preservation test, Godot 4.7 headless parse, targeted frontend lint, Vite production build, and a visible disconnected-state browser smoke test.

- NPC authoring is a hard cut with no legacy fallback. `data/npc_placements.json` is the only placement source, and `levels.json.npcs` is unsupported.
- Each NPC runtime visual is a self-contained `assets/npcs/<slug>` package. `npc_asset.json` paths must remain inside that directory and its `id` must equal the directory slug.
- The `NpcActor` root position is the foot point. Generated `npc_visual.tscn` owns `AnimatedSprite2D.offset`, resource display scale, `NameLabel`, and `QuestLabel`; placement scale stays on the actor root as a separate map-instance layer.
- The web workshop stages generated resources in memory. It validates all resources and five JSON documents, checks original file hashes, completes a mandatory backup, then writes resources followed by data. Hashes update only after complete success.
- A failed resource write is rolled back by restoring all five original JSON texts and deleting only newly created NPC directories. A backup failure starts no writes.
- Character reuse is authoring-time conversion only: the real idle row is read from the character manifest and every idle frame is copied into a new NPC atlas. Runtime NPC code never reads `characters.json`.
- NPC Step 6 defaults to quest generation and requires an explicit `talk`, `kill`, or `collect` choice. Kill targets come from `enemies.json`; collect targets and optional item rewards come from `items.json`.
- AI receives selected display names but never NPC/dialogue/quest/enemy/item IDs. It returns a semantic dialogue blueprint, four quest-state entries, a quest blueprint, and stable start/turn-in intent keys using a fixed placeholder whitelist.
- Blueprint validation never triggers an automatic AI repair. Invalid raw JSON stays editable and “重新校验” performs structure validation only.
- Staging allocates local IDs, creates `start_quest` / `turn_in_quest` interaction bindings, preserves `text_template`, and resolves final text. Orchestration edits re-resolve template-driven text while `text_mode=manual` preserves hand-written lines.
- NPC workbench saves retain the resource-panel source snapshot after staging, so saving from the Hub or orchestration step still preserves profile text, the original mother image, idle sheet, individual idle frames, and per-frame transforms. Legacy saves with `resourcePanel=null` can reconstruct editable frames from the compiled atlas; profile text and original pre-atlas transforms require a matching earlier source snapshot because the compiled Godot package never contained them.
- Runtime dialogue completion records talk only. Quest acceptance and delivery are explicit intent dispatches; collect items are consumed only on successful delivery, completed quests cannot pay rewards twice, and `quest_updated` refreshes UI and schedules a save.
- Map placement resolves PackedScene references recursively until the map scene's `source.png` is found. Instance IDs begin with the NPC package slug and are unique per level.

- Playable characters are complete independent `CharacterBody2D` prefabs. `player.tscn` is now a `PartyManager` control container whose exported `Array[PackedScene]` supports inspector drag-and-drop lineup configuration; it currently contains only `new_kivin` at index 0.
- Character artwork alignment is prefab-owned: `visual.position + (foot_center - image_center) * visual.scale` must equal the body collision bottom center. For `new_kivin`, `(-11, -29.5) + (11, 50) = (0, 20.5)`.
- `PartyManager` is an editor tool and previews the scene at `initial_active_index` directly in `player.tscn`; the preview has no owner and is never serialized or spawned at runtime.
- Character import reads each asset's JSON `foot_center` and `frameSize`, then computes `offset = (-(foot.x-center.x)*scale, collision_bottom-(foot.y-center.y)*scale)`. Collision-bottom coordinates are actor-local and must never be multiplied by sprite scale.
- Character import repairs incomplete external `spriteframes.tres` files: it always restores the atlas Texture2D declaration and binds every AtlasTexture subresource to `ExtResource("sheet")`. A SpriteFrames file with valid regions but missing these bindings produces invisible animations.
- New-format assets with top-level `bodyBox` use `foot_origin`: the CharacterBody2D root is the JSON `foot_center`, artwork offset is `(image_center-foot_center)*scale`, and body/ladder/HurtBox RectangleShape sizes and positions are numeric bodyBox values multiplied by display scale while every CollisionShape2D node keeps scale 1. Legacy assets without bodyBox retain body-centered coordinates.
- Enemy prefab generation follows the same bodyBox contract as playable characters. For bodyBox enemies, both the root physics CollisionShape2D and HurtBox shape use the generated `body_size` and `body_position`; legacy enemies retain the old 24x38 body and 20x36 HurtBox defaults.
- The character import menu generates all character prefabs and does not mutate `player.tscn`; this prevents filesystem enumeration order or stale resource UIDs from silently changing the active hero.

- Asset import explicitly distinguishes `resource_type=character` under `assets/characters` from `resource_type=enemy` under `assets/enemies`. New enemy skill lists are derived from enemy skill configs whose animation names actually exist in that enemy manifest; existing curated lists are preserved except for skills whose animation disappeared.
- Player body collision and HurtBox remain centered on the actor root; any scene-authored CharacterActionSet X correction belongs only to the artwork and must mirror with facing.
- When a scene intentionally authors a non-zero `CharacterActionSet.position.x`, that visual-root offset mirrors with `flip_h` (for example player left=-5.005, right=+5.005). Mirroring the nested AnimatedSprite2D is ineffective when its own position is zero.
- Skills now carry `description` and `effect_timing` (`cast_start`, `active_frame`, or `animation_end`). Self buffs configured for `active_frame` are applied once when the animation enters a configured hit window instead of immediately on key press.
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
- Collision/HurtBox/HitBox debug geometry is rendered by a dedicated absolute-z CombatDebugOverlay above character sprites. Drawing on the actor root placed rectangles behind z-indexed artwork, so opaque pixels hid half the box and falsely made correctly aligned boxes look offset.
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

## UI 统一管理架构

- GameRoot 只保留一个 UIRoot 节点作为 UI 入口；旧的 InventoryPanel/CharacterPanel/BattleHud 不再直接挂载在 GameRoot 上。
- UIRoot 管理 5 个固定 CanvasLayer：HUDLayer(z=10)、ScreenLayer(z=20)、PopupLayer(z=30)、NotificationLayer(z=40)、DebugLayer(z=100)。
- BattleHud 常驻 HUDLayer；MainMenu 和 TaskDrawer 属于 ScreenLayer；装备选择弹窗属于 PopupLayer；DebugPanel 属于 DebugLayer。
- UISkin 资源持有共享 Theme 和语义化 Icon 映射；业务页面通过 `skin.get_icon(StringName(name))` 获取图标，不硬编码 PNG 路径。
- 皮肤迁移路径：StyleBoxFlat 线框 → 独立透明 PNG + 九宫格 StyleBoxTexture → AtlasTexture；迁移只改 UISkin，业务代码零改动。
- Escape 关闭优先级：Popup 栈顶 → TaskDrawer → MainMenu；B/C 直接切到 inventory/equipment 页。
- 菜单打开时世界继续模拟；移动/跳跃/Tab 切人保留，J/K/L/U 手动施法通过 `PartyManager.set_manual_skill_input_enabled(false)` 屏蔽。
- 主菜单最大约 900×520，内含左侧导航和右侧 ScrollContainer；未实现的时装和宠物页签隐藏。
- TaskDrawer 为右侧滑入抽屉；任务系统未实现时展示真实空状态而非假数据。
- `UIRoot.close_top()` 使用 `var top: Control = _popup_stack.back()` 显式类型标注，避免 Godot 4.7 的 Variant 推断报错。
- `MainMenu` 中 `_pages` 字典取值后需显式标注 `var page: Control = _pages[page_key]`，否则 `page.get_node_or_null(...)` 返回 Variant 导致 `var spin := ...` 推断失败。
- `MainMenu` 的 `_skill_rows` 字典必须存入 `fallback` 字段，供 `_refresh_skills_page` 的 `skill.get("name", row_data["fallback"])` 兜底。
- `MarginContainer` 的间距用 `add_theme_constant_override("margin_*", n)`，不是 `add_theme_constant(...)`。
- InventoryPanel 的场景和脚本已删除；CharacterPanel 脚本保留作为历史参考但不再挂载。

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
