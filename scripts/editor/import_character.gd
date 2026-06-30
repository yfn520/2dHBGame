extends SceneTree

const MANIFEST_FILE := "manifest.json"
const ACTIONS_SCENE_FILE := "godot/character_actions.tscn"
const SPRITEFRAMES_FILE := "godot/spriteframes.tres"
const ATLAS_FILE := "godot/all_actions_atlas.png"
const CONFIG_FILE := "character_config.json"
const DEFAULT_TARGET_HEIGHT := 52.0


func _initialize() -> void:
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
		"default_facing": "left"
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
	var display_scale := _get_display_scale(manifest_data, float(options["target_height"]))
	var display_offset_y := _get_display_offset_y(manifest_data, display_scale)
	var config := {
		"character_name": manifest_data.get("characterName", source_dir.get_file()),
		"default_animation": manifest_data.get("defaultAnimation", "idle"),
		"actions_scene": actions_scene_path,
		"spriteframes": spriteframes_path,
		"atlas": atlas_path,
		"display_scale": display_scale,
		"display_offset": {
			"x": 0,
			"y": display_offset_y
		},
		"faces_right_by_default": String(options["default_facing"]) == "right",
		"centered": true,
		"target_display_height": float(options["target_height"]),
		"available_actions": manifest_data.get("exportOrder", []),
		"unified_box": manifest_data.get("unifiedBox", {})
	}

	var spriteframes_text := FileAccess.get_file_as_string(spriteframes_path)
	spriteframes_text = _replace_ext_resource_path(
		spriteframes_text,
		"Texture2D",
		"all_actions_atlas.png",
		atlas_path
	)
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

	var apply_player_path := String(options["apply_player"])
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
		player_text = _replace_character_transform(player_text, display_scale, display_offset_y)
		write_error = _write_text_file(apply_player_path, player_text)
		if write_error != OK:
			return write_error

	print("Imported character:")
	print("  source: ", source_dir)
	print("  actions: ", actions_scene_path)
	print("  config: ", config_path)
	print("  scale: ", display_scale)
	print("  offset_y: ", display_offset_y)
	if not apply_player_path.is_empty():
		print("  applied_to_player: ", apply_player_path)

	return OK


func _get_display_scale(manifest_data: Dictionary, target_height: float) -> float:
	var unified_box: Dictionary = manifest_data.get("unifiedBox", {})
	var height := float(unified_box.get("height", 144.0))
	if height <= 0.0:
		height = 144.0

	return snappedf(target_height / height, 0.001)


func _get_display_offset_y(manifest_data: Dictionary, display_scale: float) -> int:
	var unified_box: Dictionary = manifest_data.get("unifiedBox", {})
	var height := float(unified_box.get("height", 144.0))
	return -int(round(height * display_scale * 0.5))


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

	return line.substr(0, start) + new_path + line.substr(end)


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


func _replace_character_transform(text: String, display_scale: float, display_offset_y: int) -> String:
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
			lines[index] = "position = Vector2(0, %s)" % display_offset_y
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


func _print_usage() -> void:
	print("Usage:")
	print("  godot --headless --script res://scripts/editor/import_character.gd -- --source <character_dir> [--apply-player <player_scene>] [--target-height <pixels>] [--facing left|right]")
