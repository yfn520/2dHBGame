extends Node
class_name HitFlashController
## 受击半透控制器：运行时给角色精灵注入半透 ShaderMaterial，受击时变半透，duration 秒后还原。
## 半透程度在 hit_flash.gdshader 的 hit_alpha uniform 配置（默认 0.5）

var _sprite: CanvasItem
var _shader_mat: ShaderMaterial
var _timer: SceneTreeTimer = null


func setup(sprite: CanvasItem) -> void:
	_sprite = sprite
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = preload("res://scenes/effects/hit_flash.gdshader")
	# hit_alpha 用 shader 默认值，无需运行时设置


## 触发半透：把 sprite.material 设为半透材质，duration 秒后还原
func flash(duration: float = 0.1) -> void:
	if _sprite == null or _shader_mat == null:
		return
	_sprite.material = _shader_mat
	if _timer != null and _timer.time_left > 0.0:
		_timer.timeout.disconnect(_restore)
	_timer = _sprite.get_tree().create_timer(duration)
	_timer.timeout.connect(_restore)


func _restore() -> void:
	if _sprite != null:
		_sprite.material = null
