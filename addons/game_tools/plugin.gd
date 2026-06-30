@tool
extends EditorPlugin

var _submenu: PopupMenu


func _enter_tree() -> void:
	_submenu = PopupMenu.new()
	_submenu.name = "GameToolsMenu"
	_submenu.add_item("导入所有场景", 0)
	_submenu.add_item("导入所有角色", 1)
	_submenu.add_item("导入所有怪物", 3)
	_submenu.add_item("转换 Excel → JSON", 2)
	_submenu.id_pressed.connect(_on_menu_pressed)
	add_tool_submenu_item("游戏工具", _submenu)


func _exit_tree() -> void:
	remove_tool_menu_item("游戏工具")


# ---- 菜单回调 ----

func _on_menu_pressed(id: int) -> void:
	match id:
		0:
			_do_import_worlds()
		1:
			_do_import_characters()
		2:
			_do_convert_excel()
		3:
			_do_import_enemies()


# ---- 场景导入 ----

func _do_import_worlds() -> void:
	var world_dir := "res://world/stitched"
	var dir := DirAccess.open(world_dir)
	if dir == null:
		push_error("无法打开目录: %s" % world_dir)
		return

	dir.list_dir_begin()
	var count := 0
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			if _do_import_single_world(world_dir, folder):
				count += 1
		folder = dir.get_next()
	dir.list_dir_end()

	print("[GameTools] 场景导入完成: %d 个场景" % count)
	EditorInterface.get_resource_filesystem().scan()


func _do_import_single_world(base_dir: String, folder_name: String) -> bool:
	var source_dir := base_dir.path_join(folder_name)
	var raw_scene_path := source_dir.path_join("map_stitch_godot.tscn")
	var raw_json_path := source_dir.path_join("map_stitch_godot.json")

	if not FileAccess.file_exists(raw_scene_path):
		push_warning("跳过 %s: 缺少 map_stitch_godot.tscn" % folder_name)
		return false
	if not FileAccess.file_exists(raw_json_path):
		push_warning("跳过 %s: 缺少 map_stitch_godot.json" % folder_name)
		return false

	var raw_scene := load(raw_scene_path) as PackedScene
	if raw_scene == null:
		push_error("加载场景失败: %s" % raw_scene_path)
		return false

	var json_text := FileAccess.get_file_as_string(raw_json_path)
	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_error("解析 JSON 失败: %s" % raw_json_path)
		return false

	var root := Node2D.new()
	root.name = _to_pascal(folder_name)

	var map_instance := raw_scene.instantiate()
	map_instance.name = "Map"
	root.add_child(map_instance)
	map_instance.owner = root

	var spawn := Marker2D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = _calc_default_spawn(json.data)
	root.add_child(spawn)
	spawn.owner = root

	var spawn_pos: Vector2 = spawn.position

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("打包场景失败: %s" % folder_name)
		root.free()
		return false

	var output_path := "res://scenes/%s.tscn" % folder_name
	var err := ResourceSaver.save(packed, output_path)
	root.free()

	if err != OK:
		push_error("保存场景失败: %s" % output_path)
		return false

	print("[GameTools] 已导入: %s → %s (spawn: %s)" % [folder_name, output_path, spawn_pos])
	return true


func _calc_default_spawn(data: Variant) -> Vector2:
	if typeof(data) != TYPE_DICTIONARY:
		return Vector2(160, 350)
	var canvas: Dictionary = data.get("canvas", {})
	var width: float = float(canvas.get("width", 1376))
	var height: float = float(canvas.get("height", 768))
	var spawn_x := clampf(width * 0.12, 96.0, maxf(96.0, width - 96.0))
	var spawn_y := clampf(height * 0.46, 96.0, maxf(96.0, height - 96.0))
	return Vector2(spawn_x, spawn_y)


# ---- 角色导入 ----

func _do_import_characters() -> void:
	var char_dir := "res://assets/characters"
	var player_scene := "res://scenes/player.tscn"
	var dir := DirAccess.open(char_dir)
	if dir == null:
		push_error("无法打开目录: %s" % char_dir)
		return

	dir.list_dir_begin()
	var count := 0
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var char_path := char_dir.path_join(folder)
			var manifest_path := char_path.path_join("manifest.json")
			if FileAccess.file_exists(manifest_path):
				if _do_import_single_character(char_path, folder, player_scene):
					count += 1
		folder = dir.get_next()
	dir.list_dir_end()

	print("[GameTools] 角色导入完成: %d 个角色" % count)
	EditorInterface.get_resource_filesystem().scan()


func _do_import_enemies() -> void:
	var enemy_dir := "res://assets/enemies"
	var dir := DirAccess.open(enemy_dir)
	if dir == null:
		push_warning("怪物目录不存在: %s" % enemy_dir)
		return

	dir.list_dir_begin()
	var count := 0
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var char_path := enemy_dir.path_join(folder)
			var manifest_path := char_path.path_join("manifest.json")
			if FileAccess.file_exists(manifest_path):
				if _do_import_single_character(char_path, folder, ""):
					count += 1
		folder = dir.get_next()
	dir.list_dir_end()

	print("[GameTools] 怪物导入完成: %d 个怪物" % count)
	EditorInterface.get_resource_filesystem().scan()


func _do_import_single_character(source_dir: String, folder_name: String, player_scene: String, display_scale_override: float = -1.0) -> bool:
	var actions_path := source_dir.path_join("godot/character_actions.tscn")
	var sf_path := source_dir.path_join("godot/spriteframes.tres")
	var atlas_path := source_dir.path_join("godot/all_actions_atlas.png")
	var manifest_path := source_dir.path_join("manifest.json")
	var config_path := source_dir.path_join("character_config.json")

	if not FileAccess.file_exists(manifest_path):
		push_warning("跳过 %s: 缺少 manifest.json" % folder_name)
		return false
	if not FileAccess.file_exists(actions_path):
		push_warning("跳过 %s: 缺少 character_actions.tscn" % folder_name)
		return false
	if not FileAccess.file_exists(sf_path):
		push_warning("跳过 %s: 缺少 spriteframes.tres" % folder_name)
		return false
	if not FileAccess.file_exists(atlas_path):
		push_warning("跳过 %s: 缺少 all_actions_atlas.png" % folder_name)
		return false

	var manifest_text := FileAccess.get_file_as_string(manifest_path)
	var json := JSON.new()
	if json.parse(manifest_text) != OK:
		push_error("解析 manifest 失败: %s" % manifest_path)
		return false

	var md: Dictionary = json.data
	var ub: Dictionary = md.get("unifiedBox", {})
	var target_height := 52.0
	var raw_height := _get_content_height(md)
	var display_scale: float
	if display_scale_override > 0.0:
		display_scale = display_scale_override
	else:
		display_scale = snappedf(target_height / raw_height, 0.001)
	var cell_h := _get_frame_cell_height(md)
	var content_offset_y := _get_content_offset_y(md)
	var draw_h := _get_content_height(md)
	var anchor_dist := cell_h * 0.5 - content_offset_y - draw_h
	var display_offset_y := snappedf(19.0 + anchor_dist * display_scale, 0.1)

	# 修正 spriteframes.tres
	var sf_text := FileAccess.get_file_as_string(sf_path)
	sf_text = _replace_path_in_text(sf_text, "Texture2D", "all_actions_atlas.png", atlas_path)
	_write_file(sf_path, sf_text)

	# 修正 character_actions.tscn
	var act_text := FileAccess.get_file_as_string(actions_path)
	act_text = _replace_path_in_text(act_text, "SpriteFrames", "spriteframes.tres", sf_path)
	act_text = _ensure_centered(act_text)
	_write_file(actions_path, act_text)

	# 写配置
	var config := {
		"character_name": md.get("characterName", folder_name),
		"default_animation": md.get("defaultAnimation", "idle"),
		"actions_scene": actions_path,
		"spriteframes": sf_path,
		"atlas": atlas_path,
		"display_scale": display_scale,
		"display_offset": {"x": 0, "y": display_offset_y},
		"centered": true,
		"target_display_height": target_height,
		"available_actions": md.get("exportOrder", []),
		"unified_box": ub,
		"frame_cell_height": cell_h,
	}
	_write_file(config_path, JSON.stringify(config, "\t") + "\n")

	# 更新 player.tscn
	if FileAccess.file_exists(player_scene):
		var pl_text := FileAccess.get_file_as_string(player_scene)
		pl_text = _replace_path_in_text(pl_text, "PackedScene", "character_actions.tscn", actions_path)
		pl_text = _replace_char_transform(pl_text, display_scale, display_offset_y)
		_write_file(player_scene, pl_text)

	print("[GameTools] 已导入角色: %s (scale: %s, offset_y: %s)" % [folder_name, display_scale, display_offset_y])
	return true


# ---- Excel 转换 ----

func _do_convert_excel() -> void:
	var excel_dir := "res://data/excel"
	var dir := DirAccess.open(excel_dir)
	if dir == null:
		push_error("无法打开 Excel 目录: %s" % excel_dir)
		return

	var python := _find_python()
	if python.is_empty():
		push_warning("找不到 Python，跳过 Excel 转换")
		return

	dir.list_dir_begin()
	var count := 0
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".xlsx") and not file.begins_with("~$"):
			var excel_path := excel_dir.path_join(file)
			var output_name := file.get_basename()
			var script_path := ProjectSettings.globalize_path("res://tools/excel_to_json.py")
			var output := []
			OS.execute(python, [script_path, output_name], output, true, false)
			print("[GameTools] 已转换: %s" % file)
			count += 1
		file = dir.get_next()
	dir.list_dir_end()

	print("[GameTools] Excel 转换完成: %d 个文件" % count)
	EditorInterface.get_resource_filesystem().scan()


func _find_python() -> String:
	var output := []
	if OS.execute("python", ["--version"], output, true, false) == OK:
		return "python"
	output = []
	if OS.execute("py", ["--version"], output, true, false) == OK:
		return "py"
	return ""


# ---- 工具函数 ----

func _replace_path_in_text(text: String, res_type: String, file_name: String, new_path: String) -> String:
	var lines := text.split("\n")
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.contains("[ext_resource") and line.contains('type="%s"' % res_type) and line.contains(file_name):
			lines[i] = _replace_path_value(line, new_path)
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
	return line.substr(0, start) + new_path + line.substr(end)


func _ensure_centered(text: String) -> String:
	var lines := text.split("\n")
	var sprite_idx := -1
	var centered_idx := -1
	for i in range(lines.size()):
		if lines[i].contains('[node name="AnimatedSprite2D" type="AnimatedSprite2D"'):
			sprite_idx = i
		elif sprite_idx != -1 and lines[i].begins_with("centered = "):
			centered_idx = i
			break
	if centered_idx != -1:
		lines[centered_idx] = "centered = true"
	elif sprite_idx != -1:
		lines.insert(sprite_idx + 3, "centered = true")
	return "\n".join(lines)


func _replace_char_transform(text: String, display_scale: float, display_offset_y: float) -> String:
	var lines := text.split("\n")
	var in_char := false
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.contains('[node name="CharacterActionSet" parent="."'):
			in_char = true
			continue
		if in_char and line.begins_with("[node "):
			in_char = false
		if not in_char:
			continue
		if line.begins_with("position = Vector2("):
			lines[i] = "position = Vector2(0, %s)" % display_offset_y
		elif line.begins_with("scale = Vector2("):
			lines[i] = "scale = Vector2(%s, %s)" % [display_scale, display_scale]
	return "\n".join(lines)


func _write_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("写入文件失败: %s" % path)
		return
	file.store_string(text)


func _get_content_height(manifest_data: Dictionary) -> float:
	# 优先从 frameRects 读 drawHeight（有压缩流水线的角色）
	var frame_rects: Array = manifest_data.get("frameRects", [])
	if frame_rects.size() > 0:
		var first_frame: Dictionary = frame_rects[0]
		var draw_h := float(first_frame.get("drawHeight", 0))
		if draw_h > 0.0:
			return draw_h
	# 回退到 unifiedBox.height（无压缩的角色如 girl）
	var ub: Dictionary = manifest_data.get("unifiedBox", {})
	var height := float(ub.get("height", 144.0))
	if height <= 0.0:
		height = 144.0
	return height


func _get_frame_cell_height(manifest_data: Dictionary) -> float:
	var frame_rects: Array = manifest_data.get("frameRects", [])
	if frame_rects.size() > 0:
		var cell_h := float(frame_rects[0].get("cellHeight", 0))
		if cell_h > 0.0:
			return cell_h
	var ub: Dictionary = manifest_data.get("unifiedBox", {})
	var height := float(ub.get("height", 144.0))
	return height if height > 0.0 else 144.0


func _get_content_offset_y(manifest_data: Dictionary) -> float:
	var frame_rects: Array = manifest_data.get("frameRects", [])
	if frame_rects.size() > 0:
		return float(frame_rects[0].get("offsetY", 0))
	return 0.0


func _to_pascal(value: String) -> String:
	var words := PackedStringArray()
	var current := ""
	for character in value:
		var code := character.unicode_at(0)
		var is_alnum := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		if is_alnum:
			current += character
		else:
			if not current.is_empty():
				words.append(current)
				current = ""
	if not current.is_empty():
		words.append(current)
	var result := ""
	for word in words:
		if not word.is_empty():
			result += word.left(1).to_upper() + word.substr(1)
	return result if not result.is_empty() else "ImportedLevel"
