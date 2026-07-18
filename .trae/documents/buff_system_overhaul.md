# Buff 系统重构计划

## 概述

将现有硬编码的 buff 系统重构为**数据驱动的效果系统**，新增独立 buff 编辑器工具，扩展角色属性（暴击率/暴击伤害/攻击速度），并在战斗 HUD 上显示 buff 图标/计时器/层数。

## 现状分析

### 现有 Buff 架构
- `BuffConfig` 从 `res://data/buffs.json` 加载 7 个 buff（1001-1007），字段为扁平结构（type/duration/interval/tick_damage/slow_ratio/max_stacks/effect_scene）
- `BuffManager` 硬编码了 5 种类型检查：`can_act()` 查 stun/freeze，`can_move()` 查 paralysis，`modify_damage()` 查 invincible，`get_speed_multiplier()` 查 slow，DoT 用 interval+tick_damage
- `BuffInstance` 存储 stacks/remaining/tick_timer，`add_stack()` 叠层并刷新持续时间
- 技能节点 `apply_target_buff`/`apply_self_buff` 仅引用 `buff_id`，不能编辑 buff 本体
- 无 buff 编辑器，只能手动编辑 JSON
- `battle_hud.gd` 未连接 buff 信号，无 buff 图标显示
- 1001 中毒 `tick_damage: 0.1` 被 `int()` 截断为 0（bug）

### 角色属性系统
- 三个互不继承的属性对象：`PartyMemberStats`、`EnemyStats`、`CharacterStats`
- 仅 5 个属性：max_hp/hp/attack/defense/move_speed
- 无暴击、攻速、穿透、抗性等 RPG 属性
- 伤害公式：`calculate_damage = max(1, round(attack * ratio))` → `take_damage: max(1, amount - defense)`

### 战斗 HUD
- `battle_hud.gd`（CanvasLayer）全代码构建 UI
- 主控卡片左上角（282×96），含头像/名字/HP条/蓝条/等级
- 队友卡片列表在主控下方
- 敌人面板顶部中央
- 技能槽底部中央
- 右上角入口按钮

## 改动计划

### 第 1 步：迁移 buffs.json 到新格式

**文件**: `data/buffs.json`

将扁平结构迁移为 `effects` 数组结构。每个 buff 新增 `category`（buff/debuff）、`description`、`icon`、`stack_behavior` 字段。

**效果类型定义**：
- `stat_modifier` — 修改属性（stat/mode/value），mode = add|mul|set
- `dot` — 周期伤害（interval/damage/damage_type）
- `hot` — 周期治疗（interval/heal）
- `shield` — 护盾吸收（amount）
- `control` — 控制效果（control_type/affects[]），affects = act|move|skill|be_damaged

**迁移后的 7 个原 buff + 4 个新示例 buff**：

```json
{
  "1001": {
    "name": "中毒", "description": "每秒受到毒伤害，可叠加5层",
    "category": "debuff", "duration": 5, "max_stacks": 5,
    "stack_behavior": "stack", "icon": "", "effect_scene": "res://assets/effects/poison_fx.tscn",
    "effects": [{"type": "dot", "interval": 1.0, "damage": 5, "damage_type": "poison"}]
  },
  "1002": { ... "effects": [{"type": "dot", "interval": 0.5, "damage": 8, "damage_type": "fire"}] },
  "1003": { ... "effects": [{"type": "control", "control_type": "freeze", "affects": ["act", "move"]}] },
  "1004": { ... "effects": [{"type": "control", "control_type": "paralysis", "affects": ["move"]}] },
  "1005": { ... "effects": [{"type": "control", "control_type": "invincible", "affects": ["be_damaged"]}] },
  "1006": { ... "effects": [{"type": "control", "control_type": "stun", "affects": ["act", "move", "skill"]}] },
  "1007": { ... "effects": [{"type": "stat_modifier", "stat": "move_speed", "mode": "mul", "value": 0.5}] },
  "1101": { "name": "攻击强化", "category": "buff", "duration": 10, "effects": [{"type": "stat_modifier", "stat": "attack", "mode": "mul", "value": 1.3}] },
  "1102": { "name": "防御强化", "category": "buff", "duration": 10, "effects": [{"type": "stat_modifier", "stat": "defense", "mode": "mul", "value": 1.5}] },
  "1103": { "name": "沉默", "category": "debuff", "duration": 3, "effects": [{"type": "control", "control_type": "silence", "affects": ["skill"]}] },
  "1104": { "name": "护盾", "category": "buff", "duration": 10, "effects": [{"type": "shield", "amount": 100}] }
}
```

### 第 2 步：更新 BuffConfig 加载新格式

**文件**: `scripts/data/buff_config.gd`

- 解析 `effects` 数组（每个 effect 是一个 Dictionary）
- 解析新字段 `category`、`description`、`icon`、`stack_behavior`
- 保持 `get_buff(id)` / `get_all_buffs()` / `is_valid_buff(id)` 接口不变
- 新增 `get_buffs_by_category(category: String) -> Array` 方法

### 第 3 步：重构 BuffInstance 支持效果系统

**文件**: `scripts/combat/buff_instance.gd`

- 新增字段：`effects: Array`、`category: String`、`icon: String`、`stack_behavior: String`
- `_init` 从 config 解析 effects 数组
- shield 效果的运行时状态：在 effect dict 中增加 `remaining` 字段（初始 = amount）
- `is_dot()` 改为遍历 effects 查找 dot 类型
- `add_stack()` 逻辑不变（叠层+刷新时间）
- 新增 `get_dot_effects() -> Array` 返回所有 dot 效果
- 新增 `get_shield_remaining() -> int` 返回剩余护盾量

### 第 4 步：重构 BuffManager 为数据驱动

**文件**: `scripts/combat/buff_manager.gd`

替换所有硬编码类型检查，改为遍历 effects 查询：

- `can_act() -> bool`：遍历 effects，有 `control` 且 `affects` 含 `"act"` 则返回 false
- `can_move() -> bool`：can_act 为假返回 false；有 control 且 affects 含 `"move"` 返回 false
- `can_use_skill() -> bool`：can_act 为假返回 false；有 control 且 affects 含 `"skill"` 返回 false
- `is_invincible() -> bool`：有 control 且 affects 含 `"be_damaged"`
- `get_speed_multiplier() -> float`：遍历 `stat_modifier` 效果中 stat=move_speed 的 mul 值
- `get_modified_stat(stat_name: String, base_value: float) -> float`：遍历所有 buff 的 stat_modifier 效果，按 add→mul→set 顺序应用
- `modify_damage(incoming: int) -> int`：先查 invincible（返回 0），再扣 shield
- DoT 处理在 `_process` 中：遍历每个 buff 的 dot 效果，按 interval 跳 damage * stacks
- 新增 `dispel(category: String, count: int = -1)` 方法：移除指定类别的 buff（-1 = 全部）
- 信号保持不变：`buff_applied`/`buff_removed`/`buff_ticked`

### 第 5 步：扩展角色属性系统

**文件**：
- `scripts/combat/party_member_stats.gd`
- `scripts/combat/enemy_stats.gd`
- `scripts/data/character_stats.gd`

三个文件统一新增 3 个字段：
```gdscript
var crit_rate: float = 0.0       # 暴击率 0.0~1.0
var crit_damage: float = 1.5     # 暴击伤害倍率（1.5 = 150%）
var attack_speed: float = 1.0    # 攻击速度倍率（影响技能冷却）
```

- `PartyMemberStats.recalculate()` 中从 character_config 的 base_stats 读取（若无则用默认值）
- `EnemyStats._init()` 中从 enemies.json 读取（若无则用默认值）
- `CharacterStats` 的 recalculate 同理
- `plugin.gd` 的 `_default_character_base_stats()` 新增 crit_rate/crit_damage/attack_speed 默认值

### 第 6 步：CombatComponent 集成新属性和 Buff 查询

**文件**: `scripts/combat/combat_component.gd`

**伤害计算增强**：
- `take_damage` 中 `_buff_manager.modify_damage(amount)` 不变（内部已改为数据驱动）
- `apply_buff_from_config` 中，检查 control 效果的 affects 是否含 act/skill，若含则 `cancel_cast`

**技能施放增强**：
- `try_use_skill` 中新增 `_buff_manager.can_use_skill()` 检查（沉默时不能放技能）
- `_cooldowns[skill_id]` 除以 attack_speed：`_cooldowns[skill_id] = cooldown / attack_speed`

**属性查询**：
- 所有使用 `_stats.attack` / `_stats.defense` 的地方，改为通过 `_buff_manager.get_modified_stat("attack", _stats.attack)` 获取

**SkillExecutor 伤害计算增强**：

**文件**: `scripts/combat/skill_executor.gd`

- `calculate_damage(ratio)` 中：
  1. 取 attack = `_buff_manager.get_modified_stat("attack", _stats.attack)`
  2. 计算 base_damage = `max(1, round(attack * ratio))`
  3. 取 crit_rate = `_buff_manager.get_modified_stat("crit_rate", _stats.crit_rate)`
  4. `if randf() < crit_rate:` 取 crit_damage = `_buff_manager.get_modified_stat("crit_damage", _stats.crit_damage)`，damage *= crit_damage
  5. 返回 `roundi(damage)`

### 第 7 步：创建 Buff 编辑器工具

**新文件**: `addons/game_tools/buff_editor.gd`

`@tool extends Window`，UI 布局参考 `skill_sequence_editor.gd`：

**左侧栏**（宽 200）：
- Buff 列表（ItemList），显示 `ID + 名称 + 类别颜色`（buff 绿色/debuff 红色）
- "新增 Buff" 按钮
- "删除 Buff" 按钮

**右侧面板**：
- 基本信息 GridContainer：
  - 名称（LineEdit）
  - 描述（TextEdit，2行高）
  - 类别（OptionButton: buff/debuff）
  - 持续时间（SpinBox）
  - 最大层数（SpinBox）
  - 叠加方式（OptionButton: stack/refresh/independent）
  - 图标路径（LineEdit + 文件选择按钮）
  - 特效场景（LineEdit + 文件选择按钮）
- 效果列表（VBoxContainer）：
  - 每个效果一行，含效果类型（OptionButton）+ 类型特定字段
  - "添加效果" 按钮
  - "删除效果" 按钮（每行一个）
- 效果类型表单：
  - `stat_modifier`: stat（OptionButton: attack/defense/move_speed/max_hp/crit_rate/crit_damage/attack_speed）+ mode（OptionButton: add/mul/set）+ value（SpinBox）
  - `dot`: interval（SpinBox）+ damage（SpinBox）+ damage_type（OptionButton: physical/fire/poison/true）
  - `hot`: interval（SpinBox）+ heal（SpinBox）
  - `shield`: amount（SpinBox）
  - `control`: control_type（LineEdit）+ affects（多选: act/move/skill/be_damaged）
- 保存按钮 → 写入 `res://data/buffs.json`
- 保存成功浮层提示（复用 level_editor 的模式）

### 第 8 步：插件注册 Buff 编辑器

**文件**: `addons/game_tools/plugin.gd`

- 新增 `const BuffEditor = preload("res://addons/game_tools/buff_editor.gd")`
- 新增 `var _buff_editor: Window`
- 菜单新增 `_submenu.add_item("配置 Buff...", 10)`
- `_on_menu_pressed` 新增 `case 10: _open_buff_editor()`
- `_open_buff_editor()` 方法
- `_exit_tree` 中 free buff_editor

### 第 9 步：技能编辑器集成 Buff 选择

**文件**: `addons/game_tools/skill_sequence_editor.gd`

- `_build_target_buff_fields` 和 `_build_self_buff_fields` 中，把 `buff_id` 的 SpinBox 改为 OptionButton
  - 选项从 `GameRegistry.buff_config.get_all_buffs()` 动态加载
  - 显示格式：`1001 - 中毒`（ID + 名称）
  - 若 GameRegistry 不可用（@tool 模式），直接从 `res://data/buffs.json` 读取
- `_build_damage_fields` 中的附加 `buff_id` / `buff_chance` 也改用同样的 OptionButton
- 保存时 OptionButton 的 selected ID 转回 int 写入 JSON

### 第 10 步：战斗 HUD 显示 Buff 图标

**文件**: `scripts/ui/battle_hud.gd`

**主控卡片 buff 条**：
- 在主控卡片（`_build_main_card`）的信息区下方新增 HBoxContainer `_main_buff_bar`
- buff 图标尺寸 24×24，间距 2px
- buff 排列：buff（增益）在左，debuff（减益）在右，中间用分隔
- 每个图标元素：
  - TextureRect 显示 buff icon（若无 icon 则显示名称首字的 Label）
  - 右下角层数角标（>1 时显示）
  - 底部进度条（remaining/duration 比例）
  - Tooltip 显示 buff 名称 + 描述 + 剩余时间

**连接 buff 信号**：
- `_connect_active_combat` 中，获取 `_active_character.get_node_or_null("CombatComponent")` 的 `BuffManager`
- 连接 `buff_applied` / `buff_removed` / `buff_ticked` 信号到 `_on_buff_changed`
- `_on_buff_changed` 触发 `_refresh_main_buffs()` 重建 buff 图标行

**敌人面板 buff 条**（可选，若敌人面板有空间）：
- 在敌人面板 `_enemy_info_label` 下方新增 debuff 图标行
- 从敌人节点的 CombatComponent → BuffManager 获取 active buffs

**刷新逻辑**：
- `_refresh_all()` 中调用 `_refresh_main_buffs()`
- `_refresh_main_buffs()` 遍历 `_active_combat.get_buff_manager().get_active_buffs()`，为每个 buff 创建图标元素

## 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `data/buffs.json` | 修改 | 迁移到 effects 数组格式 + 4 个新 buff |
| `scripts/data/buff_config.gd` | 修改 | 解析新格式，新增 get_buffs_by_category |
| `scripts/combat/buff_instance.gd` | 修改 | 新增 effects/category/icon/stack_behavior 字段 |
| `scripts/combat/buff_manager.gd` | 修改 | 数据驱动查询替换硬编码，新增 get_modified_stat/dispel/can_use_skill |
| `scripts/combat/party_member_stats.gd` | 修改 | 新增 crit_rate/crit_damage/attack_speed |
| `scripts/combat/enemy_stats.gd` | 修改 | 新增 crit_rate/crit_damage/attack_speed |
| `scripts/data/character_stats.gd` | 修改 | 新增 crit_rate/crit_damage/attack_speed |
| `scripts/combat/combat_component.gd` | 修改 | can_use_skill 检查、attack_speed 影响冷却、属性查询改用 get_modified_stat |
| `scripts/combat/skill_executor.gd` | 修改 | calculate_damage 增加暴击逻辑 |
| `addons/game_tools/buff_editor.gd` | 新建 | Buff 编辑器工具 |
| `addons/game_tools/plugin.gd` | 修改 | 注册 buff 编辑器菜单 |
| `addons/game_tools/skill_sequence_editor.gd` | 修改 | buff_id 改为 OptionButton 下拉选择 |
| `scripts/ui/battle_hud.gd` | 修改 | 新增 buff 图标行显示 |
| `scripts/combat/skill_executor.gd` | 修改 | apply_target_buff/apply_self_buff 使用新 buff_config 接口 |

## 假设与决策

1. **向后兼容**：迁移后旧 buffs.json 格式不再支持（一次性迁移，非渐进式）
2. **damage_type 暂不接入抗性系统**：dot 的 damage_type 字段仅记录，不影响计算（未来扩展用）
3. **暴击最小伤害仍为 1**：暴击后 damage = round(damage * crit_damage)，最终 take_damage 仍 max(1, amount - defense)
4. **attack_speed 仅影响技能冷却**：不影响动画播放速度（避免动作错乱）
5. **buff icon 暂用文字占位**：buff JSON 的 icon 字段为空时，HUD 显示 buff 名称首字
6. **shield 效果不叠加**：同 ID shield buff 叠层时刷新 duration，shield remaining 取 max（不累加）
7. **stack_behavior**：stack = 叠层（最多 max_stacks）；refresh = 仅刷新时间不变层数；independent = 独立实例（暂不实现，留接口）
8. **EnemyStats 新增属性默认值**：crit_rate=0, crit_damage=1.5, attack_speed=1.0（怪物默认无暴击）

## 验证步骤

1. **编译检查**：所有修改后的 .gd 文件无编译错误
2. **buff 编辑器**：打开"配置 Buff..."，能看到 11 个 buff，编辑后保存成功
3. **技能编辑器**：apply_target_buff 节点的 buff_id 下拉显示 buff 名称
4. **运行时验证**：
   - 中毒 buff 实际造成伤害（tick_damage=5，不再被截断为 0）
   - 减速 buff 通过 stat_modifier 降低移速
   - 无敌 buff 通过 control/be_damaged 免伤
   - 沉默 buff 阻止技能释放
   - 护盾 buff 吸收伤害
   - 暴击率/暴击伤害生效
   - attack_speed 缩短技能冷却
5. **HUD 验证**：主控卡片下方显示 buff 图标，有计时进度和层数角标
