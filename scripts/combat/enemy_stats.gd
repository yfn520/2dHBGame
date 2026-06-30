class_name EnemyStats
## 怪物属性对象，接口与 CharacterStats 一致，供 CombatComponent 使用

var max_hp: int
var hp: int
var attack: int
var defense: int
var move_speed: float


func _init(cfg: Dictionary) -> void:
	max_hp = int(cfg.get("max_hp", 50))
	hp = max_hp
	attack = int(cfg.get("attack", 1))
	defense = int(cfg.get("defense", 0))
	move_speed = float(cfg.get("move_speed", 80.0))


func is_alive() -> bool:
	return hp > 0
