# 第一版受击特效实现计划

## 概述

当前游戏受击时只有 `hurt` 动画 + 硬直 + 短暂无敌，**没有任何视觉受击反馈**。本计划实现第一版受击特效，包含两个元素：

1. **命中闪白**：受击瞬间角色精灵闪白 0.1 秒，通过 CanvasItem Shader 实现
2. **伤害飘字**：受击时在受击者位置弹出伤害数字，向上飘动并淡出

## 当前状态分析

### 已完成（3/5 新文件）

| 文件 | 状态 | 说明 |
|---|---|---|
| `assets/effects/hit_flash.gdshader` | ✅ 已创建 | CanvasItem shader，`flash_amount` 控制白色混合 |
| `scripts/combat/hit_flash_controller.gd` | ✅ 已创建 | `class_name HitFlashController`，`setup(sprite)` + `flash(duration)` + `_restore()` |
| `scripts/combat/damage_number.gd` | ✅ 已创建 | `class_name DamageNumber` extends Label，`popup(value, world_pos, is_crit)` 用 Tween 飘动淡出 |

### 待完成（2 新文件 + 1 修改）

| 文件 | 状态 | 说明 |
|---|---|---|
| `assets/effects/damage_number.tscn` | ⏳ 待创建 | Label 场景，z_index=300 |
| `scripts/combat/damage_number_spawner.gd` | ⏳ 待创建 | 监听 `combat.took_damage` 信号，生成飘字 |
| `scripts/combat_actor_base.gd` | ⏳ 待修改 | 集成 HitFlashController + DamageNumberSpawner |

### 已有基础设施（可复用）

| 设施 | 位置 | 状态 |
|---|---|---|
| `took_damage(amount, source)` 信号 | `combat_component.gd:7` 声明，`556` 行 emit | **已声明已 emit，但无人监听** |
| 受击触发调用链 | `hurt_box.gd` → `combat_actor_base.gd:154` → `combat_component.gd:537` | 已实现 |
| 受击 hurt 动画 | `combat_component.gd:560` → `combat_actor_base.gd:103`（hit→hurt 回退） | 已实现 |
| 场景根访问方式 | `_owner.get_tree().current_scene` | 弹道/特效已用此方式挂载 |

### 关键现状

- `combat_component.gd:556` `took_damage.emit(actual, source)` —— `actual` 是扣血后的实际伤害值（int），`source` 是伤害来源节点
- `combat_component.gd:543-556` 流程：`modify_damage` → 扣 HP → `hp_changed.emit` → `took_damage.emit(actual, source)` → 死亡判定 → `play_combat_animation("hit")`
- `combat_actor_base.gd:7` `sprite: AnimatedSprite2D = $CharacterActionSet/AnimatedSprite2D`
- `combat_actor_base.gd:8` `visual_root: Node2D = $CharacterActionSet`
- `combat_actor_base.gd:9` `combat: Node = $CombatComponent`
- `character_actions.tscn` 的 AnimatedSprite2D **没有 material 属性**，运行时注入
- player.gd / enemy.gd 均 extends CombatActorBase，集成点统一在基类

## 实现方案（剩余工作）

### 一、新建伤害飘字场景

**新建文件**：`assets/effects/damage_number.tscn`

结构（参考 `assets/effects/stun_fx.tscn` 的极简格式）：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/combat/damage_number.gd" id="1_script"]

[node name="DamageNumber" type="Label"]
z_as_relative = false
z_index = 300
horizontal_alignment = 1
vertical_alignment = 1
script = ExtResource("1_script")
```

关键属性：
- `z_as_relative = false` + `z_index = 300`：绝对层级，高于弹道(200)和角色(100)
- `horizontal_alignment = 1` (CENTER) + `vertical_alignment = 1` (CENTER)：数字居中
- 挂载 `damage_number.gd` 脚本

**为什么**：飘字需要作为 PackedScene 由 Spawner 实例化，场景文件承载节点类型+属性+脚本绑定，避免运行时手动配置。

### 二、新建飘字生成器

**新建文件**：`scripts/combat/damage_number_spawner.gd`

职责：监听 `combat.took_damage` 信号，在受击者位置生成飘字。

```gdscript
extends Node
class_name DamageNumberSpawner
## 伤害飘字生成器：监听 combat.took_damage 信号，在受击者位置生成飘字

var _owner_node: Node2D
var _combat: Node
var _packed: PackedScene = preload("res://assets/effects/damage_number.tscn")


func setup(owner_node: Node2D, combat: Node) -> void:
	_owner_node = owner_node
	_combat = combat
	if _combat != null and _combat.has_signal("took_damage"):
		_combat.took_damage.connect(_on_took_damage)


func _on_took_damage(amount: int, source: Node) -> void:
	if amount <= 0 or _owner_node == null:
		return
	var scene := _owner_node.get_tree().current_scene
	if scene == null:
		return
	var label := _packed.instantiate() as DamageNumber
	if label == null:
		return
	scene.add_child(label)
	# 飘字位置：角色脚部位置（global_position 即角色根坐标）
	var pos := _owner_node.global_position
	label.popup(amount, pos)
```

**为什么**：
- 挂在角色身上（add_child 到角色节点），生命周期跟随角色；但生成的飘字挂到 `current_scene`，世界坐标，跟随场景根销毁
- 监听 `took_damage` 而非 `play_combat_animation`，因为飘字需要伤害数值（amount），信号正好携带
- `_owner_node.global_position` 是角色脚部坐标（CharacterBody2D 根），`damage_number.gd` 内部已加 `(-10~10, -20)` 偏移到身体上方

### 三、修改 combat_actor_base.gd 集成

**修改文件**：`scripts/combat_actor_base.gd`

#### 改动点 1：新增成员变量（L11 附近）

在 `var _combat_anim_playing := false` 上方或下方新增：

```gdscript
var _hit_flash: HitFlashController = null
```

#### 改动点 2：_setup_actor_base() 末尾创建控制器（L28 后）

在 `_apply_visual_facing_offset()` 之后追加：

```gdscript
	# 受击闪白控制器
	_hit_flash = HitFlashController.new()
	add_child(_hit_flash)
	_hit_flash.setup(sprite)
	# 伤害飘字生成器
	var spawner := DamageNumberSpawner.new()
	add_child(spawner)
	spawner.setup(self, combat)
```

**为什么用 add_child 而非成员变量持有 spawner**：spawner 通过信号回调工作，不需要外部访问；挂到节点树即可跟随角色销毁。`_hit_flash` 需要成员变量是因为 `play_combat_animation` 要主动调用 `flash()`。

#### 改动点 3：play_combat_animation() 受击时触发闪白（L108-113 附近）

当前代码：
```gdscript
if sprite.sprite_frames.has_animation(target_animation):
	_combat_anim_playing = true
	sprite.animation = target_animation
	sprite.stop()
	sprite.frame = 0
	sprite.play()
	if not sprite.animation_finished.is_connected(_on_combat_anim_finished):
		sprite.animation_finished.connect(_on_combat_anim_finished)
```

修改为在 `sprite.play()` 后追加闪白触发：
```gdscript
if sprite.sprite_frames.has_animation(target_animation):
	_combat_anim_playing = true
	sprite.animation = target_animation
	sprite.stop()
	sprite.frame = 0
	sprite.play()
	# 受击动画触发闪白
	if target_animation == "hit" or target_animation == "hurt":
		if _hit_flash != null:
			_hit_flash.flash(0.1)
	if not sprite.animation_finished.is_connected(_on_combat_anim_finished):
		sprite.animation_finished.connect(_on_combat_anim_finished)
```

**为什么判断 hit 或 hurt**：`combat_component.gd:560` 调用的是 `play_combat_animation("hit")`，而 `combat_actor_base.gd:106` 会把 `"hit"` 回退为 `"hurt"`（部分角色精灵只有 hurt 动画）。判断回退后的 `target_animation` 确保两种命名都触发。

## 涉及文件清单

### 新建文件（剩余 2 个）

| 文件 | 用途 |
|---|---|
| `assets/effects/damage_number.tscn` | 伤害飘字场景（Label + z_index=300） |
| `scripts/combat/damage_number_spawner.gd` | 飘字生成器（监听 took_damage 信号） |

### 修改文件（1 个）

| 文件 | 改动 |
|---|---|
| `scripts/combat_actor_base.gd` | 新增 `_hit_flash` 成员；`_setup_actor_base()` 末尾创建 HitFlashController + DamageNumberSpawner；`play_combat_animation()` 受击时触发 `_hit_flash.flash(0.1)` |

## 假设与决策

1. **闪白触发时机**：在 `play_combat_animation("hit")` 时触发（即 `combat_component.gd:560` 调用时），而非 `took_damage` 信号。原因：闪白是视觉反馈，与动画同步更自然；且 `play_combat_animation` 是受击反应的统一入口。

2. **飘字触发时机**：监听 `took_damage` 信号，因为飘字需要伤害数值（amount），而信号正好携带。且飘字应在所有伤害来源（普攻/技能/弹道）都触发，信号是统一入口。

3. **飘字挂载位置**：挂到 `current_scene`（场景根），世界坐标，与弹道同一层级。不挂 UI 层，因为 2D 动作游戏飘字应跟随世界位置。

4. **闪白不修改 .tscn**：不改角色场景文件，运行时注入 material，保持角色资源纯净。`_restore()` 把 `sprite.material` 设回 `null`，不影响原资源。

5. **飘字 z_index=300**：高于弹道(200)和角色(100)，确保数字不被遮挡。`z_as_relative=false` 使用绝对层级，不受父节点 z_index 影响。

6. **第一版不做暴击区分**：`is_crit` 参数保留但第一版不触发，统一白色。后续可扩展。

7. **闪白 duration=0.1s**：与 `_hit_stun_timer` 一致，受击硬直结束闪白也结束。

8. **Spawner 不需要成员变量持有**：通过 `add_child` 挂到节点树，信号连接保持引用，角色销毁时自动清理。

## 验证步骤

1. **闪白验证**：进入游戏，让怪物攻击角色或角色攻击怪物，确认受击瞬间精灵变白 0.1 秒后恢复
2. **飘字验证**：受击时头顶弹出伤害数字，向上飘 40px 并在 0.6 秒内淡出消失
3. **多目标验证**：多个敌人同时受击时，各自飘字独立显示不冲突
4. **无敌帧验证**：受击后 0.8 秒无敌期内不再受击，不重复闪白/飘字
5. **死亡验证**：致命一击时飘字正常弹出，角色死亡动画不受影响
6. **弹道命中验证**：弓手箭矢命中怪物时，怪物也有闪白+飘字（走 projectile → take_hit → take_damage 同一链路）
