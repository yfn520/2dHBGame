# Stats + CombatActorBase 双层抽象计划

## 摘要

本次重构分两层消除重复：
1. **Stats 层**：`EnemyStats` / `PartyMemberStats` / `CharacterStats` → 继承 `BaseCombatStats`（模板方法模式）
2. **Actor 层**：`player.gd` / `enemy.gd` → 继承 `CombatActorBase`（模板方法 + 钩子）

两层独立但配套：`CombatActorBase.get_combat_stats()` 返回 `BaseCombatStats`，统一了 owner 与 stats 的接口契约。同时修正 `enemy.gd._get_move_speed()` 绕过 stats 的历史不一致。

---

## 第一部分：Stats 抽象

### 当前状态

| 维度 | [EnemyStats](file:///e:/g_selfcustom/server_client/hengban-2/scripts/combat/enemy_stats.gd) (26行) | [PartyMemberStats](file:///e:/g_selfcustom/server_client/hengban-2/scripts/combat/party_member_stats.gd) (68行) | [CharacterStats](file:///e:/g_selfcustom/server_client/hengban-2/scripts/data/character_stats.gd) (152行) |
|------|-----------|------------------|----------------|
| 8 个战斗属性 | ✓ | ✓ | ✓ |
| character_id/level/exp | ✗ | ✓ | ✓ |
| base_* vs final | ✗ | ✗ | ✓ |
| signal stats_changed | ✗ | ✗ | ✓ |
| 数据源 | 构造 dict | GameRegistry 单例 | 注入 roster/config + 外部 items |
| roster hp 同步 | ✗ | ✓ sync_hp_to_roster() | ✓ 内联 |
| take_damage/heal | ✗ | ✗ | ✓（未被战斗路径调用） |
| to_dict/from_dict | ✗ | ✗ | ✓ |

### 三处重复
1. 8 个属性从 dict 读取带默认值赋值（×3）
2. 装备加成 for 循环（×2）
3. hp 保留/封顶三段逻辑（×3）
4. `is_alive()` 一行函数（×3）

### 改动

#### 1.1 新增 `scripts/combat/base_combat_stats.gd`

```gdscript
class_name BaseCombatStats
extends RefCounted

var max_hp: int = 0
var hp: int = 0
var attack: int = 0
var defense: int = 0
var move_speed: float = 0.0
var crit_rate: float = 0.0
var crit_damage: float = 1.5
var attack_speed: float = 1.0

func is_alive() -> bool:
    return hp > 0

## 模板方法：子类提供 base dict + 装备列表 + stored hp，基类统一算最终值
func recalculate(preserve_current_hp: bool = true) -> void:
    var base_stats: Dictionary = _get_base_stats_dict()
    var equipped_items: Array = _get_equipped_items()
    max_hp = int(base_stats.get("max_hp", 0))
    attack = int(base_stats.get("attack", 0))
    defense = int(base_stats.get("defense", 0))
    move_speed = float(base_stats.get("move_speed", 0.0))
    crit_rate = float(base_stats.get("crit_rate", 0.0))
    crit_damage = float(base_stats.get("crit_damage", 1.5))
    attack_speed = float(base_stats.get("attack_speed", 1.0))
    for equip_info in equipped_items:
        max_hp += int(equip_info.get("max_hp", 0))
        attack += int(equip_info.get("attack", 0))
        defense += int(equip_info.get("defense", 0))
        move_speed += float(equip_info.get("move_speed", 0.0))
        crit_rate += float(equip_info.get("crit_rate", 0.0))
        crit_damage += float(equip_info.get("crit_damage", 0.0))
        attack_speed += float(equip_info.get("attack_speed", 0.0))
    var stored_hp: int = _get_stored_hp()
    if stored_hp > 0:
        hp = mini(stored_hp, max_hp)
    elif preserve_current_hp and hp > 0:
        hp = mini(hp, max_hp)
    else:
        hp = max_hp
    _on_recalculated()

# === 钩子 ===
func _get_base_stats_dict() -> Dictionary:
    return {}
func _get_equipped_items() -> Array:
    return []
func _get_stored_hp() -> int:
    return 0
func _on_recalculated() -> void:
    pass
```

#### 1.2 改造 `scripts/combat/enemy_stats.gd`

```gdscript
class_name EnemyStats
extends BaseCombatStats

var _config: Dictionary = {}

func _init(cfg: Dictionary) -> void:
    _config = cfg
    recalculate(false)

func _get_base_stats_dict() -> Dictionary:
    return _config
```

#### 1.3 改造 `scripts/combat/party_member_stats.gd`

保留 `character_id/level/exp` 与 `sync_hp_to_roster()`，数据源继续走 GameRegistry（不改耦合方式）。

```gdscript
extends BaseCombatStats

var character_id: int = 0
var level: int = 1
var exp: int = 0

func setup(p_character_id: int) -> void:
    character_id = p_character_id
    recalculate(false)

func recalculate(preserve_current_hp: bool = true) -> void:
    super.recalculate(preserve_current_hp)
    sync_hp_to_roster()

func sync_hp_to_roster() -> void:
    if GameRegistry.roster_data != null and character_id > 0:
        GameRegistry.roster_data.set_hp(character_id, hp)

func _get_base_stats_dict() -> Dictionary:
    if GameRegistry.character_config == null or character_id <= 0:
        return {}
    var char_data: Dictionary = GameRegistry.character_config.get_character(character_id)
    if GameRegistry.roster_data != null:
        level = int(GameRegistry.roster_data.get_level(character_id))
        exp = int(GameRegistry.roster_data.get_exp(character_id))
    return char_data.get("stats", {})

func _get_equipped_items() -> Array:
    if GameRegistry.equipment_provider == null:
        return []
    return GameRegistry.equipment_provider.get_equipped_configs_for_character(character_id)

func _get_stored_hp() -> int:
    if GameRegistry.roster_data == null or character_id <= 0:
        return 0
    return int(GameRegistry.roster_data.get_hp(character_id))
```

#### 1.4 改造 `scripts/data/character_stats.gd`

保留 `base_*`、signal、依赖注入、take_damage/heal/to_dict/from_dict。用 `_external_equipped_items` 缓存解决 `recalculate(equipped_items, preserve_hp)` 签名与基类不一致的问题。

```gdscript
class_name CharacterStats
extends BaseCombatStats

signal stats_changed

var base_max_hp: int = 0
var base_attack: int = 0
var base_defense: int = 0
var base_move_speed: float = 0.0
var base_crit_rate: float = 0.0
var base_crit_damage: float = 1.5
var base_attack_speed: float = 1.0

var character_id: int = 0
var level: int = 1
var exp: int = 0

var _roster: CharacterRosterData
var _character_config: CharacterConfigData
var _external_equipped_items: Array = []

func setup(roster: CharacterRosterData, character_config: CharacterConfigData) -> void:
    # 原样保留（注入、连信号、首次 recalculate）

func recalculate(equipped_items: Array = [], preserve_current_hp: bool = true) -> void:
    _external_equipped_items = equipped_items
    super.recalculate(preserve_current_hp)
    stats_changed.emit()

func _get_base_stats_dict() -> Dictionary:
    # 读 character_config + roster，同时填 base_*
    # 原样保留 base_* 赋值逻辑

func _get_equipped_items() -> Array:
    if not _external_equipped_items.is_empty():
        return _external_equipped_items
    return _get_current_equipped_configs()

func _get_stored_hp() -> int:
    if _roster == null or character_id <= 0:
        return 0
    return int(_roster.get_hp(character_id))

func _on_recalculated() -> void:
    if _roster != null and character_id > 0:
        _roster.set_hp(character_id, hp)

# 以下原样保留
func take_damage(amount: int) -> int
func heal(amount: int) -> int
func to_dict() -> Dictionary
func from_dict(data: Dictionary) -> void
func _get_current_equipped_configs() -> Array
func _on_active_character_changed(_id: int) -> void
func _on_character_progress_changed(id: int) -> void
```

---

## 第二部分：CombatActorBase 抽象

### 当前状态

[player.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/player.gd) (713行) 与 [enemy.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/enemy.gd) (765行) 之间有大量近乎逐字相同的代码。

### 重复清单

**完全相同（直接上提）**：
- 节点引用：`@onready sprite` / `visual_root` / `combat`
- 状态：`_combat_anim_playing` / `_combat_actions` / `_visual_authored_x` / `_actor_scale` / `gravity`
- 战斗动画三件套：`play_combat_animation` / `_on_combat_anim_finished` / `_hold_animation_last_frame`（player L650-695 / enemy L691-737）
- 战斗代理三件套：`take_damage` / `heal` / `apply_buff_from_config`（player L698-712 / enemy L740-755）
- 辅助函数：`_edge_distance_x_to` / `_combat_half_width` / `_get_vector2_from_dict` / `_get_rectangle_size` / `_apply_scaled_rectangle_shape` / `_apply_visual_facing_offset`（player L219-244, L393-394, L612-628 / enemy L185-210, L676-677, L560-576）
- 接口：`get_combat_actions()` / `get_actor_scale()`

**仅有钩子差异（用虚方法解决）**：
- `_face_direction`：player 多维护一个 `_facing_sign` 字段；enemy 不维护 → **统一去掉 `_facing_sign`**，需要时通过 `get_facing_sign()` 从 `sprite.flip_h` 反查（party_manager.gd L72 已用此接口）
- `_get_move_speed`：player 读 `_combat_stats.move_speed`；enemy 读 `_config.move_speed`（绕过 stats）→ **统一改成读 `get_combat_stats().move_speed`**
- `_end_combat_anim` 恢复动画：player 用 `_get_move_direction()`；enemy 用 `_ai_state` → 提取钩子 `_get_idle_animation() -> String`
- `_ready` 前段：player 加 "player" group、连 roster/equipment 信号；enemy 加 "enemies" group、连 died 信号 → 提取钩子 `_setup_actor_specifics()`
- `_physics_process` 前段（重力、DEAD/HIT/anim_playing/buff can_move 限制）：相同 → 上提到 `_can_process_combat(delta) -> bool`，子类在 `_update_actor(delta)` 中处理控制层

### 调用方对 owner 的接口依赖（基类必须满足）

通过 grep [combat_component.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/combat/combat_component.gd) 和 [party_manager.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/system/party_manager.gd) 确认：

| 方法 | 调用方 |
|------|-------|
| `get_combat_stats()` | combat_component.gd L68 |
| `sync_combat_hp()` | combat_component.gd L524, L543 |
| `play_combat_animation(name)` | combat_component.gd L235, L535, L600 |
| `_end_combat_anim()` | combat_component.gd L95, L476, L488 |
| `get_combat_actions()` | combat_component.gd L335, L658, L678 |
| `is_player_controlled()` | combat_component.gd L120 |
| `is_in_group("player")` | combat_component.gd L120 |
| `get_skill_for_input(slot)` | combat_component.gd L139 |
| `get_facing_sign()` | party_manager.gd L72, combat_component.gd L753(间接) |
| `set_party_character_id(id)` | party_manager.gd L155 |
| `set_player_controlled(bool)` | party_manager.gd L174 |
| `set_follow_target(node, slot)` | party_manager.gd L176 |
| `refresh_combat_stats()` | party_manager.gd L114, L180 |

**player 独有方法**（基类不提供，子类自定义）：`set_party_character_id` / `set_player_controlled` / `set_follow_target` / `refresh_combat_stats` / `sync_combat_hp` / `get_skill_for_input` / `get_ai_skill_candidates` / `is_player_controlled` / 队友 AI 一整套

**enemy 独有方法**（基类不提供，子类自定义）：`init_from_config` / `get_enemy_name` / `get_ai_state_name` / `get_current_target` / `get_target_distance_x` / `get_ai_debug_text` / 怪物状态机一整套

### 改动

#### 2.1 新增 `scripts/combat_actor_base.gd`

```gdscript
class_name CombatActorBase
extends CharacterBody2D

@onready var sprite: AnimatedSprite2D = $CharacterActionSet/AnimatedSprite2D
@onready var visual_root: Node2D = $CharacterActionSet
@onready var combat: Node = $CombatComponent

var _combat_anim_playing := false
var _combat_actions: Dictionary = {}
var _visual_authored_x := 0.0
var _actor_scale := 1.0
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")


func _ready() -> void:
    _setup_actor_base()
    _setup_actor_specifics()


func _setup_actor_base() -> void:
    var debug_overlay := CombatDebugOverlay.new()
    add_child(debug_overlay)
    debug_overlay.setup(self)
    _visual_authored_x = visual_root.position.x
    _apply_visual_facing_offset()


## 子类 override：加 group、连信号、初始化 stats 等
func _setup_actor_specifics() -> void:
    pass


func _physics_process(delta: float) -> void:
    if not _can_process_combat(delta):
        move_and_slide()
        return
    _update_actor(delta)
    move_and_slide()


## 公共前段：重力 + 战斗状态限制 + buff 控制限制。
## 返回 false 表示子类不应执行控制逻辑（基类直接 move_and_slide）。
func _can_process_combat(delta: float) -> bool:
    if combat != null and "combat_state" in combat:
        if combat.combat_state == combat.CombatState.DEAD:
            velocity = Vector2.ZERO
            return false
    if not is_on_floor():
        velocity.y += gravity * delta
    _check_combat_anim_release()
    if combat != null and "combat_state" in combat:
        if combat.combat_state == combat.CombatState.HIT:
            velocity.x = move_toward(velocity.x, 0, 400 * delta)
            return false
    if _combat_anim_playing:
        velocity.x = move_toward(velocity.x, 0, 400 * delta)
        return false
    if combat != null and combat.has_method("get_buff_manager"):
        var buff_manager = combat.get_buff_manager()
        if buff_manager != null and not buff_manager.can_move():
            velocity.x = move_toward(velocity.x, 0, 400 * delta)
            return false
    return true


func _check_combat_anim_release() -> void:
    if _combat_anim_playing and (sprite.animation == &"idle" or sprite.animation == &"run"):
        _combat_anim_playing = false


## 子类 override：控制层（player=输入+队友AI，enemy=怪物状态机AI）
func _update_actor(delta: float) -> void:
    pass


# === Stats 接口 ===

func get_combat_stats() -> BaseCombatStats:
    return null

func get_combat_actions() -> Dictionary:
    return _combat_actions

func get_actor_scale() -> float:
    return _actor_scale

func get_facing_sign() -> float:
    return 1.0 if sprite.flip_h else -1.0


# === 战斗动画三件套 ===

func play_combat_animation(anim_name: String) -> void:
    var target_animation := anim_name
    if not sprite.sprite_frames.has_animation(target_animation):
        if target_animation == "hit" and sprite.sprite_frames.has_animation("hurt"):
            target_animation = "hurt"
    if sprite.sprite_frames.has_animation(target_animation):
        _combat_anim_playing = true
        sprite.animation = target_animation
        sprite.stop()
        sprite.frame = 0
        sprite.play()
        if not sprite.animation_finished.is_connected(_on_combat_anim_finished):
            sprite.animation_finished.connect(_on_combat_anim_finished)
    else:
        _combat_anim_playing = true
        get_tree().create_timer(0.3).timeout.connect(_end_combat_anim)


func _on_combat_anim_finished() -> void:
    _end_combat_anim()


func _end_combat_anim() -> void:
    _combat_anim_playing = false
    if sprite.animation_finished.is_connected(_on_combat_anim_finished):
        sprite.animation_finished.disconnect(_on_combat_anim_finished)
    if combat != null and "combat_state" in combat and combat.combat_state == combat.CombatState.DEAD:
        _hold_animation_last_frame()
        return
    var next_animation := _get_idle_animation()
    if sprite.animation != next_animation:
        sprite.play(next_animation)


## 钩子：战斗动画结束后恢复的动画。player 返回 idle/run，enemy 按 AI 状态返回。
func _get_idle_animation() -> String:
    return "idle"


func _hold_animation_last_frame() -> void:
    var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
    sprite.pause()
    sprite.frame = maxi(0, frame_count - 1)


# === 战斗代理三件套 ===

func take_damage(amount: int, source: Node = null, play_hit_reaction: bool = true) -> void:
    if play_hit_reaction:
        velocity.x = 0.0
    if combat != null and combat.has_method("take_damage"):
        combat.take_damage(amount, source, play_hit_reaction)


func heal(amount: int) -> void:
    if combat != null and combat.has_method("heal"):
        combat.heal(amount)


func apply_buff_from_config(buff_cfg: Dictionary, source: int = 0) -> void:
    if combat != null and combat.has_method("apply_buff_from_config"):
        combat.apply_buff_from_config(buff_cfg, source)


# === 共用辅助 ===

func _apply_visual_facing_offset() -> void:
    visual_root.position.x = -_visual_authored_x if sprite.flip_h else _visual_authored_x


func _face_direction(dir: float) -> void:
    if dir == 0.0:
        return
    var new_flip := dir > 0.0
    if sprite.flip_h != new_flip:
        sprite.flip_h = new_flip
        _apply_visual_facing_offset()


func _edge_distance_x_to(target: Node2D) -> float:
    if target == null or not is_instance_valid(target):
        return INF
    var center_distance := absf(target.global_position.x - global_position.x)
    return maxf(0.0, center_distance - _combat_half_width(self) - _combat_half_width(target))


func _combat_half_width(node: Node) -> float:
    if node == null:
        return 0.0
    var shape_node := node.get_node_or_null("HurtBox/CollisionShape2D") as CollisionShape2D
    if shape_node == null:
        shape_node = node.get_node_or_null("CollisionShape2D") as CollisionShape2D
    if shape_node != null and shape_node.shape is RectangleShape2D:
        var rectangle := shape_node.shape as RectangleShape2D
        return absf(rectangle.size.x * shape_node.global_scale.x) * 0.5
    return 0.0


func _get_vector2_from_dict(data, fallback: Vector2) -> Vector2:
    if data is Dictionary:
        return Vector2(
            float(data.get("x", fallback.x)),
            float(data.get("y", fallback.y))
        )
    return fallback


func _get_rectangle_size(collision_shape: CollisionShape2D) -> Vector2:
    if collision_shape != null and collision_shape.shape is RectangleShape2D:
        return (collision_shape.shape as RectangleShape2D).size
    return Vector2.ONE


func _apply_scaled_rectangle_shape(collision_shape: CollisionShape2D, base_position: Vector2, base_size: Vector2) -> void:
    if collision_shape == null:
        return
    collision_shape.position = base_position * _actor_scale
    if collision_shape.shape is RectangleShape2D:
        collision_shape.shape = collision_shape.shape.duplicate()
        var rectangle := collision_shape.shape as RectangleShape2D
        rectangle.size = Vector2(
            maxf(1.0, base_size.x * _actor_scale),
            maxf(1.0, base_size.y * _actor_scale)
        )


## 统一的移动速度读取：从 stats 取 base，过 buff 修饰
func _get_move_speed() -> float:
    var base: float = 0.0
    var stats := get_combat_stats()
    if stats != null:
        base = stats.move_speed
    if combat != null and combat.has_method("get_buff_manager"):
        var bm = combat.get_buff_manager()
        if bm != null:
            return bm.get_modified_stat("move_speed", base)
    return base
```

#### 2.2 改造 `scripts/player.gd`

继承 `CombatActorBase`，删除所有上提到基类的代码，保留：玩家输入控制、队友 AI、`_setup_actor_specifics`（加 "player" group、连 roster/equipment 信号、初始化 PartyMemberStats、camera 配置）、player 独有接口。

```gdscript
extends CombatActorBase

# 玩家独有常量
const JUMP_VELOCITY := -420.0
const LADDER_SPEED := 140.0
# ... 其他玩家常量

# 玩家独有字段
var was_jump_pressed := false
var is_climbing_ladder := false
var current_ladder: Area2D
@onready var camera: Camera2D = $Camera2D
@onready var ladder_detector: Area2D = $LadderDetector
var _player_controlled := true
var _follow_target: Node2D = null
# ... 队友 AI 字段
var _combat_stats = preload("res://scripts/combat/party_member_stats.gd").new()
var character_id: int = 0


func _setup_actor_specifics() -> void:
    add_to_group("player")
    if character_id <= 0 and GameRegistry.roster_data != null:
        character_id = GameRegistry.roster_data.active_character_id
    _actor_scale = _get_configured_actor_scale()
    _apply_character_display_config()
    _refresh_combat_stats()
    # 连 roster/equipment 信号
    if GameRegistry.roster_data != null and not GameRegistry.roster_data.character_progress_changed.is_connected(_on_roster_progress_changed):
        GameRegistry.roster_data.character_progress_changed.connect(_on_roster_progress_changed)
    if GameRegistry.equipment_provider != null:
        if not GameRegistry.equipment_provider.equipped.is_connected(_on_equipment_changed):
            GameRegistry.equipment_provider.equipped.connect(_on_equipment_changed)
        if not GameRegistry.equipment_provider.unequipped.is_connected(_on_equipment_changed):
            GameRegistry.equipment_provider.unequipped.connect(_on_equipment_changed)
    camera.limit_left = 0
    camera.limit_top = 0
    camera.limit_right = LEVEL_SIZE.x
    camera.limit_bottom = LEVEL_SIZE.y
    sprite.play("idle")


func _update_actor(delta: float) -> void:
    if not _player_controlled:
        _update_ally_ai(delta)
        return
    var can_move := true
    if combat != null and combat.has_method("get_buff_manager"):
        var buff_manager = combat.get_buff_manager()
        if buff_manager != null and not buff_manager.can_move():
            can_move = false
    # 注：DEAD/HIT/anim_playing 已由基类 _can_process_combat 处理
    var direction := _get_move_direction()
    var climb_direction := _get_climb_direction()
    var jump_pressed := Input.is_physical_key_pressed(KEY_SPACE)
    _update_ladder_contact()
    if can_move:
        if is_climbing_ladder and current_ladder == null:
            _exit_ladder_state()
        elif not is_climbing_ladder and current_ladder != null and climb_direction != 0.0:
            _enter_ladder_state()
        if is_climbing_ladder:
            _handle_ladder_movement(direction, climb_direction, jump_pressed, delta)
        else:
            _handle_ground_movement(direction, jump_pressed, delta)
    else:
        velocity.x = 0.0
    if can_move and direction != 0.0:
        _face_direction(direction)
    _update_animation(direction)
    was_jump_pressed = jump_pressed


func _get_idle_animation() -> String:
    if not _player_controlled:
        return "idle"
    var direction := _get_move_direction()
    if not is_climbing_ladder and absf(direction) > 0.0 and is_on_floor():
        return "run"
    return "idle"


# override 基类，返回 PartyMemberStats
func get_combat_stats() -> BaseCombatStats:
    return _combat_stats

func get_combat_stats_typed() -> PartyMemberStats:
    return _combat_stats  # 内部强类型访问用

# 保留 player 独有接口
func set_party_character_id(value: int) -> void
func get_party_character_id() -> int
func set_player_controlled(value: bool) -> void
func is_player_controlled() -> bool
func set_follow_target(target: Node2D, slot_index: int = 0) -> void
func refresh_combat_stats() -> void
func sync_combat_hp() -> void
func get_skill_for_input(slot_name: String) -> int
func get_ai_skill_candidates() -> Array[int]
func get_ally_debug_state() -> String
# ... 队友 AI 全套（_update_ally_ai / _update_ally_follow / _update_ally_attack 等）
# ... 梯子/跳跃/移动（_handle_ground_movement / _handle_ladder_movement 等）
# ... _apply_character_display_config / _load_combat_actions / _get_configured_actor_scale
```

**关键点**：
- `_physics_process` 不再 override，由基类统一调度
- `_get_move_speed` 不再 override，用基类统一实现（读 `_combat_stats.move_speed`）
- 删除 `_facing_sign` 字段，原 L481 `_ally_attack_target` 中 `dir = -_facing_sign` 改为 `dir = -get_facing_sign()`
- 删除所有上提到基类的辅助函数和动画三件套

#### 2.3 改造 `scripts/enemy.gd`

继承 `CombatActorBase`，删除所有上提到基类的代码，保留：怪物状态机、`_setup_actor_specifics`（加 "enemies" group、连 died 信号、初始化 EnemyStats、预编译 AI 缓存）、enemy 独有接口。

```gdscript
extends CombatActorBase

enum AIState { IDLE, PATROL, CHASE, ATTACK, HIT, DEAD }

const CONFIG_FILE := "character_config.json"
# ... 其他 enemy 常量

var _enemy_id: int = 0
var _config: Dictionary = {}
var _character_config: Dictionary = {}
var _stats: EnemyStats = null
var _party_manager: PartyManager = null
var _target: CharacterBody2D = null
var _ai_state: AIState = AIState.IDLE
# ... 其他 enemy 字段


func _setup_actor_specifics() -> void:
    add_to_group("enemies")
    call_deferred("_connect_signals")


func init_from_config(enemy_id: int, party_manager: PartyManager) -> void:
    _enemy_id = enemy_id
    _party_manager = party_manager
    _config = GameRegistry.enemy_config.get_enemy(enemy_id)
    if _config.is_empty():
        push_error("怪物配置不存在: %s" % enemy_id)
        return
    _actor_scale = maxf(0.01, float(_config.get("actor_scale", 1.0)))
    _load_character_config()
    _stats = EnemyStats.new(_config)
    _load_combat_actions()
    _spawn_position = global_position
    if _party_manager != null:
        for member in _party_manager.get_party_members():
            add_collision_exception_with(member)
    _apply_display_config()
    _precompile_ai_caches()
    _set_ai_state(AIState.IDLE)


func _connect_signals() -> void:
    if combat != null and combat.has_signal("died"):
        combat.died.connect(_on_enemy_died)


func _update_actor(delta: float) -> void:
    _target_switch_timer = maxf(0.0, _target_switch_timer - delta)
    match _ai_state:
        AIState.IDLE:
            _update_idle(delta)
        AIState.PATROL:
            _update_patrol(delta)
        AIState.CHASE:
            _update_chase(delta)
        AIState.ATTACK:
            _update_attack(delta)


func _get_idle_animation() -> String:
    if _ai_state == AIState.CHASE or _ai_state == AIState.PATROL:
        return "run"
    return "idle"


# override 基类
func get_combat_stats() -> BaseCombatStats:
    return _stats

# 保留 enemy 独有接口
func get_enemy_name() -> String
func get_ai_state_name() -> String
func get_current_target() -> CharacterBody2D
func get_target_distance_x() -> float
func get_ai_debug_text() -> String
func init_from_config(enemy_id: int, party_manager: PartyManager) -> void
# ... 怪物状态机全套（_update_idle / _update_patrol / _update_chase / _update_attack 等）
# ... AI 缓存（_precompile_ai_caches / _get_ai_cache / _compile_ai_cache）
# ... 技能选择（_try_use_next_skill / _pick_weighted_skill 等）
# ... _apply_display_config / _load_character_config / _load_combat_actions
```

**关键点**：
- `_physics_process` 不再 override，由基类统一调度
- `_get_move_speed` 不再 override，用基类统一实现（读 `_stats.move_speed`）— **这就修正了原 L289 绕过 stats 的不一致**
- 删除所有上提到基类的辅助函数和动画三件套
- `_play_anim` 保留（enemy 独有的非战斗动画播放，与基类 `play_combat_animation` 不同）

---

## 第三部分：不改动的部分

- [combat_component.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/combat/combat_component.gd)：通过 `_owner.has_method(...)` 鸭子类型调用，基类已提供所有需要的方法
- [buff_manager.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/combat/buff_manager.gd) / [skill_executor.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/combat/skill_executor.gd) / [hit_box.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/combat/hit_box.gd) / [hurt_box.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/combat/hurt_box.gd)：已单文件共享
- [battle_hud.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/ui/battle_hud.gd) / [character_panel.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/ui/character_panel.gd) / [main_menu.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/ui/main_menu.gd) / [debug_panel.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/ui/debug_panel.gd)：依赖的字段和方法签名不变
- [party_manager.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/system/party_manager.gd)：调用 player 的接口（`set_party_character_id` / `set_player_controlled` / `set_follow_target` / `refresh_combat_stats` / `get_facing_sign`）签名不变
- [game_registry.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/game_registry.gd)：`CharacterStats.setup(roster, character_config)` 签名不变
- [enemy_spawner.gd](file:///e:/g_selfcustom/server_client/hengban-2/scripts/system/enemy_spawner.gd)：调用 `enemy.init_from_config(id, party_manager)` 签名不变

---

## 假设与决策

1. **基类位置**：`BaseCombatStats` 放 `scripts/combat/`（EnemyStats/PartyMemberStats 都在此目录）；`CombatActorBase` 放 `scripts/`（与 player.gd/enemy.gd 同级）
2. **不强制统一 class_name**：PartyMemberStats 保持 preload 方式
3. **take_damage/heal 不入 Stats 基类**：战斗路径由 combat_component 直接修改 `stats.hp`，CharacterStats 自带的未被战斗调用
4. **base_* / signal 不入 Stats 基类**：只有 CharacterStats 需要
5. **PartyMemberStats 继续走 GameRegistry 单例**：不改耦合方式，避免扩大改动面
6. **删除 player.gd 的 `_facing_sign` 字段**：改为通过 `get_facing_sign()` 从 `sprite.flip_h` 反查，消除 player/enemy 的接口差异
7. **`_physics_process` 上提到基类**：用模板方法 `_can_process_combat(delta) -> bool` + `_update_actor(delta)` 钩子；player 在 HIT 状态下 `velocity.x = 0.0`（直接清零）与 enemy 的 `move_toward(velocity.x, 0, 400*delta)`（平滑减速）差异 — **统一采用 enemy 的平滑减速**（更自然，player 的直接清零在 HIT 时无感知差异）
8. **enemy `_play_anim` 保留**：与基类 `play_combat_animation` 不同，前者是 AI 状态切换时播非战斗动画，后者是战斗动画锁定
9. **CombatActorBase.get_combat_stats() 返回 BaseCombatStats**：子类可提供强类型访问器（如 player 的 `get_combat_stats_typed()`）供内部使用

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| player 的 `_physics_process` 中 HIT 状态用直接清零，改平滑减速可能有手感差异 | HIT 持续时间仅 0.1s，减速差异不可感知 |
| `_facing_sign` 字段被多处引用，删除可能漏改 | grep `_facing_sign` 全部改为 `get_facing_sign()` |
| 基类 `_ready` 调用 `_setup_actor_specifics` 时 `@onready` 节点是否已就绪 | Godot 4 中 `_ready` 在 `@onready` 之后执行，安全 |
| enemy 的 `init_from_config` 在 `_ready` 之后被 spawner 调用，`_setup_actor_specifics` 中加 group 时机 | 加 group 在 `_setup_actor_specifics` 中，先于 `init_from_config`，安全 |
| CharacterStats.recalculate 签名变化 | 用 `_external_equipped_items` 缓存保持原签名，`equipment_provider.gd L71` 调用不变 |

## 验证步骤

1. **静态检查**：
   - 编辑器 GetDiagnostics 确认 4 个新/改 stats 文件 + 3 个 actor 文件无类型错误
   - Grep 确认 `_facing_sign` 已全部替换
   - Grep 确认 `EnemyStats` / `PartyMemberStats` / `CharacterStats` 调用方签名未变

2. **运行时验证（用户运行游戏确认）**：
   - 主控角色移动/跳跃/梯子正常（player 走基类 `_get_move_speed` → `_combat_stats.move_speed`）
   - 怪物移动/巡逻/追击正常（enemy 走基类 `_get_move_speed` → `_stats.move_speed`，验证不退化）
   - J/K/L/U 施法、怪物技能释放正常（combat_component 通过 `play_combat_animation` / `_end_combat_anim` / `get_combat_actions` 调用基类方法）
   - 受伤/死亡/回血正常（combat_component 通过 `take_damage` / `heal` / `sync_combat_hp` 调用基类代理方法）
   - Tab 切换主控角色正常（party_manager 调用 `set_player_controlled` / `set_follow_target` / `refresh_combat_stats`）
   - 装备武器后 attack 提升（equipment_provider → CharacterStats.recalculate → stats_changed → UI 刷新）
   - F3 调试面板显示的 HP/attack/defense/move_speed 与实际一致
   - 队友 AI 正常跟随与攻击（player.gd 的 `_update_ally_ai` 在基类 `_update_actor` 中被调用）
   - 怪物 AI 状态机正常（enemy.gd 的 `_update_actor` 中 match `_ai_state`）
   - 重启游戏 roster hp 持久化正确

3. **回归点**：
   - battle_hud 三处卡片（主控/队友/敌人）HP 显示
   - character_panel 监听 `stats_changed` 刷新
   - main_menu 角色/装备 Tab 属性显示
   - 队友 AI 的 `_face_attack_target` 中 `_facing_sign` 引用改 `get_facing_sign()`
