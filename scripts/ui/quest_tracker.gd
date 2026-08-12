class_name QuestTracker
extends PanelContainer
## 主 HUD 常驻任务追踪：只显示进行中/可交付任务及实时目标数量。

const TRACKER_WIDTH := 340.0
const MAX_VISIBLE_QUESTS := 3

var _service: QuestService
var _list: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"HUDCard"
	custom_minimum_size.x = TRACKER_WIDTH
	_build_layout()
	get_viewport().size_changed.connect(_apply_viewport_layout)
	call_deferred("_apply_viewport_layout")


func setup(service: QuestService) -> void:
	_service = service
	if _service != null and not _service.quest_updated.is_connected(_on_quest_updated):
		_service.quest_updated.connect(_on_quest_updated)
	_refresh()


func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	margin.add_child(content)
	var header := Label.new()
	header.text = "当前任务"
	header.theme_type_variation = &"HUDTitle"
	header.add_theme_font_size_override("font_size", 17)
	content.add_child(header)
	var separator := HSeparator.new()
	content.add_child(separator)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 9)
	content.add_child(_list)


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var active_tasks: Array[Dictionary] = []
	if _service != null:
		for value in _service.get_visible_tasks():
			if value is Dictionary and str(value.get("status", "")) in ["active", "ready"]:
				active_tasks.append(value as Dictionary)
	visible = not active_tasks.is_empty()
	for task_index in range(mini(active_tasks.size(), MAX_VISIBLE_QUESTS)):
		_add_task(active_tasks[task_index])
	_apply_viewport_layout()


func _add_task(quest: Dictionary) -> void:
	var status := str(quest.get("status", "active"))
	var title := Label.new()
	title.text = "%s  %s" % ["○" if status == "ready" else "!", str(quest.get("title", "任务"))]
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("58c7ff") if status == "ready" else Color("ffd84d"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(title)
	var objectives: Array = quest.get("objectives", [])
	for index in range(objectives.size()):
		if not objectives[index] is Dictionary:
			continue
		var objective: Dictionary = objectives[index]
		var progress := _service.get_objective_progress(int(quest.get("id", 0)), objective, index)
		var line := Label.new()
		line.text = "  %s  %d/%d" % [
			_service.get_objective_text(objective),
			int(progress.get("current", 0)),
			int(progress.get("required", 1)),
		]
		line.add_theme_font_size_override("font_size", 14)
		line.add_theme_color_override("font_color", Color("7edb8f") if bool(progress.get("complete", false)) else Color("eee4c7"))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(line)


func _apply_viewport_layout() -> void:
	if not visible:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	position = Vector2(maxf(12.0, viewport_size.x - TRACKER_WIDTH - 22.0), 292.0)
	size.x = TRACKER_WIDTH


func _on_quest_updated(_quest_id: int) -> void:
	_refresh()
