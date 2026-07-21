@tool
extends Window

## 角色/怪物编辑器。可视化查看 res://data/characters.json 和 res://data/enemies.json。
## 设计原则:
## - 导入流程（plugin.gd）会同步的字段只读展示，避免被覆盖。
## - 技能配置由 skill_sequence_editor 管理，只读展示。
## - 角色: 仅 description 可编辑（导入流程不写此字段）。
## - 怪物: max_hp/attack/defense/move_speed/attack_range/detect_range/patrol_range/traits/drop_items/exp 可编辑。
## - 所有字段配中文注解（label + 括号简注 + tooltip 完整说明）。

const CHARACTERS_PATH := "res://data/characters.json"
const ENEMIES_PATH := "res://data/enemies.json"
const EnemyTraits = preload("res://scripts/data/enemy_traits.gd")

# base_stats 完整字段列表（角色属性，由导入流程管理，只读展示）
const BASE_STAT_FIELDS := [
	"max_hp", "attack", "defense", "move_speed",
	"crit_rate", "crit_damage", "attack_speed",
	"armor_pen_flat", "armor_pen_percent",
	"magic_pen_flat", "magic_pen_percent", "magic_resist",
	"block_rate", "dodge_rate", "lifesteal",
	"heal_bonus", "heal_received", "shield_bonus",
	"skill_haste", "status_resist",
]

# base_stats 中文字段名 + 注解映射
const BASE_STAT_LABELS := {
	"max_hp": "最大生命值（角色血量上限）",
	"attack": "攻击力（普攻和技能伤害基础值）",
	"defense": "防御力（减免物理伤害）",
	"move_speed": "移动速度（像素/秒）",
	"crit_rate": "暴击率（0~1，触发暴击概率）",
	"crit_damage": "暴击伤害（暴击倍率，1.5=150%伤害）",
	"attack_speed": "攻击速度（1.0=正常，2.0=双倍）",
	"armor_pen_flat": "护甲穿透-固定（无视点数护甲）",
	"armor_pen_percent": "护甲穿透-百分比（0~1，无视护甲比例）",
	"magic_pen_flat": "法术穿透-固定（无视点数魔抗）",
	"magic_pen_percent": "法术穿透-百分比（0~1，无视魔抗比例）",
	"magic_resist": "魔法抗性（减免法术伤害）",
	"block_rate": "格挡率（0~1，格挡概率）",
	"dodge_rate": "闪避率（0~1，完全闪避概率）",
	"lifesteal": "生命汲取（0~1，伤害转化为治疗比例）",
	"heal_bonus": "治疗加成（0~1，治疗效果提升比例）",
	"heal_received": "受疗加成（0~1，受到治疗提升比例）",
	"shield_bonus": "护盾加成（0~1，护盾值提升比例）",
	"skill_haste": "技能急速（降低技能冷却，1.0=正常）",
	"status_resist": "异常抗性（0~1，抵抗异常状态概率）",
}

# growth 字段中文注解（每级增量）
const GROWTH_LABELS := {
	"attack": "攻击成长（每级攻击力增量）",
	"defense": "防御成长（每级防御力增量）",
	"max_hp": "生命成长（每级生命值增量）",
	"move_speed": "速度成长（每级移动速度增量，通常为 0）",
}

# 数据缓存
var _characters: Dictionary = {}   # int id -> dict
var _enemies: Dictionary = {}      # int id -> dict
var _current_tab := 0              # 0=角色, 1=怪物
var _selected_id := 0
var _loading := false
# 实体预览图标缓存：id_str -> Texture2D（idle 第一帧）
var _preview_textures: Dictionary = {}

# UI 控件引用
var _tab_bar: TabBar
var _entity_list: ItemList
var _list_label: Label
var _content_container: VBoxContainer
var _status_label: Label

# 角色表单控件
var _char_desc_edit: TextEdit
var _char_spins: Dictionary = {}         # field_path -> SpinBox（base_stats/growth/max_level/actor_scale）

# 怪物表单控件（动态创建，保存时遍历读取）
var _enemy_spins: Dictionary = {}        # field_name -> SpinBox
var _enemy_trait_checks: Dictionary = {} # trait_key -> CheckBox
var _enemy_exp_spin: SpinBox
var _drop_items_container: VBoxContainer
var _drop_item_rows: Array = []          # Array of {row: HBoxContainer, id_spin: SpinBox, min_spin: SpinBox, max_spin: SpinBox}

# 左右分隔拖动条
var _left_panel: VBoxContainer
var _divider: Control
var _dragging := false
const _LEFT_MIN_WIDTH := 150.0
const _LEFT_MAX_WIDTH := 560.0


func _ready() -> void:
	title = "角色/怪物编辑器"
	size = Vector2i(1280, 820)
	close_requested.connect(hide)
	_load_config()
	_build_layout()
	_refresh_entity_list()
	if _selected_id > 0:
		_show_entity_details(_selected_id)


func open_editor() -> void:
	_load_config()
	_refresh_entity_list()
	if _selected_id > 0:
		_show_entity_details(_selected_id)
	popup_centered()
	mode = Window.MODE_MAXIMIZED


# ---- 数据加载 ----

func _load_config() -> void:
	_characters.clear()
	_enemies.clear()
	_load_json_into(CHARACTERS_PATH, _characters)
	_load_json_into(ENEMIES_PATH, _enemies)
	# 默认选第一个
	if _current_tab == 0:
		if _characters.size() > 0:
			var ids := _characters.keys()
			ids.sort()
			_selected_id = ids[0]
	elif _enemies.size() > 0:
		var ids := _enemies.keys()
		ids.sort()
		_selected_id = ids[0]


func _load_json_into(path: String, target: Dictionary) -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data := json.data as Dictionary
	for id_str in data:
		target[int(id_str)] = (data[id_str] as Dictionary).duplicate(true)


# ---- 布局构建 ----

func _build_layout() -> void:
	for child in get_children():
		child.queue_free()
	# 整体竖向: TabBar + 主内容 + 底部状态栏
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 顶部 TabBar
	_tab_bar = TabBar.new()
	_tab_bar.add_tab("角色")
	_tab_bar.add_tab("怪物")
	_tab_bar.tab_changed.connect(_on_tab_changed)
	root.add_child(_tab_bar)

	# 主内容区（左列表 + 右表单）
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	root.add_child(main)

	# 左侧实体列表
	_left_panel = VBoxContainer.new()
	_left_panel.custom_minimum_size = Vector2(240, 0)
	_left_panel.add_theme_constant_override("separation", 4)
	main.add_child(_left_panel)

	_list_label = Label.new()
	_list_label.text = "角色列表"
	_left_panel.add_child(_list_label)

	_entity_list = ItemList.new()
	_entity_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 网格图标模式（参考 skill_sequence_editor 左侧列表）
	_entity_list.max_columns = 2
	_entity_list.fixed_icon_size = Vector2i(72, 72)
	_entity_list.fixed_column_width = 150
	_entity_list.same_column_width = true
	_entity_list.item_selected.connect(_on_entity_selected)
	_left_panel.add_child(_entity_list)

	var tip_label := Label.new()
	tip_label.text = "新建请走「导入所有角色/怪物」流程"
	tip_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	tip_label.add_theme_font_size_override("font_size", 11)
	_left_panel.add_child(tip_label)

	# 可拖动分隔条
	_divider = Panel.new()
	_divider.custom_minimum_size = Vector2(6, 0)
	_divider.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_divider.set_default_cursor_shape(Control.CURSOR_HSIZE)
	_divider.gui_input.connect(_on_divider_gui_input)
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.5, 0.5, 0.5, 0.35)
	sep_style.set_content_margin_all(0)
	_divider.add_theme_stylebox_override("panel", sep_style)
	main.add_child(_divider)

	# 右侧表单
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	main.add_child(right)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)

	_content_container = VBoxContainer.new()
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_content_container)

	# 底部状态 + 保存
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_status_label)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.custom_minimum_size = Vector2(100, 32)
	save_btn.pressed.connect(_on_save)
	bottom.add_child(save_btn)


# ---- 左右分隔条拖动 ----

func _on_divider_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var w: float = _left_panel.size.x + event.relative.x
		w = clampf(w, _LEFT_MIN_WIDTH, _LEFT_MAX_WIDTH)
		_left_panel.custom_minimum_size.x = w


# ---- Tab 切换 ----

func _on_tab_changed(tab: int) -> void:
	_current_tab = tab
	_list_label.text = "角色列表" if tab == 0 else "怪物列表"
	_refresh_entity_list()
	if _selected_id > 0:
		_show_entity_details(_selected_id)


func _refresh_entity_list() -> void:
	_entity_list.clear()
	var data: Dictionary = _characters if _current_tab == 0 else _enemies
	var ids := data.keys()
	ids.sort()
	print("[CharacterEditor] _refresh_entity_list tab=%d data_size=%d ids=%s" % [_current_tab, data.size(), str(ids)])
	for id in ids:
		var id_str := str(id)
		var config: Dictionary = data[id]
		var display_name := str(config.get("name", id_str))
		var label_text := "%s  %s" % [id_str, display_name]
		_entity_list.add_item(label_text)
		_entity_list.set_item_metadata(_entity_list.item_count - 1, id)
		var tex := _get_entity_preview_texture(id_str, config)
		if tex != null:
			_entity_list.set_item_icon(_entity_list.item_count - 1, tex)
	# 选中当前 _selected_id（若存在于当前 tab）
	if _selected_id > 0 and data.has(_selected_id):
		var idx := 0
		for id in ids:
			if id == _selected_id:
				_entity_list.select(idx)
				break
			idx += 1


## 加载实体 idle 动画第一帧作为列表图标（带缓存，参考 skill_sequence_editor._get_entity_preview_texture）。
func _get_entity_preview_texture(id_str: String, config: Dictionary) -> Texture2D:
	if _preview_textures.has(id_str):
		return _preview_textures[id_str]
	var asset := String(config.get("asset", ""))
	if asset.is_empty():
		_preview_textures[id_str] = null
		return null
	var sf_path := asset.path_join("godot/spriteframes.tres")
	if not ResourceLoader.exists(sf_path):
		_preview_textures[id_str] = null
		return null
	var sf := load(sf_path) as SpriteFrames
	if sf == null or not sf.has_animation("idle") or sf.get_frame_count("idle") == 0:
		_preview_textures[id_str] = null
		return null
	var tex := sf.get_frame_texture("idle", 0)
	_preview_textures[id_str] = tex
	return tex


func _on_entity_selected(idx: int) -> void:
	if idx < 0 or idx >= _entity_list.item_count:
		return
	var id = _entity_list.get_item_metadata(idx)
	if id == null:
		return
	_selected_id = int(id)
	_show_entity_details(_selected_id)


# ---- 表单构建 ----

func _show_entity_details(entity_id: int) -> void:
	# 清空旧表单
	for child in _content_container.get_children():
		child.queue_free()
	# 重置控件引用
	_char_desc_edit = null
	_char_spins.clear()
	_enemy_spins.clear()
	_enemy_trait_checks.clear()
	_enemy_exp_spin = null
	_drop_items_container = null
	_drop_item_rows.clear()

	if _current_tab == 0 and _characters.has(entity_id):
		_build_character_form(entity_id)
	elif _current_tab == 1 and _enemies.has(entity_id):
		_build_enemy_form(entity_id)
	else:
		var empty := Label.new()
		empty.text = "请从左侧选择一个条目"
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_content_container.add_child(empty)


# ============ 角色表单 ============

func _build_character_form(char_id: int) -> void:
	var data: Dictionary = _characters[char_id]

	# 顶部提示
	_add_section_header(_content_container, "角色配置（ID/路径由导入流程管理，其余可编辑）")

	# 1. 基本信息（ID/路径只读，name/actor_scale/max_level 可编辑）
	var info_grid := _make_grid(_content_container, "基本信息")
	_add_grid_readonly(info_grid, "ID（角色唯一标识，自动分配 7001-7999）", "由导入流程管理，只读", str(char_id))
	_add_grid_readonly(info_grid, "名称 name（由 manifest.json 的 characterName 决定）", "由导入流程管理，只读", String(data.get("name", "")))
	_add_grid_readonly(info_grid, "场景 scene（由导入流程自动生成）", "由导入流程管理，只读", String(data.get("scene", "")))
	_add_grid_readonly(info_grid, "资源目录 asset（由导入流程自动生成）", "由导入流程管理，只读", String(data.get("asset", "")))
	_add_grid_readonly(info_grid, "角色配置 character_config（由导入流程自动生成）", "由导入流程管理，只读", String(data.get("character_config", "")))
	_char_spins["actor_scale"] = _add_grid_spin(info_grid, "显示缩放 actor_scale（1.0=原始尺寸）", "角色显示大小缩放系数，导入流程只在字段缺失时写默认值 1.0，已存在则保留", 0.1, 10.0, 0.1, float(data.get("actor_scale", 1.0)))
	_char_spins["max_level"] = _add_grid_spin(info_grid, "最大等级 max_level（角色可升级的最高等级）", "角色可升级的最高等级，导入流程只在字段缺失时写默认值 60，已存在则保留", 1.0, 999.0, 1.0, float(data.get("max_level", 60)))

	# 2. 描述（可编辑）
	_add_section_header(_content_container, "描述 description（可自由编辑，导入流程不覆盖）")
	var desc_label := Label.new()
	desc_label.text = "描述 description（角色介绍文本，可自由编辑）"
	_content_container.add_child(desc_label)
	_char_desc_edit = TextEdit.new()
	_char_desc_edit.custom_minimum_size = Vector2(0, 80)
	_char_desc_edit.text = String(data.get("description", ""))
	_char_desc_edit.tooltip_text = "角色介绍文本，导入流程不写此字段，可自由编辑"
	_content_container.add_child(_char_desc_edit)

	# 3. base_stats（可编辑）
	var stats_grid := _make_grid(_content_container, "基础属性 base_stats（可编辑，导入流程只在字段缺失时写默认值，已存在则保留）")
	var base_stats: Dictionary = data.get("base_stats", {})
	for field in BASE_STAT_FIELDS:
		var label_text: String = String(BASE_STAT_LABELS.get(field, field))
		var current_val: float = float(base_stats.get(field, 0))
		# 根据字段类型设置范围和步进
		var min_v: float = 0.0
		var max_v: float = 99999.0
		var step_v: float = 1.0
		if field in ["crit_rate", "crit_damage", "attack_speed", "armor_pen_percent", "magic_pen_percent", "block_rate", "dodge_rate", "lifesteal", "heal_bonus", "heal_received", "shield_bonus", "status_resist"]:
			max_v = 10.0
			step_v = 0.01
		elif field in ["max_hp", "move_speed"]:
			max_v = 99999.0
			step_v = 1.0
		_char_spins["base_stats:" + field] = _add_grid_spin(stats_grid, label_text, "导入流程只在字段缺失时写默认值，已存在则保留，可安全编辑", min_v, max_v, step_v, current_val)

	# 4. growth（可编辑）
	var growth_grid := _make_grid(_content_container, "成长属性 growth（可编辑，每级增量，导入流程只在字段缺失时写默认值）")
	var growth: Dictionary = data.get("growth", {})
	for field in ["attack", "defense", "max_hp", "move_speed"]:
		var label_text: String = String(GROWTH_LABELS.get(field, field))
		var current_val: float = float(growth.get(field, 0))
		_char_spins["growth:" + field] = _add_grid_spin(growth_grid, label_text, "每级增量，导入流程只在字段缺失时写默认值，已存在则保留", 0.0, 9999.0, 0.1, current_val)

	# 5. 技能配置（只读，由 skill_sequence_editor 管理）
	var skill_grid := _make_grid(_content_container, "技能配置（由「配置技能节点」编辑器管理，只读展示）")
	_add_grid_readonly(skill_grid, "普攻技能 normal_skill", "普攻技能 ID，请到「配置技能节点」编辑", str(data.get("normal_skill", 0)))
	_add_grid_readonly(skill_grid, "技能列表 skills", "全部技能 ID 列表，请到「配置技能节点」编辑", str(data.get("skills", [])))
	var skill_unlocks: Dictionary = data.get("skill_unlocks", {})
	for slot in ["skill1", "skill2", "skill3"]:
		var unlock: Dictionary = skill_unlocks.get(slot, {})
		_add_grid_readonly(skill_grid, "技能槽位 %s" % slot, "技能 ID %s，解锁等级 %d" % [str(unlock.get("skill_id", 0)), int(unlock.get("unlock_level", 0))], "")


# ============ 怪物表单 ============

func _build_enemy_form(enemy_id: int) -> void:
	var data: Dictionary = _enemies[enemy_id]

	# 顶部提示
	_add_section_header(_content_container, "怪物配置（数值字段可编辑，技能配置只读）")

	# 1. 基本信息（只读）
	var info_grid := _make_grid(_content_container, "基本信息（由导入流程管理，只读）")
	_add_grid_readonly(info_grid, "ID", "怪物唯一标识，自动分配 8001-8999", str(enemy_id))
	_add_grid_readonly(info_grid, "名称 name", "显示名，由 manifest.json 的 characterName 决定", String(data.get("name", "")))
	_add_grid_readonly(info_grid, "资源目录 asset", "怪物素材目录，由导入流程自动生成", String(data.get("asset", "")))
	_add_grid_readonly(info_grid, "角色配置 character_config", "character_config.json 路径，由导入流程自动生成", String(data.get("character_config", "")))

	# 2. 属性（可编辑）
	var stats_grid := _make_grid(_content_container, "属性（可编辑，导入流程对已存在怪物不覆盖）")
	_enemy_spins["max_hp"] = _add_grid_spin(stats_grid, "最大生命值 max_hp（怪物血量上限）", "怪物血量上限，导入流程对已存在怪物不覆盖此字段", 0.0, 999999.0, 1.0, float(data.get("max_hp", 50)))
	_enemy_spins["attack"] = _add_grid_spin(stats_grid, "攻击力 attack（普攻和技能伤害基础值）", "攻击力基础值，导入流程对已存在怪物不覆盖此字段", 0.0, 9999.0, 1.0, float(data.get("attack", 2)))
	_enemy_spins["defense"] = _add_grid_spin(stats_grid, "防御力 defense（减免物理伤害）", "防御力，导入流程对已存在怪物不覆盖此字段", 0.0, 9999.0, 1.0, float(data.get("defense", 0)))
	_enemy_spins["move_speed"] = _add_grid_spin(stats_grid, "移动速度 move_speed（像素/秒）", "移动速度，导入流程对已存在怪物不覆盖此字段", 0.0, 9999.0, 1.0, float(data.get("move_speed", 80)))

	# 3. AI 范围（可编辑）
	var ai_grid := _make_grid(_content_container, "AI 范围（可编辑，导入流程对已存在怪物不覆盖）")
	_enemy_spins["attack_range"] = _add_grid_spin(ai_grid, "攻击范围 attack_range（怪物在此距离内发起攻击，像素）", "怪物在此距离内发起攻击", 0.0, 2000.0, 10.0, float(data.get("attack_range", 80)))
	_enemy_spins["detect_range"] = _add_grid_spin(ai_grid, "侦测范围 detect_range（怪物在此距离内发现玩家并追击，像素）", "怪物在此距离内发现玩家并追击", 0.0, 3000.0, 10.0, float(data.get("detect_range", 300)))
	_enemy_spins["patrol_range"] = _add_grid_spin(ai_grid, "巡逻范围 patrol_range（怪物在出生点周围巡逻的半径，像素）", "怪物在出生点周围巡逻的半径", 0.0, 2000.0, 10.0, float(data.get("patrol_range", 120)))

	# 4. 特征 traits（多选）
	_add_section_header(_content_container, "特征 traits（可编辑，导入流程不触碰）")
	var traits_label := Label.new()
	traits_label.text = "勾选怪物拥有的特征（导入流程不管理此字段，可自由编辑）"
	traits_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	traits_label.add_theme_font_size_override("font_size", 11)
	_content_container.add_child(traits_label)

	var current_traits: Array = data.get("traits", [])
	var trait_grid := GridContainer.new()
	trait_grid.columns = 3
	trait_grid.add_theme_constant_override("h_separation", 12)
	trait_grid.add_theme_constant_override("v_separation", 4)
	_content_container.add_child(trait_grid)

	for trait_key in EnemyTraits.TRAITS:
		var trait_data: Dictionary = EnemyTraits.TRAIT_DATA.get(trait_key, {})
		var trait_label: String = String(trait_data.get("label", trait_key))
		var cb := CheckBox.new()
		cb.text = trait_label
		cb.tooltip_text = "特征: %s\n护甲修正: %s\n魔抗修正: %s\n标签倍率: %s\n异常免疫: %s" % [
			trait_key,
			str(trait_data.get("armor_modifier", 0.0)),
			str(trait_data.get("magic_resist_modifier", 0.0)),
			str(trait_data.get("tag_multipliers", {})),
			str(trait_data.get("status_immunities", [])),
		]
		cb.set_pressed_no_signal(current_traits.has(trait_key))
		trait_grid.add_child(cb)
		_enemy_trait_checks[trait_key] = cb

	# 5. 掉落与经验（可编辑）
	var drop_grid := _make_grid(_content_container, "掉落与经验（可编辑，导入流程对已存在怪物不覆盖）")
	_enemy_exp_spin = _add_grid_spin(drop_grid, "经验值 exp（击杀后玩家获得的经验）", "击杀后玩家获得的经验值", 0.0, 99999.0, 1.0, float(data.get("exp", 10)))

	_add_section_header(_content_container, "掉落物品 drop_items（可增删改）")
	_drop_items_container = VBoxContainer.new()
	_drop_items_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_items_container.add_theme_constant_override("separation", 4)
	_content_container.add_child(_drop_items_container)

	var drop_items: Array = data.get("drop_items", [])
	for item in drop_items:
		_add_drop_item_row(item)

	var add_drop_btn := Button.new()
	add_drop_btn.text = "添加掉落"
	add_drop_btn.pressed.connect(_on_add_drop_item)
	_content_container.add_child(add_drop_btn)

	# 6. 技能配置（只读）
	var skill_grid := _make_grid(_content_container, "技能配置（由「配置技能节点」编辑器管理，只读展示）")
	_add_grid_readonly(skill_grid, "普攻技能 normal_skill", "普攻技能 ID，请到「配置技能节点」编辑", str(data.get("normal_skill", 0)))
	_add_grid_readonly(skill_grid, "技能列表 skills", "主动技能 ID 列表，请到「配置技能节点」编辑", str(data.get("skills", [])))
	_add_grid_readonly(skill_grid, "技能权重 skill_weights", "与 skills 一一对应的 AI 加权选择权重，请到「配置技能节点」编辑", str(data.get("skill_weights", [])))


func _on_add_drop_item() -> void:
	_add_drop_item_row({"item_id": 100001, "min_count": 1, "max_count": 1})


func _add_drop_item_row(item: Variant) -> void:
	var item_dict: Dictionary = item if item is Dictionary else {}
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_drop_items_container.add_child(row)

	var id_label := Label.new()
	id_label.text = "物品ID"
	id_label.tooltip_text = "物品 ID（100001-199999，六位数）"
	row.add_child(id_label)

	var id_spin := SpinBox.new()
	id_spin.min_value = 100001
	id_spin.max_value = 199999
	id_spin.step = 1
	id_spin.value = float(item_dict.get("item_id", 100001))
	id_spin.tooltip_text = "物品 ID（100001-199999，六位数）"
	id_spin.custom_minimum_size = Vector2(120, 0)
	row.add_child(id_spin)

	var min_label := Label.new()
	min_label.text = "最小数量"
	min_label.tooltip_text = "掉落最小数量"
	row.add_child(min_label)

	var min_spin := SpinBox.new()
	min_spin.min_value = 0
	min_spin.max_value = 9999
	min_spin.step = 1
	min_spin.value = float(item_dict.get("min_count", 1))
	min_spin.custom_minimum_size = Vector2(80, 0)
	row.add_child(min_spin)

	var max_label := Label.new()
	max_label.text = "最大数量"
	max_label.tooltip_text = "掉落最大数量"
	row.add_child(max_label)

	var max_spin := SpinBox.new()
	max_spin.min_value = 0
	max_spin.max_value = 9999
	max_spin.step = 1
	max_spin.value = float(item_dict.get("max_count", 1))
	max_spin.custom_minimum_size = Vector2(80, 0)
	row.add_child(max_spin)

	var del_btn := Button.new()
	del_btn.text = "删除"
	del_btn.pressed.connect(func(): row.queue_free(); _drop_item_rows.erase(_drop_item_rows.find(row)))
	row.add_child(del_btn)

	_drop_item_rows.append({row: row, id_spin: id_spin, min_spin: min_spin, max_spin: max_spin})


# ============ 保存逻辑 ============

func _on_save() -> void:
	_loading = true
	# 收集角色改动
	if _current_tab == 0 and _selected_id > 0 and _characters.has(_selected_id):
		_collect_character_changes(_selected_id)
	# 收集怪物改动
	if _current_tab == 1 and _selected_id > 0 and _enemies.has(_selected_id):
		_collect_enemy_changes(_selected_id)
	_loading = false

	# 写回 JSON
	_save_json(CHARACTERS_PATH, _characters)
	_save_json(ENEMIES_PATH, _enemies)

	# 同步运行时配置（编辑器模式下 GameRegistry 可能未运行）
	_reload_runtime_config("character_config")
	_reload_runtime_config("enemy_config")

	_status_label.text = "已保存 %d 个角色, %d 个怪物" % [_characters.size(), _enemies.size()]


func _collect_character_changes(char_id: int) -> void:
	var data: Dictionary = _characters[char_id]
	# description
	if _char_desc_edit != null:
		data["description"] = _char_desc_edit.text
	# actor_scale / max_level
	if _char_spins.has("actor_scale") and _char_spins["actor_scale"] != null:
		data["actor_scale"] = _char_spins["actor_scale"].value
	if _char_spins.has("max_level") and _char_spins["max_level"] != null:
		data["max_level"] = int(_char_spins["max_level"].value)
	# base_stats
	var base_stats: Dictionary = data.get("base_stats", {})
	for key in _char_spins:
		if key.begins_with("base_stats:"):
			var field: String = key.substr(len("base_stats:"))
			base_stats[field] = _char_spins[key].value
	data["base_stats"] = base_stats
	# growth
	var growth: Dictionary = data.get("growth", {})
	for key in _char_spins:
		if key.begins_with("growth:"):
			var field: String = key.substr(len("growth:"))
			growth[field] = _char_spins[key].value
	data["growth"] = growth


func _collect_enemy_changes(enemy_id: int) -> void:
	var data: Dictionary = _enemies[enemy_id]
	# 数值字段
	for field in _enemy_spins:
		if _enemy_spins[field] != null:
			data[field] = _enemy_spins[field].value
	# traits
	var new_traits: Array = []
	for trait_key in _enemy_trait_checks:
		if _enemy_trait_checks[trait_key] != null and _enemy_trait_checks[trait_key].is_pressed():
			new_traits.append(trait_key)
	data["traits"] = new_traits
	# exp
	if _enemy_exp_spin != null:
		data["exp"] = _enemy_exp_spin.value
	# drop_items
	var new_drops: Array = []
	for row_data in _drop_item_rows:
		if !is_instance_valid(row_data.row):
			continue
		new_drops.append({
			"item_id": int(row_data.id_spin.value),
			"min_count": int(row_data.min_spin.value),
			"max_count": int(row_data.max_spin.value),
		})
	data["drop_items"] = new_drops


func _save_json(path: String, data: Dictionary) -> void:
	var sorted: Dictionary = {}
	var ids := data.keys()
	ids.sort()
	for id in ids:
		sorted[str(id)] = data[id]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status_label.text = "写入失败: " + path
		return
	file.store_string(JSON.stringify(sorted, "\t") + "\n")
	file.close()


func _reload_runtime_config(config_name: String) -> void:
	if Engine.is_editor_hint():
		return
	var reg = Engine.get_singleton("GameRegistry") if Engine.has_singleton("GameRegistry") else null
	if reg == null:
		var root := get_tree().get_root()
		reg = root.get_node_or_null("/root/GameRegistry")
	if reg == null:
		return
	var cfg = reg.get(config_name) if reg.get(config_name) != null else null
	if cfg != null and cfg.has_method("load_config"):
		cfg._loaded = false
		cfg.load_config()


# ============ 辅助函数 ============

func _add_section_header(parent: Node, text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	parent.add_child(header)


func _make_grid(parent: Node, title: String) -> GridContainer:
	if not title.is_empty():
		_add_section_header(parent, title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	return grid


func _add_grid_readonly(parent: GridContainer, label_text: String, tooltip: String, value: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = tooltip
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	var val_label := Label.new()
	val_label.text = value
	val_label.tooltip_text = tooltip
	val_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(val_label)


func _add_grid_spin(parent: GridContainer, label_text: String, tooltip: String, min_v: float, max_v: float, step: float, value: float) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = tooltip
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = value
	spin.tooltip_text = tooltip
	spin.custom_minimum_size = Vector2(140, 0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin
