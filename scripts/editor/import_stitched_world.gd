extends SceneTree

const RAW_SCENE_FILE := "map_stitch_godot.tscn"
const RAW_JSON_FILE := "map_stitch_godot.json"


func _init() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	if options.is_empty():
		_print_usage()
		quit(1)
		return

	var error := _import_world(options)
	if error != OK:
		push_error("World import failed with code %s" % error)
		quit(1)
		return

	quit()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var options := {
		"source_dir": "",
		"output_scene": "",
		"root_name": ""
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
			"--output":
				options["output_scene"] = next_value
				index += 2
			"--root-name":
				options["root_name"] = next_value
				index += 2
			_:
				index += 1

	if options["source_dir"].is_empty():
		return {}

	if options["output_scene"].is_empty():
		var folder_name := options["source_dir"].trim_suffix("/").trim_suffix("\\").get_file()
		options["output_scene"] = "res://scenes/%s.tscn" % folder_name

	if options["root_name"].is_empty():
		options["root_name"] = _to_pascal_case(options["output_scene"].get_file().get_basename())

	return options


func _import_world(options: Dictionary) -> int:
	var source_dir: String = options["source_dir"]
	var output_scene: String = options["output_scene"]
	var root_name: String = options["root_name"]

	var raw_scene_path := source_dir.path_join(RAW_SCENE_FILE)
	var raw_json_path := source_dir.path_join(RAW_JSON_FILE)

	if not FileAccess.file_exists(raw_scene_path):
		push_error("Missing raw scene: %s" % raw_scene_path)
		return ERR_FILE_NOT_FOUND

	if not FileAccess.file_exists(raw_json_path):
		push_error("Missing raw json: %s" % raw_json_path)
		return ERR_FILE_NOT_FOUND

	var raw_scene := load(raw_scene_path) as PackedScene
	if raw_scene == null:
		push_error("Failed to load raw scene: %s" % raw_scene_path)
		return ERR_PARSE_ERROR

	var json_text := FileAccess.get_file_as_string(raw_json_path)
	var json := JSON.new()
	var parse_error := json.parse(json_text)
	if parse_error != OK:
		push_error("Failed to parse json: %s" % raw_json_path)
		return parse_error

	var root := Node2D.new()
	root.name = root_name

	var map_instance := raw_scene.instantiate()
	map_instance.name = "Map"
	root.add_child(map_instance)
	map_instance.owner = root

	var spawn := Marker2D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = _get_default_spawn(json.data)
	root.add_child(spawn)
	spawn.owner = root

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		push_error("Failed to pack scene: %s" % output_scene)
		return pack_error

	var output_dir := output_scene.get_base_dir()
	var make_dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if make_dir_error != OK:
		push_error("Failed to create output directory: %s" % output_dir)
		return make_dir_error

	var save_error := ResourceSaver.save(packed, output_scene)
	if save_error != OK:
		push_error("Failed to save output scene: %s" % output_scene)
		return save_error

	print("Imported world:")
	print("  source: ", source_dir)
	print("  output: ", output_scene)
	print("  root: ", root_name)
	print("  spawn: ", spawn.position)
	return OK


func _get_default_spawn(data: Variant) -> Vector2:
	if typeof(data) != TYPE_DICTIONARY:
		return Vector2(160, 350)

	var canvas: Dictionary = data.get("canvas", {})
	var width := float(canvas.get("width", 1376))
	var height := float(canvas.get("height", 768))
	var spawn_x := clampf(width * 0.12, 96.0, maxf(96.0, width - 96.0))
	var spawn_y := clampf(height * 0.46, 96.0, maxf(96.0, height - 96.0))
	return Vector2(spawn_x, spawn_y)


func _to_pascal_case(value: String) -> String:
	var words := PackedStringArray()
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


func _is_word_character(character: String) -> bool:
	if character.is_empty():
		return false

	var code := character.unicode_at(0)
	var is_digit := code >= 48 and code <= 57
	var is_upper := code >= 65 and code <= 90
	var is_lower := code >= 97 and code <= 122
	return is_digit or is_upper or is_lower


func _print_usage() -> void:
	print("Usage:")
	print("  godot --headless --script res://scripts/editor/import_stitched_world.gd -- --source <world_dir> [--output <scene_path>] [--root-name <node_name>]")
