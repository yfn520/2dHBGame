# Buff 系统测试修复 + 图标补全 + 全面数据配置

## Summary

Buff 系统已在上一会话完整落地（11 个 buff、5 种效果类型 `stat_modifier/dot/hot/shield/control`、数据驱动架构、BuffConfig→BuffInstance→BuffManager 运行时、BuffEditor 工具面板、技能编辑器 `buff_id` 下拉、BattleHUD buff 图标行、CombatComponent/SkillExecutor 暴击与攻速集成）。本次 plan 聚焦用户选定的 **测试与修复** 方向，并完成两项配套：**补全 buff UI 图标**、**配置一套全面的 RPG buff 数据**。不改动技能—buff 映射（用户自行配置）。

## Current State Analysis

经探索确认现状：

| 模块 | 状态 | 说明 |
|------|------|------|
| `data/buffs.json` | 已存在，11 个 buff | 全部 `icon` 字段为空串；6 个 `effect_scene` 指向不存在的 .tscn（运行时被 `_spawn_effect` 静默跳过） |
| `scripts/data/buff_config.gd` | 完整 | 解析 effects 数组，含 `get_buffs_by_category` |
| `scripts/combat/buff_instance.gd` | 完整 | 含 `add_stack`（按 `stack_behavior`）、`get_dot/hot/shield_effects`、`has_control_affect` |
| `scripts/combat/buff_manager.gd` | 完整 | `apply_buff`/`dispel`/`can_act`/`can_use_skill`/`is_invincible`/`get_modified_stat`(add→mul→set)/`modify_damage`(护盾吸收)/`_process`(DoT+HoT) |
| `scripts/combat/combat_component.gd` | 完整 | `try_use_skill` 查沉默+冷却÷攻速；`take_damage` 查无敌+护盾+防御；`apply_buff_from_config` 检查 control 并 `cancel_cast` |
| `scripts/combat/skill_executor.gd` | 完整 | `calculate_damage` 应用 buff 攻击/暴击率/暴击伤害；命中按概率 `_apply_optional_buff` |
| 三套属性对象 | 完整 | 均含 `crit_rate/crit_damage/attack_speed` |
| `addons/game_tools/buff_editor.gd` + 插件注册 | 完整 | 菜单 id 10「配置 Buff...」 |
| `addons/game_tools/skill_sequence_editor.gd` | 完整 | `_add_buff_id_option` 下拉，5 处节点已接入 |
| `scripts/ui/battle_hud.gd` | 基本完整 | `_main_buff_bar` + `_make_buff_icon`：有 icon 加载 TextureRect，否则用名称首字 Label 回退；缺倒计时进度条（非本次范围） |
| buff 图标资源 | **全部缺失** | 无 `assets/icons/` 目录；所有 buff 走 Label 回退 |
| buff 特效场景 | 6 个缺失 | `scenes/effects/` 下无 `poison/burn/freeze/paralysis/invincible/stun_fx.tscn`，运行时静默跳过（**本次不动**，属视觉资产而非数据/测试范围） |

### 待验证的集成点（测试项）

以下为基于代码阅读发现的需验证项，执行阶段逐项检查并修复：

1. **DoT 调用签名** — `buff_manager.gd:30` `_owner.take_damage(dmg, null, false)` 三参签名需与 `combat_component.gd`/`player.gd`/`enemy.gd` 的 `take_damage` 一致。
2. **HoT heal 方法** — `buff_manager.gd:39` `_owner.heal(heal_amount)`，需确认 owner（角色节点）是否暴露 `heal` 方法或需走 CombatComponent。
3. **移速集成** — `get_speed_multiplier()` 只收集 `mul` 模式 move_speed；需确认 `player.gd`/`enemy.gd` 的移动代码确实调用了 `buff_manager.get_speed_multiplier()` 并尊重 `can_move()`。
4. **add_stack 上限** — `BuffInstance.add_stack()` 需 cap 在 `max_stacks`，不能无限叠加。
5. **dispel 边界** — `dispel(category, count)` 中 `count=-1` 表示清空，`count>0` 清 count 个；确认逻辑无 off-by-one。
6. **护盾剩余同步** — `modify_damage` 修改 effect 的 `remaining`，确认该写回对 `_process` 持久（effect 是 Dictionary 引用，应 OK）。
7. **apply_buff_from_config 中断施法** — 施加含 `act/skill` control 时调 `cancel_cast`，确认不会在已经 IDLE 时误触发。

## Proposed Changes

### Step 1 — 静态测试与修复（核心）

逐项核对上文「待验证的集成点」，读取以下文件确认签名/调用链，修复发现的缺口：

- `d:\game\2dHBGame\scripts\combat\combat_component.gd`（`take_damage` 完整签名与护盾/无敌流程）
- `d:\game\2dHBGame\scripts\combat\player.gd`（`take_damage`/`heal` 是否暴露、移动是否查 `can_move`/`get_speed_multiplier`）
- `d:\game\2dHBGame\scripts\combat\enemy.gd`（同上）
- `d:\game\2dHBGame\scripts\combat\buff_instance.gd`（`add_stack` 上限与 `stack_behavior`）
- `d:\game\2dHBGame\scripts\combat\buff_manager.gd`（`dispel`、`_process` DoT/HoT 调用）

修复原则：仅修真实缺口，不做无谓重构。常见预期修复（视实际代码而定）：
- 若 owner 无 `heal`：让 CombatComponent 暴露 `heal` 转发到 stats，或 BuffManager 改为通过 `_owner.combat_component` 调用。
- 若移动代码未查 `can_move()`/`get_speed_multiplier()`：在 `player.gd`/`enemy.gd` 的 `_physics_process` 速度计算处补上。
- 若 `add_stack` 未 cap：加 `if stacks < max_stacks: stacks += 1`。

### Step 2 — Buff 图标生成器（新建 @tool 脚本）

新建 `d:\game\2dHBGame\addons\game_tools\buff_icon_generator.gd`（`@tool extends Window`，与 `buff_editor.gd` 同模式）：

- 读取 `res://data/buffs.json`。
- 对每个 buff，用 `SubViewport`（32×32，透明背景）渲染一个图标：圆角彩色底（buff=绿/蓝系，debuff=红/紫系，按 `damage_type`/`control_type` 微调色相）+ 居中中文首字 Label（用默认字体保证中文渲染）。
- `await RenderingServer.frame_post_draw` 后取 `viewport.get_texture().get_image()`，`img.save_png("res://assets/icons/buffs/<id>.png")`。
- 渲染完成后回写 `buffs.json` 的 `icon` 字段为 `"res://assets/icons/buffs/<id>.png"`。
- 保存时调用 `fsync` 确保落盘，并触发 `EditorInterface.get_resource_filesystem().scan()` 让 Godot 识别新资源。
- 在 `plugin.gd` 注册菜单项 id 11「生成 Buff 图标...」，`_open_buff_icon_generator()` 弹窗执行。

产物目录：`d:\game\2dHBGame\assets\icons\buffs\<id>.png`（每个 buff 一个）。

### Step 3 — 配置全面 buff 数据

将 `data/buffs.json` 从 11 个扩展到 **30 个**，全部使用现有 5 种效果类型，不引入新机制。ID 段沿用既有约定（1xxx 减益 / 11xx+12xx 增益）。保留现有 11 个（微调数值），新增 19 个：

#### DoT 减益（1001-1010）
| ID | 名称 | effects |
|----|------|---------|
| 1001 | 中毒 | dot poison 5/1s stack×5（保留） |
| 1002 | 燃烧 | dot fire 8/0.5s refresh（保留） |
| 1008 | 流血 | dot physical 6/0.8s stack×3 |
| 1009 | 腐蚀 | dot shadow 4/1s + stat_modifier defense mul 0.8 refresh |
| 1010 | 剧毒 | dot poison 3/0.5s stack×10 |

#### 控制减益（1003-1006, 1103, 1016）
| ID | 名称 | effects |
|----|------|---------|
| 1003 | 冰冻 | control freeze act+move（保留） |
| 1004 | 麻痹 | control paralysis move（保留） |
| 1006 | 眩晕 | control stun act+move+skill（保留） |
| 1103 | 沉默 | control silence skill（保留） |
| 1016 | 睡眠 | control sleep act+move+skill dur 3 |

#### 属性减益（1007, 1011-1015）
| ID | 名称 | effects |
|----|------|---------|
| 1007 | 减速 | stat_modifier move_speed mul 0.5（保留） |
| 1011 | 攻击削弱 | stat_modifier attack mul 0.7 |
| 1012 | 防御削弱 | stat_modifier defense mul 0.5 |
| 1013 | 致盲 | stat_modifier crit_rate add -0.3 |
| 1014 | 迟缓 | stat_modifier move_speed mul 0.7 + attack_speed mul 0.8 |
| 1015 | 虚弱 | stat_modifier attack mul 0.7 + defense mul 0.7 |

#### 防御增益（1005, 1104, 1111）
| ID | 名称 | effects |
|----|------|---------|
| 1005 | 无敌 | control invincible be_damaged（保留） |
| 1104 | 护盾 | shield 100（保留） |
| 1111 | 强效护盾 | shield 300 |

#### HoT 增益（1201-1202）
| ID | 名称 | effects |
|----|------|---------|
| 1201 | 回复 | hot 10/1s |
| 1202 | 神圣祝福 | hot 8/0.5s |

#### 属性增益（1101, 1102, 1105-1109）
| ID | 名称 | effects |
|----|------|---------|
| 1101 | 攻击强化 | stat_modifier attack mul 1.3（保留） |
| 1102 | 防御强化 | stat_modifier defense mul 1.5（保留） |
| 1105 | 速度强化 | stat_modifier move_speed mul 1.3 |
| 1106 | 暴击强化 | stat_modifier crit_rate add 0.2 |
| 1107 | 暴伤强化 | stat_modifier crit_damage add 0.5 |
| 1108 | 攻速强化 | stat_modifier attack_speed mul 1.3 |
| 1109 | 神力 | stat_modifier attack mul 1.5 + defense mul 1.2 |

#### 多效果复合增益（1203-1205）
| ID | 名称 | effects |
|----|------|---------|
| 1203 | 狂暴 | stat_modifier attack mul 1.5 + defense mul 0.7 + crit_rate add 0.1 |
| 1204 | 圣盾 | shield 200 + hot 5/1s |
| 1205 | 战斗狂热 | stat_modifier attack_speed mul 1.4 + crit_rate add 0.15 |

每个新 buff 均含：`name/description/category/duration/max_stacks/stack_behavior/icon/effect_scene/effects`。`icon` 先留空，由 Step 2 生成器回写；`effect_scene` 留空（不创建特效场景，本次范围外）。

### Step 4 — 最终验证

- 确认 `buffs.json` 被 `BuffConfig.load_config()` 正确解析（无 JSON 错误，30 条全部加载）。
- 确认 `buff_icon_generator` 产出的 PNG 路径在 `battle_hud.gd:515` `ResourceLoader.exists(buff.icon)` 通过，HUD 显示 TextureRect 而非首字回退。
- 确认 `skill_sequence_editor.gd` `_add_buff_id_option` 下拉能列出全部 30 个 buff（直接读 buffs.json，无需改动）。
- 确认 `buff_editor.gd` 打开后左侧列表显示 30 条。
- 跑一遍静态检查：`grep` 确认无残留 `_scatter_spin` 之类历史缓存问题，无对已删字段的引用。

## Assumptions & Decisions

1. **不引入新效果类型** — 用户选定「测试与修复」方向，本次仅用现有 5 种效果类型组合表达，不增加 `aura/trigger/reflect/lifesteal` 等需新代码的机制。
2. **不创建 buff 特效场景** — `effect_scene` 的 6 个缺失引用属视觉资产范畴（非数据/测试），本次保留现状（运行时静默跳过）。新增 buff 的 `effect_scene` 留空。用户后续要视觉反馈时再单独立项。
3. **图标用 @tool 脚本生成而非手绘** — 可复现、支持中文、用户加新 buff 后可重跑。用 SubViewport 渲染圆角底+首字，落盘为 PNG。
4. **不改技能—buff 映射** — 用户明确「技能要配什么buff我自己来」，`skill_sequence_editor.gd` 不改 buff 选项逻辑（已能用），不动 skills.json。
5. **HUD 倒计时进度条本次不做** — 用户方向是测试+数据+图标，进度条属 UI 增益，非本次范围。
6. **ID 段约定** — 1xxx 减益、11xx/12xx 增益，沿用既有约定，便于编辑器分类与未来 dispel 规则。
7. **数值为初版** — 30 个 buff 的具体数值（伤害/持续时间/系数）按 RPG 常识给初值，用户可在 BuffEditor 里微调。
8. **`stack_behavior` 选择** — DoT 多用 `stack`（中毒/流血/剧毒可叠层），控制类用 `refresh`（刷新持续时间），属性增益用 `refresh`，护盾用 `refresh`（不叠加吸收量）。

## Verification Steps

1. 在 Godot 编辑器打开项目，菜单「游戏工具 → 生成 Buff 图标...」，确认 `assets/icons/buffs/` 下生成 30 个 PNG 且 `buffs.json` 的 `icon` 字段被回写。
2. 菜单「游戏工具 → 配置 Buff...」打开 BuffEditor，确认左侧 30 条，任选一条查看 effects 表单正常。
3. 菜单「游戏工具 → 技能序列编辑器」打开，任一 buff_id 下拉确认列出 30 个 buff。
4. 运行游戏进入战斗，给角色施加一个 DoT（如中毒）确认掉血；施加护盾确认吸收；施加眩晕确认无法行动；施加攻击强化确认伤害提升。
5. 确认 HUD buff 图标显示为生成的 PNG（非首字回退），多层 buff 显示 `x层数` 角标。
6. Step 1 修复项逐条复核：DoT/HoT 调用链通、移动查 `can_move`/`get_speed_multiplier`、`add_stack` 有上限。

## Files Changed

| 文件 | 操作 | 说明 |
|------|------|------|
| `data/buffs.json` | 修改 | 11→30 个 buff；icon 字段由生成器回写 |
| `addons/game_tools/buff_icon_generator.gd` | 新建 | @tool 图标生成器（SubViewport 渲染+save_png+回写 icon） |
| `addons/game_tools/plugin.gd` | 修改 | 注册菜单 id 11「生成 Buff 图标...」+ `_open_buff_icon_generator` |
| `assets/icons/buffs/*.png` | 新建(生成) | 30 个 32×32 buff 图标 |
| Step 1 修复涉及的文件 | 视情况修改 | `combat_component.gd`/`player.gd`/`enemy.gd`/`buff_instance.gd`/`buff_manager.gd` 中发现的集成缺口 |
