# 计划：enemy.gd 改造为继承 CombatActorBase

## 背景

前序会话已完成双层抽象的绝大部分工作：
- **Stats 层**：`BaseCombatStats` 基类 + `EnemyStats` / `PartyMemberStats` / `CharacterStats` 三个子类（均已完成）
- **Actor 层**：`CombatActorBase` 基类已创建，`player.gd` 已改造为继承基类

**唯一剩余工作**：`scripts/enemy.gd` 仍 `extends CharacterBody2D`，包含大量与 `CombatActorBase` 重复的代码（节点引用、战斗动画三件套、战斗代理三件套、辅助函数、`_physics_process` 公共前段）。

**其他类排查结论**：`projectile.gd` / `hit_box.gd` / `combat_component.gd` 是组件/弹道，非战斗角色主体，不适用 Actor 层抽象。无其他需要抽象的类。

## 当前问题分析

`enemy.gd` 与 `CombatActorBase` 的重复代码清单：

### 1. 重复字段（基类已提供，应删除）
- `@onready var sprite` / `visual_root` / `combat`（基类 L7-9）
- `var _combat_anim_playing` / `_visual_authored_x` / `_actor_scale` / `gravity`（基类 L11-15）
- `var _combat_actions`（基类 L12）

### 2. 重复函数（基类已提供，应删除）
- `get_combat_actions()` / `get_actor_scale()`（基类 L85-90）
- `_get_vector2_from_dict` / `_get_rectangle_size` / `_apply_scaled_rectangle_shape`（基类 L204-229）
- `_apply_visual_facing_offset` / `_face_direction`（基类 L172-182）
- `_edge_distance_x_to` / `_combat_half_width`（基类 L185-201）
- `play_combat_animation` / `_on_combat_anim_finished` / `_end_combat_anim` / `_hold_animation_last_frame`（基类 L100-146）
- `take_damage` / `heal` / `apply_buff_from_config`（基类 L151-166）
- `_ready`（基类 L18-20 统一调度，子类改用 `_setup_actor_specifics`）
- `_physics_process`（基类 L36-41 统一调度，子类改用 `_update_actor`）

### 3. 不一致问题（重构时一并修正）
- **`_get_move_speed` 绕过 stats**：enemy L289-297 直接读 `_config.move_speed`，而基类 L233-242 从 `get_combat_stats().move_speed` 读取。由于 `EnemyStats` 构造时已从 `_config` 拷贝 `move_speed`，两者等价，删除 enemy 的 override 即可统一。

## 改造方案

### 文件：`scripts/enemy.gd`

#### 修改 1：类声明
```gdscript
extends CombatActorBase   # 原: extends CharacterBody2D
```

#### 修改 2：删除重复字段
删除以下字段声明（基类已提供）：
- `@onready var sprite` / `visual_root` / `combat`
- `var _combat_anim_playing` / `_visual_authored_x` / `_actor_scale` / `_combat_actions` / `gravity`

保留 enemy 特有字段：`_enemy_id` / `_config` / `_character_config` / `_stats` / `_party_manager` / `_target` / `_ai_state` / `_spawn_position` / `_patrol_target` / `_idle_timer` / `_skill_index` / `_target_switch_timer` / `_ai_caches` / `_ai_debug_text`

#### 修改 3：用 `_setup_actor_specifics` 替换 `_ready`
删除 `_ready`，新增：
```gdscript
func _setup_actor_specifics() -> void:
    add_to_group("enemies")
    call_deferred("_connect_signals")
```
基类 `_ready` → `_setup_actor_base()` 已负责创建 `CombatDebugOverlay`、设置 `_visual_authored_x`、调用 `_apply_visual_facing_offset`。

#### 修改 4：用 `_update_actor` 替换 `_physics_process` 中的 AI 调度
删除 `_physics_process`，新增：
```gdscript
func _update_actor(delta: float) -> void:
    if _config.is_empty():
        return
    _target_switch_timer = maxf(0.0, _target_switch_timer - delta)
    match _ai_state:
        AIState.IDLE: _update_idle(delta)
        AIState.PATROL: _update_patrol(delta)
        AIState.CHASE: _update_chase(delta)
        AIState.ATTACK: _update_attack(delta)
```
基类 `_physics_process` → `_can_process_combat` 已负责：重力、DEAD/HIT 状态限制、`_combat_anim_playing` 限制、buff `can_move` 限制。

#### 修改 5：删除 `_get_move_speed` override
直接删除 enemy L289-297 的 `_get_move_speed`，使用基类 L233-242 统一实现（从 `get_combat_stats().move_speed` 读取，过 buff 修饰）。这修正了原代码绕过 stats 的不一致。

#### 修改 6：新增 `_get_idle_animation` override
基类 `_end_combat_anim` 通过 `_get_idle_animation()` 恢复动画。enemy 需按 AI 状态返回：
```gdscript
func _get_idle_animation() -> String:
    match _ai_state:
        AIState.CHASE, AIState.PATROL: return "run"
        _: return "idle"
```
替换原 `_end_combat_anim` 中硬编码的 target_animation 逻辑（L724-728）。

#### 修改 7：删除所有重复的辅助/动画/战斗代理函数
删除以下函数（基类已提供）：`get_combat_actions` / `get_actor_scale` / `_get_vector2_from_dict` / `_get_rectangle_size` / `_apply_scaled_rectangle_shape` / `_apply_visual_facing_offset` / `_face_direction` / `_edge_distance_x_to` / `_combat_half_width` / `play_combat_animation` / `_on_combat_anim_finished` / `_end_combat_anim` / `_hold_animation_last_frame` / `take_damage` / `heal` / `apply_buff_from_config`

#### 保留的 enemy 特有函数
- `init_from_config` / `_load_character_config` / `_load_combat_actions` / `_connect_signals` / `_apply_display_config`
- `get_combat_stats`（override，返回 `_stats`，返回类型 `EnemyStats` 是 `BaseCombatStats` 子类，协变合法）
- `get_enemy_name` / `get_ai_state_name` / `get_current_target` / `get_current_target_name` / `get_target_distance_x` / `get_ai_debug_text`
- `_play_anim`（enemy 独有的非战斗动画播放，与基类 `play_combat_animation` 语义不同，保留）
- `_face_target`（enemy 独有，带 dead zone，保留）
- 全部 AI 状态机：`_set_ai_state` / `_update_idle` / `_update_patrol` / `_update_chase` / `_update_attack`
- 全部 AI 技能选择：`_try_use_next_skill` / `_pick_weighted_skill` / `_get_nearest_engage_distance` / `_get_max_engage_distance` / `_get_retreat_distance` / `_get_ai_cache` / `_compile_ai_cache` / `_precompile_ai_caches`
- 全部 AI 目标管理：`_can_detect_player` / `_distance_x_to_target` / `_refresh_target` / `_find_nearest_party_member` / `_is_valid_party_target`
- 全部技能配置：`_get_configured_skill_ids` / `_get_configured_skill_weights` / `_pick_patrol_target`
- `_on_enemy_died`

## 假设与决策

1. **`init_from_config` 调用顺序**：无论在 `_ready` 之前还是之后调用，都能正确工作。`_apply_display_config` 会设置 `_visual_authored_x`，基类 `_setup_actor_base` 会重新捕获，两者兼容。
2. **`_config.is_empty()` 守卫**：放入 `_update_actor` 开头。未初始化的 enemy 仍受重力下落（基类 `_can_process_combat` 保证），但不执行 AI。
3. **协变返回类型**：GDScript 4 允许子类 `get_combat_stats() -> EnemyStats` 覆盖基类 `get_combat_stats() -> BaseCombatStats`。
4. **`CombatComponent` 鸭子类型不受影响**：通过 `_owner.has_method(...)` 调用，所有依赖的方法（`get_combat_stats` / `play_combat_animation` / `get_combat_actions` / `_end_combat_anim`）均由基类或 enemy override 提供。

## 验证步骤

1. 改造完成后用 GetDiagnostics 检查 `enemy.gd` 无静态错误
2. 同步检查 `combat_actor_base.gd` / `player.gd` 无错误
3. 确认 enemy.gd 中不再有 `extends CharacterBody2D` / 重复字段 / 重复函数
4. 确认 `_get_move_speed` 已删除（使用基类统一实现）
