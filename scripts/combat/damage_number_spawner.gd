extends Node
class_name DamageNumberSpawner
## 伤害飘字生成器：监听 combat.took_damage 信号，在受击者头顶生成飘字

var _owner_node: Node2D
var _combat: Node
var _packed: PackedScene = preload("res://scenes/effects/damage_number.tscn")


func setup(owner_node: Node2D, combat: Node) -> void:
	_owner_node = owner_node
	_combat = combat
	if _combat != null and _combat.has_signal("took_damage"):
		_combat.took_damage.connect(_on_took_damage)


func _on_took_damage(amount: int, source: Node) -> void:
	if amount <= 0 or _owner_node == null:
		return
	var scene := _owner_node.get_tree().current_scene
	if scene == null:
		return
	var label := _packed.instantiate() as DamageNumber
	if label == null:
		return
	scene.add_child(label)
	# 飘字位置：受击者头顶上方 10px
	var pos := _owner_node.global_position
	pos.y = _get_head_top_y(_owner_node) - 10.0
	label.popup(amount, pos)


## 读取 HurtBox CollisionShape2D 顶部世界 y 坐标；读不到则回退到角色根上方 120px
func _get_head_top_y(node: Node) -> float:
	var shape_node := node.get_node_or_null("HurtBox/CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var rect := shape_node.shape as RectangleShape2D
		var height := absf(rect.size.y * shape_node.global_scale.y)
		# shape 中心在世界 y，顶部 = 中心 - height/2
		return shape_node.global_position.y - height * 0.5
	if node is Node2D:
		return (node as Node2D).global_position.y - 120.0
	return 0.0
