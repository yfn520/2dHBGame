extends AnimatedSprite2D

## 单次播放附着特效:播放完毕后自动 queue_free()。
func _ready() -> void:
    if not is_playing:
        play()
    animation_finished.connect(_on_finished)

func _on_finished() -> void:
    queue_free()
