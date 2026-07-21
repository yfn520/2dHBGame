@tool
extends RefCounted

## 导入 GameTool 地图拼接工具导出的 zip 包为新的关卡地图。
##
## 流程：
## 1. 推断 map_name（zip 文件名去掉 _godot_package 后缀）
## 2. 解压到 res://scenes/<map_name>/
## 3. 生成关卡场景 res://scenes/<map_name>.tscn（Node2D + Map instance + PlayerSpawn）
## 4. 追加到 res://data/levels.json
##
## 不重写 map_stitch_godot.tscn 内的相对路径（./images/xxx.png），
## 解压到 <map_name>/ 后 Godot 按场景文件所在目录自动解析。

const SCENES_DIR := "res://scenes"
const LEVELS_PATH := "res://data/levels.json"
const MAP_SCENE_FILE := "map_stitch_godot.tscn"
const MAP_JSON_FILE := "map_stitch_godot.json"


static func import_zip(zip_path: String) -> Dictionary:
	var map_name := _infer_map_name(zip_path)
	if map_name.is_empty():
		return _failure("无法从 zip 文件名推断地图名：%s" % zip_path)

	var reader := ZIPReader.new()
	var open_error := reader.open(zip_path)
	if open_error != OK:
		return _failure("无法打开 ZIP 文件（错误码 %d）：%s" % [open_error, zip_path])

	var source_files := reader.get_files()
	if source_files.is_empty():
		reader.close()
		return _failure("ZIP 包为空：%s" % zip_path)

	# 校验 + 收集要写入的文件
	var has_scene := false
	var has_json := false
	for entry in source_files:
		var p := String(entry).replace("\\", "/").trim_prefix("/")
		if p.ends_with("/"):
			continue
		if not _is_safe_archive_path(p):
			reader.close()
			return _failure("ZIP 包含不安全路径，已取消导入：%s" % entry)
		if p == MAP_SCENE_FILE:
			has_scene = true
		if p == MAP_JSON_FILE:
			has_json = true

	if not has_scene or not has_json:
		reader.close()
		return _failure("不是有效的 GameTool 地图包：需要 %s 和 %s" % [MAP_SCENE_FILE, MAP_JSON_FILE])

	# 解压到 res://scenes/<map_name>/
	var target_dir_res := "%s/%s" % [SCENES_DIR, map_name]
	var target_dir_abs := ProjectSettings.globalize_path(target_dir_res)
	var mk_err := DirAccess.make_dir_recursive_absolute(target_dir_abs)
	if mk_err != OK:
		reader.close()
		return _failure("无法创建目标目录（错误码 %d）：%s" % [mk_err, target_dir_res])

	var written := 0
	for entry in source_files:
		var p := String(entry).replace("\\", "/").trim_prefix("/")
		if p.ends_with("/"):
			continue
		# zip 内部路径都是相对的（map_stitch_godot.tscn / images/xxx.png），
		# 直接拼到 target_dir 下
		var dest_res := "%s/%s" % [target_dir_res, p]
		var dest_abs := ProjectSettings.globalize_path(dest_res)
		var parent_err := DirAccess.make_dir_recursive_absolute(dest_abs.get_base_dir())
		if parent_err != OK:
			reader.close()
			return _failure("无法创建子目录（错误码 %d）：%s" % [parent_err, dest_abs.get_base_dir()])
		var data := reader.read_file(entry)
		var out := FileAccess.open(dest_abs, FileAccess.WRITE)
		if out == null:
			reader.close()
			return _failure("无法写入文件：%s" % dest_res)
		out.store_buffer(data)
		out.close()
		written += 1

	reader.close()

	# 读 map_stitch_godot.json 算 spawn
	var json_res := "%s/%s" % [target_dir_res, MAP_JSON_FILE]
	var json_text := FileAccess.get_file_as_string(json_res)
	var json := JSON.new()
	var parse_err := json.parse(json_text)
	if parse_err != OK:
		return _failure("解析 %s 失败" % MAP_JSON_FILE)
	var canvas: Dictionary = {}
	if typeof(json.data) == TYPE_DICTIONARY:
		canvas = json.data.get("canvas", {})
	var spawn := _get_default_spawn(canvas)

	# 生成关卡场景 res://scenes/<map_name>.tscn
	var root_name := _to_pascal_case(map_name)
	var level_scene_res := "%s/%s.tscn" % [SCENES_DIR, map_name]
	var map_scene_res := "%s/%s" % [target_dir_res, MAP_SCENE_FILE]
	var tscn := "[gd_scene load_steps=2 format=3]\n\n"
	tscn += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_map\"]\n\n" % map_scene_res
	tscn += "[node name=\"%s\" type=\"Node2D\"]\n\n" % root_name
	tscn += "[node name=\"Map\" type=\"Node2D\" parent=\".\" instance=ExtResource(\"1_map\")]\n\n"
	tscn += "[node name=\"PlayerSpawn\" type=\"Marker2D\" parent=\".\"]\n"
	tscn += "position = Vector2(%d, %d)\n" % [int(spawn.x), int(spawn.y)]

	var level_abs := ProjectSettings.globalize_path(level_scene_res)
	var lvl_out := FileAccess.open(level_abs, FileAccess.WRITE)
	if lvl_out == null:
		return _failure("无法写入关卡场景：%s" % level_scene_res)
	lvl_out.store_string(tscn)
	lvl_out.close()

	# 追加到 levels.json
	var add_result := _append_level_to_json(map_name, level_scene_res, spawn)
	if not bool(add_result.get("ok", false)):
		return add_result
	var level_id: int = int(add_result["level_id"])

	return {
		"ok": true,
		"message": "已导入地图：%s\n拼接场景：%s\n关卡场景：%s\n关卡 ID：%d（已写入 levels.json）" % [
			map_name, map_scene_res, level_scene_res, level_id
		],
		"map_name": map_name,
		"stitched_path": map_scene_res,
		"level_scene_path": level_scene_res,
		"level_id": level_id,
		"files_written": written,
	}


## 从 zip 文件名推断 map_name。
## city_godot_package.zip -> city
## shulin.zip -> shulin
static func _infer_map_name(zip_path: String) -> String:
	var fname := zip_path.get_file().get_basename()
	# 去掉 _godot_package 后缀
	if fname.ends_with("_godot_package"):
		fname = fname.substr(0, fname.length() - "_godot_package".length())
	fname = fname.strip_edges()
	if fname.is_empty():
		return "imported_map"
	return fname


static func _is_safe_archive_path(path: String) -> bool:
	if path.is_empty() or path.contains(":"):
		return false
	for segment in path.split("/", true):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true


## 默认 spawn 算法（与 import_stitched_world.gd 一致）：
## x = clamp(width * 0.12, 96, width - 96)
## y = clamp(height * 0.46, 96, height - 96)
static func _get_default_spawn(canvas: Dictionary) -> Vector2:
	var width := float(canvas.get("width", 1376))
	var height := float(canvas.get("height", 768))
	var spawn_x := clampf(width * 0.12, 96.0, maxf(96.0, width - 96.0))
	var spawn_y := clampf(height * 0.46, 96.0, maxf(96.0, height - 96.0))
	return Vector2(spawn_x, spawn_y)


## PascalCase 转换（与 import_stitched_world.gd 一致）。
static func _to_pascal_case(value: String) -> String:
	var words: Array[String] = []
	var current := ""
	for character in value:
		if _is_word_character(character):
			current += character
		else:
			if not current.is_empty():
				words.append(current)
				current = ""
	if not current.is_empty():
		words.append(current)
	var result := ""
	for word in words:
		if word.is_empty():
			continue
		result += word.left(1).to_upper() + word.substr(1)
	return result if not result.is_empty() else "ImportedLevel"


static func _is_word_character(character: String) -> bool:
	if character.is_empty():
		return false
	var code := character.unicode_at(0)
	var is_digit := code >= 48 and code <= 57
	var is_upper := code >= 65 and code <= 90
	var is_lower := code >= 97 and code <= 122
	return is_digit or is_upper or is_lower


## 追加一条关卡到 levels.json，id = max(已有) + 1。
static func _append_level_to_json(map_name: String, level_scene_path: String, spawn: Vector2) -> Dictionary:
	var data: Dictionary = {}
	if FileAccess.file_exists(LEVELS_PATH):
		var text := FileAccess.get_file_as_string(LEVELS_PATH)
		var j := JSON.new()
		var err := j.parse(text)
		if err != OK:
			return _failure("解析 levels.json 失败")
		if typeof(j.data) == TYPE_DICTIONARY:
			data = j.data

	var max_id := 0
	for key in data:
		var k := int(key)
		if k > max_id:
			max_id = k
	var new_id := max_id + 1

	# 保留原有键的顺序：新键追加到末尾
	data[str(new_id)] = {
		"name": map_name,
		"description": "",
		"scene_path": level_scene_path,
		"spawn_x": int(spawn.x),
		"spawn_y": int(spawn.y),
		"bgm": "",
		"enemies": [],
	}

	# 按 id 升序重排
	var sorted: Dictionary = {}
	var ids := data.keys()
	var int_ids: Array[int] = []
	for k in ids:
		int_ids.append(int(k))
	int_ids.sort()
	for k in int_ids:
		sorted[str(k)] = data[str(k)]

	var abs_path := ProjectSettings.globalize_path(LEVELS_PATH)
	var out := FileAccess.open(abs_path, FileAccess.WRITE)
	if out == null:
		return _failure("无法写入 levels.json：%s" % LEVELS_PATH)
	out.store_string(JSON.stringify(sorted, "\t") + "\n")
	out.close()

	return {"ok": true, "level_id": new_id}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
