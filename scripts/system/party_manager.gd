@tool
class_name PartyManager
extends Node2D

signal active_character_changed(character: CharacterBody2D)

@export_category("上阵配置")
@export var lineup: Array[PackedScene] = []
@export_range(0, 8, 1) var initial_active_index := 0

var active_character: CharacterBody2D
var active_index := -1
var _editor_preview: Node2D
var _preview_signature := ""


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		_refresh_editor_preview()
		return
	if not lineup.is_empty():
		switch_character(clampi(initial_active_index, 0, lineup.size() - 1))


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var signature := _get_preview_signature()
	if signature != _preview_signature:
		_refresh_editor_preview()


func _get_preview_signature() -> String:
	var paths := PackedStringArray()
	for scene in lineup:
		paths.append(scene.resource_path if scene != null else "<empty>")
	return "%d|%s" % [initial_active_index, "|".join(paths)]


func _refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_preview_signature = _get_preview_signature()
	if _editor_preview != null and is_instance_valid(_editor_preview):
		_editor_preview.free()
		_editor_preview = null
	if lineup.is_empty():
		return
	var index := clampi(initial_active_index, 0, lineup.size() - 1)
	if lineup[index] == null:
		return
	var instance := lineup[index].instantiate()
	if not instance is Node2D:
		instance.free()
		return
	_editor_preview = instance as Node2D
	_editor_preview.name = "当前主控预览"
	_editor_preview.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_editor_preview)
	# owner 留空，因此预览只存在于编辑器内存，不会写进 player.tscn。
	_editor_preview.owner = null


func get_active_character() -> CharacterBody2D:
	return active_character


func switch_character(index: int) -> bool:
	if index < 0 or index >= lineup.size() or lineup[index] == null:
		push_warning("[PartyManager] 无效的上阵角色索引: %d" % index)
		return false

	var previous_position := global_position
	if active_character != null:
		previous_position = active_character.global_position
		active_character.queue_free()

	var instance := lineup[index].instantiate()
	if not instance is CharacterBody2D:
		push_error("[PartyManager] 上阵预制体根节点必须是 CharacterBody2D")
		instance.queue_free()
		return false

	active_character = instance as CharacterBody2D
	active_index = index
	add_child(active_character)
	active_character.global_position = previous_position
	active_character_changed.emit(active_character)
	return true
