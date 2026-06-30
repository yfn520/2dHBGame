extends Area2D
## 传送门触发器
## 放置在关卡场景中，玩家进入后切换关卡
##
## 使用方法:
##   1. 在关卡场景中添加一个 Area2D 节点
##   2. 挂载此脚本
##   3. 在检查器中设置 target_level_id 和 spawn_position
##   4. 添加一个 CollisionShape2D 定义触发区域

## 目标关卡 ID（对应 levels.xlsx 中的 ID）
@export var target_level_id: int = 1

## 目标出生点（覆盖目标关卡的默认 PlayerSpawn）
@export var spawn_position: Vector2 = Vector2.ZERO

## 是否需要按键触发（false = 走进即触发）
@export var require_key: bool = true

## 触发按键
@export var action_key: Key = KEY_E

var _player_inside: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = false


func _unhandled_input(event: InputEvent) -> void:
	if not _player_inside:
		return
	if not require_key:
		_do_teleport()
		return
	if event is InputEventKey and event.pressed and event.keycode == action_key:
		_do_teleport()
		get_viewport().set_input_as_handled()


func _do_teleport() -> void:
	if GameRegistry.level_manager == null:
		push_error("LevelManager 未初始化")
		return
	if spawn_position != Vector2.ZERO:
		GameRegistry.level_manager.teleport_to(target_level_id, spawn_position)
	else:
		GameRegistry.level_manager.load_level(target_level_id)
