# 技能配置说明

技能配置分成两部分：

1. `data/skills.json`：技能类型、伤害、冷却、弹道场景、Buff ID 等数值参数。
2. `assets/**/combat_actions.json`：动作的攻击判定框、动画事件、受击霸体和插槽位置。

“配置技能节点”窗口里的节点，只负责组织技能释放流程。节点里的英文值是程序内部值，界面显示为中文。

## 一、节点和事件的区别

### 技能节点

节点是技能释放时执行的动作：

| 节点 | 用途 | 常见用法 |
| --- | --- | --- |
| 播放动画 | 播放指定动作 | 第一个节点 |
| 技能生效点（判定框） | 根据当前动画帧执行近战伤害、弹道发射或技能生效 | 普攻、弹道、自身 Buff |
| 等待动作事件 | 等待动画中的 `release`、`impact` 或 `effect` 事件 | 事件驱动的技能 |
| 等待动画结束（阻塞） | 等待动作播放完，期间暂停后续节点 | 技能末尾 |
| 执行技能效果 | 按技能 `type` 执行伤害、弹道或范围效果 | 事件驱动的技能 |
| 生成弹道 | 执行弹道技能 | 一般优先使用攻击判定框模板 |
| 范围攻击 | 执行范围伤害 | 范围技能 |
| 施加自身 Buff | 施加 `buff_on_self` | 简单的自身 Buff |
| 治疗 | 直接治疗，数值来自节点 `amount` | 回复技能 |
| 播放特效 | 实例化 `scene` 或 `effect_scene` | 特效、音效配合 |
| 结束技能（立即结束） | 立即结束当前技能流程并清理战斗状态 | 通常放在等待动画结束之后 |

### 动画事件

事件写在对应动作的 `combat_actions.json` 中，例如：

```json
{
  "events": [
    {"name": "release", "frame": 2},
    {"name": "impact", "frame": 4},
    {"name": "effect", "frame": 3}
  ]
}
```

事件只表示“动画播放到了某一帧”。它需要由“等待动作事件”节点消费，后面的节点才会继续执行：

```json
[
  {"type": "play_animation", "action": "skill1"},
  {"type": "wait_action_event", "event": "release"},
  {"type": "execute_skill_effect"},
  {"type": "wait_animation_end"},
  {"type": "end_skill"}
]
```

`release`、`impact`、`effect` 没有固定的伤害含义，名字只是约定：

- `release`：释放、发射、出手的时刻。
- `impact`：命中或爆炸的时刻。
- `effect`：播放特效、声音或附加表现的时刻。

事件不会自动造成伤害，也不会自动生成弹道。必须在等待事件后面接“执行技能效果”“生成弹道”或“播放特效”等节点。

技能节点工具的事件下拉只显示当前动作从外部工具导出的实际事件。若外部工具没有导出 `release`、`impact` 或 `effect`，下拉不会伪造该事件，窗口会提示编辑者，必须回到外部动作工具或 `combat_actions.json` 中补上对应帧。

时间轴会根据当前技能 ID 查找 `data/characters.json` 和 `data/enemies.json` 中所属角色或怪物的 `asset`，再读取该资源下的 `combat_actions.json`。因此同名的 `attack`、`skill1` 不会再误用其他角色的动作配置。

## 二、攻击判定框和事件怎么选

### 技能生效点（判定框）

这个节点不是单纯的“碰撞框节点”，而是一个动画有效帧触发器。工具中选择“生效方式”后，它可以执行三种行为：

- `近战伤害`：启用判定框，命中敌人后造成近战伤害。
- `弹道发射`：不直接造成伤害，在有效帧从判定框中心生成弹道。
- `技能生效帧`：不直接造成伤害，用有效帧触发自身 Buff 或其他技能效果。

攻击判定框配置在动作的 `hit_windows` 中：

```json
{
  "hit_windows": [
    {
      "start_frame": 2,
      "end_frame": 2,
      "authored_x": -24.0,
      "y": -32.0,
      "width": 35.0,
      "height": 36.0
    }
  ]
}
```

判定框中心同时用于弹道的出生点。要调整弹道上下位置，修改判定框的 `y`；要调整左右位置，修改 `authored_x` 或 `forward`。

推荐用于：

- 普攻伤害。
- 弹道发射。
- 有明确攻击动作的 Buff 技能。

### 使用动作事件

事件适合技能效果不需要碰撞框，或者需要把多个效果安排在不同动画时刻的情况，例如：

```text
播放动画 -> 等待 release -> 生成弹道 -> 等待 impact -> 播放爆炸特效 -> 结束技能
```

如果同一个技能同时使用攻击判定框和事件，要避免两条流程都执行伤害或发射，否则可能重复触发。

当前项目推荐：普攻和弹道使用攻击判定框；只有需要精确按事件分段执行时才使用 `wait_action_event`。

## 三、节点顺序

节点列表从上到下就是技能的执行顺序。选择一个节点后，点击列表下方的“上移”或“下移”即可调整顺序；移动到列表边界时对应按钮会自动禁用。调整只会改变 `nodes` 数组的顺序，不会修改节点内部参数。

调整后要点击“保存 skills.json”，下次打开技能时顺序才会保留。

常用顺序如下：

```text
普攻：播放动画 -> 使用攻击判定框 -> 等待动画结束 -> 结束技能
弹道：播放动画 -> 使用攻击判定框 -> 等待动画结束 -> 结束技能
事件技能：播放动画 -> 等待动作事件 -> 执行技能效果/生成弹道 -> 等待动画结束 -> 结束技能
特效：播放动画 -> 等待动作事件 impact -> 播放特效 -> 等待动画结束 -> 结束技能
```

节点顺序错误时，技能可能会提前结束、永远等待事件，或在攻击判定框启用前就执行技能效果。

## 四、技能时间轴和节点触发时机

“配置技能节点”窗口中的时间轴分为动画事件、攻击有效区间和技能节点区域。技能节点区域会按照节点顺序一节点一行显示，避免多个节点在同一帧时文字重叠。节点列表仍然表示逻辑顺序，时间轴表示节点真正执行的动画时机。

时间轴中使用黄色表示动画事件、绿色表示攻击有效区间、紫色表示未选中的技能节点、蓝色表示当前选中的技能节点。时间轴上的文字使用中文显示，`skills.json` 仍然保存英文内部值。

选中节点后，可以设置：

| 触发方式 | 说明 | 额外配置 |
| --- | --- | --- |
| 立即执行 | 技能流程走到该节点时立即执行 | 无 |
| 动画事件 | 等待 `release`、`impact` 或 `effect` | 选择事件 |
| 攻击有效区间 | 等待指定的 `hit_windows` 区间开始 | 选择第几个有效区间 |
| 动画结束 | 等待当前动作播放结束 | 无 |

一个动作有多个有效区间时，时间轴会显示为 `#1`、`#2` 等。节点绑定“第 2 个有效区间”后，只会在第 2 个区间触发，不会因为第 1 个区间先出现而提前执行。

节点触发时机会保存到节点自身：

```json
{
  "type": "play_effect",
  "scene": "res://scenes/effects/fireball_fx.tscn",
  "trigger": "hit_window",
  "hit_window_index": 0
}
```

节点没有 `trigger` 字段时，表示旧版的“立即执行”，保持向后兼容。

## 五、通用配置模板

### 1. 普攻

在“配置技能节点”中选择动作后，点击“套用普攻模板”：

```json
{
  "type": "melee",
  "animation": "attack",
  "damage_ratio": 1.0,
  "cooldown": 0.5,
  "effect_timing": "active_frame",
  "nodes": [
    {"type": "play_animation", "action": "attack"},
    {"type": "use_action_hit_window", "action": "attack", "detects_hits": true, "trigger": "hit_window", "hit_window_index": 0},
    {"type": "wait_animation_end"},
    {"type": "end_skill"}
  ]
}
```

然后在“配置攻击判定”中设置 `attack` 动作的有效帧。`detects_hits: true` 表示判定框会对敌人造成近战伤害。

### 2. 弹道技能

点击“套用弹道模板”，再填写弹道场景和技能数值：

```json
{
  "type": "projectile",
  "animation": "skill1",
  "damage_ratio": 1.5,
  "cooldown": 3.0,
  "range": 300,
  "projectile_scene": "res://scenes/effects/projectiles/fireball.tscn",
  "projectile_speed": 300.0,
  "projectile_lifetime": 5.0,
  "max_pierce": 0,
  "effect_timing": "active_frame",
  "nodes": [
    {"type": "play_animation", "action": "skill1"},
    {"type": "use_action_hit_window", "action": "skill1", "detects_hits": false, "trigger": "hit_window", "hit_window_index": 0},
    {"type": "wait_animation_end"},
    {"type": "end_skill"}
  ]
}
```

`detects_hits: false` 表示攻击判定框不直接造成伤害；当动画进入有效帧时，程序从判定框中心生成弹道。弹道之后再通过自己的碰撞检测造成伤害。

### 3. 自身正向 Buff

点击“套用自身 Buff 模板”，并填写 `buff_on_self`：

```json
{
  "type": "self",
  "animation": "skill2",
  "cooldown": 5.0,
  "buff_on_self": 1005,
  "effect_timing": "active_frame",
  "nodes": [
    {"type": "play_animation", "action": "skill2"},
    {"type": "use_action_hit_window", "action": "skill2", "detects_hits": false, "trigger": "hit_window", "hit_window_index": 0},
    {"type": "wait_animation_end"},
    {"type": "end_skill"}
  ]
}
```

自身 Buff 不需要攻击敌人，但仍建议配置一个有效帧作为施加时刻。`buff_on_self` 的 ID 必须存在于 `data/buffs.json`。

### 4. 普攻附带 Buff

普通近战攻击只需要在普攻配置上增加目标 Buff：

```json
{
  "type": "melee",
  "damage_ratio": 1.0,
  "buff_on_hit": 1001,
  "buff_chance": 1.0,
  "nodes": [
    {"type": "play_animation", "action": "attack"},
    {"type": "use_action_hit_window", "action": "attack", "detects_hits": true, "trigger": "hit_window", "hit_window_index": 0},
    {"type": "wait_animation_end"},
    {"type": "end_skill"}
  ]
}
```

### 5. 多段攻击和事件特效

多段攻击要为每一段创建独立节点，并分别绑定有效区间：

```text
播放动画
近战伤害（第 1 个有效区间）
播放特效（第 1 个有效区间）
近战伤害（第 2 个有效区间）
播放特效（第 2 个有效区间）
等待动画结束
结束技能
```

不依赖攻击框的特效可以直接绑定动画事件：

```text
播放动画
播放特效（impact 事件）
等待动画结束
结束技能
```

这种情况下，“播放特效”节点的触发方式选择“动画事件”，事件选择 `impact`。

## 六、推荐操作顺序

1. 在 `skills.json` 中选择或创建技能，填写 `type`、伤害倍率、冷却、弹道场景或 Buff ID。
2. 打开“游戏工具 > 配置技能节点”。
3. 选择技能和动作，点击对应模板。
4. 打开“游戏工具 > 配置攻击判定”，给动作设置有效帧和判定框位置。
5. 需要分段触发时，再添加“等待动作事件”节点，并选择 `release`、`impact` 或 `effect`。
6. 点击“保存 skills.json”。

## 七、常见错误

- 弹道不出现：检查 `projectile_scene` 是否存在，并确认动作有有效帧。
- 弹道位置不对：调整 `hit_windows` 的 `y`、`authored_x` 或 `forward`，不要只移动弹道场景根节点。
- 普攻不造成伤害：确认节点使用 `detects_hits: true`，并且动作有效帧覆盖当前动画帧。
- Buff 不生效：确认 Buff ID 存在，并使用 `buff_on_self` 或 `buff_on_hit` 的正确字段。
- 伤害或弹道触发两次：检查是否同时使用了攻击判定框和事件驱动的执行节点。
