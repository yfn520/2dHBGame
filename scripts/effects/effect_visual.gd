extends AnimatedSprite2D

@export var fallback_lifetime := 2.0


func manages_own_lifetime() -> bool:
	return true


func _ready() -> void:
	if sprite_frames == null or not sprite_frames.has_animation(animation):
		queue_free()
		return
	play(animation)
	if sprite_frames.get_animation_loop(animation):
		get_tree().create_timer(maxf(0.05, fallback_lifetime)).timeout.connect(queue_free)
	else:
		animation_finished.connect(queue_free, CONNECT_ONE_SHOT)
