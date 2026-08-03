extends Node
## 全局音频管理器（autoload）。
## 提供非空间化 / 2D 空间化 / 固定位置三种播放方式，
## 内部维护播放器池避免频繁实例化，支持音量持久化。
##
## 技能音效通过 play_sound 节点 / 弹道音效字段 / 伤害绑定音效调用本管理器。

const SETTINGS_PATH := "user://settings.json"
const BUS_MASTER := "Master"
const BUS_BGM := "BGM"
const BUS_SFX := "SFX"
const BUS_UI := "UI"
const DEFAULT_MAX_POLYPHONY := 3
const POOL_SIZE_NON_SPATIAL := 16
const POOL_SIZE_SPATIAL := 16

# --- 播放器池 ---
var _non_spatial_pool: Array[AudioStreamPlayer] = []
var _spatial_pool: Array[AudioStreamPlayer2D] = []
var _non_spatial_index := 0
var _spatial_index := 0

# --- 通道管理：channel_id → {player, loop, stream_path} ---
var _channels: Dictionary = {}
var _next_channel_id := 1

# --- 多音节限制：stream_path → 当前播放数 ---
var _polyphony_counts: Dictionary = {}
var _polyphony_limits: Dictionary = {}  # stream_path → max

# --- 音量缓存 ---
var _bus_volumes: Dictionary = {}  # bus_name → db


func _ready() -> void:
	_create_pools()
	_load_settings()


## 非空间化播放（全屏/UI/Buff）。返回 channel_id（>0），失败返回 -1。
func play_sfx(stream: AudioStream, gain_db: float = 0.0, pitch_variation: float = 0.0, loop: bool = false, bus: String = BUS_SFX, max_polyphony: int = DEFAULT_MAX_POLYPHONY) -> int:
	if stream == null:
		return -1
	var stream_path := _stream_key(stream)
	if not _can_play(stream_path, max_polyphony):
		return -1
	var player := _acquire_non_spatial(bus)
	if player == null:
		return -1
	_configure_player(player, stream, gain_db, pitch_variation, loop)
	player.play()
	var channel_id := _register_channel(player, loop, stream_path)
	return channel_id


## 2D 空间化播放（跟随 Node2D）。返回 channel_id（>0），失败返回 -1。
func play_sfx_2d(stream: AudioStream, follow: Node2D, gain_db: float = 0.0, pitch_variation: float = 0.0, loop: bool = false, bus: String = BUS_SFX, max_polyphony: int = DEFAULT_MAX_POLYPHONY) -> int:
	if stream == null:
		return -1
	var stream_path := _stream_key(stream)
	if not _can_play(stream_path, max_polyphony):
		return -1
	var player := _acquire_spatial(bus)
	if player == null:
		return -1
	_configure_player(player, stream, gain_db, pitch_variation, loop)
	# 跟随目标节点位置
	if follow != null and is_instance_valid(follow):
		player.global_position = follow.global_position
		# 循环音效持续跟随
		if loop:
			player.set_meta("follow_node", follow)
	player.play()
	var channel_id := _register_channel(player, loop, stream_path)
	return channel_id


## 在固定世界位置播放。返回 channel_id（>0），失败返回 -1。
func play_sfx_at(stream: AudioStream, pos: Vector2, gain_db: float = 0.0, pitch_variation: float = 0.0, loop: bool = false, bus: String = BUS_SFX, max_polyphony: int = DEFAULT_MAX_POLYPHONY) -> int:
	if stream == null:
		return -1
	var stream_path := _stream_key(stream)
	if not _can_play(stream_path, max_polyphony):
		return -1
	var player := _acquire_spatial(bus)
	if player == null:
		return -1
	_configure_player(player, stream, gain_db, pitch_variation, loop)
	player.global_position = pos
	player.play()
	var channel_id := _register_channel(player, loop, stream_path)
	return channel_id


## 停止指定通道（flight loop 用）。
func stop(channel_id: int) -> void:
	if not _channels.has(channel_id):
		return
	var entry: Dictionary = _channels[channel_id]
	var player = entry.get("player")
	if player != null and is_instance_valid(player):
		player.stop()
		var stream_path := String(entry.get("stream_path", ""))
		_decrement_polyphony(stream_path)
	_channels.erase(channel_id)


## 设置 bus 音量（db），并持久化。
func set_bus_volume(bus: String, db: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, db)
	_bus_volumes[bus] = db
	_save_settings()


## 获取 bus 音量（db）。
func get_bus_volume(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return 0.0
	return AudioServer.get_bus_volume_db(idx)


## 通过资源路径加载并播放（便捷方法）。
func play_sfx_by_path(audio_path: String, gain_db: float = 0.0, pitch_variation: float = 0.0, loop: bool = false, bus: String = BUS_SFX) -> int:
	var stream := _load_stream(audio_path)
	if stream == null:
		return -1
	return play_sfx(stream, gain_db, pitch_variation, loop, bus)


## 通过资源路径加载并 2D 空间化播放（便捷方法）。
func play_sfx_2d_by_path(audio_path: String, follow: Node2D, gain_db: float = 0.0, pitch_variation: float = 0.0, loop: bool = false, bus: String = BUS_SFX) -> int:
	var stream := _load_stream(audio_path)
	if stream == null:
		return -1
	return play_sfx_2d(stream, follow, gain_db, pitch_variation, loop, bus)


# ===================== 内部实现 =====================

func _create_pools() -> void:
	for i in range(POOL_SIZE_NON_SPATIAL):
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_non_spatial_pool.append(player)
	for i in range(POOL_SIZE_SPATIAL):
		var player := AudioStreamPlayer2D.new()
		player.bus = BUS_SFX
		add_child(player)
		_spatial_pool.append(player)


func _acquire_non_spatial(bus: String) -> AudioStreamPlayer:
	for i in range(POOL_SIZE_NON_SPATIAL):
		var idx := (_non_spatial_index + i) % POOL_SIZE_NON_SPATIAL
		var player := _non_spatial_pool[idx]
		if not player.playing:
			_non_spatial_index = (idx + 1) % POOL_SIZE_NON_SPATIAL
			player.bus = bus
			return player
	# 全部占用：复用第一个（打断最旧的）
	var fallback := _non_spatial_pool[_non_spatial_index]
	_non_spatial_index = (_non_spatial_index + 1) % POOL_SIZE_NON_SPATIAL
	fallback.bus = bus
	return fallback


func _acquire_spatial(bus: String) -> AudioStreamPlayer2D:
	for i in range(POOL_SIZE_SPATIAL):
		var idx := (_spatial_index + i) % POOL_SIZE_SPATIAL
		var player := _spatial_pool[idx]
		if not player.playing:
			_spatial_index = (idx + 1) % POOL_SIZE_SPATIAL
			player.bus = bus
			return player
	var fallback := _spatial_pool[_spatial_index]
	_spatial_index = (_spatial_index + 1) % POOL_SIZE_SPATIAL
	fallback.bus = bus
	return fallback


func _configure_player(player: Node, stream: AudioStream, gain_db: float, pitch_variation: float, loop: bool) -> void:
	player.stream = stream
	# 音量：gain_db 为负值降低音量
	var base_volume := 0.0 if not player is AudioStreamPlayer else (player as AudioStreamPlayer).volume_db
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).volume_db = gain_db
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).volume_db = gain_db
	# 音调随机
	var pitch := 1.0
	if pitch_variation > 0.0:
		pitch = 1.0 + randf_range(-pitch_variation, pitch_variation)
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).pitch_scale = pitch
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).pitch_scale = pitch
	# 循环（仅对支持的 AudioStream 有效）
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED


func _register_channel(player: Node, loop: bool, stream_path: String) -> int:
	var channel_id := _next_channel_id
	_next_channel_id += 1
	_channels[channel_id] = {
		"player": player,
		"loop": loop,
		"stream_path": stream_path,
	}
	_increment_polyphony(stream_path)
	# 非循环音效播放结束后自动清理
	if not loop:
		player.finished.connect(_on_channel_finished.bind(channel_id), CONNECT_ONE_SHOT)
	return channel_id


func _on_channel_finished(channel_id: int) -> void:
	if not _channels.has(channel_id):
		return
	var entry: Dictionary = _channels[channel_id]
	var stream_path := String(entry.get("stream_path", ""))
	_decrement_polyphony(stream_path)
	_channels.erase(channel_id)


func _can_play(stream_path: String, max_polyphony: int) -> bool:
	if max_polyphony <= 0:
		return true
	var current := int(_polyphony_counts.get(stream_path, 0))
	return current < max_polyphony


func _increment_polyphony(stream_path: String) -> void:
	_polyphony_counts[stream_path] = int(_polyphony_counts.get(stream_path, 0)) + 1


func _decrement_polyphony(stream_path: String) -> void:
	var current := int(_polyphony_counts.get(stream_path, 0))
	if current > 0:
		_polyphony_counts[stream_path] = current - 1
		if _polyphony_counts[stream_path] <= 0:
			_polyphony_counts.erase(stream_path)


func _stream_key(stream: AudioStream) -> String:
	if stream == null:
		return ""
	# 用资源路径或实例 ID 作为多音节计数键
	var path := stream.resource_path
	if not path.is_empty():
		return path
	return str(stream.get_instance_id())


func _load_stream(audio_path: String) -> AudioStream:
	if audio_path.is_empty() or not ResourceLoader.exists(audio_path):
		push_warning("AudioManager: 音频资源不存在: %s" % audio_path)
		return null
	return load(audio_path) as AudioStream


func _physics_process(_delta: float) -> void:
	# 循环空间化音效跟随目标节点
	for channel_id in _channels:
		var entry: Dictionary = _channels[channel_id]
		if not bool(entry.get("loop", false)):
			continue
		var player = entry.get("player")
		if player == null or not is_instance_valid(player):
			continue
		if not player is AudioStreamPlayer2D:
			continue
		var follow = player.get_meta("follow_node", null)
		if follow != null and is_instance_valid(follow) and follow is Node2D:
			(player as AudioStreamPlayer2D).global_position = (follow as Node2D).global_position


# --- 音量持久化 ---

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	var data: Dictionary = json.data
	var audio: Dictionary = data.get("audio", {})
	var volumes: Dictionary = audio.get("bus_volumes", {})
	for bus_name in volumes:
		var db := float(volumes[bus_name])
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, db)
		_bus_volumes[bus_name] = db


func _save_settings() -> void:
	var data: Dictionary = {}
	# 读取现有 settings（不覆盖其他字段）
	if FileAccess.file_exists(SETTINGS_PATH):
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file != null:
			var text := file.get_as_text()
			file.close()
			var json := JSON.new()
			if json.parse(text) == OK and json.data is Dictionary:
				data = json.data
	var audio: Dictionary = data.get("audio", {})
	audio["bus_volumes"] = _bus_volumes
	data["audio"] = audio
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
