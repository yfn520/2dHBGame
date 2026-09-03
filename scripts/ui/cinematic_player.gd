class_name CinematicPlayer
extends CanvasLayer

## 全屏过场视频播放器：播放任务时间轴里的 kind="video" 片段（.ogv / Ogg Theora）。
## UIRoot 监听 DialogueService.video_clip_started 后调用 play_video()；
## 播放完成或玩家点击「跳过」时发出 finished 信号，由 UIRoot 调用 tl_video_finished() 推进时间轴。
##
## 数据契约（dialogues.json 片段）：
##   { "kind": "video", "asset": "res://assets/cinematics/xxx.ogv", "durationMs": 8000, "text": "过场标题" }

signal finished

var _bg: ColorRect
var _player: VideoStreamPlayer
var _texture_rect: TextureRect
var _subtitle: Label
var _skip_button: Button
var _playing := false
# 图+文模式：按 durationMs 定时结束（也可点击跳过）
var _still_duration := 0.0
var _still_elapsed := 0.0


func _init() -> void:
	layer = 90
	visible = false
	# 对白期间主树可能被暂停：视频与跳过按钮必须继续工作
	process_mode = Node.PROCESS_MODE_ALWAYS

	_bg = ColorRect.new()
	_bg.color = Color.BLACK
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg.gui_input.connect(_on_bg_input)
	add_child(_bg)

	_texture_rect = TextureRect.new()
	_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_texture_rect)

	_player = VideoStreamPlayer.new()
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.expand = true
	_player.finished.connect(_on_finished)
	add_child(_player)

	_subtitle = Label.new()
	_subtitle.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_subtitle.offset_top = -76.0
	_subtitle.offset_bottom = -28.0
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 22)
	_subtitle.add_theme_color_override("font_color", Color(0.96, 0.94, 0.9))
	_subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_subtitle.add_theme_constant_override("shadow_offset_x", 1)
	_subtitle.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_subtitle)

	_skip_button = Button.new()
	_skip_button.text = "跳过 ▸"
	_skip_button.add_theme_font_size_override("font_size", 14)
	_skip_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_button.offset_left = -108.0
	_skip_button.offset_top = -52.0
	_skip_button.offset_right = -20.0
	_skip_button.offset_bottom = -16.0
	_skip_button.pressed.connect(_skip)
	add_child(_skip_button)


## 播放一段过场演出；clip 为 kind="video" 的 dialogues.json 片段：
## medium="video" 播 .ogv；medium="still" 全屏展示 .png 并按 durationMs 定时（可点击跳过）
func play_clip(clip: Dictionary) -> void:
	var asset := str(clip.get("asset", ""))
	if str(clip.get("medium", "video")) == "still":
		_play_still(asset, str(clip.get("text", "")), int(clip.get("durationMs", 3000)))
	else:
		play_video(asset, str(clip.get("text", "")))


## 播放一段过场视频；asset 为 res:// 下的 .ogv 路径，subtitle 为底部字幕（可空）
func play_video(asset: String, subtitle: String = "") -> void:
	if asset.is_empty() or not ResourceLoader.exists(asset):
		# 调用方应先确认资源存在；防御性兜底：直接完成，不阻塞时间轴
		finished.emit()
		return
	var stream := load(asset)
	if stream == null:
		finished.emit()
		return
	_subtitle.text = subtitle
	_player.stream = stream
	visible = true
	_playing = true
	_player.play()


## 全屏图 + 文字：展示一张 .png，按 durationMs 定时结束，点击/跳过按钮提前结束
func _play_still(texture_path: String, subtitle: String, duration_ms: int) -> void:
	var texture := load(texture_path)
	if texture == null:
		finished.emit()
		return
	_subtitle.text = subtitle
	_texture_rect.texture = texture
	_still_duration = maxf(1.5, float(duration_ms) / 1000.0)
	_still_elapsed = 0.0
	visible = true
	_playing = true
	set_process(true)


func _process(delta: float) -> void:
	if not _playing or _texture_rect.texture == null:
		return
	_still_elapsed += delta
	if _still_elapsed >= _still_duration:
		_on_finished()


func is_playing() -> bool:
	return _playing


func _skip() -> void:
	if not _playing:
		return
	if _texture_rect.texture != null:
		_texture_rect.texture = null
	_player.stop()
	_on_finished()


func _on_bg_input(event: InputEvent) -> void:
	# 图+文模式：点击任意处继续；视频模式交给右下角跳过按钮
	if _playing and _texture_rect.texture != null and event is InputEventMouseButton and event.is_pressed():
		_skip()


func _on_finished() -> void:
	if not _playing:
		return
	_playing = false
	set_process(false)
	_texture_rect.texture = null
	_player.stream = null
	visible = false
	finished.emit()
