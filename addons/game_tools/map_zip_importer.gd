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
const MAP_RUNTIME_FILE := "map_stitch_runtime.gd"


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
	var manifest_entry := ""
	var normalized_files: Array[String] = []
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
			manifest_entry = String(entry)
		normalized_files.append(p)

	if not has_scene or not has_json or not normalized_files.has(MAP_RUNTIME_FILE):
		reader.close()
		return _failure("不是有效的 GameTool v2 地图包：缺少场景、清单或线性 mipmap 运行脚本")

	var manifest_json := JSON.new()
	var manifest_parse_error := manifest_json.parse(reader.read_file(manifest_entry).get_string_from_utf8())
	if manifest_parse_error != OK or typeof(manifest_json.data) != TYPE_DICTIONARY:
		reader.close()
		return _failure("无法解析 %s" % MAP_JSON_FILE)
	var manifest_validation := _validate_v2_manifest(manifest_json.data, normalized_files)
	if not bool(manifest_validation.get("ok", false)):
		reader.close()
		return manifest_validation

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
	var manifest: Dictionary = json.data
	var spawn := _get_default_spawn(manifest)

	# 生成关卡场景 res://scenes/<map_name>.tscn
	var root_name := _to_pascal_case(map_name)
	var level_scene_res := "%s/%s.tscn" % [SCENES_DIR, map_name]
	var map_scene_res := "%s/%s" % [target_dir_res, MAP_SCENE_FILE]
	var tscn := "[gd_scene load_steps=2 format=3]\n\n"
	tscn += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_map\"]\n\n" % map_scene_res
	tscn += "[node name=\"%s\" type=\"Node2D\"]\n\n" % root_name
	tscn += "metadata/profile = \"side_scroller_battle\"\n"
	tscn += "metadata/ground_line_y = %d\n\n" % int(manifest.get("composition", {}).get("ground_line_y", 605))
	tscn += "[node name=\"Map\" type=\"Node2D\" parent=\".\" instance=ExtResource(\"1_map\")]\n\n"
	tscn += "scale = Vector2(1, 1)\n\n"
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
## y = v2 composition.ground_line_y（默认 605）
static func _get_default_spawn(manifest: Dictionary) -> Vector2:
	var canvas: Dictionary = manifest.get("canvas", {})
	var composition: Dictionary = manifest.get("composition", {})
	var width := float(canvas.get("width", 1536))
	var height := float(canvas.get("height", 864))
	var spawn_x := clampf(width * 0.12, 96.0, maxf(96.0, width - 96.0))
	var spawn_y := clampf(float(composition.get("ground_line_y", 605)), 96.0, maxf(96.0, height - 96.0))
	return Vector2(spawn_x, spawn_y)


static func _validate_v2_manifest(data: Dictionary, archive_files: Array[String]) -> Dictionary:
	if int(data.get("version", 0)) != 2:
		return _failure("地图清单必须为 v2，请回到新版网页拼接工具重新导出")
	if str(data.get("profile", "")) != "side_scroller_battle":
		return _failure("地图清单缺少 profile=side_scroller_battle")

	var runtime: Dictionary = data.get("runtime", {})
	if (
		int(runtime.get("reference_width", 0)) != 1536
		or int(runtime.get("reference_height", 0)) != 864
		or not is_equal_approx(float(runtime.get("pixels_per_world_unit", 0.0)), 1.0)
		or not is_equal_approx(float(runtime.get("world_scale", 0.0)), 1.0)
		or not is_equal_approx(float(runtime.get("camera_zoom", 0.0)), 1.0)
		or str(runtime.get("texture_filter", "")) != "linear_mipmap"
	):
		return _failure("runtime 必须使用 1536×864、1px=1单位、scale/zoom=1、linear_mipmap")

	var composition: Dictionary = data.get("composition", {})
	var ground_line_y := int(composition.get("ground_line_y", -1))
	var ground_ratio := float(composition.get("ground_ratio", -1.0))
	if ground_line_y < 570 or ground_line_y > 639:
		return _failure("地面线越界：必须位于 570–639px")
	if absf(ground_ratio - float(ground_line_y) / 864.0) > 0.01:
		return _failure("ground_ratio 与 ground_line_y 不一致")

	var layout: Dictionary = data.get("layout", {})
	var tile_count := int(layout.get("tile_count", 0))
	var direction := str(layout.get("direction", ""))
	if tile_count < 1 or tile_count > 3:
		return _failure("战斗地图仅支持 1/2/3 块")
	if (
		(tile_count == 1 and direction != "center")
		or (tile_count == 2 and direction != "left" and direction != "right")
		or (tile_count == 3 and direction != "both")
	):
		return _failure("布局方向与块数不匹配")

	var source: Dictionary = data.get("source", {})
	if int(source.get("width", 0)) != 1536 or int(source.get("height", 0)) != 864:
		return _failure("源图片必须为 1536×864，旧图不得自动拉伸")
	var canvas: Dictionary = data.get("canvas", {})
	if int(canvas.get("height", 0)) != 864:
		return _failure("禁止纵向拼接：画布高度必须为 864")

	var overlap: Dictionary = data.get("overlap", {})
	var horizontal_overlap := float(overlap.get("horizontal_percent", 15.0))
	if tile_count > 1 and (horizontal_overlap < 12.0 or horizontal_overlap > 18.0):
		return _failure("横向重叠必须位于 12%–18%")
	if not is_zero_approx(float(overlap.get("vertical_percent", 0.0))):
		return _failure("禁止战斗地图纵向拼接")
	var expected_canvas_width := roundi(1536.0 * (tile_count - float(tile_count - 1) * horizontal_overlap / 100.0))
	if absi(int(canvas.get("width", 0)) - expected_canvas_width) > 2:
		return _failure("画布宽度与块数/重叠比例不一致")

	var tiles: Array = data.get("tiles", [])
	if tiles.size() != tile_count:
		return _failure("图片未完成：tiles 数量与布局块数不一致")
	for tile_value in tiles:
		if typeof(tile_value) != TYPE_DICTIONARY:
			return _failure("tiles 数据格式错误")
		var tile: Dictionary = tile_value
		var pixel: Dictionary = tile.get("pixel", {})
		if int(pixel.get("width", 0)) != 1536 or int(pixel.get("height", 0)) != 864:
			return _failure("每个拼接块都必须为 1536×864")
		var image_path := str(tile.get("image", ""))
		if image_path.is_empty() or not archive_files.has(image_path):
			return _failure("图片未完成或 ZIP 缺少文件：%s" % image_path)

	var collisions: Dictionary = data.get("collisions", {})
	if str(collisions.get("mode", "none")) == "none":
		return _failure("地图缺少碰撞，禁止导入")
	if tile_count == 1:
		var wide_fill: Dictionary = layout.get("wide_fill", {})
		if not bool(wide_fill.get("enabled", false)) or int(wide_fill.get("side_width", 0)) < 240:
			return _failure("单块地图缺少左右 240px 宽屏装饰补边")
	return {"ok": true}


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
