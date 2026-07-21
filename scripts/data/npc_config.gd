class_name NpcConfig

const CONFIG_PATH := "res://data/npcs.json"
const REQUIRED_ASSET_VERSION := 1

var _npcs: Dictionary = {}
var _errors: Array[String] = []


func load_config(dialogue_config = null) -> void:
	_npcs.clear()
	_errors.clear()
	var data := _read_json(CONFIG_PATH)
	for id_value in data:
		if not data[id_value] is Dictionary:
			_errors.append("NPC %s definition must be an object" % id_value)
			continue
		var id := int(id_value)
		if id <= 0:
			_errors.append("NPC id must be a positive integer: %s" % id_value)
			continue
		var config := _validate_npc(id, data[id_value] as Dictionary, dialogue_config)
		if not config.is_empty():
			_npcs[id] = config
	for error in _errors:
		push_error(error)


func get_npc(npc_id: int) -> Dictionary:
	return (_npcs.get(npc_id, {}) as Dictionary).duplicate(true)


func get_all_npcs() -> Dictionary:
	return _npcs.duplicate(true)


func get_errors() -> Array[String]:
	return _errors.duplicate()


func _validate_npc(id: int, raw: Dictionary, dialogue_config) -> Dictionary:
	var allowed_fields := ["name", "asset", "dialogue_id", "interaction_radius", "default_facing"]
	for field in raw:
		if String(field) not in allowed_fields:
			_errors.append("NPC %d definition contains unsupported field: %s" % [id, field])
			return {}
	if not raw.get("name") is String or not raw.get("asset") is String or not raw.get("dialogue_id") is String:
		_errors.append("NPC %d name, asset and dialogue_id must be strings" % id)
		return {}
	var display_name := String(raw.get("name", "")).strip_edges()
	var asset_path := String(raw.get("asset", "")).trim_suffix("/")
	var dialogue_id := String(raw.get("dialogue_id", "")).strip_edges()
	if display_name.is_empty() or asset_path.is_empty() or dialogue_id.is_empty():
		_errors.append("NPC %d is missing name, asset or dialogue_id" % id)
		return {}
	var asset_slug := asset_path.trim_prefix("res://assets/npcs/")
	if not asset_path.begins_with("res://assets/npcs/") or asset_slug.contains("/") or not _is_slug(asset_slug):
		_errors.append("NPC %d asset must be one res://assets/npcs/<slug> directory: %s" % [id, asset_path])
		return {}
	if not _is_number(raw.get("interaction_radius")) or float(raw.get("interaction_radius")) < 16.0:
		_errors.append("NPC %d interaction_radius must be a number of at least 16" % id)
		return {}
	if not raw.get("default_facing") is String or String(raw.get("default_facing")) not in ["left", "right"]:
		_errors.append("NPC %d default_facing must be left or right" % id)
		return {}
	if dialogue_config != null and dialogue_config.get_dialogue(dialogue_id).is_empty():
		_errors.append("NPC %d references missing dialogue_id: %s" % [id, dialogue_id])
		return {}

	var manifest_path := asset_path.path_join("npc_asset.json")
	var asset := _read_json(manifest_path)
	if asset.is_empty() or not _validate_asset(id, asset_path, asset):
		return {}
	return {
		"id": id,
		"name": display_name,
		"asset": asset_path,
		"dialogue_id": dialogue_id,
		"interaction_radius": float(raw.get("interaction_radius")),
		"default_facing": String(raw.get("default_facing")),
		"asset_data": asset,
		"portrait": String(asset.get("portrait")),
	}


func _validate_asset(npc_id: int, asset_path: String, asset: Dictionary) -> bool:
	if not _is_number(asset.get("version")) or int(asset.get("version")) != REQUIRED_ASSET_VERSION:
		_errors.append("NPC %d npc_asset.json version must be 1" % npc_id)
		return false
	for field in ["id", "display_name", "default_animation", "spriteframes", "visual_scene", "portrait"]:
		if not asset.get(field) is String or String(asset.get(field)).strip_edges().is_empty():
			_errors.append("NPC %d npc_asset.json field %s must be a non-empty string" % [npc_id, field])
			return false
	if String(asset.get("id")) != asset_path.get_file():
		_errors.append("NPC %d npc_asset.json id must match its package directory" % npc_id)
		return false
	for field in ["spriteframes", "visual_scene", "portrait"]:
		var resource_path := String(asset.get(field))
		if not _is_owned_resource_path(asset_path, resource_path):
			_errors.append("NPC %d %s must stay inside its NPC package: %s" % [npc_id, field, resource_path])
			return false
		if not ResourceLoader.exists(resource_path):
			_errors.append("NPC %d %s does not exist: %s" % [npc_id, field, resource_path])
			return false
	var sprite_frames := load(String(asset.get("spriteframes"))) as SpriteFrames
	if sprite_frames == null or not sprite_frames.has_animation(String(asset.get("default_animation"))):
		_errors.append("NPC %d spriteframes is invalid or missing its default animation" % npc_id)
		return false
	if not load(String(asset.get("visual_scene"))) is PackedScene:
		_errors.append("NPC %d visual_scene must be a PackedScene" % npc_id)
		return false
	if not load(String(asset.get("portrait"))) is Texture2D:
		_errors.append("NPC %d portrait must be a Texture2D" % npc_id)
		return false
	if not asset.get("frame_size") is Dictionary or not asset.get("foot_center") is Dictionary:
		_errors.append("NPC %d frame_size and foot_center must be objects" % npc_id)
		return false
	var frame_size := asset.get("frame_size") as Dictionary
	var foot_center := asset.get("foot_center") as Dictionary
	if not _is_number(frame_size.get("width")) or not _is_number(frame_size.get("height")):
		_errors.append("NPC %d frame_size width and height must be numbers" % npc_id)
		return false
	var width := float(frame_size.get("width"))
	var height := float(frame_size.get("height"))
	if width <= 0.0 or height <= 0.0:
		_errors.append("NPC %d frame_size must be positive" % npc_id)
		return false
	if not _is_number(foot_center.get("x")) or not _is_number(foot_center.get("y")):
		_errors.append("NPC %d foot_center x and y must be numbers" % npc_id)
		return false
	var foot_x := float(foot_center.get("x"))
	var foot_y := float(foot_center.get("y"))
	if foot_x < 0.0 or foot_x > width or foot_y < 0.0 or foot_y > height:
		_errors.append("NPC %d foot_center must be inside frame_size" % npc_id)
		return false
	if not _is_number(asset.get("display_scale")) or float(asset.get("display_scale")) <= 0.0:
		_errors.append("NPC %d display_scale must be a positive number" % npc_id)
		return false
	return true


func _is_owned_resource_path(asset_path: String, resource_path: String) -> bool:
	return resource_path.begins_with(asset_path + "/") and not resource_path.contains("/../")


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_slug(value: String) -> bool:
	var pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return pattern.search(value) != null


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_errors.append("Required NPC JSON file does not exist: %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		_errors.append("NPC JSON parse failed: %s" % path)
		return {}
	return json.data
