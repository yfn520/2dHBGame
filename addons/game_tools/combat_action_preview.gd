@tool
extends Control

var frame_texture: Texture2D
var sprite_scale := 1.0
var frame_index := 0
var window_data: Dictionary = {}
var facing_right := false
var sprite_position := Vector2.ZERO
var sprite_offset := Vector2.ZERO
var sprite_node_scale := Vector2.ONE
var sprite_centered := true
var root_position := Vector2.ZERO


func set_preview(texture: Texture2D, scale_value: float, frame: int, hit_window: Dictionary, right: bool, visual: Dictionary = {}) -> void:
	frame_texture = texture
	sprite_scale = maxf(0.01, scale_value)
	frame_index = frame
	window_data = hit_window
	facing_right = right
	sprite_position = visual.get("position", Vector2.ZERO)
	sprite_offset = visual.get("offset", Vector2.ZERO)
	sprite_node_scale = visual.get("scale", Vector2.ONE)
	sprite_centered = bool(visual.get("centered", true))
	root_position = visual.get("root_position", Vector2.ZERO)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("171b22"), true)
	if frame_texture == null:
		draw_string(ThemeDB.fallback_font, Vector2(20, 32), "没有可预览的动画帧", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		return
	var texture_size := frame_texture.get_size()
	var world_size := texture_size * sprite_scale
	var available := size - Vector2(32, 52)
	var zoom := minf(available.x / world_size.x, available.y / world_size.y)
	zoom = maxf(0.01, zoom)
	var origin := Vector2(size.x * 0.5, size.y * 0.5 + 12.0)
	var visual_origin := origin + root_position * zoom + sprite_position * sprite_scale * zoom
	var draw_scale := zoom * sprite_scale
	var horizontal_scale := (-draw_scale if facing_right else draw_scale) * sprite_node_scale.x
	var vertical_scale := draw_scale * sprite_node_scale.y
	var texture_origin := sprite_offset
	if sprite_centered:
		texture_origin -= texture_size * 0.5
	draw_set_transform(visual_origin, 0.0, Vector2(horizontal_scale, vertical_scale))
	draw_texture(frame_texture, texture_origin)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(origin + Vector2(-8, 0), origin + Vector2(8, 0), Color("64b5f6"), 1.0)
	draw_line(origin + Vector2(0, -8), origin + Vector2(0, 8), Color("64b5f6"), 1.0)
	var start_frame := int(window_data.get("start_frame", -1))
	var end_frame := int(window_data.get("end_frame", -1))
	if frame_index >= start_frame and frame_index <= end_frame:
		var direction := 1.0 if facing_right else -1.0
		var center := origin + Vector2(
			direction * absf(float(window_data.get("forward", 0.0))),
			float(window_data.get("y", 0.0))
		) * zoom
		var hit_size := Vector2(
			float(window_data.get("width", 1.0)),
			float(window_data.get("height", 1.0))
		) * zoom
		draw_rect(Rect2(center - hit_size * 0.5, hit_size), Color(1.0, 0.2, 0.2, 0.22), true)
		draw_rect(Rect2(center - hit_size * 0.5, hit_size), Color("ff5252"), false, 2.0)
	var direction_text := "朝右" if facing_right else "朝左（素材默认）"
	draw_string(ThemeDB.fallback_font, Vector2(14, 24), "帧 %d · %s · Sprite位置(%.1f, %.1f)" % [frame_index, direction_text, sprite_position.x, sprite_position.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e8eaed"))
