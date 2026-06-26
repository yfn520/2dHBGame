extends Node2D

@onready var level_container: Node2D = $LevelContainer
@onready var player: CharacterBody2D = $Player


func _ready() -> void:
	call_deferred("_place_player_at_spawn")


func _place_player_at_spawn() -> void:
	if level_container.get_child_count() == 0:
		return

	var current_level := level_container.get_child(0)
	var spawn: Marker2D = current_level.get_node_or_null("PlayerSpawn")
	if spawn != null:
		player.global_position = spawn.global_position
