@tool
extends RefCounted

## Imports UI scene ZIP packages exported by GameTool.
##
## Current packages are rooted at assets/ui/. The two older layouts generated
## by GameTool (godot/... and scenes/ui/...) are normalized during import so an
## already-exported package can still be used.

const UI_ROOT := "assets/ui"


static func import_zip(zip_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	var open_error := reader.open(zip_path)
	if open_error != OK:
		return _failure("无法打开 ZIP 文件（错误码 %d）：%s" % [open_error, zip_path])

	var source_files := reader.get_files()
	if source_files.is_empty():
		reader.close()
		return _failure("ZIP 包为空：%s" % zip_path)

	var plans: Array[Dictionary] = []
	var scene_targets: Array[String] = []
	var seen_targets: Dictionary = {}
	var has_manifest := false

	for source_variant in source_files:
		var source_path := String(source_variant)
		var normalized := source_path.replace("\\", "/").trim_prefix("/")
		if normalized.ends_with("/"):
			continue
		if not _is_safe_archive_path(normalized):
			reader.close()
			return _failure("ZIP 包含不安全路径，已取消导入：%s" % source_path)

		# Legacy packages used a top-level godot/ directory.
		if normalized.begins_with("godot/"):
			normalized = normalized.trim_prefix("godot/")

		var target_path := _target_path_for_entry(normalized)
		if target_path.is_empty():
			continue
		if seen_targets.has(target_path):
			reader.close()
			return _failure(
				"ZIP 中多个文件会写入同一目标，已取消导入：%s" % target_path
			)
		seen_targets[target_path] = source_path
		plans.append({"source": source_path, "target": target_path})
		if target_path.ends_with(".tscn"):
			scene_targets.append(target_path)
		if target_path.get_file() == "ui_scene_manifest.json":
			has_manifest = true

	if plans.is_empty() or scene_targets.is_empty() or not has_manifest:
		reader.close()
		return _failure(
			"不是有效的 GameTool UI 场景包：需要 UI 主场景和 ui_scene_manifest.json"
		)

	var written := 0
	var overwritten := 0
	for plan in plans:
		var source_path := String(plan["source"])
		var target_path := String(plan["target"])
		var target_res_path := "res://%s" % target_path
		var target_abs_path := ProjectSettings.globalize_path(target_res_path)
		var parent_error := DirAccess.make_dir_recursive_absolute(target_abs_path.get_base_dir())
		if parent_error != OK:
			reader.close()
			return _failure("无法创建导入目录（错误码 %d）：%s" % [parent_error, target_path.get_base_dir()])

		if FileAccess.file_exists(target_res_path):
			overwritten += 1
		var data := reader.read_file(source_path)
		if _is_rewritable_text_file(target_path):
			var text := _rewrite_resource_paths(data.get_string_from_utf8(), scene_targets)
			if target_path.ends_with(".tscn"):
				text = _normalize_legacy_control_sizing(text)
			data = text.to_utf8_buffer()

		var output := FileAccess.open(target_abs_path, FileAccess.WRITE)
		if output == null:
			reader.close()
			return _failure("无法写入导入文件：%s" % target_res_path)
		output.store_buffer(data)
		output.close()
		written += 1

	reader.close()
	var imported_scenes: Array[String] = []
	for scene_target in scene_targets:
		imported_scenes.append("res://%s" % scene_target)
	return {
		"ok": true,
		"message": "已导入 %d 个文件（覆盖 %d 个）\n主场景：\n%s" % [
			written,
			overwritten,
			"\n".join(imported_scenes),
		],
		"files_written": written,
		"overwritten": overwritten,
		"scenes": imported_scenes,
	}


static func _target_path_for_entry(normalized_path: String) -> String:
	if normalized_path.begins_with("%s/" % UI_ROOT):
		return normalized_path
	# Compatibility with the previous export layout. Move the scene beside the
	# per-screen asset folders: assets/ui/<screen>.tscn.
	if normalized_path.begins_with("scenes/ui/") and normalized_path.ends_with(".tscn"):
		var screen := normalized_path.get_file().get_basename()
		return "%s/%s.tscn" % [UI_ROOT, screen]
	return ""


static func _is_safe_archive_path(path: String) -> bool:
	if path.is_empty() or path.contains(":"):
		return false
	for segment in path.split("/", true):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true


static func _is_rewritable_text_file(path: String) -> bool:
	return path.ends_with(".tscn") or path.ends_with(".json") or path.ends_with(".md")


static func _rewrite_resource_paths(text: String, scene_targets: Array[String]) -> String:
	var rewritten := text.replace("res://godot/assets/ui/", "res://assets/ui/")
	# GameTool versions before this importer used reversed TextureButton property
	# names, which Godot ignored and therefore rendered as invisible buttons.
	rewritten = rewritten.replace("normal_texture = ", "texture_normal = ")
	rewritten = rewritten.replace("hover_texture = ", "texture_hover = ")
	rewritten = rewritten.replace("pressed_texture = ", "texture_pressed = ")
	rewritten = rewritten.replace("disabled_texture = ", "texture_disabled = ")
	for scene_target in scene_targets:
		var screen := scene_target.get_file().get_basename()
		var new_scene_path := "res://%s" % scene_target
		rewritten = rewritten.replace(
			"res://godot/scenes/ui/%s.tscn" % screen,
			new_scene_path
		)
		rewritten = rewritten.replace(
			"res://scenes/ui/%s.tscn" % screen,
			new_scene_path
		)
	return rewritten


## Older GameTool scenes omitted the Godot flags that make texture-backed
## controls obey their explicit rect. Infer the old TextureRect stretch mode:
## expand_mode existed only for keep_aspect_center; otherwise it was scale.
static func _normalize_legacy_control_sizing(text: String) -> String:
	var source_lines := text.split("\n")
	var output_lines: Array[String] = []
	var index := 0
	while index < source_lines.size():
		var line := String(source_lines[index])
		if not line.begins_with("[node "):
			output_lines.append(line)
			index += 1
			continue

		var block_end := index + 1
		while block_end < source_lines.size() and not String(source_lines[block_end]).begins_with("["):
			block_end += 1
		var block: Array[String] = []
		for block_index in range(index, block_end):
			block.append(String(source_lines[block_index]))
		_normalize_control_block(block)
		output_lines.append_array(block)
		index = block_end
	return "\n".join(output_lines)


static func _normalize_control_block(block: Array[String]) -> void:
	if block.is_empty():
		return
	var header := block[0]
	if 'type="TextureRect"' in header:
		var had_expand_mode := _block_has_property(block, "expand_mode")
		if not had_expand_mode:
			block.insert(1, "expand_mode = 1")
		if not _block_has_property(block, "stretch_mode"):
			block.insert(2, "stretch_mode = %d" % (5 if had_expand_mode else 0))
	elif 'type="TextureButton"' in header:
		if not _block_has_property(block, "ignore_texture_size"):
			block.insert(1, "ignore_texture_size = true")
		if not _block_has_property(block, "stretch_mode"):
			block.insert(2, "stretch_mode = 0")
	elif 'type="TextureProgressBar"' in header:
		if not _block_has_property(block, "nine_patch_stretch"):
			block.insert(1, "nine_patch_stretch = true")


static func _block_has_property(block: Array[String], property_name: String) -> bool:
	var prefix := "%s =" % property_name
	for line in block:
		if line.begins_with(prefix):
			return true
	return false


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
