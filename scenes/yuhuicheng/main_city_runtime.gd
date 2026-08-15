extends Node2D

func _ready() -> void:
	scale = Vector2.ONE
	for child in find_children("*", "Sprite2D", true, false):
		var sprite := child as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var image := sprite.texture.get_image()
		if image == null:
			continue
		if not image.has_mipmaps():
			image.generate_mipmaps()
		sprite.texture = ImageTexture.create_from_image(image)
