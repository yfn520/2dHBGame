extends Node2D

@onready var level_container: Node2D = $LevelContainer
@onready var player: CharacterBody2D = $Player
@onready var inventory_panel: CanvasLayer = $InventoryPanel
@onready var character_panel: CanvasLayer = $CharacterPanel


func _ready() -> void:
	call_deferred("_place_player_at_spawn")


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	# 有面板打开时，不处理 B/C（由面板自己处理关闭）
	if inventory_panel.is_open() or character_panel.is_open():
		return
	match event.keycode:
		KEY_B:
			inventory_panel.toggle()
			get_viewport().set_input_as_handled()
		KEY_C:
			character_panel.toggle()
			get_viewport().set_input_as_handled()


func _place_player_at_spawn() -> void:
	if level_container.get_child_count() == 0:
		return

	var current_level := level_container.get_child(0)
	var spawn: Marker2D = current_level.get_node_or_null("PlayerSpawn")
	if spawn != null:
		player.global_position = spawn.global_position
