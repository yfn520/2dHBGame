# Buff 系统完善计划 — Bug 修复 + 视觉资产 + 注册表重构

## 总结

本轮 buff 系统完善聚焦三件事：
1. **运行时 Bug 修复** — 修复 3 个确认缺陷 + 1 处死代码清理
2. **视觉资产补齐** — 为 6 个悬空 `effect_scene` 引用创建最小可用特效场景
3. **注册表/策略模式重构** — 把 5 种 effect type 的元数据集中到 `BuffEffectRegistry`，让 `buff_config` / `buff_editor` 通过注册表消费，为后续扩展铺路（本轮不新增 effect type）

**范围约束**（用户明确）：
- 本轮只在现有 5 种 effect type 内工作，不新增 type
- 不做触发机制扩展（aura / on_hit_taken / on_kill 等留待后续）
- 不引入元素抗性系统
- 不改 take_damage 签名

## 当前状态分析

基于源码逐文件阅读：

### 已确认的运行时缺陷

| # | 文件 | 行号 | 问题 | 影响 |
|---|------|------|------|------|
| B1 | [player.gd](file:///d:/game/2dHBGame/scripts/player.gd#L310-L316) | L311 | `_get_move_speed()` 自调用：`var base := _get_move_speed() if _combat_stats != null else 0.0` | 玩家移动时栈溢出崩溃（任何移速 buff 之外的移动输入都会触发） |
| B2 | [buff_instance.gd](file:///d:/game/2dHBGame/scripts/combat/buff_instance.gd#L92-L103) | L92-103 | `add_stack()` 在 refresh/stack 满层时不重置 shield 效果的 `remaining` | 护盾 buff 被刷新后旧护盾吸收量不更新（可能已耗尽），新施放等同没刷新护盾量 |
| B3 | [buff_manager.gd](file:///d:/game/2dHBGame/scripts/combat/buff_manager.gd#L140-L148) | L140-148 | `get_speed_multiplier()` 是死代码 | 全代码库无调用方；player.gd/enemy.gd 实际都用 `get_modified_stat("move_speed", base)`，此方法误导后人 |
| B4 | [buff_manager.gd](file:///d:/game/2dHBGame/scripts/combat/buff_manager.gd#L44-L55) | L44-55 | `apply_buff` 对 `stack_behavior == "independent"` 仍走 `add_stack`，与 refresh 等价 | `independent` 语义未实现（当前 30 条 buff 无一使用，但 BuffEditor 下拉里仍存在该选项，是隐藏陷阱） |

### 已确认的视觉资产缺口

`data/buffs.json` 中 6 条 buff 的 `effect_scene` 指向不存在的 `.tscn`：

| Buff ID | 名称 | 引用路径（不存在） |
|---------|------|-------------------|
| 1001 | 中毒 | `res://assets/effects/poison_fx.tscn` |
| 1002 | 燃烧 | `res://assets/effects/burn_fx.tscn` |
| 1003 | 冰冻 | `res://assets/effects/freeze_fx.tscn` |
| 1004 | 麻痹 | `res://assets/effects/paralysis_fx.tscn` |
| 1005 | 无敌 | `res://assets/effects/invincible_fx.tscn` |
| 1006 | 眩晕 | `res://assets/effects/stun_fx.tscn` |

`assets/effects/` 目录下当前只有 `attachments/` 与 `projectiles/` 两个子目录，这 6 个 `.tscn` 文件均不存在。运行时 [_spawn_effect](file:///d:/game/2dHBGame/scripts/combat/buff_manager.gd#L206-L216) 静默跳过，buff 无视觉反馈。

其余 24 条 buff 的 `effect_scene` 为空串。

### 已确认的架构债务

[buff_config.gd](file:///d:/game/2dHBGame/scripts/data/buff_config.gd#L33-L57) L33-57 与 [buff_editor.gd](file:///d:/game/2dHBGame/scripts/data/buff_config.gd#L353-L379) L353-379 各有一份 effect type 的硬编码 `match`/表单分支。新增 effect type 需同时改这 4 处文件（buff_config / buff_instance / buff_manager / buff_editor），扩展成本高。

### 不在本轮范围（用户明确排除）

- damage_type 抗性消费（DoT L30 `take_damage(dmg, null, false)` 丢弃 damage_type — 留作下轮元素抗性专题）
- aura / on_hit_taken / on_kill / on_death / on_buff_expire 等新触发机制
- 友方目标选择（target=ally/ally_area/all_allies）
- 单节点多 buff、施加参数覆盖、dispel/cleanse 节点、buff 条件查询节点
- HUD 倒计时进度条、敌人/队友面板 buff 显示

## 提议变更

### Phase 1 — 运行时 Bug 修复（4 项）

#### B1 修复 player.gd `_get_move_speed()` 无限递归

**文件**：`d:\game\2dHBGame\scripts\player.gd` L310-316

**变更**：
```gdscript
# 修复前（L311 自调用）
func _get_move_speed() -> float:
	var base := _get_move_speed() if _combat_stats != null else 0.0
	...

# 修复后
func _get_move_speed() -> float:
	var base := _combat_stats.move_speed if _combat_stats != null else 0.0
	...
```

依据：`party_member_stats.gd` L11 `var move_speed: float = 220.0` 确认是公开字段。

#### B2 修复护盾 buff refresh 不重置 `remaining`

**文件**：`d:\game\2dHBGame\scripts\combat\buff_instance.gd` L92-103

**变更**：在 `add_stack()` 末尾追加一段重置所有 shield 效果 `remaining` 的逻辑：
```gdscript
func add_stack() -> bool:
	if stack_behavior == "stack":
		if stacks < max_stacks:
			stacks += 1
			remaining = duration
			_reset_shield_remaining()
			return true
		remaining = duration
		_reset_shield_remaining()
		return false
	# refresh / independent: 仅刷新持续时间
	remaining = duration
	_reset_shield_remaining()
	return false


func _reset_shield_remaining() -> void:
	for effect in effects:
		if effect is Dictionary and String(effect.get("type", "")) == "shield":
			effect["remaining"] = int(effect.get("amount", 0))
```

#### B3 移除死代码 `get_speed_multiplier`

**文件**：`d:\game\2dHBGame\scripts\combat\buff_manager.gd` L140-148

**变更**：删除整个 `get_speed_multiplier()` 方法（已确认全代码库无调用方）。

#### B4 实现 `stack_behavior == "independent"` 语义

**文件**：`d:\game\2dHBGame\scripts\combat\buff_manager.gd` L44-55

**变更**：在 `apply_buff` 顶部检查目标 buff 的 stack_behavior，若为 `independent` 则跳过同 ID 查找、直接创建新实例：
```gdscript
func apply_buff(config: Dictionary, source: int = 0) -> void:
	var buff_id := int(config.get("id", 0))
	var behavior := String(config.get("stack_behavior", "refresh"))
	# independent: 每次施加都创建独立实例，不与已有同 ID buff 叠加
	if behavior != "independent":
		for buff in _buffs:
			if buff.buff_id == buff_id:
				buff.add_stack()
				buff_applied.emit(buff)
				return
	var buff := BuffInstance.new(config, source)
	_buffs.append(buff)
	_spawn_effect(buff)
	buff_applied.emit(buff)
```

依据：当前 30 条 buff 无一使用 `independent`，但 BuffEditor 下拉里仍存在该选项，此修复让选项真正生效，避免后续踩坑。

### Phase 2 — 视觉资产补齐（6 个特效场景）

为 6 个悬空 `effect_scene` 引用创建最小可用的 `.tscn` 场景。每个场景是 `Node2D` 根 + 一个 `CPUParticles2D` 子节点，用颜色和发射参数区分效果类型。

**目录**：`d:\game\2dHBGame\scenes\effects\`（已存在）

**新建文件**（6 个）：

| 文件路径 | 颜色（粒色 + 发光） | 发射参数 | 视觉描述 |
|---------|---------------------|---------|---------|
| `poison_fx.tscn` | 暗绿 `#7fff5f` | 短促向上漂、emission_sphere 直径 24 | 中毒气泡 |
| `burn_fx.tscn` | 橙红 `#ff7f3f` | 向上跃动、gravity y=-30 | 燃烧火苗 |
| `freeze_fx.tscn` | 冰蓝 `#7fcfff` | 缓慢向下落冰屑、低速度 | 冰冻结晶 |
| `paralysis_fx.tscn` | 紫黄 `#cfcfff` | 静电环绕（tangential_accel） | 麻痹电弧 |
| `invincible_fx.tscn` | 金白 `#fff7cf` | 持续环绕光环（emission_ring） | 无敌光环 |
| `stun_fx.tscn` | 亮黄 `#ffd700` | 围绕头顶星轨（emission_ring + 向上偏移 32px） | 眩晕星轨 |

**实现策略**：
- 用 GDScript 在 @tool 模式下生成（不依赖 Godot 编辑器手动操作）
- 或者直接写 `.tscn` 文本（更可控，避免脚本生成时的资源路径问题）
- 选择后者：手写 6 个 `.tscn` 文本文件，每个 ~30 行

**额外改进**：`_spawn_effect`（[buff_manager.gd](file:///d:/game/2dHBGame/scripts/combat/buff_manager.gd#L206-L216) L206-216）当 `effect_scene` 非空但 `ResourceLoader.exists` 失败时，从静默 return 改为 `push_warning`，让设计师在 Output 面板看到悬空引用：
```gdscript
func _spawn_effect(buff: BuffInstance) -> void:
	if buff.effect_scene.is_empty():
		return
	if not ResourceLoader.exists(buff.effect_scene):
		push_warning("Buff effect_scene 引用不存在: %s (buff_id=%d)" % [buff.effect_scene, buff.buff_id])
		return
	...
```

**图标**：`buff_icon_generator.gd` 已就绪并已注册菜单 id 11，本轮**不改代码**，仅验证其正确性（运行时由用户在 Godot 编辑器手动触发菜单生成 PNG）。

### Phase 3 — 注册表/策略模式重构

引入 `BuffEffectRegistry` 集中声明 5 种 effect type 的元数据，让 `buff_config` 解析与 `buff_editor` 表单生成通过注册表消费。**不新增 effect type**。

#### 3.1 新建 `BuffEffectRegistry`

**新文件**：`d:\game\2dHBGame\scripts\combat\buff_effect_registry.gd`

```gdscript
class_name BuffEffectRegistry
extends RefCounted

## Buff 效果类型注册表。集中声明 5 种 effect type 的元数据，
## 让 buff_config 解析与 buff_editor 表单生成统一从此消费。
## 新增 effect type 时只需在此 register 一处。

const STAT_OPTIONS := ["attack", "defense", "move_speed", "max_hp", "crit_rate", "crit_damage", "attack_speed"]
const MODE_OPTIONS := ["add", "mul", "set"]
const DAMAGE_TYPE_OPTIONS := ["physical", "fire", "poison", "true"]
const AFFECTS_OPTIONS := ["act", "move", "skill", "be_damaged"]


static func get_type_info(type_str: String) -> Dictionary:
	match type_str:
		"stat_modifier":
			return {
				"label": "属性修改",
				"fields": [
					{"name": "stat", "label": "属性", "kind": "option", "options": STAT_OPTIONS},
					{"name": "mode", "label": "模式", "kind": "option", "options": MODE_OPTIONS},
					{"name": "value", "label": "数值", "kind": "float", "min": -9999.0, "max": 9999.0, "step": 0.1},
				],
			}
		"dot":
			return {
				"label": "周期伤害 (DoT)",
				"fields": [
					{"name": "interval", "label": "间隔", "kind": "float", "min": 0.0, "max": 999.0, "step": 0.1},
					{"name": "damage", "label": "伤害", "kind": "int", "min": 0.0, "max": 99999.0, "step": 1.0},
					{"name": "damage_type", "label": "类型", "kind": "option", "options": DAMAGE_TYPE_OPTIONS},
				],
			}
		"hot":
			return {
				"label": "周期治疗 (HoT)",
				"fields": [
					{"name": "interval", "label": "间隔", "kind": "float", "min": 0.0, "max": 999.0, "step": 0.1},
					{"name": "heal", "label": "治疗", "kind": "int", "min": 0.0, "max": 99999.0, "step": 1.0},
				],
			}
		"shield":
			return {
				"label": "护盾",
				"fields": [
					{"name": "amount", "label": "吸收量", "kind": "int", "min": 0.0, "max": 99999.0, "step": 10.0},
				],
			}
		"control":
			return {
				"label": "控制效果",
				"fields": [
					{"name": "control_type", "label": "控制类型", "kind": "string"},
					{"name": "affects", "label": "影响行为", "kind": "checkbox_group", "options": AFFECTS_OPTIONS},
				],
			}
		_:
			return {}


static func get_all_types() -> Array:
	return ["stat_modifier", "dot", "hot", "shield", "control"]


## 把原始 JSON 字典解析为运行时字典（含 tick_timer/remaining 运行时字段）
static func parse_effect(raw: Dictionary) -> Dictionary:
	var type_str := String(raw.get("type", ""))
	var parsed := {"type": type_str}
	var info := get_type_info(type_str)
	for field in info.get("fields", []):
		var fname := String(field.name)
		var kind := String(field.get("kind", ""))
		match kind:
			"option":
				parsed[fname] = String(raw.get(fname, ""))
			"float":
				parsed[fname] = float(raw.get(fname, 0.0))
			"int":
				parsed[fname] = int(raw.get(fname, 0))
			"string":
				parsed[fname] = String(raw.get(fname, ""))
			"checkbox_group":
				var arr: Array = raw.get(fname, [])
				var arr_str: Array[String] = []
				for v in arr:
					arr_str.append(String(v))
				parsed[fname] = arr_str
	# 运行时字段（不在 schema 内，由 effect type 决定）
	match type_str:
		"dot", "hot":
			parsed["tick_timer"] = float(parsed.get("interval", 1.0))
		"shield":
			parsed["remaining"] = int(parsed.get("amount", 0))
	return parsed
```

#### 3.2 重构 `buff_config.gd` 使用注册表

**文件**：`d:\game\2dHBGame\scripts\data\buff_config.gd` L9-70

把 L27-57 的硬编码 `match parsed["type"]` 替换为 `BuffEffectRegistry.parse_effect(e)`：

```gdscript
const BuffEffectRegistry = preload("res://scripts/combat/buff_effect_registry.gd")

func load_config() -> void:
	...
	for effect in effects_raw:
		if effect is Dictionary:
			effects.append(BuffEffectRegistry.parse_effect(effect as Dictionary))
	...
```

行为不变，仅把硬编码 switch 改为注册表查询。

#### 3.3 重构 `buff_editor.gd` 表单生成使用注册表

**文件**：`d:\game\2dHBGame\addons\game_tools\buff_editor.gd` L301-379

把 `_make_effect_row` 的 `EFFECT_TYPES` 常量（L8-14）改为从 `BuffEffectRegistry.get_all_types()` 派生，把 `_populate_effect_fields` 的硬编码 `match` 改为遍历 `BuffEffectRegistry.get_type_info(type_str).fields` 动态生成控件。

保留 `STAT_OPTIONS` / `MODE_OPTIONS` / `DAMAGE_TYPE_OPTIONS` / `AFFECTS_OPTIONS` 常量从 `buff_editor.gd` 移除，统一从 `BuffEffectRegistry` 引用。

**风险控制**：`_populate_effect_fields` 当前的 `_add_field_option` / `_add_field_spin` / `_add_field_edit` 工厂方法保留，仅在调用处改为遍历 fields 数组按 kind 分发。`control` 的 `affects` checkbox_group 用现有 `_on_affects_toggled` 回调保留。

#### 3.4 `buff_instance.gd` / `buff_manager.gd` 保持不变

`BuffInstance.get_dot_effects()` / `get_hot_effects()` / `get_shield_effects()` / `has_control_affect()` 是简单 `filter` 调用，已经够通用，本轮不动。`BuffManager._process` 的 DoT/HoT 消费逻辑也不动。这两个文件的"消费方"逻辑保持原样，注册表只解决"声明方"的重复问题。

## 假设与决策

### 假设
1. `party_member_stats.gd` L11 `move_speed` 是公开字段（已读源码确认）
2. 当前 30 条 buff 无一使用 `stack_behavior: "independent"`（已 grep 确认）
3. `BuffManager.get_speed_multiplier()` 全代码库无调用方（已 grep 确认）
4. 6 个悬空 `effect_scene` 路径在 `assets/effects/` 下确实不存在（已 LS 确认）
5. `buff_icon_generator.gd` 已就绪（已读源码，无需改动）

### 决策
1. **不修复 damage_type 丢失问题**：用户明确排除元素抗性系统，且修复需改 take_damage 签名（4-arg），破坏面广。留作下轮专题。
2. **不实现 HoT 受 attack 加成 / 暴击**：当前 HoT 是固定值，与设计意图一致，不在本轮范围。
3. **CPUParticles2D 而非 GPUParticles2D**：保证 @tool 模式与低端机兼容，性能对本场景足够。
4. **手写 .tscn 文本而非脚本生成**：避免 @tool 模式下 ResourceSaver 时机问题，6 个场景体积小（每个 ~30 行），手写更可控。
5. **注册表只重构声明方**：`buff_instance` / `buff_manager` 的消费方逻辑不动，避免一次性改动面过大。
6. **`independent` 实现 B4 而非删除选项**：让 BuffEditor 下拉真正可用，比删选项更符合"完善"语义。

## 验证步骤

### 1. 运行时 Bug 修复验证

- **B1**：在 Godot 编辑器运行项目，玩家移动不崩溃；施加移速 buff（如 1105 速度强化）后实际移速变化
- **B2**：施加 1005 无敌或 1111 强效护盾 buff，等护盾吸收耗尽后再次施加，确认 `remaining` 被重置为 `amount`
- **B3**：`grep -rn "get_speed_multiplier" scripts/ addons/` 应返回 0 行
- **B4**：把某 buff 的 `stack_behavior` 改为 `independent`，连续施加 3 次，确认 `_buffs` 数组里有 3 个独立 BuffInstance（duration 各自独立倒计时）

### 2. 视觉资产补齐验证

- 6 个 `.tscn` 文件存在于 `assets/effects/` 下
- 运行时施加 1001/1002/1003/1004/1005/1006 buff，确认对应特效节点被 `_spawn_effect` 实例化并添加到角色下
- 故意把某 buff 的 `effect_scene` 改为不存在的路径，确认 Output 面板出现 `push_warning` 文字（而非静默跳过）

### 3. 注册表重构验证

- `BuffEffectRegistry` 文件存在，`get_all_types()` 返回 5 项，`get_type_info("stat_modifier")` 返回非空
- `buff_config.load_config()` 加载 `data/buffs.json` 后 `_buffs.size() == 30`，每条 buff 的 effects 数组与重构前结构等价（重点对比 `tick_timer` / `remaining` 运行时字段是否被正确初始化）
- `buff_editor` 打开后左侧列表显示 30 条，右侧选择不同 effect type 时表单字段与重构前一致（5 种 type 都能正确渲染控件）
- 在 BuffEditor 里编辑某 buff 的 effect 字段并保存，重新加载后值正确持久化

### 4. 静态检查

- `grep -rn "get_speed_multiplier" scripts/ addons/` → 0 行（B3 已删）
- `grep -rn "_get_move_speed" scripts/player.gd` → 5 处调用，定义 L310 不再自调用
- `grep -rn "stack_behavior.*independent" data/buffs.json` → 当前 0 处（确认 B4 不影响现有数据）
- `grep -rn "EFFECT_TYPES" addons/game_tools/buff_editor.gd` → 0 行（已迁移到注册表）

## 执行顺序

按 Phase 1 → 2 → 3 顺序执行。Phase 1 是纯 Bug 修复，风险最低；Phase 2 是新增资源文件，独立于代码；Phase 3 是重构，最后做避免影响前两步的验证。
