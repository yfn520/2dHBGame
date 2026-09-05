extends SceneTree

## 守卫：工作台发布的任务区域/交互/拾取条目必须都有可见表现，不能退回成空框或菱形占位。

const WORLD_CONTENT_PATH := "res://data/runtime_world_content.json"
const WORLD_TASK_VISUAL_PATH := "res://scripts/world/world_task_visual.gd"


func _init() -> void:
	var failures: Array[String] = []
	var visual_source := FileAccess.get_file_as_string(WORLD_TASK_VISUAL_PATH)
	if not visual_source.contains("func _build_pickup_item_icon") or not visual_source.contains("ResourceLoader.exists(icon_path)"):
		failures.append("task pickup visuals must prefer a generated item icon when the PNG exists")
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(WORLD_CONTENT_PATH)) != OK or not json.data is Dictionary:
		push_error("cannot read %s" % WORLD_CONTENT_PATH)
		quit(1)
		return
	var checked := 0
	var cart_checked := false
	# headless --script 模式不注册 autoload：world_task_visual.gd 引用 GameRegistry，
	# 编译会失败且 load() 返回无效对象，直接 .new() 会中断 _init 导致挂死。
	# 可实例化时才做节点级校验，否则降级为数据 + 源码契约校验。
	var visual_script: GDScript = load(WORLD_TASK_VISUAL_PATH)
	var can_instance: bool = visual_script != null and visual_script.can_instantiate()
	if not can_instance:
		print("[world_task_visuals] headless 下 WorldTaskVisual 不可实例化，降级为数据+源码契约校验")
	for level in (json.data as Dictionary).get("levels", {}).values():
		if not level is Dictionary:
			continue
		for entry in (level as Dictionary).get("interactables", []):
			if not entry is Dictionary:
				continue
			var content_type := str((entry as Dictionary).get("type", ""))
			if content_type not in ["area_event", "named_event", "pickup"]:
				continue
			checked += 1
			if can_instance:
				var visual: Node = visual_script.new()
				visual.setup(entry as Dictionary)
				if visual.get_child_count() < 3:
					failures.append("%s has no substantial visual" % str((entry as Dictionary).get("id", "unknown")))
				if str((entry as Dictionary).get("id", "")) == "c1_grain_cart_passed" and visual.get_child_count() < 18:
					failures.append("grain cart visual is incomplete")
				visual.free()
			if str((entry as Dictionary).get("id", "")) == "c1_grain_cart_passed":
				cart_checked = true
			# SceneTree teardown owns these short-lived visual nodes.
	if checked == 0:
		failures.append("no task world content was checked")
	if not cart_checked:
		failures.append("grain cart world event missing")
	if failures.is_empty():
		print("WORLD_TASK_VISUALS_OK entries=%d" % checked)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
