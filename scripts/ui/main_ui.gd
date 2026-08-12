class_name MainUI
extends Control
## 常驻 HUD：从 GameTool Godot UI 交互编排导出的 .tscn 实例化，替换原纯代码 BattleHud。
## 场景设计画布 1536×864，运行时等比缩放居中。M 键由 ui_root.toggle_main_ui() 切换显隐。
## HUD 模式：隐藏全屏背景与 14 个顶部功能按钮；保留队伍血条、底部 3 栏技能栏、怪物血条。
## 底部 3 栏技能：中=玩家操控角色，左/右=队友1/2；含技能冷却倒计时（遮罩+秒数）。
## 怪物血条：独立预设 enemy_hp_bar.tscn，顶部中央（完整）+ 怪物头顶（紧凑投影）。

const SCENE_PATH := "res://assets/ui/ui_main_lp.tscn"
## GameTool 导出的节点/绑定清单；main_ui 依据其中的 bindings 按绑定键自动接线。
const MANIFEST_PATH := "res://assets/ui/ui_main_lp/ui_scene_manifest.json"
const ENEMY_BAR_SCENE := "res://assets/ui/enemy_hp_bar/enemy_hp_bar.tscn"
const DESIGN_SIZE := Vector2(1536, 864)
const BLUE_PLACEHOLDER_MAX := 100
const SKILL_SLOTS := ["skill1", "skill2", "skill3"]
# 场景里技能图标按钮命名：第1/3个为 button_skill_icon_1/3 + 组前缀，第2个为 button_skill_icon_2_2 + 组前缀
const SKILL_ICON_BASES := ["button_skill_icon_1", "button_skill_icon_2_2", "button_skill_icon_3"]

# ── 绑定键契约（数据驱动接线）──────────────────────────────
# 网页侧 UiInteractionComposer 给节点设置 bindingKey 后，导出清单的 bindings 按下列键
# 由 main_ui 自动接线；未设绑定键的节点回退到场景唯一节点名（_get_unique 兜底）。
#  signal/pressed：open_character / open_skills / open_inventory / close_hud /
#                   toggle_hud_buttons / placeholder / switch_1..3 / skill_passive_1..3
#  skill_<g>_<s>：g=1..3(左/中/右=队友1/主控/队友2)，s=1..3(skill1..3) → 释放技能
#  range/value：player_hp / player_energy / player_exp / ally1_hp/_energy/_exp / ally2_hp/_energy/_exp
#  texture：player_avatar / ally1_avatar / ally2_avatar
#  text：gold / sstone / stone
# ────────────────────────────────────────────────────────────

# HUD 模式下隐藏的节点（全屏背景 + 货币 + 顶部功能按钮，button_set 除外）
const HUD_HIDDEN_NODES: PackedStringArray = [
	"Background", "image_token_background",
	"label_gold", "image_gold", "label_Sstone", "image_Sstone", "label_stone", "image_stone",
	"button_hero", "button_skill", "button_map", "button_back", "button_Trading",
	"button_plan", "button_military", "button_friend", "button_calendar", "button_rune",
	"button_mail", "button_副本", "button_pet",
]

# 由 button_set 控制的顶部功能按钮（默认隐藏，点击 button_set 切换显隐）
const TOGGLE_BUTTONS: PackedStringArray = [
	"button_hero", "button_skill", "button_map", "button_back", "button_Trading",
	"button_plan", "button_military", "button_friend", "button_calendar", "button_rune",
	"button_mail", "button_副本", "button_pet",
]

var ui_root: Node = null

var _scene_root: Control = null
var _built: bool = false
var _party_manager: Node = null
var _enemy_spawner: Node = null
var _refresh_timer := 0.0
var _function_buttons_visible := false

# 顶部主控状态
var _main_hp_bar: ProgressBar
var _main_blue_bar: ProgressBar
var _main_exp_bar: ProgressBar
var _main_avatar: TextureRect
# 队友面板（player_one / player_one_2）
var _ally_panels: Array = []  # [{panel, avatar, hp, blue, exp}]
# 底部角色技能栏（3 组：左=队友1 / 中=主控 / 右=队友2）
var _skill_groups: Array = []  # [{root, char_btn, member, icons:[{btn,overlay,label}]}]
# 绑定键 → 节点映射（来自 ui_scene_manifest.json 的 bindings）
var _bar_by_key: Dictionary = {}    # bindingKey -> ProgressBar
var _avatar_by_key: Dictionary = {} # bindingKey -> TextureRect
var _label_by_key: Dictionary = {}  # bindingKey -> Label
var _button_by_key: Dictionary = {} # bindingKey -> Button/TextureButton
var _panel_by_key: Dictionary = {}  # bindingKey -> Control（面板）
var _skill_icon_by_key: Dictionary = {} # "skill_<g>_<s>" -> TextureButton
# 货币标签
var _gold_label: Label
var _sstone_label: Label
var _stone_label: Label
# 怪物血条
var _enemy_bar_top: Control
var _enemy_bar_head: Control
var _tracked_enemy: Node


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# HUD 空区穿透到游戏，技能按钮等子节点仍可点击
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 直接构建：visibility_changed 在节点进入场景树时即触发，早于这里连接信号，会漏掉首次构建
	_build()
	_built = true


func setup(party_manager: Node, enemy_spawner: Node = null) -> void:
	_party_manager = party_manager
	_enemy_spawner = enemy_spawner
	_connect_signals()


func _process(delta: float) -> void:
	if not visible or not _built:
		return
	_update_head_bar_position()
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = 0.1
	_refresh_all()


func _build() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_warning("[MainUI] 无法加载场景: %s" % SCENE_PATH)
		return
	_scene_root = packed.instantiate() as Control
	if _scene_root == null:
		push_warning("[MainUI] 场景根节点不是 Control")
		return
	add_child(_scene_root)
	_scene_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_hud_mode()
	_load_manifest_bindings()
	_bind_bars()
	_connect_buttons()
	_connect_skill_bars()
	_connect_enemy_bars()
	_connect_signals()
	get_viewport().size_changed.connect(_apply_design_scale)
	_apply_design_scale()
	_refresh_all()


# ---- HUD 模式 ----

func _apply_hud_mode() -> void:
	if _scene_root == null:
		return
	for name in HUD_HIDDEN_NODES:
		var node := _scene_root.get_node_or_null(name)
		if node != null:
			node.visible = false
	# 顶部功能按钮默认隐藏，button_set 常驻用于切换其显隐
	_set_function_buttons_visible(false)


# ---- 节点引用 ----

func _bind_bars() -> void:
	if _scene_root == null:
		return
	_main_hp_bar = _get_by_key(_bar_by_key, "player_hp", "progress_health_bar") as ProgressBar
	_main_blue_bar = _get_by_key(_bar_by_key, "player_energy", "progress_magicbar") as ProgressBar
	_main_exp_bar = _get_by_key(_bar_by_key, "player_exp", "progress_expbar") as ProgressBar
	_main_avatar = _get_by_key(_avatar_by_key, "player_avatar", "image_avatar") as TextureRect
	_gold_label = _get_by_key(_label_by_key, "gold", "label_gold") as Label
	_sstone_label = _get_by_key(_label_by_key, "sstone", "label_Sstone") as Label
	_stone_label = _get_by_key(_label_by_key, "stone", "label_stone") as Label

	_ally_panels.clear()
	_ally_panels.append({
		# 隐藏整个队员栏，而不是只隐藏其中的底图。否则空头像、血条仍会残留。
		"panel": _get_by_key(_panel_by_key, "ally1_panel", "role_information_bar_2"),
		"avatar": _get_by_key(_avatar_by_key, "ally1_avatar", "image_002"),
		"hp": _get_by_key(_bar_by_key, "ally1_hp", "progress_005") as ProgressBar,
		"blue": _get_by_key(_bar_by_key, "ally1_energy", "progress_006") as ProgressBar,
		"exp": _get_by_key(_bar_by_key, "ally1_exp", "progress_003") as ProgressBar,
	})
	_ally_panels.append({
		"panel": _get_by_key(_panel_by_key, "ally2_panel", "role_information_bar_3"),
		"avatar": _get_by_key(_avatar_by_key, "ally2_avatar", "image_002_2"),
		"hp": _get_by_key(_bar_by_key, "ally2_hp", "progress_005_2") as ProgressBar,
		"blue": _get_by_key(_bar_by_key, "ally2_energy", "progress_006_2") as ProgressBar,
		"exp": _get_by_key(_bar_by_key, "ally2_exp", "progress_003_2") as ProgressBar,
	})


func _get_unique(node_name: String) -> Node:
	if _scene_root == null:
		return null
	var unique_node := _scene_root.get_node_or_null(NodePath("%" + node_name))
	if unique_node != null:
		return unique_node
	# 导出的 UI 场景没有给所有绑定节点设置 unique_name_in_owner；按名称递归兜底。
	return _scene_root.find_child(node_name, true, false)


## 绑定键优先取节点，缺键/缺节点时回退到场景唯一节点名兜底。
func _get_by_key(node_map: Dictionary, binding_key: String, fallback_name: String) -> Node:
	if node_map.has(binding_key):
		return node_map[binding_key]
	return _get_unique(fallback_name)


## 读取 ui_scene_manifest.json 的 bindings，按 kind 分类建立绑定键→节点映射。
## 清单缺失、解析失败或某键找不到节点时静默跳过，不影响兜底绑定。
func _load_manifest_bindings() -> void:
	_bar_by_key.clear()
	_avatar_by_key.clear()
	_label_by_key.clear()
	_button_by_key.clear()
	_panel_by_key.clear()
	_skill_icon_by_key.clear()
	if _scene_root == null or not FileAccess.file_exists(MANIFEST_PATH):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(MANIFEST_PATH)) != OK:
		return
	var data: Variant = json.data
	if not (data is Dictionary):
		return
	var bindings: Variant = data.get("bindings", [])
	if not (bindings is Array):
		return
	for entry in bindings:
		if not (entry is Dictionary):
			continue
		var binding_key := str(entry.get("bindingKey", ""))
		var node_ref := str(entry.get("node", ""))
		var kind := str(entry.get("kind", ""))
		if binding_key.is_empty():
			continue
		var ctrl := _get_unique(node_ref.trim_prefix("%")) as Control
		if ctrl == null:
			continue
		match kind:
			"signal":
				if binding_key.begins_with("skill_"):
					_skill_icon_by_key[binding_key] = ctrl
				else:
					_button_by_key[binding_key] = ctrl
			"range":
				if ctrl is ProgressBar:
					_bar_by_key[binding_key] = ctrl
			"texture":
				if ctrl is TextureRect:
					_avatar_by_key[binding_key] = ctrl
			"text":
				if ctrl is Label:
					_label_by_key[binding_key] = ctrl
			"container":
				pass


# ---- 顶部功能按钮（HUD 模式下隐藏，保留连接） ----

func _connect_buttons() -> void:
	# 绑定键优先，缺键/缺节点时回退到场景唯一节点名。
	_bind_button_by_key("open_character", "button_hero", Callable(self, "_on_character_button"))
	_bind_button_by_key("open_skills", "button_skill", Callable(self, "_on_skills_button"))
	_bind_button_by_key("open_inventory", "button_plan", Callable(self, "_on_inventory_button"))
	_bind_button_by_key("close_hud", "button_back", Callable(self, "_on_back_button"))
	for name in [
		"button_map", "button_Trading", "button_military", "button_friend",
		"button_calendar", "button_rune", "button_mail", "button_副本",
		"button_pet",
	]:
		_bind_button_by_key("placeholder", name, Callable(self, "_on_placeholder_button"))
	_bind_button_by_key("toggle_hud_buttons", "button_set", Callable(self, "_on_toggle_buttons"))


## 按绑定键连接按钮回调；绑定键缺节点时回退到场景唯一节点名。
func _bind_button_by_key(binding_key: String, fallback_name: String, callback: Callable) -> void:
	_connect_button_signal(_get_by_key(_button_by_key, binding_key, fallback_name), callback)


func _connect_button_signal(btn: Node, callback: Callable) -> void:
	if btn == null:
		return
	if btn is TextureButton:
		if not btn.pressed.is_connected(callback):
			btn.pressed.connect(callback)
	elif btn is Button:
		if not btn.pressed.is_connected(callback):
			btn.pressed.connect(callback)


func _on_character_button() -> void:
	if ui_root != null:
		ui_root.toggle_main_menu(ui_root.TAB_CHARACTER)

func _on_skills_button() -> void:
	if ui_root != null:
		ui_root.toggle_main_menu(ui_root.TAB_SKILLS)

func _on_inventory_button() -> void:
	if ui_root != null:
		ui_root.toggle_backpack()

func _on_back_button() -> void:
	if ui_root != null:
		ui_root.toggle_main_ui()

func _on_placeholder_button() -> void:
	if ui_root != null and ui_root.has_method("show_notification"):
		ui_root.show_notification("功能开发中")


# ---- 顶部功能按钮显隐切换（由 button_set 控制） ----

func _on_toggle_buttons() -> void:
	_set_function_buttons_visible(not _function_buttons_visible)


func _set_function_buttons_visible(visible: bool) -> void:
	_function_buttons_visible = visible
	if _scene_root == null:
		return
	for name in TOGGLE_BUTTONS:
		var node := _scene_root.get_node_or_null(name)
		if node != null:
			node.visible = visible


# ---- 底部角色技能栏 ----
# 组顺序固定：左(_2_3)=队友1、中(_2)=主控、右(_2_2_2)=队友2

func _connect_skill_bars() -> void:
	if _scene_root == null:
		return
	_skill_groups.clear()
	_skill_groups.append(_make_skill_group(0, "button_skill_background_2_3", "_2_3"))
	_skill_groups.append(_make_skill_group(1, "button_skill_background_2", "_2"))
	_skill_groups.append(_make_skill_group(2, "button_skill_background_2_2_2", "_2_2_2"))


func _make_skill_group(group_index: int, bg_name: String, prefix: String) -> Dictionary:
	var root := _get_unique(bg_name)
	var char_btn := _get_unique("button_character_num%s" % prefix)
	var char_key := "switch_%d" % (group_index + 1)
	var passive_key := "skill_passive_%d" % (group_index + 1)
	var passive_btn := _get_by_key(_button_by_key, passive_key, "button_skill_passive%s" % prefix)
	var icons: Array = []
	for i in range(SKILL_SLOTS.size()):
		var icon_key := "skill_%d_%d" % [group_index + 1, i + 1]
		var icon_name: String = SKILL_ICON_BASES[i] + prefix
		var btn := _get_by_key(_skill_icon_by_key, icon_key, icon_name) as TextureButton
		var overlay := _make_cooldown_overlay(btn)
		_bind_button_by_key(icon_key, icon_name, Callable(self, "_on_skill_icon_pressed").bind(group_index, i))
		icons.append({"btn": btn, "overlay": overlay["overlay"], "label": overlay["label"]})
	_bind_button_by_key(char_key, "button_character_num%s" % prefix, Callable(self, "_on_character_num_pressed").bind(group_index))
	_bind_button_by_key(passive_key, "button_skill_passive%s" % prefix, Callable(self, "_on_placeholder_button"))
	return {"root": root, "char_btn": char_btn, "passive_btn": passive_btn, "member": null, "icons": icons}


## 为技能图标按钮附加冷却遮罩+倒计时标签。
func _make_cooldown_overlay(btn: TextureButton) -> Dictionary:
	var overlay := ColorRect.new()
	overlay.name = "CooldownOverlay"
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	if btn != null:
		btn.add_child(overlay)
	var label := Label.new()
	label.name = "CooldownLabel"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(label)
	return {"overlay": overlay, "label": label}


func _on_skill_icon_pressed(group_index: int, slot_index: int) -> void:
	if group_index < 0 or group_index >= _skill_groups.size():
		return
	var group: Dictionary = _skill_groups[group_index]
	var member = group.get("member")
	if member == null or not is_instance_valid(member):
		return
	var combat: Node = member.get_node_or_null("CombatComponent")
	if combat == null or not combat.has_method("try_use_skill"):
		return
	var skill_id := _get_skill_id(member, SKILL_SLOTS[slot_index])
	if skill_id > 0:
		combat.try_use_skill(skill_id)


func _on_character_num_pressed(group_index: int) -> void:
	if group_index < 0 or group_index >= _skill_groups.size():
		return
	var member = _skill_groups[group_index].get("member")
	if member == null or not is_instance_valid(member):
		return
	var members: Array = _get_members()
	var idx := members.find(member)
	if idx >= 0 and _party_manager != null and _party_manager.has_method("switch_character"):
		_party_manager.switch_character(idx)


# ---- 怪物血条 ----

func _connect_enemy_bars() -> void:
	var top_packed := load(ENEMY_BAR_SCENE) as PackedScene
	if top_packed == null:
		return
	_enemy_bar_top = top_packed.instantiate() as Control
	_enemy_bar_top.name = "EnemyHpBarTop"
	_enemy_bar_top.anchor_left = 0.5
	_enemy_bar_top.anchor_right = 0.5
	_enemy_bar_top.anchor_top = 0.0
	_enemy_bar_top.anchor_bottom = 0.0
	_enemy_bar_top.offset_left = -105
	_enemy_bar_top.offset_right = 105
	_enemy_bar_top.offset_top = 10
	_enemy_bar_top.offset_bottom = 60
	add_child(_enemy_bar_top)
	if _enemy_bar_top.has_method("set_compact"):
		_enemy_bar_top.set_compact(false)

	_enemy_bar_head = top_packed.instantiate() as Control
	_enemy_bar_head.name = "EnemyHpBarHead"
	_enemy_bar_head.visible = false
	add_child(_enemy_bar_head)
	if _enemy_bar_head.has_method("set_compact"):
		_enemy_bar_head.set_compact(true)


func _update_head_bar_position() -> void:
	if _enemy_bar_head == null or not _enemy_bar_head.visible:
		return
	if _tracked_enemy == null or not is_instance_valid(_tracked_enemy):
		return
	var world_pos := Vector2.ZERO
	if _tracked_enemy.has_method("get_head_world_position"):
		world_pos = _tracked_enemy.get_head_world_position()
	else:
		world_pos = _tracked_enemy.global_position
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * world_pos
	var bs := Vector2(120, 10)
	if _enemy_bar_head.has_method("get_content_size"):
		var content_size: Vector2 = _enemy_bar_head.get_content_size()
		if content_size.x > 0.0:
			bs = content_size
	_enemy_bar_head.position = screen_pos - Vector2(bs.x * 0.5, bs.y + 4.0)


func _refresh_enemy_bars() -> void:
	var enemy := _select_current_enemy()
	_tracked_enemy = enemy
	if _enemy_bar_top != null and _enemy_bar_top.has_method("set_enemy"):
		_enemy_bar_top.set_enemy(enemy)
	if _enemy_bar_head != null and _enemy_bar_head.has_method("set_enemy"):
		_enemy_bar_head.set_enemy(enemy)


# ---- 数据信号 ----

func _connect_signals() -> void:
	if _party_manager == null:
		return
	if not _party_manager.party_changed.is_connected(_on_data_changed):
		_party_manager.party_changed.connect(_on_data_changed)
	if not _party_manager.active_character_changed.is_connected(_on_data_changed):
		_party_manager.active_character_changed.connect(_on_data_changed)
	if GameRegistry.character_stats != null and not GameRegistry.character_stats.stats_changed.is_connected(_refresh_all):
		GameRegistry.character_stats.stats_changed.connect(_refresh_all)
	if GameRegistry.roster_data != null and not GameRegistry.roster_data.character_progress_changed.is_connected(_refresh_all):
		GameRegistry.roster_data.character_progress_changed.connect(_refresh_all)


func _on_data_changed(_arg = null) -> void:
	_refresh_all()


# ---- 刷新 ----

func _refresh_all(_by_id: int = -1) -> void:
	if _scene_root == null or not _built:
		return
	var members := _get_members()
	_refresh_main(members)
	_refresh_ally_panels(members)
	_refresh_skill_groups(members)
	_refresh_enemy_bars()


func _get_members() -> Array:
	if _party_manager == null or not _party_manager.has_method("get_party_members"):
		return []
	return _party_manager.get_party_members()


func _refresh_main(members: Array) -> void:
	var active: Variant = _party_manager.get_active_character() if _party_manager != null and _party_manager.has_method("get_active_character") else null
	if _main_hp_bar != null:
		var hp := 0
		var max_hp := 1
		var stats = _get_member_stats(active)
		if stats != null:
			hp = int(stats.hp)
			max_hp = maxi(1, int(stats.max_hp))
		_main_hp_bar.max_value = max_hp
		_main_hp_bar.value = clampi(hp, 0, max_hp)
	if _main_blue_bar != null:
		_main_blue_bar.max_value = BLUE_PLACEHOLDER_MAX
		_main_blue_bar.value = BLUE_PLACEHOLDER_MAX
	if _main_exp_bar != null:
		_set_exp_bar(_main_exp_bar, active)
	if _main_avatar != null:
		_set_avatar_texture(_main_avatar, active)
	if _gold_label != null:
		_gold_label.text = "0"
	if _sstone_label != null:
		_sstone_label.text = "0"
	if _stone_label != null:
		_stone_label.text = "0"


func _refresh_ally_panels(members: Array) -> void:
	for i in range(_ally_panels.size()):
		var panel_data: Dictionary = _ally_panels[i]
		var panel: Control = panel_data.get("panel")
		var member_index := i + 1  # player_one=成员1、player_one_2=成员2
		var is_visible := member_index < members.size()
		if panel != null:
			panel.visible = is_visible
		if not is_visible:
			continue
		var member = members[member_index]
		var stats = _get_member_stats(member)
		var hp_bar: ProgressBar = panel_data.get("hp")
		if hp_bar != null and stats != null:
			var hp := int(stats.hp)
			var max_hp := maxi(1, int(stats.max_hp))
			hp_bar.max_value = max_hp
			hp_bar.value = clampi(hp, 0, max_hp)
		var blue_bar: ProgressBar = panel_data.get("blue")
		if blue_bar != null:
			blue_bar.max_value = BLUE_PLACEHOLDER_MAX
			blue_bar.value = BLUE_PLACEHOLDER_MAX
		var exp_bar: ProgressBar = panel_data.get("exp")
		if exp_bar != null:
			_set_exp_bar(exp_bar, member)
		var avatar := panel_data.get("avatar") as TextureRect
		if avatar != null:
			_set_avatar_texture(avatar, member)


func _refresh_skill_groups(members: Array) -> void:
	var active: Variant = _party_manager.get_active_character() if _party_manager != null and _party_manager.has_method("get_active_character") else null
	var allies: Array = []
	for m in members:
		if m != active:
			allies.append(m)
	# 位置：左=队友1、中=主控、右=队友2
	var positions: Array = [
		allies[0] if allies.size() > 0 else null,
		active,
		allies[1] if allies.size() > 1 else null,
	]
	for i in range(_skill_groups.size()):
		var group: Dictionary = _skill_groups[i]
		group["member"] = positions[i]
		_refresh_skill_group(group, positions[i])


## 整组统一显隐。新版导出会把技能组包进组容器 Control（compound_*），
## 直接切换容器即可覆盖底框/边框/切换/被动/图标及其全部子层；
## 旧版平铺场景没有容器，退回逐节点隐藏（底框/切换/被动/3个技能图标）。
func _set_skill_group_visible(group: Dictionary, visible: bool) -> void:
	var root: Control = group.get("root")
	if root != null and is_instance_valid(root):
		var container := root.get_parent()
		if container is Control and container != _scene_root:
			container.visible = visible
			return
	var nodes: Array[Control] = [
		root,
		group.get("char_btn"),
		group.get("passive_btn"),
	]
	for icon_data in group.get("icons", []):
		nodes.append(icon_data.get("btn"))
	for ctrl in nodes:
		if ctrl is Control and is_instance_valid(ctrl):
			ctrl.visible = visible


func _refresh_skill_group(group: Dictionary, member) -> void:
	var has_member := member != null and is_instance_valid(member)
	_set_skill_group_visible(group, has_member)
	if not has_member:
		return
	var root: Control = group.get("root")
	var combat: Node = member.get_node_or_null("CombatComponent")
	var cooldowns: Dictionary = {}
	if combat != null and combat.has_method("get_cooldowns_dict"):
		cooldowns = combat.get_cooldowns_dict()
	var icons: Array = group.get("icons")
	for i in range(icons.size()):
		var icon_data: Dictionary = icons[i]
		var skill_id := _get_skill_id(member, SKILL_SLOTS[i])
		var has_skill := skill_id > 0
		var btn := icon_data.get("btn") as TextureButton
		if btn != null:
			btn.disabled = not has_skill
		var overlay := icon_data.get("overlay") as ColorRect
		var label := icon_data.get("label") as Label
		var cd := float(cooldowns.get(skill_id, 0.0))
		var on_cd := has_skill and cd > 0.05
		if overlay != null:
			overlay.visible = on_cd
			if label != null:
				label.text = "%.0f" % cd if on_cd else ""


# ---- 敌人选择 ----

func _select_current_enemy() -> Node:
	if _enemy_spawner == null or not is_instance_valid(_enemy_spawner):
		return null
	var enemies: Array[Node] = []
	if _enemy_spawner.has_method("get_active_enemies"):
		enemies = _enemy_spawner.get_active_enemies()
	var active: Variant = _party_manager.get_active_character() if _party_manager != null and _party_manager.has_method("get_active_character") else null
	var best: Node = null
	var best_score := INF
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var stats = enemy.get_combat_stats() if enemy.has_method("get_combat_stats") else null
		if stats == null or int(stats.hp) <= 0:
			continue
		var dist_to_active := INF
		if active != null and is_instance_valid(active):
			dist_to_active = absf(enemy.global_position.x - active.global_position.x)
		var score := dist_to_active
		var target = enemy.get_current_target() if enemy.has_method("get_current_target") else null
		if target == active:
			score -= 10000.0
		elif target != null and is_instance_valid(target):
			score -= 5000.0
		if enemy.has_method("get_ai_state_name"):
			var ai_name := str(enemy.get_ai_state_name())
			if ai_name == "ATTACK":
				score -= 1000.0
			elif ai_name == "CHASE":
				score -= 500.0
		if score < best_score:
			best_score = score
			best = enemy
	return best


# ---- 数据辅助 ----

func _get_member_stats(member):
	if member == null or not is_instance_valid(member):
		return null
	if member.has_method("get_combat_stats"):
		return member.get_combat_stats()
	return null


func _get_member_character_id(member) -> int:
	if member != null and member.has_method("get_party_character_id"):
		return member.get_party_character_id()
	return 0


func _get_member_level(member) -> int:
	var character_id := _get_member_character_id(member)
	if GameRegistry.roster_data != null and character_id > 0:
		return GameRegistry.roster_data.get_level(character_id)
	return 1


func _get_skill_id(member, slot_name: String) -> int:
	var character_id := _get_member_character_id(member)
	if GameRegistry.character_config == null or character_id <= 0:
		return 0
	return GameRegistry.character_config.get_skill_for_slot(character_id, slot_name, _get_member_level(member))


func _set_exp_bar(bar: ProgressBar, member) -> void:
	var character_id := _get_member_character_id(member)
	var level := _get_member_level(member)
	var exp := 0
	if GameRegistry.roster_data != null and character_id > 0:
		exp = GameRegistry.roster_data.get_exp(character_id)
	var need := maxi(1, level * 100)
	bar.max_value = need
	bar.value = clampi(exp, 0, need)


func _set_avatar_texture(tex: TextureRect, member) -> void:
	if tex == null:
		return
	tex.texture = null
	if member == null or not is_instance_valid(member):
		return
	var character_id := _get_member_character_id(member)
	var portrait_path := _get_portrait_path(character_id)
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
		tex.texture = load(portrait_path) as Texture2D


func _get_portrait_path(character_id: int) -> String:
	if character_id >= 7001 and character_id <= 7999 and GameRegistry.character_config != null:
		var config: Dictionary = GameRegistry.character_config.get_character(character_id)
		var cc_path := str(config.get("character_config", ""))
		if not cc_path.is_empty() and FileAccess.file_exists(cc_path):
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(cc_path)) == OK and json.data is Dictionary:
				return str(json.data.get("portrait", ""))
	if character_id >= 8001 and GameRegistry.enemy_config != null:
		var enemy: Dictionary = GameRegistry.enemy_config.get_enemy(character_id)
		var cc_path := str(enemy.get("character_config", ""))
		if not cc_path.is_empty() and FileAccess.file_exists(cc_path):
			var json := JSON.new()
			if json.parse(FileAccess.get_file_as_string(cc_path)) == OK and json.data is Dictionary:
				return str(json.data.get("portrait", ""))
	return ""


func _apply_design_scale() -> void:
	if _scene_root == null:
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		return
	var scale_val: float = min(vp.x / DESIGN_SIZE.x, vp.y / DESIGN_SIZE.y)
	_scene_root.scale = Vector2(scale_val, scale_val)
	_scene_root.position = (vp - DESIGN_SIZE * scale_val) * 0.5
