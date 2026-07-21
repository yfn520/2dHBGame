@tool
extends EditorPlugin

const CombatActionEditor = preload("res://addons/game_tools/combat_action_editor.gd")
const ProjectileGenerator = preload("res://addons/game_tools/projectile_generator.gd")
const SpineEffectImporter = preload("res://addons/game_tools/spine_effect_importer.gd")
const SkillSequenceEditor = preload("res://addons/game_tools/skill_sequence_editor.gd")
const LevelEditor = preload("res://addons/game_tools/level_editor.gd")
const BuffEditor = preload("res://addons/game_tools/buff_editor.gd")
const BuffIconGenerator = preload("res://addons/game_tools/buff_icon_generator.gd")
const UiSceneZipImporter = preload("res://addons/game_tools/ui_scene_zip_importer.gd")
const CharacterEditor = preload("res://addons/game_tools/character_editor.gd")
const ItemEditor = preload("res://addons/game_tools/item_editor.gd")
const MapZipImporter = preload("res://addons/game_tools/map_zip_importer.gd")

var _submenu: PopupMenu
var _top_menu_bar: MenuBar
var _combat_action_editor: Window
var _projectile_generator: Window
var _spine_effect_importer: Window
var _skill_sequence_editor: Window
var _level_editor: Window
var _buff_editor: Window
var _buff_icon_generator: Window
var _ui_zip_file_dialog: EditorFileDialog
var _ui_zip_result_dialog: AcceptDialog
var _character_editor: Window
var _item_editor: Window
var _map_zip_file_dialog: EditorFileDialog
var _map_zip_result_dialog: AcceptDialog


func _enter_tree() -> void:
	_submenu = PopupMenu.new()
	_submenu.name = "游戏工具"

	# === 资源生成 ===
	var import_menu := PopupMenu.new()
	import_menu.name = "ImportMenu"
	import_menu.add_item("导入所有场景", 0)
	import_menu.add_item("导入所有角色", 1)
	import_menu.add_item("导入所有怪物", 3)
	import_menu.add_item("从 Zip 导入角色/怪物...", 12)
	import_menu.add_item("导入 UI 场景 Zip...", 13)
	import_menu.add_item("导入地图包...", 17)
	import_menu.add_item("导入 Spine 特效...", 7)
	import_menu.add_item("生成 Buff 图标...", 11)
	import_menu.add_item("生成弹道...", 6)
	import_menu.id_pressed.connect(_on_menu_pressed)
	_submenu.add_child(import_menu)
	_submenu.add_submenu_item("资源生成", "ImportMenu")

	# === 配置编辑 ===
	var config_menu := PopupMenu.new()
	config_menu.name = "ConfigMenu"
	config_menu.add_item("配置角色/怪物...", 14)
	config_menu.add_item("配置物品...", 15)
	config_menu.add_item("配置攻击判定...", 5)
	config_menu.add_item("配置技能节点...", 8)
	config_menu.add_item("配置 Buff...", 10)
	config_menu.add_item("配置关卡...", 9)
	config_menu.id_pressed.connect(_on_menu_pressed)
	_submenu.add_child(config_menu)
	_submenu.add_submenu_item("配置编辑", "ConfigMenu")

	# === 数据转换 ===
	var convert_menu := PopupMenu.new()
	convert_menu.name = "ConvertMenu"
	convert_menu.add_item("转换 Excel → JSON", 2)
	convert_menu.add_item("生成 JSON → Excel (配置用)", 4)
	convert_menu.id_pressed.connect(_on_menu_pressed)
	_submenu.add_child(convert_menu)
	_submenu.add_submenu_item("数据转换", "ConvertMenu")

	# === 顶层：调试开关 ===
	_submenu.add_separator()
	# PC 调试触屏：勾选后写入 application/run/force_touch_controls=true
	_submenu.add_check_item("PC 调试显示触屏控件", 16)
	_submenu.id_pressed.connect(_on_menu_pressed)

	# 挂到顶部菜单栏（和"场景/项目"同级）；找不到 MenuBar 时退回到"工具"子菜单。
	_top_menu_bar = _find_editor_menu_bar()
	if _top_menu_bar != null:
		_top_menu_bar.add_child(_submenu)
	else:
		add_tool_submenu_item("游戏工具", _submenu)
	_sync_force_touch_menu_check()


## 在编辑器主控件树中查找顶部菜单栏。Godot 4 顶部菜单是 MenuBar，藏在 base_control 下多层嵌套里。
## 用递归 find_children(name, type, recursive=true, owner_owned=false) 精确过滤 MenuBar。
func _find_editor_menu_bar() -> MenuBar:
	var base := EditorInterface.get_base_control()
	var candidates := base.find_children("*", "MenuBar", true, false)
	if candidates.is_empty():
		push_warning("[GameTools] 未找到顶部 MenuBar，回退到 工具 子菜单")
		return null
	var menu_bar := candidates[0] as MenuBar
	print("[GameTools] 顶部 MenuBar 已定位: %s" % menu_bar.get_path())
	return menu_bar


func _exit_tree() -> void:
	if is_instance_valid(_combat_action_editor):
		_combat_action_editor.queue_free()
	if is_instance_valid(_projectile_generator):
		_projectile_generator.queue_free()
	if is_instance_valid(_spine_effect_importer):
		_spine_effect_importer.queue_free()
	if is_instance_valid(_skill_sequence_editor):
		_skill_sequence_editor.queue_free()
	if is_instance_valid(_level_editor):
		_level_editor.queue_free()
	if is_instance_valid(_buff_editor):
		_buff_editor.queue_free()
	if is_instance_valid(_buff_icon_generator):
		_buff_icon_generator.queue_free()
	if is_instance_valid(_ui_zip_file_dialog):
		_ui_zip_file_dialog.queue_free()
	if is_instance_valid(_ui_zip_result_dialog):
		_ui_zip_result_dialog.queue_free()
	if is_instance_valid(_map_zip_file_dialog):
		_map_zip_file_dialog.queue_free()
	if is_instance_valid(_map_zip_result_dialog):
		_map_zip_result_dialog.queue_free()
	if is_instance_valid(_character_editor):
		_character_editor.queue_free()
	if is_instance_valid(_item_editor):
		_item_editor.queue_free()
	if _top_menu_bar != null and is_instance_valid(_submenu):
		_submenu.queue_free()
		_top_menu_bar = null
	else:
		remove_tool_menu_item("游戏工具")


# ---- 菜单回调 ----

func _on_menu_pressed(id: int) -> void:
	match id:
		0:
			_do_import_worlds()
		1:
			_do_import_characters()
		2:
			_do_convert_excel()
		3:
			_do_import_enemies()
		4:
			_do_export_json_to_csv()
		5:
			_open_combat_action_editor()
		6:
			_open_projectile_generator()
		7:
			_open_spine_effect_importer()
		8:
			_open_skill_sequence_editor()
		9:
			_open_level_editor()
		10:
			_open_buff_editor()
		11:
			_open_buff_icon_generator()
		12:
			_open_zip_importer()
		13:
			_open_ui_scene_zip_importer()
		14:
			_open_character_editor()
		15:
			_open_item_editor()
		16:
			_toggle_force_touch_controls()
		17:
			_open_map_zip_importer()


func _open_combat_action_editor() -> void:
	if not is_instance_valid(_combat_action_editor):
		_combat_action_editor = CombatActionEditor.new()
		EditorInterface.get_base_control().add_child(_combat_action_editor)
	_combat_action_editor.open_editor()


func _open_projectile_generator() -> void:
	if not is_instance_valid(_projectile_generator):
		_projectile_generator = ProjectileGenerator.new()
		EditorInterface.get_base_control().add_child(_projectile_generator)
	_projectile_generator.open_generator()


func _open_spine_effect_importer() -> void:
	if not is_instance_valid(_spine_effect_importer):
		_spine_effect_importer = SpineEffectImporter.new()
		EditorInterface.get_base_control().add_child(_spine_effect_importer)
	_spine_effect_importer.open_importer()


func _open_skill_sequence_editor() -> void:
	if not is_instance_valid(_skill_sequence_editor):
		_skill_sequence_editor = SkillSequenceEditor.new()
		EditorInterface.get_base_control().add_child(_skill_sequence_editor)
		_skill_sequence_editor.request_open_buff.connect(_open_buff_editor_with_buff)
	_skill_sequence_editor.open_editor()


func _open_level_editor() -> void:
	if not is_instance_valid(_level_editor):
		_level_editor = LevelEditor.new()
		EditorInterface.get_base_control().add_child(_level_editor)
	_level_editor.open_editor()


func _open_buff_editor() -> void:
	if not is_instance_valid(_buff_editor):
		_buff_editor = BuffEditor.new()
		EditorInterface.get_base_control().add_child(_buff_editor)
	_buff_editor.open_editor()


func _open_buff_editor_with_buff(buff_id: int) -> void:
	if not is_instance_valid(_buff_editor):
		_buff_editor = BuffEditor.new()
		EditorInterface.get_base_control().add_child(_buff_editor)
	_buff_editor.open_editor_with_buff(buff_id)


func _open_buff_icon_generator() -> void:
	if not is_instance_valid(_buff_icon_generator):
		_buff_icon_generator = BuffIconGenerator.new()
		EditorInterface.get_base_control().add_child(_buff_icon_generator)
	_buff_icon_generator.open_generator()


func _open_character_editor() -> void:
	if not is_instance_valid(_character_editor):
		_character_editor = CharacterEditor.new()
		EditorInterface.get_base_control().add_child(_character_editor)
	_character_editor.open_editor()


func _open_item_editor() -> void:
	if not is_instance_valid(_item_editor):
		_item_editor = ItemEditor.new()
		EditorInterface.get_base_control().add_child(_item_editor)
	_item_editor.open_editor()


# ---- PC 触屏调试开关 ----

const FORCE_TOUCH_SETTING := "application/run/force_touch_controls"

## 切换 application/run/force_touch_controls 并保存到 project.godot。
## 勾选后 PC 运行游戏也会显示触屏控件（配合 emulate_touch_from_mouse 可用鼠标模拟触摸）。
func _toggle_force_touch_controls() -> void:
	var current: bool = bool(ProjectSettings.get_setting(FORCE_TOUCH_SETTING, false))
	ProjectSettings.set_setting(FORCE_TOUCH_SETTING, not current)
	var err := ProjectSettings.save()
	if err != OK:
		push_error("[GameTools] 保存 project.godot 失败 (err=%d)" % err)
	_sync_force_touch_menu_check()
	print("[GameTools] PC 调试显示触屏控件: %s" % ("" if not current else "关闭（已恢复鼠标/键盘模式）"))

## 按 ProjectSettings 当前值同步菜单勾选状态。
func _sync_force_touch_menu_check() -> void:
	var idx := _submenu.get_item_index(16)
	if idx == -1:
		return
	var enabled: bool = bool(ProjectSettings.get_setting(FORCE_TOUCH_SETTING, false))
	_submenu.set_item_checked(idx, enabled)


# ---- UI 场景 Zip 导入 ----

func _open_ui_scene_zip_importer() -> void:
	if not is_instance_valid(_ui_zip_file_dialog):
		_ui_zip_file_dialog = EditorFileDialog.new()
		_ui_zip_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_ui_zip_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_ui_zip_file_dialog.add_filter("*.zip", "GameTool UI 场景包")
		_ui_zip_file_dialog.title = "选择 GameTool 导出的 UI 场景 Zip"
		_ui_zip_file_dialog.file_selected.connect(_on_ui_scene_zip_selected)
		EditorInterface.get_base_control().add_child(_ui_zip_file_dialog)
	_ui_zip_file_dialog.popup_centered(Vector2i(900, 600))


func _on_ui_scene_zip_selected(zip_path: String) -> void:
	var result: Dictionary = UiSceneZipImporter.import_zip(zip_path)
	var message := String(result.get("message", "未知错误"))
	if not bool(result.get("ok", false)):
		push_error("[GameTools] UI 场景 Zip 导入失败：%s" % message)
		_show_ui_zip_result("UI 场景导入失败", message)
		return

	EditorInterface.get_resource_filesystem().scan()
	print("[GameTools] UI 场景 Zip 导入完成：%s" % message.replace("\n", " "))
	_show_ui_zip_result("UI 场景导入完成", message)


func _show_ui_zip_result(title_text: String, message: String) -> void:
	if is_instance_valid(_ui_zip_result_dialog):
		_ui_zip_result_dialog.queue_free()
	_ui_zip_result_dialog = AcceptDialog.new()
	_ui_zip_result_dialog.title = title_text
	_ui_zip_result_dialog.dialog_text = message
	_ui_zip_result_dialog.min_size = Vector2i(560, 180)
	_ui_zip_result_dialog.confirmed.connect(_ui_zip_result_dialog.queue_free)
	_ui_zip_result_dialog.close_requested.connect(_ui_zip_result_dialog.queue_free)
	EditorInterface.get_base_control().add_child(_ui_zip_result_dialog)
	_ui_zip_result_dialog.popup_centered(Vector2i(560, 220))


# ---- 地图包导入 ----

func _open_map_zip_importer() -> void:
	if not is_instance_valid(_map_zip_file_dialog):
		_map_zip_file_dialog = EditorFileDialog.new()
		_map_zip_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_map_zip_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_map_zip_file_dialog.add_filter("*.zip", "GameTool 地图包")
		_map_zip_file_dialog.title = "选择 GameTool 地图拼接导出的 Zip"
		_map_zip_file_dialog.file_selected.connect(_on_map_zip_selected)
		EditorInterface.get_base_control().add_child(_map_zip_file_dialog)
	_map_zip_file_dialog.popup_centered(Vector2i(900, 600))


func _on_map_zip_selected(zip_path: String) -> void:
	var result: Dictionary = MapZipImporter.import_zip(zip_path)
	var message := String(result.get("message", "未知错误"))
	if not bool(result.get("ok", false)):
		push_error("[GameTools] 地图包导入失败：%s" % message)
		_show_map_zip_result("地图包导入失败", message)
		return

	EditorInterface.get_resource_filesystem().scan()
	# 注：GameRegistry.level_config 是 autoload 单例，仅在游戏运行时初始化。
	# 编辑器模式下不重载它，levels.json 已直接写盘，下次运行游戏会自动加载最新数据。
	print("[GameTools] 地图包导入完成：%s" % message.replace("\n", " "))
	_show_map_zip_result("地图包导入完成", message)


func _show_map_zip_result(title_text: String, message: String) -> void:
	if is_instance_valid(_map_zip_result_dialog):
		_map_zip_result_dialog.queue_free()
	_map_zip_result_dialog = AcceptDialog.new()
	_map_zip_result_dialog.title = title_text
	_map_zip_result_dialog.dialog_text = message
	_map_zip_result_dialog.min_size = Vector2i(560, 220)
	_map_zip_result_dialog.confirmed.connect(_map_zip_result_dialog.queue_free)
	_map_zip_result_dialog.close_requested.connect(_map_zip_result_dialog.queue_free)
	EditorInterface.get_base_control().add_child(_map_zip_result_dialog)
	_map_zip_result_dialog.popup_centered(Vector2i(560, 260))


# ---- Zip 导入（角色 / 怪物） ----

var _zip_file_dialog: EditorFileDialog
var _zip_group_dialog: Window
var _zip_pending_path: String = ""

## 弹出文件选择器选 zip；选中后弹 group 选择窗口（角色 / 怪物），再解压。
func _open_zip_importer() -> void:
	if not is_instance_valid(_zip_file_dialog):
		_zip_file_dialog = EditorFileDialog.new()
		_zip_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_zip_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_zip_file_dialog.add_filter("*.zip", "Godot 角色资源包")
		_zip_file_dialog.title = "选择外部 Zip 资源包"
		_zip_file_dialog.file_selected.connect(_on_zip_selected)
		EditorInterface.get_base_control().add_child(_zip_file_dialog)
	_zip_file_dialog.popup_centered(Vector2i(900, 600))


func _on_zip_selected(zip_path: String) -> void:
	# 先解析 zip 中的 manifest.json，提取 characterName 显示给用户
	var preview_name := _peek_zip_character_name(zip_path)
	# 自定义 Window：完整控制布局，避免 ConfirmationDialog 默认按钮挤压内容
	if is_instance_valid(_zip_group_dialog):
		_zip_group_dialog.queue_free()
	_zip_group_dialog = Window.new()
	_zip_group_dialog.title = "从 Zip 导入"
	_zip_pending_path = zip_path
	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 14)
	content.offset_left = 18
	content.offset_top = 14
	content.offset_right = -18
	content.offset_bottom = -14
	_zip_group_dialog.add_child(content)
	# 标题
	var title_label := Label.new()
	title_label.text = "检测到角色：%s" % (preview_name if not preview_name.is_empty() else "<未知>")
	title_label.add_theme_font_size_override("font_size", 16)
	content.add_child(title_label)
	# 副说明
	var desc_label := Label.new()
	desc_label.text = "选择导入目标："
	desc_label.add_theme_font_size_override("font_size", 13)
	content.add_child(desc_label)
	# 按钮区
	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	var char_btn := Button.new()
	char_btn.text = "角色 (characters)"
	char_btn.custom_minimum_size = Vector2(160, 40)
	char_btn.pressed.connect(_on_zip_group_chosen.bind("characters"))
	var enemy_btn := Button.new()
	enemy_btn.text = "怪物 (enemies)"
	enemy_btn.custom_minimum_size = Vector2(160, 40)
	enemy_btn.pressed.connect(_on_zip_group_chosen.bind("enemies"))
	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(80, 40)
	cancel_btn.pressed.connect(_on_zip_group_cancel)
	btn_box.add_child(char_btn)
	btn_box.add_child(enemy_btn)
	btn_box.add_child(cancel_btn)
	content.add_child(btn_box)
	# 路径显示
	var path_label := Label.new()
	path_label.text = "Zip: %s" % zip_path
	path_label.add_theme_font_size_override("font_size", 11)
	path_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	content.add_child(path_label)
	_zip_group_dialog.close_requested.connect(_on_zip_group_cancel)
	_zip_group_dialog.wrap_controls = true
	_zip_group_dialog.min_size = Vector2i(560, 180)
	EditorInterface.get_base_control().add_child(_zip_group_dialog)
	_zip_group_dialog.popup_centered(Vector2i(560, 180))


func _on_zip_group_chosen(group: String) -> void:
	var zip_path := _zip_pending_path
	if is_instance_valid(_zip_group_dialog):
		_zip_group_dialog.queue_free()
	_zip_pending_path = ""
	_on_zip_group_confirmed(zip_path, group)


func _on_zip_group_cancel() -> void:
	if is_instance_valid(_zip_group_dialog):
		_zip_group_dialog.queue_free()
	_zip_pending_path = ""


## 用户选好 group 后调用：解压 zip 到 res://assets/{group}/{characterName}/，再走原有导入流程
func _on_zip_group_confirmed(zip_path: String, group: String) -> void:
	if is_instance_valid(_zip_group_dialog):
		_zip_group_dialog.queue_free()
	var target_dir := _extract_zip_to_assets(zip_path, group)
	if target_dir.is_empty():
		return
	# 触发文件系统扫描，让 Godot 识别新文件并生成 .import 元数据
	EditorInterface.get_resource_filesystem().scan()
	# 异步等待扫描完成后再调用 _finalize_zip_import
	call_deferred("_finalize_zip_import", group, target_dir)


func _finalize_zip_import(group: String, target_dir: String) -> void:
	# 等待资源文件系统扫描完成（最多等 10 秒）
	# 第一次 scan 会触发 Godot 为 PNG 自动生成 .import 文件并 reimport
	var fs := EditorInterface.get_resource_filesystem()
	# 先等一帧让 scan 真正启动（scan 是异步的，刚调用完 is_scanning 可能仍返回 false）
	await get_tree().create_timer(0.2).timeout
	var waited := 0
	while fs.is_scanning() and waited < 100:
		await get_tree().create_timer(0.1).timeout
		waited += 1
	# 再扫一次确保 .import 文件也被识别（避免 reimport 时找不到源文件）
	EditorInterface.get_resource_filesystem().scan()
	await get_tree().create_timer(0.2).timeout
	waited = 0
	while fs.is_scanning() and waited < 100:
		await get_tree().create_timer(0.1).timeout
		waited += 1

	# 确保 atlas png 的 .import 文件已生成；未生成则显式 scan 该目录并等待
	var atlas_path := target_dir.path_join("godot/all_actions_atlas.png")
	var atlas_import_path := atlas_path + ".import"
	if FileAccess.file_exists(atlas_path) and not FileAccess.file_exists(atlas_import_path):
		# png 存在但 .import 还没生成，说明 scan 还没处理到这个文件
		var atlas_dir := atlas_path.get_base_dir()
		if fs.has_method("scan"):
			EditorInterface.get_resource_filesystem().scan()
		await get_tree().create_timer(0.5).timeout
		waited = 0
		while fs.is_scanning() and waited < 100:
			await get_tree().create_timer(0.1).timeout
			waited += 1

	var folder_name := target_dir.get_file()
	var resource_type := "enemy" if group == "enemies" else "character"
	# 只导入这一个角色/怪物，不调用全量 _do_import_enemies / _do_import_characters
	# 避免重写其他怪物的 spriteframes.tres 造成无谓的 git 改动
	var imported := _do_import_single_character(target_dir, folder_name, "", -1.0, resource_type)
	if imported:
		if group == "enemies":
			_sync_single_enemy_config(target_dir, folder_name)
		else:
			var imported_folders: Array[String] = [folder_name]
			_sync_character_configs("res://assets/characters", imported_folders)
		EditorInterface.get_resource_filesystem().scan()
		print("[GameTools] Zip 导入完成: %s → %s" % [folder_name, target_dir])
	else:
		push_error("[GameTools] Zip 导入失败：单角色导入步骤返回 false，请检查 %s 中的资源完整性" % target_dir)


## 只更新单个怪物的 enemies.json 配置（新增或同步技能），不重写其他怪物的资源文件
func _sync_single_enemy_config(target_dir: String, folder_name: String) -> void:
	var config_path := "res://data/enemies.json"
	var manifest_path := target_dir.path_join("manifest.json")
	var enemies_cfg: Dictionary = {}
	if FileAccess.file_exists(config_path):
		var cfg_file := FileAccess.open(config_path, FileAccess.READ)
		if cfg_file != null:
			var cfg_json := JSON.new()
			if cfg_json.parse(cfg_file.get_as_text()) == OK and cfg_json.data is Dictionary:
				enemies_cfg = cfg_json.data
	# 收集已有 asset 路径，找 max_id
	var existing_assets: Dictionary = {}
	var max_id := 8000
	for id_str in enemies_cfg:
		var eid := int(id_str)
		if eid > max_id:
			max_id = eid
		var asset: String = enemies_cfg[id_str].get("asset", "")
		if not asset.is_empty():
			existing_assets[asset] = eid
	# 解析 manifest
	var manifest_data: Dictionary = {}
	var enemy_name := folder_name
	if FileAccess.file_exists(manifest_path):
		var mj := JSON.new()
		if mj.parse(FileAccess.get_file_as_string(manifest_path)) == OK and mj.data is Dictionary:
			manifest_data = mj.data
			enemy_name = String(manifest_data.get("characterName", folder_name))
	var detected_skills := _get_enemy_skills_for_actions(manifest_data)
	var normal_skill := _default_enemy_normal_skill(folder_name, max_id + 1)
	var asset_key := "res://assets/enemies/%s" % folder_name
	var new_count := 0
	var synced_count := 0
	if asset_key not in existing_assets:
		max_id += 1
		var extra_skills := detected_skills.filter(func(skill_id): return int(skill_id) != normal_skill)
		enemies_cfg[str(max_id)] = {
			"name": enemy_name,
			"asset": asset_key,
			"character_config": asset_key.path_join("character_config.json"),
			"max_hp": 50,
			"attack": 2,
			"defense": 0,
			"move_speed": 80.0,
			"attack_range": 80.0,
			"detect_range": 300.0,
			"patrol_range": 120.0,
			"normal_skill": normal_skill,
			"skills": extra_skills,
			"skill_weights": _make_equal_skill_weights(extra_skills.size()),
			"drop_items": [],
			"exp": 10,
		}
		existing_assets[asset_key] = max_id
		new_count += 1
		print("[GameTools] 新增怪物配置: %s (ID: %d)" % [enemy_name, max_id])
	else:
		# 同步已有怪物的技能配置
		for config_id in enemies_cfg:
			var existing: Dictionary = enemies_cfg[config_id]
			if String(existing.get("asset", "")) != asset_key:
				continue
			if not existing.has("normal_skill"):
				existing["normal_skill"] = _default_enemy_normal_skill(folder_name, int(config_id))
				synced_count += 1
			var filtered := _filter_existing_enemy_skills(existing.get("skills", []), manifest_data)
			filtered.erase(int(existing.get("normal_skill", 0)))
			if filtered != existing.get("skills", []):
				existing["skills"] = filtered
				existing["skill_weights"] = _make_equal_skill_weights(filtered.size())
				enemies_cfg[config_id] = existing
				synced_count += 1
				print("[GameTools] 同步怪物技能: %s -> %s" % [config_id, filtered])
	# 写回配置表
	if new_count > 0 or synced_count > 0:
		var sorted_keys: Array = enemies_cfg.keys()
		sorted_keys.sort()
		var sorted_cfg: Dictionary = {}
		for key in sorted_keys:
			sorted_cfg[key] = enemies_cfg[key]
		_write_file(config_path, JSON.stringify(sorted_cfg, "\t") + "\n")
		print("[GameTools] enemies.json 已更新：新增 %d，同步 %d" % [new_count, synced_count])


## 读取 zip 中的 manifest.json，返回 characterName；失败返回空字符串
func _peek_zip_character_name(zip_path: String) -> String:
	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		return ""
	var files := reader.get_files()
	var manifest_path := ""
	for f in files:
		if f.get_file() == "manifest.json":
			manifest_path = f
			break
	if manifest_path.is_empty():
		reader.close()
		return ""
	var bytes := reader.read_file(manifest_path)
	reader.close()
	var text := bytes.get_string_from_utf8().trim_prefix("\uFEFF")
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return ""
	return String(json.data.get("characterName", ""))


## 把 zip 解压到 res://assets/{group}/{characterName}/，返回目标 res:// 路径；失败返回空
func _extract_zip_to_assets(zip_path: String, group: String) -> String:
	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		push_error("无法打开 zip: %s (err=%d)" % [zip_path, err])
		return ""
	var files := reader.get_files()
	if files.is_empty():
		push_error("zip 内无文件: %s" % zip_path)
		reader.close()
		return ""
	# 找 manifest.json 解析 characterName
	var character_name := ""
	var manifest_path := ""
	for f in files:
		if f.get_file() == "manifest.json":
			manifest_path = f
			break
	if not manifest_path.is_empty():
		var md_bytes := reader.read_file(manifest_path)
		var md_text := md_bytes.get_string_from_utf8().trim_prefix("\uFEFF")
		var json := JSON.new()
		if json.parse(md_text) == OK and json.data is Dictionary:
			character_name = String(json.data.get("characterName", ""))
	if character_name.is_empty():
		push_error("zip 中未找到 characterName")
		reader.close()
		return ""
	# 目标目录
	var target_res := "res://assets/%s/%s" % [group, character_name]
	var target_abs := ProjectSettings.globalize_path(target_res)
	# 创建目标目录
	var dir := DirAccess.open("res://assets")
	if dir == null:
		push_error("无法打开 res://assets")
		reader.close()
		return ""
	dir.make_dir_recursive("%s/%s" % [group, character_name])
	# 解压所有文件：路径分隔符统一为 /，去掉前导 /
	var written := 0
	for f in files:
		if f.ends_with("/"):
			continue
		var normalized := f.replace("\\", "/").trim_prefix("/")
		var out_path := "%s/%s" % [target_abs.replace("\\", "/"), normalized]
		# 确保父目录存在
		var parent_abs := out_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(parent_abs)
		var out_file := FileAccess.open(out_path, FileAccess.WRITE)
		if out_file == null:
			push_warning("无法写入: %s" % out_path)
			continue
		var data := reader.read_file(f)
		out_file.store_buffer(data)
		out_file.close()
		written += 1
	reader.close()
	print("[GameTools] 已解压 %d 个文件到 %s" % [written, target_res])
	return target_res


# ---- 场景导入 ----

func _do_import_worlds() -> void:
	var world_dir := "res://world/stitched"
	var dir := DirAccess.open(world_dir)
	if dir == null:
		push_error("无法打开目录: %s" % world_dir)
		return

	dir.list_dir_begin()
	var count := 0
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			if _do_import_single_world(world_dir, folder):
				count += 1
		folder = dir.get_next()
	dir.list_dir_end()

	print("[GameTools] 场景导入完成: %d 个场景" % count)
	EditorInterface.get_resource_filesystem().scan()


func _do_import_single_world(base_dir: String, folder_name: String) -> bool:
	var source_dir := base_dir.path_join(folder_name)
	var raw_scene_path := source_dir.path_join("map_stitch_godot.tscn")
	var raw_json_path := source_dir.path_join("map_stitch_godot.json")

	if not FileAccess.file_exists(raw_scene_path):
		push_warning("跳过 %s: 缺少 map_stitch_godot.tscn" % folder_name)
		return false
	if not FileAccess.file_exists(raw_json_path):
		push_warning("跳过 %s: 缺少 map_stitch_godot.json" % folder_name)
		return false

	var raw_scene := load(raw_scene_path) as PackedScene
	if raw_scene == null:
		push_error("加载场景失败: %s" % raw_scene_path)
		return false

	var json_text := FileAccess.get_file_as_string(raw_json_path)
	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_error("解析 JSON 失败: %s" % raw_json_path)
		return false

	var root := Node2D.new()
	root.name = _to_pascal(folder_name)

	var map_instance := raw_scene.instantiate()
	map_instance.name = "Map"
	root.add_child(map_instance)
	map_instance.owner = root

	var spawn := Marker2D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = _calc_default_spawn(json.data)
	root.add_child(spawn)
	spawn.owner = root

	var spawn_pos: Vector2 = spawn.position

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("打包场景失败: %s" % folder_name)
		root.free()
		return false

	var output_path := "res://scenes/%s.tscn" % folder_name
	var err := ResourceSaver.save(packed, output_path)
	root.free()

	if err != OK:
		push_error("保存场景失败: %s" % output_path)
		return false

	print("[GameTools] 已导入: %s → %s (spawn: %s)" % [folder_name, output_path, spawn_pos])
	return true


func _calc_default_spawn(data: Variant) -> Vector2:
	if typeof(data) != TYPE_DICTIONARY:
		return Vector2(160, 350)
	var canvas: Dictionary = data.get("canvas", {})
	var width: float = float(canvas.get("width", 1376))
	var height: float = float(canvas.get("height", 768))
	var spawn_x := clampf(width * 0.12, 96.0, maxf(96.0, width - 96.0))
	var spawn_y := clampf(height * 0.46, 96.0, maxf(96.0, height - 96.0))
	return Vector2(spawn_x, spawn_y)


# ---- 角色导入 ----

func _do_import_characters() -> void:
	var char_dir := "res://assets/characters"
	var dir := DirAccess.open(char_dir)
	if dir == null:
		push_error("无法打开目录: %s" % char_dir)
		return

	dir.list_dir_begin()
	var folders: Array[String] = []
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var char_path := char_dir.path_join(folder)
			var manifest_path := char_path.path_join("manifest.json")
			if FileAccess.file_exists(manifest_path):
				folders.append(folder)
		folder = dir.get_next()
	dir.list_dir_end()
	folders.sort()
	if folders.is_empty():
		push_warning("没有找到可导入的角色目录")
		return

	var count := 0
	var imported_folders: Array[String] = []
	for candidate in folders:
		if _do_import_single_character(char_dir.path_join(candidate), candidate, "", -1.0, "character"):
			count += 1
			imported_folders.append(candidate)
	if not imported_folders.is_empty():
		_sync_character_configs(char_dir, imported_folders)

	print("[GameTools] 角色导入完成: %d 个角色预制体；上阵角色由 PartyManager 配置" % count)
	EditorInterface.get_resource_filesystem().scan()


func _do_import_enemies() -> void:
	var enemy_dir := "res://assets/enemies"
	var config_path := "res://data/enemies.json"
	var dir := DirAccess.open(enemy_dir)
	if dir == null:
		push_warning("怪物目录不存在: %s" % enemy_dir)
		return

	# 加载已有怪物配置
	var enemies_cfg: Dictionary = {}
	if FileAccess.file_exists(config_path):
		var cfg_file := FileAccess.open(config_path, FileAccess.READ)
		if cfg_file != null:
			var cfg_json := JSON.new()
			if cfg_json.parse(cfg_file.get_as_text()) == OK and cfg_json.data is Dictionary:
				enemies_cfg = cfg_json.data

	# 收集已有的 asset 路径，避免重复
	var existing_assets: Dictionary = {}
	var max_id := 8000
	for id_str in enemies_cfg:
		var eid := int(id_str)
		if eid > max_id:
			max_id = eid
		var asset: String = enemies_cfg[id_str].get("asset", "")
		if not asset.is_empty():
			existing_assets[asset] = eid

	dir.list_dir_begin()
	var imported_count := 0
	var new_count := 0
	var synced_count := 0
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var char_path := enemy_dir.path_join(folder)
			var manifest_path := char_path.path_join("manifest.json")
			if FileAccess.file_exists(manifest_path):
				if _do_import_single_character(char_path, folder, "", -1.0, "enemy"):
					imported_count += 1
					var manifest_text := FileAccess.get_file_as_string(manifest_path)
					var mj := JSON.new()
					var manifest_data: Dictionary = {}
					var enemy_name := folder
					if mj.parse(manifest_text) == OK and mj.data is Dictionary:
						manifest_data = mj.data
						enemy_name = manifest_data.get("characterName", folder)
					var detected_skills := _get_enemy_skills_for_actions(manifest_data)
					var normal_skill := _default_enemy_normal_skill(folder, max_id + 1)
					# 检查是否需要写入怪物配置表
					var asset_key := "res://assets/enemies/%s" % folder
					if asset_key not in existing_assets:
						max_id += 1
						var extra_skills := detected_skills.filter(func(skill_id): return int(skill_id) != normal_skill)
						enemies_cfg[str(max_id)] = {
							"name": enemy_name,
							"asset": asset_key,
							"character_config": asset_key.path_join("character_config.json"),
							"max_hp": 50,
							"attack": 2,
							"defense": 0,
							"move_speed": 80.0,
							"attack_range": 80.0,
							"detect_range": 300.0,
							"patrol_range": 120.0,
							"normal_skill": normal_skill,
							"skills": extra_skills,
							"skill_weights": _make_equal_skill_weights(extra_skills.size()),
							"drop_items": [],
							"exp": 10,
						}
						existing_assets[asset_key] = max_id
						new_count += 1
						print("[GameTools] 新增怪物配置: %s (ID: %d)" % [enemy_name, max_id])
					else:
						# Preserve curated choices for existing enemies, but remove skills whose
						# animation is no longer present in this enemy asset.
						for config_id in enemies_cfg:
							var existing: Dictionary = enemies_cfg[config_id]
							if String(existing.get("asset", "")) != asset_key:
								continue
							if not existing.has("normal_skill"):
								existing["normal_skill"] = _default_enemy_normal_skill(folder, int(config_id))
								synced_count += 1
							var filtered := _filter_existing_enemy_skills(existing.get("skills", []), manifest_data)
							filtered.erase(int(existing.get("normal_skill", 0)))
							if filtered != existing.get("skills", []):
								existing["skills"] = filtered
								existing["skill_weights"] = _make_equal_skill_weights(filtered.size())
								enemies_cfg[config_id] = existing
								synced_count += 1
								print("[GameTools] 同步怪物技能: %s -> %s" % [config_id, filtered])
		folder = dir.get_next()
	dir.list_dir_end()

	# 写回怪物配置表
	if new_count > 0 or synced_count > 0:
		var sorted_keys: Array = enemies_cfg.keys()
		sorted_keys.sort()
		var sorted_cfg: Dictionary = {}
		for key in sorted_keys:
			sorted_cfg[key] = enemies_cfg[key]
		_write_file(config_path, JSON.stringify(sorted_cfg, "\t") + "\n")
		print("[GameTools] enemies.json 已更新：新增 %d，同步 %d" % [new_count, synced_count])

	print("[GameTools] 怪物导入完成: %d 个怪物" % imported_count)
	EditorInterface.get_resource_filesystem().scan()


func _do_import_single_character(source_dir: String, folder_name: String, player_scene: String, display_scale_override: float = -1.0, resource_type: String = "character") -> bool:
	var actions_path := source_dir.path_join("godot/character_actions.tscn")
	var sf_path := source_dir.path_join("godot/spriteframes.tres")
	var atlas_path := source_dir.path_join("godot/all_actions_atlas.png")
	var manifest_path := source_dir.path_join("manifest.json")
	var config_path := source_dir.path_join("character_config.json")

	if not FileAccess.file_exists(manifest_path):
		push_warning("跳过 %s: 缺少 manifest.json" % folder_name)
		return false
	if not FileAccess.file_exists(actions_path):
		push_warning("跳过 %s: 缺少 character_actions.tscn" % folder_name)
		return false
	if not FileAccess.file_exists(sf_path):
		push_warning("跳过 %s: 缺少 spriteframes.tres" % folder_name)
		return false
	if not FileAccess.file_exists(atlas_path):
		push_warning("跳过 %s: 缺少 all_actions_atlas.png" % folder_name)
		return false

	var manifest_text := FileAccess.get_file_as_string(manifest_path)
	var json := JSON.new()
	if json.parse(manifest_text) != OK:
		push_error("解析 manifest 失败: %s" % manifest_path)
		return false

	var md: Dictionary = json.data
	var ub: Dictionary = md.get("unifiedBox", {})
	var target_height := 52.0
	var display_scale: float = display_scale_override if display_scale_override > 0.0 else 1.0
	var cell_h := _get_frame_cell_height(md)
	var external_combat := _load_external_combat_data(source_dir)
	var is_production := not external_combat.is_empty()
	var foot_center := _get_foot_center(external_combat, md)
	var body_box := _get_body_box(external_combat, md)
	var uses_foot_origin := not body_box.is_empty()
	var default_body_bottom := 20.5 if resource_type == "character" else 19.0
	var body_bottom := _get_scene_body_bottom(player_scene, default_body_bottom)
	var image_center := Vector2(
		float(md.get("frameSize", {}).get("width", cell_h)) * 0.5,
		float(md.get("frameSize", {}).get("height", cell_h)) * 0.5
	)
	var foot_from_center := foot_center - image_center
	var display_offset: Vector2
	var body_position := Vector2.ZERO
	var body_size := Vector2(24.0, 41.0) if resource_type == "character" else Vector2(24.0, 38.0)
	if uses_foot_origin:
		# 新格式：角色根节点就是 JSON 脚底中心。Shape 节点 scale 永远为 1，
		# bodyBox 的中心和尺寸直接换算成角色本地像素。
		display_offset = -foot_from_center * display_scale
		body_position = Vector2(
			float(body_box.get("forwardDistance", 0.0)),
			float(body_box.get("yOffset", 0.0))
		) * display_scale
		body_size = Vector2(
			maxf(1.0, float(body_box.get("width", body_size.x)) * display_scale),
			maxf(1.0, float(body_box.get("height", body_size.y)) * display_scale)
		)
		# Source bodyBox may extend below the foot center (yOffset + height/2 > 0).
		# Shift the collision body AND visual sprite up together so the body bottom
		# sits exactly at the foot origin while keeping the sprite aligned with it.
		body_bottom = body_position.y + body_size.y * 0.5
		if body_bottom > 0.0:
			var shift := body_bottom
			body_position.y -= shift
			display_offset.y -= shift
			body_bottom = 0.0
	else:
		# 旧格式保持身体中心坐标，避免旧角色/怪物的攻击框整体迁移。
		display_offset = Vector2(
			-foot_from_center.x * display_scale,
			body_bottom - foot_from_center.y * display_scale
		)

	# 修正 spriteframes.tres
	var sf_text := FileAccess.get_file_as_string(sf_path)
	sf_text = _ensure_spriteframes_atlas(sf_text, atlas_path)
	sf_text = _ensure_spriteframes_animation_loops(sf_text)
	_write_file(sf_path, sf_text)

	# 修正 character_actions.tscn
	var act_text := FileAccess.get_file_as_string(actions_path)
	act_text = _replace_path_in_text(act_text, "SpriteFrames", "spriteframes.tres", sf_path)
	act_text = _ensure_centered(act_text)
	_write_file(actions_path, act_text)

	# 写配置
	var config := {
		"resource_type": resource_type,
		"character_name": md.get("characterName", folder_name),
		"scene_name": folder_name,
		"default_animation": md.get("defaultAnimation", "idle"),
		"actions_scene": actions_path,
		"spriteframes": sf_path,
		"combat_actions": source_dir.path_join("combat_actions.json"),
		"atlas": atlas_path,
		"display_scale": display_scale,
		"display_offset": {"x": display_offset.x, "y": display_offset.y},
		"centered": true,
		"target_display_height": target_height,
		"available_actions": md.get("exportOrder", []),
		"unified_box": ub,
		"frame_cell_height": cell_h,
		"production_format": is_production,
		"foot_center": {"x": foot_center.x, "y": foot_center.y},
		"anchor_mode": "foot_origin" if uses_foot_origin else "legacy_body_center",
		"alignment": "json_foot_origin" if uses_foot_origin else "json_foot_center_to_collision_bottom",
		"collision_bottom": body_bottom,
		"body_box": body_box,
		"body_position": {"x": body_position.x, "y": body_position.y},
		"body_size": {"x": body_size.x, "y": body_size.y},
		"combat_source": source_dir.path_join("combat/attack_frames.json") if is_production else "",
	}
	_write_file(config_path, JSON.stringify(config, "\t") + "\n")

	# 兼容旧的命令式调用；编辑器批量导入不再覆盖 player.tscn。
	if FileAccess.file_exists(player_scene):
		var pl_text := FileAccess.get_file_as_string(player_scene)
		pl_text = _replace_path_in_text(pl_text, "PackedScene", "character_actions.tscn", actions_path)
		pl_text = _replace_char_transform(pl_text, display_scale, display_offset)
		_write_file(player_scene, pl_text)

	# 外部制作工具的数据是生产源，每次导入都刷新；旧格式仍保留人工配置。
	if is_production:
		_write_external_combat_actions(source_dir, external_combat, display_scale, 0.0 if uses_foot_origin else body_bottom)
	else:
		_ensure_combat_actions_config(source_dir, md, display_scale)
	# 生成模板场景（怪物/新角色）
	if player_scene.is_empty():
		var prefab_path := source_dir.path_join("godot/%s.tscn" % folder_name)
		if resource_type == "character":
			_generate_playable_character_scene(prefab_path, actions_path, config)
		else:
			_generate_template_scene(prefab_path, actions_path, config)
		var legacy_scene_path := source_dir.path_join("godot/character_template.tscn")
		if FileAccess.file_exists(legacy_scene_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_scene_path))

	print("[GameTools] 已导入%s: %s → godot/%s.tscn (scale: %s, offset: %s, production: %s)" % ["怪物" if resource_type == "enemy" else "角色", folder_name, folder_name, display_scale, display_offset, is_production])
	return true


func _get_manifest_action_names(manifest: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for action_name in manifest.get("exportOrder", []):
		result[String(action_name)] = true
	for action_value in manifest.get("actions", []):
		if action_value is Dictionary:
			result[String(action_value.get("actionName", ""))] = true
	return result


func _get_enemy_skills_for_actions(manifest: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var action_names := _get_manifest_action_names(manifest)
	var skills_path := "res://data/skills.json"
	if not FileAccess.file_exists(skills_path):
		return result
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(skills_path)) != OK or not json.data is Dictionary:
		return result
	for id_value in json.data:
		var skill_id := int(id_value)
		if skill_id < 5000:
			continue
		var skill: Dictionary = json.data[id_value]
		if action_names.has(String(skill.get("animation", ""))):
			result.append(skill_id)
	result.sort()
	return result


func _filter_existing_enemy_skills(existing_skills: Array, manifest: Dictionary) -> Array[int]:
	var available := _get_enemy_skills_for_actions(manifest)
	var result: Array[int] = []
	for skill_value in existing_skills:
		var skill_id := int(skill_value)
		if available.has(skill_id):
			result.append(skill_id)
	return result


func _make_equal_skill_weights(count: int) -> Array[int]:
	var result: Array[int] = []
	for _index in range(count):
		result.append(100)
	return result


func _sync_character_configs(base_dir: String, folders: Array[String]) -> void:
	var config_path := "res://data/characters.json"
	var characters_cfg: Dictionary = {}
	if FileAccess.file_exists(config_path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(config_path)) == OK and json.data is Dictionary:
			characters_cfg = json.data

	var existing_assets: Dictionary = {}
	var max_id := 7000
	for id_str in characters_cfg:
		var cid := int(id_str)
		max_id = maxi(max_id, cid)
		var asset := String(characters_cfg[id_str].get("asset", ""))
		if not asset.is_empty():
			existing_assets[asset] = str(id_str)

	var changed := false
	for folder in folders:
		var asset_key := "res://assets/characters/%s" % folder
		var manifest_path := base_dir.path_join(folder).path_join("manifest.json")
		var character_name := folder
		if FileAccess.file_exists(manifest_path):
			var manifest_json := JSON.new()
			if manifest_json.parse(FileAccess.get_file_as_string(manifest_path)) == OK and manifest_json.data is Dictionary:
				character_name = String(manifest_json.data.get("characterName", folder))

		var id_str := String(existing_assets.get(asset_key, ""))
		if id_str.is_empty():
			max_id += 1
			id_str = str(max_id)
			characters_cfg[id_str] = _make_default_character_config(folder, character_name, asset_key, int(id_str))
			existing_assets[asset_key] = id_str
			changed = true
			print("[GameTools] 新增角色配置: %s (ID: %s)" % [folder, id_str])
		else:
			var entry: Dictionary = characters_cfg[id_str]
			var before := JSON.stringify(entry)
			entry["name"] = entry.get("name", character_name)
			entry["scene"] = asset_key.path_join("godot/%s.tscn" % folder)
			entry["asset"] = asset_key
			entry["character_config"] = asset_key.path_join("character_config.json")
			entry["actor_scale"] = float(entry.get("actor_scale", 1.0))
			entry["base_stats"] = entry.get("base_stats", _default_character_base_stats())
			entry["growth"] = entry.get("growth", _default_character_growth())
			entry["max_level"] = int(entry.get("max_level", 60))
			entry["normal_skill"] = int(entry.get("normal_skill", _default_character_normal_skill(folder, int(id_str))))
			entry["skill_unlocks"] = entry.get("skill_unlocks", _default_character_skill_unlocks(folder, int(id_str)))
			entry["skills"] = entry.get("skills", _default_character_skill_list(folder, int(id_str)))
			characters_cfg[id_str] = entry
			if before != JSON.stringify(entry):
				changed = true

	if not changed:
		return
	var sorted_keys: Array = characters_cfg.keys()
	sorted_keys.sort()
	var sorted_cfg: Dictionary = {}
	for key in sorted_keys:
		sorted_cfg[key] = characters_cfg[key]
	_write_file(config_path, JSON.stringify(sorted_cfg, "\t") + "\n")
	print("[GameTools] characters.json 已同步")


func _make_default_character_config(folder: String, character_name: String, asset_key: String, character_id: int) -> Dictionary:
	return {
		"name": character_name,
		"scene": asset_key.path_join("godot/%s.tscn" % folder),
		"asset": asset_key,
		"character_config": asset_key.path_join("character_config.json"),
		"actor_scale": 1.0,
		"base_stats": _default_character_base_stats(),
		"growth": _default_character_growth(),
		"max_level": 60,
		"normal_skill": _default_character_normal_skill(folder, character_id),
		"skill_unlocks": _default_character_skill_unlocks(folder, character_id),
		"skills": _default_character_skill_list(folder, character_id),
		"description": "",
	}


func _default_character_normal_skill(_folder: String, character_id: int) -> int:
	var base_id := character_id if character_id > 0 else 7001
	return 6001 + maxi(0, base_id - 7001) * 10


func _default_character_skill_unlocks(folder: String, character_id: int) -> Dictionary:
	var normal := _default_character_normal_skill(folder, character_id)
	return {
		"skill1": {"skill_id": normal + 1, "unlock_level": 1},
		"skill2": {"skill_id": normal + 2, "unlock_level": 1},
		"skill3": {"skill_id": normal + 3, "unlock_level": 1},
	}


func _default_character_skill_list(folder: String, character_id: int) -> Array[int]:
	var normal := _default_character_normal_skill(folder, character_id)
	return [normal, normal + 1, normal + 2, normal + 3]


func _default_enemy_normal_skill(_folder: String, enemy_id: int) -> int:
	var base_id := enemy_id if enemy_id > 0 else 8001
	return 50001 + maxi(0, base_id - 8001) * 10


func _default_character_base_stats() -> Dictionary:
	return {
		"max_hp": 200,
		"attack": 1,
		"defense": 0,
		"move_speed": 220.0,
		"crit_rate": 0.0,
		"crit_damage": 1.5,
		"attack_speed": 1.0,
	}


func _default_character_growth() -> Dictionary:
	return {
		"max_hp": 15,
		"attack": 1,
		"defense": 0,
		"move_speed": 0.0,
	}


func _load_external_combat_data(source_dir: String) -> Dictionary:
	var path := source_dir.path_join("combat/attack_frames.json")
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("解析外部攻击帧失败: %s" % path)
		return {}
	return json.data


func _get_foot_center(combat_data: Dictionary, manifest: Dictionary) -> Vector2:
	for action in combat_data.get("actions", []):
		if action is Dictionary and action.get("foot_center", {}) is Dictionary:
			var foot: Dictionary = action.get("foot_center", {})
			return Vector2(float(foot.get("x", 0.0)), float(foot.get("y", 0.0)))
	for action in manifest.get("actions", []):
		if action is Dictionary:
			var runtime: Dictionary = action.get("runtimeAction", {})
			var foot: Dictionary = runtime.get("foot_center", {})
			if not foot.is_empty():
				return Vector2(float(foot.get("x", 0.0)), float(foot.get("y", 0.0)))
	var frame: Dictionary = manifest.get("frameSize", {})
	return Vector2(float(frame.get("width", 0.0)) * 0.5, float(frame.get("height", 0.0)) * 0.5)


func _get_body_box(combat_data: Dictionary, manifest: Dictionary) -> Dictionary:
	var body_box = combat_data.get("bodyBox", {})
	if body_box is Dictionary and not body_box.is_empty():
		return body_box.duplicate(true)
	body_box = manifest.get("bodyBox", {})
	if body_box is Dictionary and not body_box.is_empty():
		return body_box.duplicate(true)
	return {}


func _get_scene_body_bottom(scene_path: String, fallback: float) -> float:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return fallback
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return fallback
	var instance := packed.instantiate()
	var collision := instance.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var result := fallback
	if collision != null and collision.shape is RectangleShape2D:
		result = collision.position.y + (collision.shape as RectangleShape2D).size.y * 0.5
	instance.free()
	return result


func _write_external_combat_actions(source_dir: String, source: Dictionary, display_scale: float, foot_origin_y: float) -> void:
	var actions_data: Dictionary = {}
	var frame_index_base := int(source.get("frameIndexBase", 1))
	var action_values: Array = source.get("actions", [])
	if action_values.is_empty() and source.has("actionName"):
		action_values = [source]
	for action_value in action_values:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		var action_name := String(action.get("actionName", ""))
		if action_name.is_empty():
			continue
		actions_data[action_name] = _convert_external_combat_action(action, display_scale, foot_origin_y, frame_index_base)
	var data := {
		"version": 3,
		"source": "combat/attack_frames.json",
		"source_schema_version": int(source.get("schemaVersion", 2)),
		"coordinate_space": "actor_root_pixels",
		"sprite_scale": display_scale,
		"actions": actions_data,
	}
	_write_file(source_dir.path_join("combat_actions.json"), JSON.stringify(data, "\t") + "\n")


func _convert_external_combat_action(action: Dictionary, display_scale: float, foot_origin_y: float, frame_index_base: int) -> Dictionary:
	var windows: Array = []
	for attack_value in action.get("attacks", []):
		if not attack_value is Dictionary:
			continue
		var attack: Dictionary = attack_value
		var start_frame := _external_frame_to_godot(int(attack.get("startFrame", 1)), frame_index_base)
		var end_frame := maxi(start_frame, _external_frame_to_godot(int(attack.get("endFrame", start_frame + frame_index_base)), frame_index_base))
		for region_value in attack.get("regions", []):
			if not region_value is Dictionary:
				continue
			var region: Dictionary = region_value
			var region_scale := float(region.get("scale", 1.0))
			var authored_x := float(region.get("forwardDistance", 0.0)) * display_scale
			windows.append({
				"id": "%s:%s" % [String(attack.get("id", "")), String(region.get("id", ""))],
				"start_frame": start_frame,
				"end_frame": end_frame,
				"forward": absf(authored_x),
				"authored_x": authored_x,
				"y": foot_origin_y + float(region.get("yOffset", 0.0)) * display_scale,
				"width": maxf(1.0, float(region.get("width", 1.0)) * display_scale * region_scale),
				"height": maxf(1.0, float(region.get("height", 1.0)) * display_scale * region_scale),
				"source_attack_id": String(attack.get("id", "")),
				"source_region_id": String(region.get("id", "")),
			})
	windows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("start_frame", 0)) < int(right.get("start_frame", 0))
	)
	var events := _convert_external_events(action.get("events", []), frame_index_base)
	if events.is_empty() and not windows.is_empty():
		events.append({
			"id": "compat-release",
			"name": "release",
			"frame": int((windows[0] as Dictionary).get("start_frame", 0)),
			"fallback": true,
		})
	return {
		"hit_windows": windows,
		"events": events,
		"cancel_windows": _convert_external_windows(action.get("cancelWindows", []), frame_index_base),
		"armor_windows": _convert_external_windows(action.get("armorWindows", []), frame_index_base),
		"movement_windows": _convert_external_movement_windows(action.get("movementWindows", []), display_scale, frame_index_base),
		"sockets": _convert_external_sockets(action.get("sockets", {}), display_scale, foot_origin_y, frame_index_base),
	}


func _external_frame_to_godot(frame: int, frame_index_base: int) -> int:
	return maxi(0, frame - frame_index_base)


func _convert_external_events(raw_events: Variant, frame_index_base: int) -> Array:
	var events: Array = []
	if not raw_events is Array:
		return events
	for value in raw_events:
		if not value is Dictionary:
			continue
		var event: Dictionary = value
		events.append({
			"id": String(event.get("id", "")),
			"name": String(event.get("name", "")),
			"frame": _external_frame_to_godot(int(event.get("frame", 1)), frame_index_base),
		})
	return events


func _convert_external_windows(raw_windows: Variant, frame_index_base: int) -> Array:
	var windows: Array = []
	if not raw_windows is Array:
		return windows
	for value in raw_windows:
		if not value is Dictionary:
			continue
		var window: Dictionary = value
		var start_frame := _external_frame_to_godot(int(window.get("startFrame", 1)), frame_index_base)
		var end_frame := maxi(start_frame, _external_frame_to_godot(int(window.get("endFrame", start_frame + frame_index_base)), frame_index_base))
		windows.append({"id": String(window.get("id", "")), "start_frame": start_frame, "end_frame": end_frame})
	return windows


func _convert_external_movement_windows(raw_windows: Variant, display_scale: float, frame_index_base: int) -> Array:
	var windows: Array = _convert_external_windows(raw_windows, frame_index_base)
	if not raw_windows is Array:
		return windows
	for index in range(mini(windows.size(), (raw_windows as Array).size())):
		var source_window = (raw_windows as Array)[index]
		if source_window is Dictionary:
			(windows[index] as Dictionary)["delta_x"] = float((source_window as Dictionary).get("deltaX", 0.0)) * display_scale
	return windows


func _convert_external_sockets(raw_sockets: Variant, display_scale: float, foot_origin_y: float, frame_index_base: int) -> Dictionary:
	var sockets: Dictionary = {}
	if not raw_sockets is Dictionary:
		return sockets
	for socket_name in (raw_sockets as Dictionary).keys():
		var frames_value = (raw_sockets as Dictionary).get(socket_name, [])
		if not frames_value is Array:
			continue
		var frames: Array = []
		for value in frames_value:
			if not value is Dictionary:
				continue
			var socket: Dictionary = value
			frames.append({
				"frame": _external_frame_to_godot(int(socket.get("frame", 1)), frame_index_base),
				"x": float(socket.get("x", 0.0)) * display_scale,
				"y": foot_origin_y + float(socket.get("y", 0.0)) * display_scale,
			})
		sockets[String(socket_name)] = frames
	return sockets


func _ensure_combat_actions_config(source_dir: String, manifest: Dictionary, display_scale: float) -> void:
	var output_path := source_dir.path_join("combat_actions.json")
	if FileAccess.file_exists(output_path):
		return
	var hit_frame := 0
	var has_attack := false
	for action in manifest.get("actions", []):
		if action is Dictionary and String(action.get("actionName", "")) == "attack":
			has_attack = true
			hit_frame = maxi(0, int(action.get("frameCount", 1)) / 2)
			break
	var actions_data: Dictionary = {}
	if has_attack:
		actions_data["attack"] = {
			"hit_windows": [{
				"start_frame": hit_frame,
				"end_frame": hit_frame,
				"forward": 30.0,
				"y": 0.0,
				"width": 20.0,
				"height": 20.0,
			}]
		}
	var data := {
		"version": 1,
		"sprite_scale": display_scale,
		"actions": actions_data,
	}
	_write_file(output_path, JSON.stringify(data, "\t") + "\n")


# ---- Excel 转换 ----

func _do_convert_excel() -> void:
	var excel_dir := "res://data/excel"
	var dir := DirAccess.open(excel_dir)
	if dir == null:
		push_error("无法打开 Excel 目录: %s" % excel_dir)
		return

	var python := _find_python()
	if python.is_empty():
		push_warning("找不到 Python，跳过 Excel 转换")
		return

	dir.list_dir_begin()
	var count := 0
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".xlsx") and not file.begins_with("~$"):
			var excel_path := excel_dir.path_join(file)
			var output_name := file.get_basename()
			var script_path := ProjectSettings.globalize_path("res://tools/excel_to_json.py")
			var output := []
			OS.execute(python, [script_path, output_name], output, true, false)
			print("[GameTools] 已转换: %s" % file)
			count += 1
		file = dir.get_next()
	dir.list_dir_end()

	print("[GameTools] Excel 转换完成: %d 个文件" % count)
	EditorInterface.get_resource_filesystem().scan()


func _find_python() -> String:
	var output := []
	if OS.execute("python", ["--version"], output, true, false) == OK:
		return "python"
	output = []
	if OS.execute("py", ["--version"], output, true, false) == OK:
		return "py"
	return ""


# ---- 工具函数 ----

func _ensure_spriteframes_atlas(text: String, atlas_path: String) -> String:
	var lines := text.split("\n")
	var texture_line := '[ext_resource type="Texture2D" path="%s" id="sheet"]' % atlas_path
	var texture_index := -1
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.contains("[ext_resource") and line.contains('type="Texture2D"') and line.contains("all_actions_atlas.png"):
			texture_index = i
			lines[i] = texture_line
			break
	if texture_index == -1:
		# gd_resource 头之后补入纹理声明；不要依赖外部导出文件一定完整。
		lines.insert(1, "")
		lines.insert(2, texture_line)

	var i := 0
	while i < lines.size():
		if lines[i].begins_with('[sub_resource type="AtlasTexture"'):
			var next_index := i + 1
			if next_index >= lines.size() or not lines[next_index].begins_with("atlas = ExtResource("):
				lines.insert(next_index, 'atlas = ExtResource("sheet")')
				i += 1
		i += 1
	return "\n".join(lines)


func _ensure_spriteframes_animation_loops(text: String) -> String:
	var regex := RegEx.new()
	var error := regex.compile('"loop"\\s*:\\s*(true|false|0|1),\\s*"name"\\s*:\\s*&"([^"]+)"')
	if error != OK:
		return text

	var output := ""
	var cursor := 0
	for result in regex.search_all(text):
		var anim_name := String(result.get_string(2))
		var loop_value := "1" if _should_animation_loop(anim_name) else "0"
		output += text.substr(cursor, result.get_start(1) - cursor)
		output += loop_value
		cursor = result.get_end(1)
	output += text.substr(cursor)
	return output


func _should_animation_loop(animation_name: String) -> bool:
	var normalized := animation_name.strip_edges().to_lower()
	return normalized == "idle" or normalized == "run" or normalized == "walk" or normalized == "move"


func _replace_path_in_text(text: String, res_type: String, file_name: String, new_path: String) -> String:
	var lines := text.split("\n")
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.contains("[ext_resource") and line.contains('type="%s"' % res_type) and line.contains(file_name):
			lines[i] = _replace_path_value(line, new_path)
	return "\n".join(lines)


func _replace_path_value(line: String, new_path: String) -> String:
	var key := 'path="'
	var start := line.find(key)
	if start == -1:
		return line
	start += key.length()
	var end := line.find('"', start)
	if end == -1:
		return line
	var replaced := line.substr(0, start) + new_path + line.substr(end)
	# 路径切换后不能保留旧资源 UID。Godot 会优先按 UID 解析，导致文本
	# 已指向新角色但运行时仍实例化旧角色。
	var uid_start := replaced.find(' uid="')
	if uid_start != -1:
		var uid_end := replaced.find('"', uid_start + 6)
		if uid_end != -1:
			replaced = replaced.erase(uid_start, uid_end - uid_start + 1)
	return replaced


func _ensure_centered(text: String) -> String:
	var lines := text.split("\n")
	var sprite_idx := -1
	var centered_idx := -1
	for i in range(lines.size()):
		if lines[i].contains('[node name="AnimatedSprite2D" type="AnimatedSprite2D"'):
			sprite_idx = i
		elif sprite_idx != -1 and lines[i].begins_with("centered = "):
			centered_idx = i
			break
	if centered_idx != -1:
		lines[centered_idx] = "centered = true"
	elif sprite_idx != -1:
		lines.insert(sprite_idx + 3, "centered = true")
	return "\n".join(lines)


func _replace_char_transform(text: String, display_scale: float, display_offset: Vector2) -> String:
	var lines := text.split("\n")
	var in_char := false
	for i in range(lines.size()):
		var line: String = lines[i]
		if line.contains('[node name="CharacterActionSet" parent="."'):
			in_char = true
			continue
		if in_char and line.begins_with("[node "):
			in_char = false
		if not in_char:
			continue
		if line.begins_with("position = Vector2("):
			lines[i] = "position = Vector2(%s, %s)" % [display_offset.x, display_offset.y]
		elif line.begins_with("scale = Vector2("):
			lines[i] = "scale = Vector2(%s, %s)" % [display_scale, display_scale]
	return "\n".join(lines)


func _write_file(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("写入文件失败: %s" % path)
		return
	file.store_string(text)


func _get_content_height(manifest_data: Dictionary) -> float:
	# 优先从 frameRects 读 drawHeight（有压缩流水线的角色）
	var frame_rects: Array = manifest_data.get("frameRects", [])
	if frame_rects.size() > 0:
		var first_frame: Dictionary = frame_rects[0]
		var draw_h := float(first_frame.get("drawHeight", 0))
		if draw_h > 0.0:
			return draw_h
	# 回退到 unifiedBox.height（无压缩角色）
	var ub: Dictionary = manifest_data.get("unifiedBox", {})
	var height := float(ub.get("height", 144.0))
	if height <= 0.0:
		height = 144.0
	return height


func _get_frame_cell_height(manifest_data: Dictionary) -> float:
	var frame_rects: Array = manifest_data.get("frameRects", [])
	if frame_rects.size() > 0:
		var cell_h := float(frame_rects[0].get("cellHeight", 0))
		if cell_h > 0.0:
			return cell_h
	var ub: Dictionary = manifest_data.get("unifiedBox", {})
	var height := float(ub.get("height", 144.0))
	return height if height > 0.0 else 144.0


func _get_content_offset_y(manifest_data: Dictionary) -> float:
	var frame_rects: Array = manifest_data.get("frameRects", [])
	if frame_rects.size() > 0:
		return float(frame_rects[0].get("offsetY", 0))
	return 0.0


func _to_pascal(value: String) -> String:
	var words := PackedStringArray()
	var current := ""
	for character in value:
		var code := character.unicode_at(0)
		var is_alnum := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		if is_alnum:
			current += character
		else:
			if not current.is_empty():
				words.append(current)
				current = ""
	if not current.is_empty():
		words.append(current)
	var result := ""
	for word in words:
		if not word.is_empty():
			result += word.left(1).to_upper() + word.substr(1)
	return result if not result.is_empty() else "ImportedLevel"


# ---- JSON → Excel 导出 ----

func _do_export_json_to_csv() -> void:
	var python := _find_python()
	if python.is_empty():
		push_warning("找不到 Python，跳过 JSON → Excel 转换")
		return

	var script_path := ProjectSettings.globalize_path("res://tools/json_to_excel.py")
	var output := []
	OS.execute(python, [script_path, "--force"], output, true, false)

	for line in output:
		print(line)

	EditorInterface.get_resource_filesystem().scan()


# ---- 模板场景生成 ----

func _generate_playable_character_scene(template_path: String, actions_scene_path: String, config: Dictionary) -> void:
	var char_name: String = config.get("scene_name", config.get("character_name", "Character"))
	var offset: Dictionary = config.get("display_offset", {})
	var display_scale := float(config.get("display_scale", 1.0))
	var body_position: Dictionary = config.get("body_position", {})
	var body_size: Dictionary = config.get("body_size", {})
	var body_x := float(body_position.get("x", 0.0))
	var body_y := float(body_position.get("y", 0.0))
	var body_width := float(body_size.get("x", 24.0))
	var body_height := float(body_size.get("y", 41.0))
	var scene_text := '''[gd_scene load_steps=9 format=3]

[ext_resource type="Script" path="res://scripts/player.gd" id="0_script"]
[ext_resource type="PackedScene" path="%s" id="1_visual"]
[ext_resource type="Script" path="res://scripts/combat/combat_component.gd" id="2_combat"]
[ext_resource type="Script" path="res://scripts/combat/hurt_box.gd" id="3_hurt"]
[ext_resource type="Script" path="res://scripts/combat/hit_box.gd" id="4_hit"]

[sub_resource type="RectangleShape2D" id="1_shape"]
size = Vector2(%s, %s)

[sub_resource type="RectangleShape2D" id="2_ladder_shape"]
size = Vector2(%s, %s)

[sub_resource type="RectangleShape2D" id="3_hit_shape"]
size = Vector2(30, 30)

[sub_resource type="RectangleShape2D" id="4_hurt_shape"]
size = Vector2(%s, %s)

[node name="%s" type="CharacterBody2D"]
script = ExtResource("0_script")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
position = Vector2(%s, %s)
shape = SubResource("1_shape")

[node name="LadderDetector" type="Area2D" parent="."]
collision_layer = 0
collision_mask = 2
monitorable = false

[node name="CollisionShape2D" type="CollisionShape2D" parent="LadderDetector"]
position = Vector2(%s, %s)
shape = SubResource("2_ladder_shape")

[node name="CharacterActionSet" parent="." instance=ExtResource("1_visual")]
z_index = 100
position = Vector2(%s, %s)
scale = Vector2(%s, %s)

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(0, %s)
position_smoothing_enabled = true
position_smoothing_speed = 8.0

[node name="HitBox" type="Area2D" parent="."]
collision_layer = 4
collision_mask = 8
monitoring = false
script = ExtResource("4_hit")

[node name="CollisionShape2D" type="CollisionShape2D" parent="HitBox"]
shape = SubResource("3_hit_shape")
disabled = true

[node name="HurtBox" type="Area2D" parent="."]
collision_layer = 8
collision_mask = 4
script = ExtResource("3_hurt")

[node name="CollisionShape2D" type="CollisionShape2D" parent="HurtBox"]
position = Vector2(%s, %s)
shape = SubResource("4_hurt_shape")

[node name="CombatComponent" type="Node" parent="."]
script = ExtResource("2_combat")
''' % [
		actions_scene_path,
		body_width,
		body_height,
		body_width,
		body_height,
		body_width,
		body_height,
		char_name,
		body_x,
		body_y,
		body_x,
		body_y,
		float(offset.get("x", 0.0)),
		float(offset.get("y", 0.0)),
		display_scale,
		display_scale,
		body_y - 70.0,
		body_x,
		body_y,
	]
	_write_file(template_path, scene_text)

func _generate_template_scene(template_path: String, actions_scene_path: String, config: Dictionary) -> void:
	var char_name: String = config.get("scene_name", config.get("character_name", "Character"))
	var uses_body_box := String(config.get("anchor_mode", "")) == "foot_origin"
	var body_position: Dictionary = config.get("body_position", {})
	var body_size: Dictionary = config.get("body_size", {})
	var body_x := float(body_position.get("x", 0.0)) if uses_body_box else 0.0
	var body_y := float(body_position.get("y", 0.0)) if uses_body_box else 0.0
	var body_width := float(body_size.get("x", 24.0)) if uses_body_box else 24.0
	var body_height := float(body_size.get("y", 38.0)) if uses_body_box else 38.0
	var hurt_width := body_width if uses_body_box else 20.0
	var hurt_height := body_height if uses_body_box else 36.0
	var scene_text := '[gd_scene load_steps=8 format=3]\n'
	scene_text += '\n'
	scene_text += '[ext_resource type="PackedScene" path="%s" id="1_visual"]\n' % actions_scene_path
	scene_text += '[ext_resource type="Script" path="res://scripts/enemy.gd" id="0_script"]\n'
	scene_text += '[ext_resource type="Script" path="res://scripts/combat/combat_component.gd" id="2_combat"]\n'
	scene_text += '[ext_resource type="Script" path="res://scripts/combat/hurt_box.gd" id="3_hurt"]\n'
	scene_text += '[ext_resource type="Script" path="res://scripts/combat/hit_box.gd" id="4_hit"]\n'
	scene_text += '\n'
	scene_text += '[sub_resource type="RectangleShape2D" id="1_shape"]\n'
	scene_text += 'size = Vector2(%s, %s)\n' % [body_width, body_height]
	scene_text += '\n'
	scene_text += '[sub_resource type="RectangleShape2D" id="2_hit_shape"]\n'
	scene_text += 'size = Vector2(30, 30)\n'
	scene_text += '\n'
	scene_text += '[sub_resource type="RectangleShape2D" id="3_hurt_shape"]\n'
	scene_text += 'size = Vector2(%s, %s)\n' % [hurt_width, hurt_height]
	scene_text += '\n'
	scene_text += '[node name="%s" type="CharacterBody2D"]\n' % char_name
	scene_text += 'groups = ["enemies"]\n'
	scene_text += 'collision_layer = 2\n'
	scene_text += 'collision_mask = 1\n'
	scene_text += 'script = ExtResource("0_script")\n'
	scene_text += '\n'
	scene_text += '[node name="CollisionShape2D" type="CollisionShape2D" parent="."]\n'
	scene_text += 'position = Vector2(%s, %s)\n' % [body_x, body_y]
	scene_text += 'shape = SubResource("1_shape")\n'
	scene_text += '\n'
	# 直接实例化动作场景，SpriteFrames 绑定和默认动画保持单一来源。
	scene_text += '[node name="CharacterActionSet" parent="." instance=ExtResource("1_visual")]\n'
	var offset: Dictionary = config.get("display_offset", {})
	var display_scale := float(config.get("display_scale", 1.0))
	scene_text += 'position = Vector2(%s, %s)\n' % [float(offset.get("x", 0.0)), float(offset.get("y", 0.0))]
	scene_text += 'scale = Vector2(%s, %s)\n' % [display_scale, display_scale]
	scene_text += '\n'
	scene_text += '[node name="HitBox" type="Area2D" parent="."]\n'
	scene_text += 'collision_layer = 4\n'
	scene_text += 'collision_mask = 8\n'
	scene_text += 'monitoring = false\n'
	scene_text += 'script = ExtResource("4_hit")\n'
	scene_text += '\n'
	scene_text += '[node name="CollisionShape2D" type="CollisionShape2D" parent="HitBox"]\n'
	scene_text += 'shape = SubResource("2_hit_shape")\n'
	scene_text += 'disabled = true\n'
	scene_text += '\n'
	scene_text += '[node name="HurtBox" type="Area2D" parent="."]\n'
	scene_text += 'collision_layer = 8\n'
	scene_text += 'collision_mask = 4\n'
	scene_text += 'script = ExtResource("3_hurt")\n'
	scene_text += '\n'
	scene_text += '[node name="CollisionShape2D" type="CollisionShape2D" parent="HurtBox"]\n'
	scene_text += 'position = Vector2(%s, %s)\n' % [body_x, body_y]
	scene_text += 'shape = SubResource("3_hurt_shape")\n'
	scene_text += '\n'
	scene_text += '[node name="CombatComponent" type="Node" parent="."]\n'
	scene_text += 'script = ExtResource("2_combat")\n'

	_write_file(template_path, scene_text)
