# 技能编辑器模板补充 v1

> 范围：在现有 7 个模板基础上补充新模板，提升新建技能效率 + 暴露孤儿节点用法
> 不在范围：模板参数化/复用机制（独立话题）、运行时改动、AI 行为

---

## 一、现状

### 1.1 现有 7 个模板（[skill_sequence_editor.gd:1683-1727](file:///e:/g_selfcustom/server_client/hengban-2/addons/game_tools/skill_sequence_editor.gd#L1683-L1727)）

| # | 方法 | 文案 | 节点序列 |
|---|---|---|---|
| 1 | _apply_melee_template | 套用普攻 | play_anim → wait_hit_window → melee_damage → wait_end → end |
| 2 | _apply_projectile_template | 套用单发弹道 | play_anim → wait_hit_window → spawn_projectile(single,straight) → wait_end → end |
| 3 | _apply_area_template | 套用范围伤害 | play_anim → wait_hit_window → area_damage → wait_end → end |
| 4 | _apply_fullscreen_template | 套用全场伤害 | play_anim → wait_hit_window → fullscreen_damage → play_effect → wait_end → end |
| 5 | _apply_self_buff_template | 套用自身 Buff | play_anim → wait_hit_window → apply_self_buff → wait_end → end |
| 6 | _apply_sequence_template | 套用三连弹道 | play_anim → wait_hit_window → spawn_projectile(sequence) → wait_end → end |
| 7 | _apply_rain_template | 套用向上箭雨 | play_anim → wait_hit_window → spawn_projectile(area_rain,ballistic) → wait_end → end |

### 1.2 现有技能节点序列覆盖情况
- 39 个技能中 ~77% 能被现有模板骨架覆盖
- 但若干常见/独特模式无模板示范

### 1.3 孤儿节点（已注册但 0 技能使用 + 0 模板覆盖）
| 节点 type | 使用次数 | 模板覆盖 |
|---|---|---|
| `heal` | 0 | 无 |
| `move_x` | 0 | 无 |
| `wait_action_frame` | 0 | 无 |
| `wait_time` | 0 | 无 |

### 1.4 字段覆盖空白
- `spawn_projectile.emission=fan`：1 次使用（6022），无模板
- `spawn_projectile.trajectory=ballistic + emission=single`（抛射单发）：1 次（50071），无模板
- `play_effect.coordinate_space=world`：0 次使用，无模板示范

---

## 二、设计原则

1. **补模板 = 补场景示范**：每个新模板对应一种未被现有模板覆盖的技能形态
2. **暴露孤儿节点**：用模板引导用户发现 heal/move_x/wait_action_frame/wait_time 用法
3. **保持按钮数量克制**：现有 7 + 新增 7 = 14 个按钮，分两行布局（4 列 × 4 行 改为更紧凑布局）
4. **不参数化**：模板仍是固定字面量，不引入变量替换（参数化是另一个话题）
5. **damage_channel/tag 示范**：魔法系模板显式写 `damage_channel="magic"`，物理系显式写 `physical`，让用户一眼看到差异

---

## 三、新增 7 个模板

### 模板 8：近战 + 自身 Buff
- **方法**：`_apply_melee_self_buff_template`
- **文案**：套用近战+自Buff
- **节点序列**：
  ```
  play_animation(action)
  wait_hit_window(0)
  melee_damage(result_key="melee_hit", damage_ratio=1.0, damage_channel="physical", damage_tag="slash")
  apply_self_buff(buff_ids=[])
  wait_animation_end
  end_skill
  ```
- **适用**：战士系技能，伤害同时给自己上狂暴/护盾/加速
- **参考**：50004/50042/50062（出现 3 次，是未模板化序列中最高频）

### 模板 9：群体目标 Buff
- **方法**：`_apply_area_buff_template`
- **文案**：套用群体Buff
- **节点序列**：
  ```
  play_animation(action)
  play_effect(coordinate_space="character_local", target="origin", scene="")
  wait_hit_window(0)
  apply_target_buff(target="area", origin="caster", radius=200.0, chance=1.0, buff_ids=[])
  wait_animation_end
  end_skill
  ```
- **适用**：辅助/buff 类技能，群体减速/群体增益/光环 debuff
- **参考**：6023（唯一使用 apply_target_buff 的技能，该节点当前 0 模板覆盖）

### 模板 10：扇形弹道
- **方法**：`_apply_fan_projectile_template`
- **文案**：套用扇形弹道
- **节点序列**：
  ```
  play_animation(action)
  wait_hit_window(0)
  play_effect(coordinate_space="character_local", target="origin", scene="")
  spawn_projectile(emission="fan", trajectory="straight", count=3, spread_degrees=20.0,
                   max_pierce=20, speed=300.0, lifetime=5.0, damage_ratio=1.5,
                   damage_channel="magic", damage_tag="fire", scene="")
  wait_animation_end
  end_skill
  ```
- **适用**：法师散射型技能（一发分叉为多道），兼顾施法特效 + 多段弹道
- **参考**：6022（唯一 emission=fan 的技能）
- **示范价值**：首次出现 `emission=fan` + `spread_degrees` 字段

### 模板 11：动作事件驱动 Buff（蓄力释放）
- **方法**：`_apply_event_buff_template`
- **文案**：套用事件Buff
- **节点序列**：
  ```
  play_animation(action)
  play_effect(coordinate_space="character_local", target="origin", scene="")
  wait_action_event(event="release")
  apply_self_buff(buff_ids=[])
  wait_animation_end
  end_skill
  ```
- **适用**：按动画事件精确触发的技能（蓄力释放、动画中段触发）
- **参考**：6013（唯一使用 wait_action_event 的技能，该节点当前 0 模板覆盖）

### 模板 12：强化大招（双特效 + 全屏伤害）
- **方法**：`_apply_ultimate_template`
- **文案**：套用大招
- **节点序列**：
  ```
  play_animation(action)
  play_effect(coordinate_space="fullscreen", target="origin", scene="", duration=2.0)
  play_effect(coordinate_space="character_local", origin="caster", target="origin", scene="")
  wait_hit_window(0)
  fullscreen_damage(damage_channel="magic", damage_tag="fire", damage_ratio=3.0)
  wait_animation_end
  end_skill
  ```
- **适用**：法师/Boss 大招，多层特效 + 全屏伤害
- **参考**：6024
- **与现有 _apply_fullscreen_template 的区别**：现有模板特效在伤害之后，本模板前置双特效符合大招节奏（先震慑再伤害）

### 模板 13：抛射弹道（重力下坠单发）
- **方法**：`_apply_ballistic_projectile_template`
- **文案**：套用抛射弹道
- **节点序列**：
  ```
  play_animation(action)
  wait_hit_window(0)
  spawn_projectile(trajectory="ballistic", emission="single", aim_mode="enemy_area",
                  arc_height=100.0, gravity=900.0, speed=360.0, lifetime=3.0,
                  damage_ratio=1.5, scene="")
  wait_animation_end
  end_skill
  ```
- **适用**：抛物线弹道（手雷/种子/箭矢高抛），不同于现有的直线 single 与箭雨 area_rain
- **参考**：50071（唯一 trajectory=ballistic + emission=single 的技能）

### 模板 14：位移技能（冲刺/后跳）
- **方法**：`_apply_dash_template`
- **文案**：套用位移
- **节点序列**：
  ```
  play_animation(action)
  wait_action_frame(frame=0)
  move_x(distance=64.0)
  wait_animation_end
  end_skill
  ```
- **适用**：冲刺/后跳技能
- **孤儿节点示范**：`move_x` + `wait_action_frame` 均为 0 使用 + 0 模板覆盖，本模板同时暴露两个孤儿节点

---

## 四、不补充的候选（理由）

| 候选 | 理由 |
|---|---|
| 治疗模板（heal） | heal 节点 0 使用，但游戏无治疗职业定位；若未来加牧师角色再补 |
| 等待时长模板（wait_time） | 单纯的等待通常是组合技能的子片段，单独成模板价值低 |
| 世界坐标特效模板（coordinate_space=world） | 0 技能使用，属未来扩展；现 5 个 character_local + 1 个 fullscreen 已够用 |
| 多段连击模板（melee_damage × N + wait_time） | 可用现有普攻模板 + 手动加 wait_time 组合，单独模板收益低 |

---

## 五、实施清单

### 5.1 修改文件
**`addons/game_tools/skill_sequence_editor.gd`**

#### 改动 1：模板按钮布局调整（约 322-329 行）
- 现有 7 按钮 + _clear_nodes 在 4 列 GridContainer 中占 2 行
- 新增 7 个按钮后共 15 个，改用 5 列布局占 3 行
- 或保持 4 列但加滚动条（紧凑）

#### 改动 2：新增 7 个模板方法（约 1683-1727 行后追加）
```gdscript
func _apply_melee_self_buff_template() -> void:
    var action := _default_action()
    _apply_template([
        {"type": "play_animation", "action": action},
        {"type": "wait_hit_window", "hit_window_index": 0},
        {"type": "melee_damage", "result_key": "melee_hit", "damage_ratio": 1.0,
         "damage_channel": "physical", "damage_tag": "slash"},
        {"type": "apply_self_buff", "buff_ids": []},
        {"type": "wait_animation_end"},
        {"type": "end_skill"}
    ], "已套用近战+自Buff模板。")

func _apply_area_buff_template() -> void:
    var action := _default_action()
    _apply_template([
        {"type": "play_animation", "action": action},
        {"type": "play_effect", "coordinate_space": "character_local",
         "target": "origin", "scene": ""},
        {"type": "wait_hit_window", "hit_window_index": 0},
        {"type": "apply_target_buff", "target": "area", "origin": "caster",
         "radius": 200.0, "chance": 1.0, "buff_ids": []},
        {"type": "wait_animation_end"},
        {"type": "end_skill"}
    ], "已套用群体Buff模板，请填写 buff_ids 与特效场景。")

func _apply_fan_projectile_template() -> void:
    var action := _default_action()
    _apply_template([
        {"type": "play_animation", "action": action},
        {"type": "wait_hit_window", "hit_window_index": 0},
        {"type": "play_effect", "coordinate_space": "character_local",
         "target": "origin", "scene": ""},
        {"type": "spawn_projectile", "emission": "fan", "trajectory": "straight",
         "count": 3, "spread_degrees": 20.0, "max_pierce": 20,
         "speed": 300.0, "lifetime": 5.0, "damage_ratio": 1.5,
         "damage_channel": "magic", "damage_tag": "fire", "scene": ""},
        {"type": "wait_animation_end"},
        {"type": "end_skill"}
    ], "已套用扇形弹道模板，请填写弹道场景。")

func _apply_event_buff_template() -> void:
    var action := _default_action()
    _apply_template([
        {"type": "play_animation", "action": action},
        {"type": "play_effect", "coordinate_space": "character_local",
         "target": "origin", "scene": ""},
        {"type": "wait_action_event", "event": "release"},
        {"type": "apply_self_buff", "buff_ids": []},
        {"type": "wait_animation_end"},
        {"type": "end_skill"}
    ], "已套用事件Buff模板，需动作配置 release 事件。")

func _apply_ultimate_template() -> void:
    var action := _default_action()
    _apply_template([
        {"type": "play_animation", "action": action},
        {"type": "play_effect", "coordinate_space": "fullscreen",
         "target": "origin", "scene": "", "duration": 2.0},
        {"type": "play_effect", "coordinate_space": "character_local",
         "origin": "caster", "target": "origin", "scene": ""},
        {"type": "wait_hit_window", "hit_window_index": 0},
        {"type": "fullscreen_damage", "damage_channel": "magic",
         "damage_tag": "fire", "damage_ratio": 3.0},
        {"type": "wait_animation_end"},
        {"type": "end_skill"}
    ], "已套用大招模板，请填写两个特效场景。")

func _apply_ballistic_projectile_template() -> void:
    var action := _default_action()
    _apply_template([
        {"type": "play_animation", "action": action},
        {"type": "wait_hit_window", "hit_window_index": 0},
        {"type": "spawn_projectile", "trajectory": "ballistic", "emission": "single",
         "aim_mode": "enemy_area", "arc_height": 100.0, "gravity": 900.0,
         "speed": 360.0, "lifetime": 3.0, "damage_ratio": 1.5, "scene": ""},
        {"type": "wait_animation_end"},
        {"type": "end_skill"}
    ], "已套用抛射弹道模板，请填写弹道场景。")

func _apply_dash_template() -> void:
    var action := _default_action()
    _apply_template([
        {"type": "play_animation", "action": action},
        {"type": "wait_action_frame", "frame": 0},
        {"type": "move_x", "distance": 64.0},
        {"type": "wait_animation_end"},
        {"type": "end_skill"}
    ], "已套用位移模板。")
```

#### 改动 3：按钮注册（约 322-329 行）
现有按钮后追加 7 个：
```gdscript
_add_template_button("近战+自Buff", "_apply_melee_self_buff_template")
_add_template_button("群体Buff", "_apply_area_buff_template")
_add_template_button("扇形弹道", "_apply_fan_projectile_template")
_add_template_button("事件Buff", "_apply_event_buff_template")
_add_template_button("大招", "_apply_ultimate_template")
_add_template_button("抛射弹道", "_apply_ballistic_projectile_template")
_add_template_button("位移", "_apply_dash_template")
```

---

## 六、假设与决策

### 6.1 假设
1. 现有 7 模板保留不变，不与新增模板合并（保持向后兼容）
2. 模板仍是固定字面量，不引入参数化机制
3. 新增按钮数量 7 个，总按钮 15 个，可能需要调整 GridContainer 列数或加滚动

### 6.2 决策依据
- 每个新模板都对应至少 1 个未被现有模板覆盖的真实技能（参考技能 ID）
- 优先补"高频未模板化序列"（近战+自Buff 出现 3 次）
- 其次补"孤儿节点"（apply_target_buff/wait_action_event/move_x/wait_action_frame）
- 最后补"字段覆盖空白"（emission=fan、ballistic+single、双 play_effect）

### 6.3 不做的事
- 不参数化模板（变量替换是独立话题）
- 不引入片段库/ref 机制（上一轮规划已涉及，本轮聚焦模板补充）
- 不修改现有 7 模板（保持兼容）
- 不补治疗/wait_time 模板（使用场景不足）

---

## 七、验证步骤

### 7.1 编译验证
```powershell
$env:HOME="E:\g_selfcustom\tmp_godot"
& "E:\g_selfcustom\Godot_v4.7-stable_win64.exe" --headless --check-only --path "E:\g_selfcustom\server_client\hengban-2" --quit
```

### 7.2 编辑器实测
- 打开技能编辑器 → 确认 14 个模板按钮 + 清空按钮可见
- 点击每个新模板按钮 → 确认节点列表被正确替换为对应序列
- 切换技能后再点模板 → 确认不串状态
- 验证 `_apply_template` 提示文案正确显示

### 7.3 节点字段对照
逐个新模板的节点字段应与 _default_node 返回的默认值兼容：
- `wait_action_event` 默认 event="release" ✓
- `wait_action_frame` 默认 frame=0 ✓
- `move_x` 默认 distance=0（模板给 64.0） ✓
- `apply_target_buff` target="area" ✓
- `spawn_projectile` emission="fan" ✓

### 7.4 字段覆盖空白验证
点击新模板后，节点应包含此前 0 模板覆盖的字段：
- 扇形弹道模板：emission="fan" ✓
- 抛射弹道模板：trajectory="ballistic" + emission="single" ✓
- 大招模板：双 play_effect（fullscreen + character_local） ✓
- 位移模板：wait_action_frame + move_x ✓
