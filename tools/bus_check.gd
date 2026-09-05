extends SceneTree
## 诊断：验证混音总线约定（audio_manager._ensure_buses 运行时建总线）。
## 运行：godot --headless --path . --script tools/bus_check.gd

func _init() -> void:
	var script = load("res://scripts/system/audio_manager.gd")
	# 解析失败的脚本 load() 会返回无效对象（非 null），直接 .new() 会中断 _init 导致挂死
	if script == null or not script.can_instantiate():
		push_error("[bus_check] audio_manager.gd 加载/解析失败")
		quit(1)
		return
	var manager = script.new()
	if manager == null:
		push_error("[bus_check] audio_manager 实例化失败")
		quit(1)
		return
	manager._ensure_buses()
	if manager is Node:
		manager.free()
	var names: Array[String] = []
	for i in range(AudioServer.bus_count):
		names.append("%s=%.1fdB" % [AudioServer.get_bus_name(i), AudioServer.get_bus_volume_db(i)])
	print("[bus_check] " + " | ".join(names))
	var failures: Array[String] = []
	for expected in [["BGM", -10.0], ["SFX", 0.0], ["UI", -6.0]]:
		var idx := AudioServer.get_bus_index(String(expected[0]))
		if idx < 0:
			failures.append("缺少总线 %s" % expected[0])
		elif absf(AudioServer.get_bus_volume_db(idx) - float(expected[1])) > 0.01:
			failures.append("总线 %s 音量 %.1f != %.1f" % [expected[0], AudioServer.get_bus_volume_db(idx), float(expected[1])])
		elif AudioServer.get_bus_send(idx) != "Master":
			failures.append("总线 %s 未发送到 Master" % expected[0])
	if failures.is_empty():
		print("[bus_check] OK")
		quit(0)
		return
	for failure in failures:
		push_error("[bus_check] %s" % failure)
	quit(1)
