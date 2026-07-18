# 技能节点配置

技能由 `data/skills.json` 的线性节点序列定义。技能根只保存名称、说明、冷却和 `nodes`；不再有技能类型、全局伤害、全局弹道、`effect_timing` 或旧流程回退。AI 起手距离完全由各伤害节点和角色/怪物的攻击框自动计算，技能根不再保存 `cast_range`。

```json
{
  "name": "火球术",
  "cooldown": 3.0,
  "nodes": [],
  "ai_range_cache": {
    "policy": "any_damage_node",
    "source_hash": "abc123def4567890",
    "entries": [
      {"node_index": 2, "source": "projectile", "kind": "projectile", "min_edge_distance": 90, "max_edge_distance": 300}
    ]
  }
}
```

`ai_range_cache` 是只读字段，由编辑器保存或角色/怪物导入工具自动写入；不需要手工配置，也不作为第二套玩法表。运行时若缓存为空或与当前节点/攻击框不一致，怪物 AI 与队友 AI 会按当前所属资源即时重编译。

## 节点 AI 距离来源

| 节点类型 | AI 距离来源 | 是否可手填 |
| --- | --- | --- |
| `melee_damage` | 前置 `wait_hit_window` 对应攻击框 + 角色身体框 + `actor_scale` | 不可手填，自动计算 |
| `area_damage` | `origin` + 半径/矩形范围 自动计算 | 不可手填，自动计算 |
| `spawn_projectile` | 节点 `ai_min_range` / `ai_max_range` | 可手填，仅服务 AI，不影响弹道实际飞行 |
| `fullscreen_damage` | 检测范围内均可起手 | 不可手填 |
| `apply_target_buff` | 跟随前置伤害结果 | 不单独决定起手距离 |
| `apply_self_buff` / `heal` / `play_effect` | 不计入攻击距离 | — |

近战最大边缘距离：`(forward + width/2) * actor_scale - body_half_width - 安全余量`。例：史莱姆 forward=36、width=27、body_size.x=24、scale=1.0 时，`max_edge ≈ (36+13.5) - 12 - 2 = 35.5`。

多伤害节点技能采用 `any_damage_node` 策略：任意一个伤害节点的区间能命中当前目标边缘距离，就允许起手。例如“火球 + 近战斩击”可在火球距离起手；近战段够不到则自然不命中。

## 节点顺序

节点从上到下执行。动作节点产生效果，控制节点决定后面的动作何时执行。

动作节点：播放动画、近战伤害、范围伤害、全场伤害、发射弹道、播放特效、目标 Buff、自身 Buff、治疗、水平移动。

控制节点：等待动作事件、等待攻击有效区间、等待动画结束、等待时长、结束技能。

常规普攻：

```text
播放动画
-> 等待攻击有效区间 #1
-> 近战伤害
-> 等待动画结束
-> 结束技能
```

动作事件和攻击有效区间来自所属角色/怪物资源中的 `combat_actions.json`。外部数据没有导出事件或有效区间时，编辑器会显示为空，运行时不会补默认帧。

## 命中结果集

近战、范围、全场和弹道节点使用 `result_key` 发布目标。后续特效或目标 Buff 节点可把“目标”设为“命名结果集”。

```json
[
  {"type": "area_damage", "result_key": "explosion_hit", "origin": "hit_window", "shape": "circle", "radius": 100, "damage_ratio": 1.5},
  {"type": "play_effect", "scene": "res://assets/effects/hit.tscn", "target": "result", "result_key": "explosion_hit", "delivery": "each_target"}
]
```

`delivery`：

- `each_hit`：每次命中都触发。三支箭命中同一怪物三次，会播放三次。
- `each_target`：同一个目标只触发一次。适合范围或全场表现。

近战判定框和弹道都会实时发布结果，因此命中特效与目标 Buff 会在实际命中时出现，即使技能动画已经结束。

## 弹道节点

`spawn_projectile` 自己配置弹道场景、伤害、Buff、出生位置和发射方式：

```json
{
  "type": "spawn_projectile",
  "result_key": "arrow_hit",
  "scene": "res://assets/effects/projectiles/arrow.tscn",
  "origin": "socket",
  "socket": "bow",
  "trajectory": "straight",
  "aim_mode": "facing_elevation",
  "elevation_degrees": 25,
  "emission": "sequence",
  "count": 3,
  "interval": 0.15,
  "speed": 420,
  "lifetime": 2.0,
  "max_pierce": 0,
  "damage_ratio": 0.8,
  "ai_min_range": 0,
  "ai_max_range": 300
}
```

弹道配置分为三部分：

| 配置 | 选项 | 含义 |
| --- | --- | --- |
| 轨迹 | `straight`、`ballistic` | 直线或抛物线飞行 |
| 瞄准/落点 | `facing_elevation`、`nearest_enemy`、`enemy_area`、`forward_area` | 决定飞行方向或箭雨落点 |
| 发射方式 | `single`、`sequence`、`fan`、`area_rain` | 单发、连续、扇形和区域落雨 |

仰角正值向上，0 为水平。`ai_min_range` / `ai_max_range` 是 AI 起手距离的设计参数：怪物或队友 AI 只在目标边缘距离落入此区间时才选择该弹道技能，但不影响弹道实际飞行距离；扇形使用 `spread_degrees`；连续使用 `count` 与 `interval`；区域落雨使用 `target_search_range`、`area_width`、`area_height`、`arc_height` 和 `gravity`。

弹道命中特效：

```json
[
  {"type": "spawn_projectile", "result_key": "fireball_hit", "scene": "res://assets/effects/projectiles/fireball.tscn", "origin": "hit_window", "trajectory": "straight", "aim_mode": "facing_elevation", "emission": "single", "speed": 300, "lifetime": 5, "damage_ratio": 1.5, "ai_min_range": 90, "ai_max_range": 300},
  {"type": "play_effect", "scene": "res://assets/effects/fireball_impact.tscn", "target": "result", "result_key": "fireball_hit", "delivery": "each_hit"}
]
```

发射节点先生成弹道；特效节点随后订阅 `fireball_hit`。弹道碰到敌人时先造成伤害，再在目标 HurtBox 中心播放特效。

## AI 行为

- 怪物 AI 不再以 `enemies.json.attack_range` 决定何时停步；`attack_range` 保留旧表兼容，运行时不再作为攻击停止距离。
- AI 每次更新只读取当前怪物的 1 个普攻和最多 3 个技能的 `ai_range_cache`。
- 当前目标边缘距离落入任意“冷却完成的伤害节点区间”时，才随机选择对应技能并停止释放。
- 目标距离不在任何可释放区间：
  - 太远：继续追击到最近的可用最大距离。
  - 过近：优先改用其他近距离技能；若只有设置了最小距离的远程节点，则短距离后撤至其最小距离。
- 远程技能在最大距离释放后进入冷却，怪物立即继续向目标移动，寻找普攻或近战技能的有效区间。
- 玩家手动释放不受 AI 距离限制；距离缓存只服务队友 AI 和怪物 AI。

## 编辑器与导入联动

- 技能节点编辑器基础页不再显示“AI 施放距离”。
- `melee_damage` 节点显示只读的“近战自动有效距离：0～35”及其攻击框来源。
- `area_damage` 节点显示自动计算结果。
- `spawn_projectile` 节点显示可编辑的“AI 最小/最大起手距离”。
- 保存技能时自动调用 `AIRangeCompiler` 生成 `ai_range_cache` 并写回 `skills.json`。
- 重新导入角色/怪物动作（`import_character.gd`）后，自动重编译使用该资源的所有技能 `ai_range_cache`，不覆盖技能节点、伤害、Buff、冷却和人工填写的弹道 AI 起手距离。

## 旧数据迁移

- 旧技能顶层 `cast_range` 自动迁入第一个 `spawn_projectile` 节点的 `ai_max_range`；旧近战技能的 `cast_range` 丢弃，改用攻击框自动值。
- `enemies.json.attack_range` 不删除，标记为旧字段，后续新导入不再生成。
- 运行时若 `ai_range_cache` 缺失或 `source_hash` 与当前节点/攻击框不一致，怪物与队友 AI 会按当前所属资源即时重编译。

## F3 调试

F3 调试面板为每个怪物显示：

```text
AI: CHASE
目标边缘距离: 78
追击至 35（当前 78）
可用节点:
  · 普攻/melee: 0~35 太远
  · 火球/projectile: 90~300 太近
```

## 常用模板

- 普攻：播放动画 -> 等待有效区间 -> 近战伤害 -> 等待动画结束 -> 结束。
- 单发弹道：播放动画 -> 等待有效区间 -> 发射弹道 -> 等待动画结束 -> 结束。
- 三连箭：将发射方式设为 `sequence`，设置数量和间隔。
- 向上箭雨：轨迹选 `ballistic`，瞄准选 `enemy_area`，发射方式选 `area_rain`，设置抛射高度、区域和重力。
- 范围/全场受击特效：伤害节点写入结果集，后接目标为该结果集的播放特效节点。
