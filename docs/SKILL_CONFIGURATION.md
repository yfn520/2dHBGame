# 技能节点配置

技能由 `data/skills.json` 的线性节点序列定义。技能根只保存名称、说明、冷却、AI 施放距离和 `nodes`；不再有技能类型、全局伤害、全局弹道、`effect_timing` 或旧流程回退。

```json
{
  "name": "火球术",
  "cooldown": 3.0,
  "cast_range": 300,
  "nodes": []
}
```

`cast_range` 为 0 时，AI 使用角色或怪物自身的默认攻击距离。

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
  {"type": "play_effect", "scene": "res://scenes/effects/hit.tscn", "target": "result", "result_key": "explosion_hit", "delivery": "each_target"}
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
  "scene": "res://scenes/effects/projectiles/arrow.tscn",
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
  "damage_ratio": 0.8
}
```

弹道配置分为三部分：

| 配置 | 选项 | 含义 |
| --- | --- | --- |
| 轨迹 | `straight`、`ballistic` | 直线或抛物线飞行 |
| 瞄准/落点 | `facing_elevation`、`nearest_enemy`、`enemy_area`、`forward_area` | 决定飞行方向或箭雨落点 |
| 发射方式 | `single`、`sequence`、`fan`、`area_rain` | 单发、连续、扇形和区域落雨 |

仰角正值向上，0 为水平。`min_range` 是 AI 使用弹道的最小距离，可避免贴身时弹道刚出生就命中；扇形使用 `spread_degrees`；连续使用 `count` 与 `interval`；区域落雨使用 `target_search_range`、`area_width`、`area_height`、`arc_height` 和 `gravity`。

弹道命中特效：

```json
[
  {"type": "spawn_projectile", "result_key": "fireball_hit", "scene": "res://scenes/effects/projectiles/fireball.tscn", "origin": "hit_window", "trajectory": "straight", "aim_mode": "facing_elevation", "emission": "single", "speed": 300, "lifetime": 5, "damage_ratio": 1.5},
  {"type": "play_effect", "scene": "res://scenes/effects/fireball_impact.tscn", "target": "result", "result_key": "fireball_hit", "delivery": "each_hit"}
]
```

发射节点先生成弹道；特效节点随后订阅 `fireball_hit`。弹道碰到敌人时先造成伤害，再在目标 HurtBox 中心播放特效。

## 常用模板

- 普攻：播放动画 -> 等待有效区间 -> 近战伤害 -> 等待动画结束 -> 结束。
- 单发弹道：播放动画 -> 等待有效区间 -> 发射弹道 -> 等待动画结束 -> 结束。
- 三连箭：将发射方式设为 `sequence`，设置数量和间隔。
- 向上箭雨：轨迹选 `ballistic`，瞄准选 `enemy_area`，发射方式选 `area_rain`，设置抛射高度、区域和重力。
- 范围/全场受击特效：伤害节点写入结果集，后接目标为该结果集的播放特效节点。
