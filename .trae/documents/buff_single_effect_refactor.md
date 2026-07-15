# Buff 系统单 Effect 重构计划

## 摘要

将当前"一个 buff 持有 effects 数组"的设计重构为"一个 buff 持有单个 effect"，贯彻"一 buff 一 effect"原则。同时把所有技能节点的 `buff_id` 单值字段统一为 `buff_ids` 数组（自身/目标/伤害附带 buff 三类节点对等），让"组合效果"由技能节点同时施加多个 buff_id 来实现，而不是把多个 effect 塞进一个 buff。

## 当前状态分析

### 数据现状（`data/buffs.json`）
- 31 条 buff，其中 24 条单 effect（77.4%），7 条多 effect（22.6%）
- 多 effect buff 清单：
  - 1009 腐蚀（dot poison + defense mul 0.8）— 异质耦合
  - 1014 迟缓（move_speed 0.7 + attack_speed 0.8）— 同质多属性
  - 1015 虚弱（attack 0.7 + defense 0.7）— 同质多属性
  - 1109 神力（attack 1.5 + defense 1.2）— 同质多属性
  - 1203 狂暴（attack 1.5 + defense 0.7 + crit_rate +0.1）— 同质多属性
  - 1204 圣盾（shield 200 + hot heal 5）— 异质耦合
  - 1205 战斗狂热（attack_speed 1.4 + crit_rate +0.15）— 同质多属性

### 代码现状
- `buff_instance.gd`：`var effects: Array`，6 个方法（`get_dot_effects`/`get_hot_effects`/`get_shield_effects`/`has_control_affect`/`get_shield_remaining`/`_reset_shield_remaining`）遍历 effects 数组
- `buff_manager.gd`：`_process`（DoT/HoT 双层遍历）、`get_modified_stat`（三段式双层遍历）、`modify_damage`（shield 双层遍历）、`can_act`/`can_move`/`can_use_skill`/`is_invincible`（外层遍历 _buffs 调用 `has_control_affect`）
- `buff_config.gd`：`load_config` for 循环解析 effects 数组
- `buff_effect_registry.gd`：`parse_effect`/`make_default_effect`/`get_type_info` 已是单 effect 语义，**无需改动**
- `buff_editor.gd`：列表式 effect 表单（`_effects_container` + "添加效果"按钮 + 每行 × 删除 + 下标维护）
- `skill_executor.gd`：
  - `apply_self_buff`（L71-89）已支持 `buff_ids` 数组
  - `apply_target_buff`（L55-68）只读 `buff_id` 单值
  - `_apply_optional_buff`（L331-335）只读 `buff_id` + `buff_chance`
  - `_spawn_straight`/`_spawn_ballistic`（L241, L263）传递 `buff_id` 给 projectile
- `skills.json`：7 条多 effect buff **目前没有任何技能引用**（只 1001 中毒和 1108 攻速强化被引用）
- `battle_hud.gd`：只读 buff 顶层字段，**零改动**（接受多图标副作用）

## 改动方案

### Step 1：数据层重构（`data/buffs.json` + `scripts/data/buff_config.gd`）

#### 1.1 拆分 `data/buffs.json` 的 7 条多 effect buff

把每条多 effect buff 的主 effect 留在原 id，副 effect 拆为新增 id。新 id 分配：

| 原 buff | 拆分后 |
|---|---|
| 1009 腐蚀 | 1009 腐蚀(DoT: dot poison dmg4 interval1.0) + 1017 腐蚀·破甲(stat_modifier defense mul 0.8) |
| 1014 迟缓 | 1014 迟缓·减速(move_speed mul 0.7) + 1018 迟缓·钝滞(attack_speed mul 0.8) |
| 1015 虚弱 | 1015 虚弱·减攻(attack mul 0.7) + 1019 虚弱·破防(defense mul 0.7) |
| 1109 神力 | 1109 神力·加攻(attack mul 1.5) + 1110 神力·坚壁(defense mul 1.2) |
| 1203 狂暴 | 1203 狂暴·加攻(attack mul 1.5) + 1020 狂暴·减防(defense mul 0.7) + 1021 狂暴·暴击(crit_rate add 0.1) |
| 1204 圣盾 | 1204 圣盾·护盾(shield 200) + 1206 圣盾·回复(hot heal 5 interval 1.0) |
| 1205 战斗狂热 | 1205 战斗狂热·加攻速(attack_speed mul 1.4) + 1207 战斗狂热·暴击(crit_rate add 0.15) |

新增 8 条 buff，总数 31 → 39。新 buff 的 duration/max_stacks/stack_behavior/category/icon/effect_scene 与原 buff 一致（便于技能用 buff_ids 同时施加时生命周期同步）。description 改为单一效果描述。

#### 1.2 数据格式：`effects` (Array) → `effect` (Dictionary)

所有 39 条 buff 的 `"effects": [...]` 字段改为 `"effect": {...}`（单数，直接是 Dictionary，不是单元素数组）。

#### 1.3 `scripts/data/buff_config.gd` 简化解析

- `load_config`：去掉 for 循环，直接 `var effect_raw = raw.get("effect", {})` → `var effect = BuffEffectRegistry.parse_effect(effect_raw)` → 存入 `buff["effect"]`
- 兼容期：若读到 `effects` 字段（旧格式），取 `[0]` 作为 `effect`，便于过渡

### Step 2：运行时层重构（`buff_instance.gd` + `buff_manager.gd`）

#### 2.1 `scripts/combat/buff_instance.gd`

- `var effects: Array = []` → `var effect: Dictionary = {}`
- `_init`：直接 `effect = BuffEffectRegistry.parse_effect(config.get("effect", config.get("effects", [{}])[0]))`
- `is_dot()` → `return effect.get("type", "") == "dot"`
- `get_dot_effects() -> Array` → `get_dot_effect() -> Dictionary`（返回 `effect` if type=="dot" else `{}`）
- `get_hot_effects() -> Array` → `get_hot_effect() -> Dictionary`
- `get_shield_effects() -> Array` → `get_shield_effect() -> Dictionary`
- `get_shield_remaining() -> int`：直接读 `effect.get("remaining", 0)`（去掉 for）
- `has_control_affect(affect) -> bool`：`return effect.get("type") == "control" and affect in effect.get("affects", [])`
- `_reset_shield_remaining()`：直接 `effect["remaining"] = effect.get("amount", 0)`（去掉 for）
- 移除 `get_dot_effects`/`get_hot_effects`/`get_shield_effects` 三个返回数组的方法（或保留为弃用别名返回单元素数组，便于过渡——建议直接删除，调用方全改）

#### 2.2 `scripts/combat/buff_manager.gd`

- `_process`（L16-41）：内层 `for effect in buff.get_dot_effects()` 移除，改为 `var effect = buff.get_dot_effect()` + `if not effect.is_empty():` 判空后执行 DoT tick 逻辑；HoT 同理
- `get_modified_stat`（L142-165）：三段式（add→mul→set）各去掉内层 for，改为直接判断 `buff.effect.type == "stat_modifier" and buff.effect.stat == stat_name and buff.effect.mode == "add/mul/set"`
- `modify_damage`（L168-183）：内层 `for effect in buff.get_shield_effects()` 移除，改为 `var effect = buff.get_shield_effect()` + 判空后扣减 `effect["remaining"]`
- `can_act`/`can_move`/`can_use_skill`/`is_invincible`（L110-139）：外层遍历 `_buffs` 保留，`buff.has_control_affect(...)` 内部已简化，调用方无需改
- `remove_buff_by_type`/`has_buff_type`（L67, L90）：外层遍历 `_buffs` 保留，内部判断 `buff.effect.control_type == type_name`（去掉对 effects 数组的隐式遍历）

### Step 3：编辑器重构（`addons/game_tools/buff_editor.gd`）

把 effect 编辑从"列表式"退化为"单例表单"。

#### 3.1 移除列表式 UI

- 删除 `_effects_container: VBoxContainer` 字段
- 删除 `_refresh_effects(Array)`、`_make_effect_row(Dictionary)`、`_on_add_effect`、`_on_delete_effect`
- 删除"效果列表"标题 Label + "添加效果"按钮（`effects_header`）
- `_on_effect_type_changed` 的 row 下标维护逻辑删除，但保留"改类型时重建字段"的行为

#### 3.2 新增单 effect 表单

在 `info_grid` 下方（描述框上方）插入 effect 表单区域：

```
[效果类型 OptionButton]
[动态字段区域 FieldsContainer（HBoxContainer 或 GridContainer）]
```

- 新增字段 `_effect_type_option: OptionButton` + `_effect_fields_container: HBoxContainer`
- `_refresh_effect(effect: Dictionary)`：设置 `_effect_type_option` 选中 + 调用 `_populate_effect_fields(_effect_fields_container, effect)` 重建字段
- `_show_buff_details` 末尾调用 `_refresh_effect(buff.get("effect", {}))`
- `_on_effect_type_changed`：用 `BuffEffectRegistry.make_default_effect(new_type)` 替换 `_buffs[_selected_id]["effect"]`，调用 `_refresh_effect` 重建字段
- 字段变更回调（`_on_effect_field_option_changed`/`_on_effect_field_spin_changed`/`_on_effect_field_text_changed`/`_on_affects_toggled`）去掉 `row.get_index()` 下标逻辑，直接写 `_buffs[_selected_id]["effect"][field_name] = new_value`
- 保存时 `_buffs[_selected_id]["effect"]` 写入 JSON 的 `"effect"` 键（不再是 `"effects"` 数组）

#### 3.3 `_add_buff` 默认值

新增 buff 时 `effect` 字段默认为 `BuffEffectRegistry.make_default_effect("stat_modifier")`（不再是 `effects: []`）。

### Step 4：技能节点统一为 buff_ids 数组

#### 4.1 `scripts/combat/skill_executor.gd`

- `apply_target_buff(node, hurt_box)`（L55-68）：改为读 `buff_ids` 数组（回退兼容 `buff_id` 单值），循环 `get_buff(id)` + `apply_buff_from_config`
- `_apply_optional_buff(node, hurt_box)`（L331-335）：改为读 `buff_ids` 数组 + `buff_chance`，每个 id 独立掷骰（或共享一次掷骰？建议共享 `buff_chance` 一次掷骰，通过则施加全部 `buff_ids`，保持"附 buff 概率"语义）
- `_spawn_straight`/`_spawn_ballistic`/projectile setup：把 `buff_id` 参数改为 `buff_ids` 数组，projectile 击中时循环施加

#### 4.2 `addons/game_tools/skill_sequence_editor.gd`

- `apply_target_buff` 节点的表单：复用 `_build_self_buff_fields` 的模式（Label "Buff IDs" + VBoxContainer + 每行 OptionButton + × + 底部"添加 Buff"按钮）。把 `_build_self_buff_fields` 改名为 `_build_buff_ids_fields(form, node, field_name="buff_ids")` 通用化，`apply_self_buff` 和 `apply_target_buff` 都调用它。
- `melee_damage` / `area_damage` / `spawn_projectile` 节点的附带 buff 表单：当前是单 `buff_id` OptionButton + `buff_chance` SpinBox。改为 `buff_ids` 数组表单（同上）+ `buff_chance` SpinBox 保留。把 `_build_buff_ids_fields` 扩展支持"附带 buff_chance"模式，或单独新增 `_build_optional_buff_fields`。
- 节点默认值与模板：`buff_id: 0` → `buff_ids: []`；`apply_target_buff` 模板同步改
- 数据迁移：打开节点时若仍是旧 `buff_id` 字段，自动转为 `buff_ids` 数组（保留旧值），删除 `buff_id` 键

#### 4.3 `data/skills.json` 数据迁移

现有技能数据：
- 2001 史莱姆普攻 melee_damage `buff_id: 1001` → `buff_ids: [1001]`
- 2002 酸液喷射 spawn_projectile `buff_id: 1001` → `buff_ids: [1001]`
- 2003 毒雾爆发 area_damage `buff_id: 1001` → `buff_ids: [1001]`
- 某技能 apply_self_buff `buff_id: 0` → `buff_ids: []`
- 某技能 apply_self_buff `buff_id: 1108` → `buff_ids: [1108]`

直接改 JSON 数据（编辑器自动迁移逻辑作为兜底）。

### Step 5：projectile 传参链路

`skill_executor._spawn_straight`/`_spawn_ballistic` → projectile.gd 的 setup → projectile 击中时 `apply_buff_from_config`。把整条链路的 `buff_id: int` 参数改为 `buff_ids: Array`，projectile 击中时循环施加。

## 假设与决策

1. **全量拆分**：7 条多 effect buff 全部拆分，新增 8 条 buff，总数 31 → 39。包括 5 条同质多属性捆绑（接受 HUD 多图标副作用）。
2. **HUD 不合并**：接受"狂暴"显示 3 个图标的副作用，不引入 buff 组机制。
3. **目标侧全扩展**：`apply_target_buff` + `melee_damage`/`area_damage`/`spawn_projectile` 附带 buff 全部改为 `buff_ids` 数组。
4. **数据格式直接改**：`"effects": Array` → `"effect": Dictionary`（不保留过渡兼容层，一次性改干净）。`buff_config.load_config` 兼容旧 `effects` 字段取 `[0]` 作为兜底。
5. **`buff_effect_registry.gd` 不动**：已是单 effect 语义，无需改动。
6. **`battle_hud.gd` 不动**：只读 buff 顶层字段，零改动。
7. **`buff_id` 单值字段废弃**：所有技能节点统一用 `buff_ids` 数组，运行时和编辑器都兼容旧 `buff_id` 单值作为迁移兜底。
8. **buff_chance 共享**：`melee_damage` 等节点的 `buff_chance` 掷骰一次，通过则施加全部 `buff_ids`（不每个 id 独立掷骰）。

## 验证步骤

1. **数据解析**：`buff_config.load_config()` 加载 39 条 buff，无 JSON 错误，每条都有 `effect` 字段（非 `effects` 数组）
2. **运行时**：
   - `buff_manager.apply_buff(1001)` 施加中毒 DoT，`_process` 每秒跳伤害
   - `buff_manager.apply_buff(1009)` + `apply_buff(1017)` 同时施加腐蚀 DoT + 破甲，defense 降低
   - `buff_manager.get_modified_stat("attack", base)` 遍历所有 buff 的单 effect 正确叠加
   - `buff_manager.modify_damage(dmg)` 遍历所有 buff 的 shield effect 正确吸收
   - `buff_manager.can_move()` 遍历所有 buff 的 control effect 正确判断
3. **编辑器**：
   - `buff_editor.gd` 打开后右侧显示单一 effect 类型下拉 + 动态字段，无"添加效果"/"×"按钮
   - 切换 effect 类型时字段重建
   - 保存后 `buffs.json` 的 `"effect"` 字段正确写入
4. **技能编辑器**：
   - `apply_self_buff` / `apply_target_buff` 节点显示 buff_ids 数组表单
   - `melee_damage` / `area_damage` / `spawn_projectile` 节点的附带 buff 显示 buff_ids 数组 + buff_chance
   - 旧 `buff_id` 数据打开时自动迁移为 `buff_ids` 数组
5. **技能执行**：
   - 技能 2001 史莱姆普攻 30% 概率施加中毒（buff_ids: [1001]）
   - 技能节点 `buff_ids: [1009, 1017]` 同时施加腐蚀 DoT + 破甲
6. **静态检查**：grep 确认无残留 `get_dot_effects`/`get_hot_effects`/`get_shield_effects` 调用，无 `effects` 数组字面量（除兼容层），无 `buff_id` 单值字段引用（除迁移兜底）

## 实施顺序

1. Step 1.1 + 1.2：拆分 buffs.json 数据 + 改 `effects` → `effect` 格式
2. Step 1.3：改 buff_config.gd 解析（兼容旧格式兜底）
3. Step 2.1：改 buff_instance.gd（effects → effect，6 个方法简化）
4. Step 2.2：改 buff_manager.gd（去掉内层遍历）
5. Step 3：改 buff_editor.gd（列表式 → 单例表单）
6. Step 4.1：改 skill_executor.gd（apply_target_buff / _apply_optional_buff / projectile 支持 buff_ids）
7. Step 4.2：改 skill_sequence_editor.gd（apply_target_buff / 伤害节点表单改为 buff_ids 数组 UI）
8. Step 4.3 + Step 5：迁移 skills.json 数据 + projectile 传参链路
9. 静态检查 + 验证
