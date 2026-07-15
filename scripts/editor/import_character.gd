extends SceneTree

const MANIFEST_FILE := "manifest.json"
const ACTIONS_SCENE_FILE := "godot/character_actions.tscn"
const SPRITEFRAMES_FILE := "godot/spriteframes.tres"
const ATLAS_FILE := "godot/all_actions_atlas.png"
const CONFIG_FILE := "character_config.json"
const DEFAULT_TARGET_HEIGHT := 52.0
const COLLISION_BODY_BOTTOM := 19.0  # CollisionShape2D.size.y / 2 = 38/2
const AIRangeCompiler = preload("res://scripts/system/ai_range_compiler.gd")
const SKILLS_PATH := "res://data/skills.json"
const CHARACTERS_PATH := "res://data/characters.json"
const ENEMIES_PATH := "res://data/enemies.json"


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	if options.is_empty():
		_print_usage()
		quit(1)
		return

	var error := _import_character(options)
	if error != OK:
		push_error("Character import failed with code %s" % error)
		quit(1)
		return

	quit()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var options := {
		"source_dir": "",
		"apply_player": "",
		"target_height": DEFAULT_TARGET_HEIGHT,
		"display_scale_override": -1.0,
		"default_facing": "left",
	}

	var index := 0
	while index < args.size():
		var token := args[index]
		var next_value := ""
		if index + 1 < args.size():
			next_value = args[index + 1]

		match token:
			"--source":
				options["source_dir"] = next_value
				index += 2
			"--apply-player":
				options["apply_player"] = next_value
				index += 2
			"--target-height":
				options["target_height"] = float(next_value)
				index += 2
			"--display-scale":
				options["display_scale_override"] = float(next_value)
				index += 2
			"--facing":
				options["default_facing"] = next_value.to_lower()
				index += 2
			_:
				index += 1

	if options["source_dir"].is_empty():
		return {}

	return options


func _import_character(options: Dictionary) -> int:
	var source_dir: String = options["source_dir"]
	var manifest_path := source_dir.path_join(MANIFEST_FILE)
	var actions_scene_path := source_dir.path_join(ACTIONS_SCENE_FILE)
	var spriteframes_path := source_dir.path_join(SPRITEFRAMES_FILE)
	var atlas_path := source_dir.path_join(ATLAS_FILE)
	var config_path := source_dir.path_join(CONFIG_FILE)

	for path in [manifest_path, actions_scene_path, spriteframes_path, atlas_path]:
		if not FileAccess.file_exists(path):
			push_error("Missing required file: %s" % path)
			return ERR_FILE_NOT_FOUND

	var manifest_text := FileAccess.get_file_as_string(manifest_path)
	var manifest := JSON.new()
	var parse_error := manifest.parse(manifest_text)
	if parse_error != OK:
		push_error("Failed to parse manifest: %s" % manifest_path)
		return parse_error

	var manifest_data := manifest.data as Dictionary
	var display_scale: float = float(options["display_scale_override"]) if float(options["display_scale_override"]) > 0.0 else 1.0
	var frame_cell_height := _get_frame_cell_height(manifest_data)
	var external_combat := _load_external_combat_data(source_dir)
	var is_production := not external_combat.is_empty()
	var foot_center := _get_foot_center(external_combat, manifest_data)
	var apply_player_path := String(options["apply_player"])
	var body_bottom := _get_scene_body_bottom(apply_player_path, COLLISION_BODY_BOTTOM)
	var frame_size: Dictionary = manifest_data.get("frameSize", {})
	var image_center := Vector2(float(frame_size.get("width", frame_cell_height)), float(frame_size.get("height", frame_cell_height))) * 0.5
	var foot_from_center := foot_center - image_center
	var display_offset := Vector2(
		-foot_from_center.x * display_scale,
		body_bottom - foot_from_center.y * display_scale
	)
	var config := {
		"character_name": manifest_data.get("characterName", source_dir.get_file()),
		"scene_name": source_dir.get_file(),
		"default_animation": manifest_data.get("defaultAnimation", "idle"),
		"actions_scene": actions_scene_path,
		"spriteframes": spriteframes_path,
		"combat_actions": source_dir.path_join("combat_actions.json"),
		"atlas": atlas_path,
		"display_scale": display_scale,
		"display_offset": {
			"x": display_offset.x,
			"y": display_offset.y
		},
		"faces_right_by_default": String(options["default_facing"]) == "right",
		"centered": true,
		"target_display_height": float(options["target_height"]),
		"available_actions": manifest_data.get("exportOrder", []),
		"unified_box": manifest_data.get("unifiedBox", {}),
		"frame_cell_height": frame_cell_height,
		"production_format": is_production,
		"foot_center": {"x": foot_center.x, "y": foot_center.y},
		"alignment": "json_foot_center_to_collision_bottom",
		"collision_bottom": body_bottom,
		"combat_source": source_dir.path_join("combat/attack_frames.json") if is_production else ""
	}

	var spriteframes_text := FileAccess.get_file_as_string(spriteframes_path)
	spriteframes_text = _ensure_spriteframes_atlas(spriteframes_text, atlas_path)
	spriteframes_text = _ensure_spriteframes_animation_loops(spriteframes_text)
	var write_error := _write_text_file(spriteframes_path, spriteframes_text)
	if write_error != OK:
		return write_error

	var actions_text := FileAccess.get_file_as_string(actions_scene_path)
	actions_text = _replace_ext_resource_path(
		actions_text,
		"SpriteFrames",
		"spriteframes.tres",
		spriteframes_path
	)
	actions_text = _ensure_centered(actions_text)
	write_error = _write_text_file(actions_scene_path, actions_text)
	if write_error != OK:
		return write_error

	write_error = _write_text_file(config_path, JSON.stringify(config, "\t") + "\n")
	if write_error != OK:
		return write_error

	if not apply_player_path.is_empty():
		if not FileAccess.file_exists(apply_player_path):
			push_error("Player scene not found: %s" % apply_player_path)
			return ERR_FILE_NOT_FOUND

		var player_text := FileAccess.get_file_as_string(apply_player_path)
		player_text = _replace_ext_resource_path(
			player_text,
			"PackedScene",
			"character_actions.tscn",
			actions_scene_path
		)
		player_text = _replace_character_transform(player_text, display_scale, display_offset)
		write_error = _write_text_file(apply_player_path, player_text)
		if write_error != OK:
			return write_error

	if is_production:
		_write_external_combat_actions(source_dir, external_combat, display_scale, body_bottom)
	else:
		_ensure_combat_actions_config(source_dir, manifest_data, display_scale)
	# 生成模板场景（只在非 --apply-player 时生成，即怪物/新角色）
	if apply_player_path.is_empty():
		var template_path := source_dir.path_join("godot/%s.tscn" % source_dir.get_file())
		write_error = _generate_template_scene(template_path, actions_scene_path, config)
		if write_error != OK:
			push_warning("模板场景生成失败: %s" % template_path)
		else:
			var legacy_scene_path := source_dir.path_join("godot/character_template.tscn")
			if FileAccess.file_exists(legacy_scene_path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_scene_path))

	print("Imported character:")
	print("  source: ", source_dir)
	print("  actions: ", actions_scene_path)
	print("  config: ", config_path)
	if apply_player_path.is_empty():
		print("  template: ", source_dir.path_join("godot/%s.tscn" % source_dir.get_file()))
	else:
		print("  applied_to_player: ", apply_player_path)

	# 重新导入动作后，自动重编译使用该资源的技能 ai_range_cache
	_recompile_ai_range_caches(source_dir)

	return OK


## 导入完成后，为使用该资源的所有技能重编译 ai_range_cache。
## 不覆盖技能节点、伤害、Buff、冷却和人工填写的弹道 AI 起手距离。
func _recompile_ai_range_caches(source_dir: String) -> void:
	var asset_path := ProjectSettings.localize_path(source_dir)
	if asset_path.is_empty():
		asset_path = source_dir
	var skill_ids := _collect_skill_ids_for_asset(asset_path)
	if skill_ids.is_empty():
		print("  ai_range_cache: 该资源未关联任何技能，跳过")
		return

	# 读取 skills.json
	var file := FileAccess.open(SKILLS_PATH, FileAccess.READ)
	if file == null:
		push_warning("ai_range_cache 重编译：无法读取 skills.json")
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_warning("ai_range_cache 重编译：skills.json 解析失败")
		return
	var data: Dictionary = json.data

	var recompiled := 0
	for skill_id in skill_ids:
		var key := str(skill_id)
		if not data.has(key):
			continue
		var cache := AIRangeCompiler.compile(int(skill_id), asset_path)
		if cache.is_empty() or cache.get("entries", []).is_empty():
			continue
		var raw: Dictionary = data[key]
		raw["ai_range_cache"] = cache
		data[key] = raw
		recompiled += 1

	if recompiled == 0:
		print("  ai_range_cache: 没有可重编译的技能")
		return

	var out := FileAccess.open(SKILLS_PATH, FileAccess.WRITE)
	if out == null:
		push_warning("ai_range_cache 重编译：无法写入 skills.json")
		return
	out.store_string(JSON.stringify(data, "\t") + "\n")
	print("  ai_range_cache: 已重编译 %d 个技能" % recompiled)


## 查找使用指定 asset 路径的角色/怪物所拥有的全部技能 ID。
func _collect_skill_ids_for_asset(asset_path: String) -> Array:
	var ids: Array = []
	for table_path in [CHARACTERS_PATH, ENEMIES_PATH]:
		var table := _load_json(table_path)
		for key in table:
			var row_value: Variant = table[key]
			if not row_value is Dictionary:
				continue
			var row: Dictionary = row_value
			if String(row.get("asset", "")) != asset_path:
				continue
			var normal := int(row.get("normal_skill", 0))
			if normal > 0 and not ids.has(normal):
				ids.append(normal)
			for skill_value in row.get("skills", []):
				var sid := int(skill_value)
				if sid > 0 and not ids.has(sid):
					ids.append(sid)
			var unlocks: Dictionary = row.get("skill_unlocks", {})
			for slot_key in unlocks:
				var slot_value: Variant = unlocks[slot_key]
				if slot_value is Dictionary:
					var sid2 := int((slot_value as Dictionary).get("skill_id", 0))
					if sid2 > 0 and not ids.has(sid2):
						ids.append(sid2)
				else:
					var sid3 := int(slot_value)
					if sid3 > 0 and not ids.has(sid3):
						ids.append(sid3)
	return ids


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK or not j.data is Dictionary:
		return {}
	return j.data


func _load_external_combat_data(source_dir: String) -> Dictionary:
	var path := source_dir.path_join("combat/attack_frames.json")
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("Failed to parse external combat frames: %s" % path)
		return {}
	return json.data


func _get_foot_center(combat_data: Dictionary, manifest: Dictionary) -> Vector2:
	for action in combat_data.get("actions", []):
		if action is Dictionary:
			var foot: Dictionary = action.get("foot_center", {})
			if not foot.is_empty():
				return Vector2(float(foot.get("x", 0.0)), float(foot.get("y", 0.0)))
	for action in manifest.get("actions", []):
		if action is Dictionary:
			var runtime: Dictionary = action.get("runtimeAction", {})
			var foot: Dictionary = runtime.get("foot_center", {})
			if not foot.is_empty():
				return Vector2(float(foot.get("x", 0.0)), float(foot.get("y", 0.0)))
	var frame: Dictionary = manifest.get("frameSize", {})
	return Vector2(float(frame.get("width", 0.0)) * 0.5, float(frame.get("height", 0.0)))


func _get_scene_body_bottom(scene_path: String, fallback: float) -> float:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return fallback
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return fallback
	var instance := packed.instantiate()
	var collision := instance.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var result := fallback
	if collision != null and collision.shape is RectangleShape2D:
		result = collision.position.y + (collision.shape as RectangleShape2D).size.y * 0.5
	instance.free()
	return result


func _write_external_combat_actions(source_dir: String, source: Dictionary, display_scale: float, body_bottom: float) -> void:
	var actions_data: Dictionary = {}
	var frame_index_base := int(source.get("frameIndexBase", 1))
	var action_values: Array = source.get("actions", [])
	if action_values.is_empty() and source.has("actionName"):
		action_values = [source]
	for action_value in action_values:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		var action_name := String(action.get("actionName", ""))
		if action_name.is_empty():
			continue
		actions_data[action_name] = _convert_external_combat_action(action, display_scale, body_bottom, frame_index_base)
	var data := {
		"version": 3,
		"source": "combat/attack_frames.json",
		"source_schema_version": int(source.get("schemaVersion", 2)),
		"coordinate_space": "actor_root_pixels",
		"sprite_scale": display_scale,
		"actions": actions_data,
	}
	_write_text_file(source_dir.path_join("combat_actions.json"), JSON.stringify(data, "\t") + "\n")


func _convert_external_combat_action(action: Dictionary, display_scale: float, body_bottom: float, frame_index_base: int) -> Dictionary:
	var windows: Array = []
	for attack_value in action.get("attacks", []):
		if not attack_value is Dictionary:
			continue
		var attack: Dictionary = attack_value
		var start_frame := _external_frame_to_godot(int(attack.get("startFrame", 1)), frame_index_base)
		var end_frame := maxi(start_frame, _external_frame_to_godot(int(attack.get("endFrame", start_frame + frame_index_base)), frame_index_base))
		for region_value in attack.get("regions", []):
			if not region_value is Dictionary:
				continue
			var region: Dictionary = region_value
			var region_scale := float(region.get("scale", 1.0))
			var authored_x := float(region.get("forwardDistance", 0.0)) * display_scale
			windows.append({
				"id": "%s:%s" % [String(attack.get("id", "")), String(region.get("id", ""))],
				"start_frame": start_frame,
				"end_frame": end_frame,
				"forward": absf(authored_x),
				"authored_x": authored_x,
				"y": body_bottom + float(region.get("yOffset", 0.0)) * display_scale,
				"width": maxf(1.0, float(region.get("width", 1.0)) * display_scale * region_scale),
				"height": maxf(1.0, float(region.get("height", 1.0)) * display_scale * region_scale),
				"source_attack_id": String(attack.get("id", "")),
				"source_region_id": String(region.get("id", "")),
			})
	windows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("start_frame", 0)) < int(right.get("start_frame", 0))
	)
	var events := _convert_external_events(action.get("events", []), frame_index_base)
	if events.is_empty() and not windows.is_empty():
		events.append({
			"id": "compat-release",
			"name": "release",
			"frame": int((windows[0] as Dictionary).get("start_frame", 0)),
			"fallback": true,
		})
	return {
		"hit_windows": windows,
		"events": events,
		"cancel_windows": _convert_external_windows(action.get("cancelWindows", []), frame_index_base),
		"armor_windows": _convert_external_windows(action.get("armorWindows", []), frame_index_base),
		"movement_windows": _convert_external_movement_windows(action.get("movementWindows", []), display_scale, frame_index_base),
		"sockets": _convert_external_sockets(action.get("sockets", {}), display_scale, body_bottom, frame_index_base),
	}


func _external_frame_to_godot(frame: int, frame_index_base: int) -> int:
	return maxi(0, frame - frame_index_base)


func _convert_external_events(raw_events: Variant, frame_index_base: int) -> Array:
	var events: Array = []
	if not raw_events is Array:
		return events
	for value in raw_events:
		if not value is Dictionary:
			continue
		var event: Dictionary = value
		events.append({
			"id": String(event.get("id", "")),
			"name": String(event.get("name", "")),
			"frame": _external_frame_to_godot(int(event.get("frame", 1)), frame_index_base),
		})
	return events


func _convert_external_windows(raw_windows: Variant, frame_index_base: int) -> Array:
	var windows: Array = []
	if not raw_windows is Array:
		return windows
	for value in raw_windows:
		if not value is Dictionary:
			continue
		var window: Dictionary = value
		var start_frame := _external_frame_to_godot(int(window.get("startFrame", 1)), frame_index_base)
		var end_frame := maxi(start_frame, _external_frame_to_godot(int(window.get("endFrame", start_frame + frame_index_base)), frame_index_base))
		windows.append({"id": String(window.get("id", "")), "start_frame": start_frame, "end_frame": end_frame})
	return windows


func _convert_external_movement_windows(raw_windows: Variant, display_scale: float, frame_index_base: int) -> Array:
	var windows: Array = _convert_external_windows(raw_windows, frame_index_base)
	if not raw_windows is Array:
		return windows
	for index in range(mini(windows.size(), (raw_windows as Array).size())):
		var source_window = (raw_windows as Array)[index]
		if source_window is Dictionary:
			(windows[index] as Dictionary)["delta_x"] = float((source_window as Dictionary).get("deltaX", 0.0)) * display_scale
	return windows


func _convert_external_sockets(raw_sockets: Variant, display_scale: float, body_bottom: float, frame_index_base: int) -> Dictionary:
	var sockets: Dictionary = {}
	if not raw_sockets is Dictionary:
		return sockets
	for socket_name in (raw_sockets as Dictionary).keys():
		var frames_value = (raw_sockets as Dictionary).get(socket_name, [])
		if not frames_value is Array:
			continue
		var frames: Array = []
		for value in frames_value:
			if not value is Dictionary:
				continue
			var socket: Dictionary = value
			frames.append({
				"frame": _external_frame_to_godot(int(socket.get("frame", 1)), frame_index_base),
				"x": float(socket.get("x", 0.0)) * display_scale,
				"y": body_bottom + float(socket.get("y", 0.0)) * display_scale,
			})
		sockets[String(socket_name)] = frames
	return sockets


func _ensure_combat_actions_config(source_dir: String, manifest_data: Dictionary, display_scale: float) -> void:
	var output_path := source_dir.path_join("combat_actions.json")
	if FileAccess.file_exists(output_path):
		return
	var hit_frame := 0
	var has_attack := false
	for action in manifest_data.get("actions", []):
		if action is Dictionary and String(action.get("actionName", "")) == "attack":
			has_attack = true
			hit_frame = maxi(0, int(action.get("frameCount", 1)) / 2)
			break
	var actions_data: Dictionary = {}
	if has_attack:
		actions_data["attack"] = {
			"hit_windows": [{
				"start_frame": hit_frame,
				"end_frame": hit_frame,
				"forward": 30.0,
				"y": 0.0,
				"width": 20.0,
				"height": 20.0,
			}]
		}
	var data := {
		"version": 1,
		"sprite_scale": display_scale,
		"actions": actions_data,
	}
	_write_text_file(output_path, JSON.stringify(data, "\t") + "\n")


## 获取角色内容高度（drawHeight 或 unifiedBox.height）
func _get_content_height(manifest_data: Dictionary) -> float:
	var frame_rects: Array = manifest_data.get("frameRects", [])
	if frame_rects.size() > 0:
		var draw_h := float(frame_rects[0].get("drawHeight", 0))
		if draw_h > 0.0:
			return draw_h
	var unified_box: Dictionary = manifest_data.get("unifiedBox", {})
	var height := float(unified_box.get("height", 144.0))
	return height if height > 0.0 else 144.0


## 获取帧 cell 高度（sprite 尺寸），用于计算 anchor 偏移
func _get_frame_cell_height(manifest_data: Dictionary) -> float:
	var frame_rects: Array = manifest_data.get("frameRects", [])
	if frame_rects.size() > 0:
		var cell_h := float(frame_rects[0].get("cellHeight", 0))
		if cell_h > 0.0:
			return cell_h
	var unified_box: Dictionary = manifest_data.get("unifiedBox", {})
	var height := float(unified_box.get("height", 144.0))
	return height if height > 0.0 else 144.0


## 获取内容在帧内的 Y 偏移（从帧顶部到内容顶部）
func _get_content_offset_y(manifest_data: Dictionary) -> float:
	var frame_rects: Array = manifest_data.get("frameRects", [])
	if frame_rects.size() > 0:
		return float(frame_rects[0].get("offsetY", 0))
	return 0.0


## centered=true: origin在cell中心。
## 内容底边在sprite-local坐标 = -(cellH/2) + contentOffsetY + drawH
## world_bottom = pos_y + local_bottom * scale = collision_bottom
## => pos_y = collision_bottom - local_bottom * scale
##          = collision_bottom + (cellH/2 - contentOffsetY - drawH) * scale
func _get_display_offset_y(manifest_data: Dictionary, display_scale: float) -> float:
	var cell_h := _get_frame_cell_height(manifest_data)
	var content_offset_y := _get_content_offset_y(manifest_data)
	var draw_h := _get_content_height(manifest_data)
	var anchor_dist := cell_h * 0.5 - content_offset_y - draw_h
	return snappedf(COLLISION_BODY_BOTTOM + anchor_dist * display_scale, 0.1)


func _get_display_scale(manifest_data: Dictionary, target_height: float) -> float:
	var height := _get_content_height(manifest_data)
	return snappedf(target_height / height, 0.001)


func _ensure_spriteframes_atlas(text: String, atlas_path: String) -> String:
	var lines := text.split("\n")
	var texture_line := '[ext_resource type="Texture2D" path="%s" id="sheet"]' % atlas_path
	var texture_index := -1
	for index in range(lines.size()):
		var line: String = lines[index]
		if line.contains("[ext_resource") and line.contains('type="Texture2D"') and line.contains("all_actions_atlas.png"):
			texture_index = index
			lines[index] = texture_line
			break
	if texture_index == -1:
		lines.insert(1, "")
		lines.insert(2, texture_line)

	var index := 0
	while index < lines.size():
		if lines[index].begins_with('[sub_resource type="AtlasTexture"'):
			var next_index := index + 1
			if next_index >= lines.size() or not lines[next_index].begins_with("atlas = ExtResource("):
				lines.insert(next_index, 'atlas = ExtResource("sheet")')
				index += 1
		index += 1
	return "\n".join(lines)


func _ensure_spriteframes_animation_loops(text: String) -> String:
	var regex := RegEx.new()
	var error := regex.compile('"loop"\\s*:\\s*(true|false|0|1),\\s*"name"\\s*:\\s*&"([^"]+)"')
	if error != OK:
		return text

	var output := ""
	var cursor := 0
	for result in regex.search_all(text):
		var animation_name := String(result.get_string(2))
		var loop_value := "1" if _should_animation_loop(animation_name) else "0"
		output += text.substr(cursor, result.get_start(1) - cursor)
		output += loop_value
		cursor = result.get_end(1)
	output += text.substr(cursor)
	return output


func _should_animation_loop(animation_name: String) -> bool:
	var normalized := animation_name.strip_edges().to_lower()
	return normalized == "idle" or normalized == "run" or normalized == "walk" or normalized == "move"


func _replace_ext_resource_path(text: String, resource_type: String, file_name: String, new_path: String) -> String:
	var lines := text.split("\n")
	for index in range(lines.size()):
		var line := lines[index]
		if line.contains("[ext_resource") and line.contains('type="%s"' % resource_type) and line.contains(file_name):
			lines[index] = _replace_path_value(line, new_path)
	return "\n".join(lines)


func _replace_path_value(line: String, new_path: String) -> String:
	var key := 'path="'
	var start := line.find(key)
	if start == -1:
		return line

	start += key.length()
	var end := line.find('"', start)
	if end == -1:
		return line

	var replaced := line.substr(0, start) + new_path + line.substr(end)
	# Godot resolves an ext_resource by UID before its path. Remove the stale UID
	# whenever the importer changes the path, otherwise the previous character may load.
	var uid_start := replaced.find(' uid="')
	if uid_start != -1:
		var uid_end := replaced.find('"', uid_start + 6)
		if uid_end != -1:
			replaced = replaced.erase(uid_start, uid_end - uid_start + 1)
	return replaced


func _ensure_centered(text: String) -> String:
	var lines := text.split("\n")
	var sprite_line_index := -1
	var centered_line_index := -1

	for index in range(lines.size()):
		var line := lines[index]
		if line.contains('[node name="AnimatedSprite2D" type="AnimatedSprite2D"'):
			sprite_line_index = index
		elif sprite_line_index != -1 and line.begins_with("centered = "):
			centered_line_index = index
			break

	if centered_line_index != -1:
		lines[centered_line_index] = "centered = true"
	elif sprite_line_index != -1:
		lines.insert(sprite_line_index + 3, "centered = true")

	return "\n".join(lines)


func _replace_character_transform(text: String, display_scale: float, display_offset: Vector2) -> String:
	var lines := text.split("\n")
	var in_character_action_set := false

	for index in range(lines.size()):
		var line := lines[index]
		if line.contains('[node name="CharacterActionSet" parent="."'):
			in_character_action_set = true
			continue

		if in_character_action_set and line.begins_with("[node "):
			in_character_action_set = false

		if not in_character_action_set:
			continue

		if line.begins_with("position = Vector2("):
			lines[index] = "position = Vector2(%s, %s)" % [display_offset.x, display_offset.y]
		elif line.begins_with("scale = Vector2("):
			lines[index] = "scale = Vector2(%s, %s)" % [display_scale, display_scale]

	return "\n".join(lines)


func _write_text_file(path: String, text: String) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open file for writing: %s" % path)
		return FileAccess.get_open_error()

	file.store_string(text)
	return OK


## 生成完整模板场景（和 player.tscn 同结构，可直接使用或手动微调）
func _generate_template_scene(template_path: String, actions_scene_path: String, config: Dictionary) -> int:
	var char_name: String = config.get("scene_name", config.get("character_name", "Character"))
	# 默认怪物碰撞层（玩家预制体由你手动制作，不受此影响）
	var collision_layer := 2
	var collision_mask := 1
	# HitBox: 怪物打玩家(mask=8), 玩家打怪物(mask=8)
	# HurtBox: 怪物被玩家打(mask=4), 玩家被怪物打(mask=4)
	var hitbox_mask := 8
	var hurtbox_mask := 4

	var scene_text := '''[gd_scene load_steps=8 format=3]

[ext_resource type="PackedScene" path="%s" id="1_visual"]
[ext_resource type="Script" path="res://scripts/enemy.gd" id="0_script"]
[ext_resource type="Script" path="res://scripts/combat/combat_component.gd" id="2_combat"]
[ext_resource type="Script" path="res://scripts/combat/hurt_box.gd" id="3_hurt"]
[ext_resource type="Script" path="res://scripts/combat/hit_box.gd" id="4_hit"]

[sub_resource type="RectangleShape2D" id="1_shape"]
size = Vector2(24, 38)

[sub_resource type="RectangleShape2D" id="2_hit_shape"]
size = Vector2(30, 30)

[sub_resource type="RectangleShape2D" id="3_hurt_shape"]
size = Vector2(20, 36)

[node name="%s" type="CharacterBody2D"]
groups = ["enemies"]
collision_layer = %d
collision_mask = %d
script = ExtResource("0_script")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("1_shape")

[node name="CharacterActionSet" parent="." instance=ExtResource("1_visual")]
position = Vector2(%s, %s)
scale = Vector2(%s, %s)

[node name="HitBox" type="Area2D" parent="."]
collision_layer = 4
collision_mask = %d
monitoring = false
script = ExtResource("4_hit")

[node name="CollisionShape2D" type="CollisionShape2D" parent="HitBox"]
shape = SubResource("2_hit_shape")
disabled = true

[node name="HurtBox" type="Area2D" parent="."]
collision_layer = 8
collision_mask = %d
script = ExtResource("3_hurt")

[node name="CollisionShape2D" type="CollisionShape2D" parent="HurtBox"]
shape = SubResource("3_hurt_shape")

[node name="CombatComponent" type="Node" parent="."]
script = ExtResource("2_combat")
	''' % [
		actions_scene_path,
		char_name,
		collision_layer,
		collision_mask,
		float(config.get("display_offset", {}).get("x", 0.0)),
		float(config.get("display_offset", {}).get("y", 0.0)),
		float(config.get("display_scale", 1.0)),
		float(config.get("display_scale", 1.0)),
		hitbox_mask,
		hurtbox_mask,
	]
	return _write_text_file(template_path, scene_text)


func _print_usage() -> void:
	print("Usage:")
	print("  godot --headless --script res://scripts/editor/import_character.gd -- --source <character_dir> [--apply-player <player_scene>] [--target-height <pixels>] [--facing left|right]")
