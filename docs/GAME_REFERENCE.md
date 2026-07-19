# Hengban-2 游戏参考手册

## 1. 按键绑定

### 移动

| 按键 | 功能 |
|------|------|
| 左方向键 | 向左移动 |
| 右方向键 | 向右移动 |
| 上方向键 | 爬梯子向上 |
| 下方向键 | 爬梯子向下 |
| 空格 | 跳跃 |

### 战斗

| 按键 | 功能 | 技能ID | 冷却 |
|------|------|--------|------|
| J | 普攻（近战） | 1001 | 0.5秒 |
| K | 技能1：火球术（弹道） | 1002 | 3秒 |
| L | 技能2：旋风斩（范围） | 1003 | 5秒 |
| U | 技能3：冰霜箭（穿透） | 1004 | 4秒 |

### 界面

| 按键 | 功能 |
|------|------|
| B | 打开/关闭背包 |
| C | 打开/关闭角色面板 |
| E | 穿戴选中的物品（背包打开时） |
| D | 丢弃选中的物品（背包打开时） |
| Esc | 关闭当前面板 |

### 系统

| 按键 | 功能 |
|------|------|
| R | 重新加载当前关卡（测试用） |
| E | 进入传送门（靠近传送门时） |

---

## 2. 物品配置表 (items.xlsx)

来源：`data/excel/items.xlsx` → `data/items.json`

| ID | 名称 | 类型 | 可堆叠 | 上限 | 攻击 | 防御 | 生命 | 速度 | 回复 |
|----|------|------|--------|------|------|------|------|------|------|
| 1001 | 铁剑 | weapon | 否 | 1 | 5 | 0 | 0 | 0 | 0 |
| 1002 | 铁甲 | armor | 否 | 1 | 0 | 3 | 10 | 0 | 0 |
| 1003 | 铁靴 | boots | 否 | 1 | 0 | 1 | 0 | 10 | 0 |
| 1004 | 生命戒指 | accessory | 否 | 1 | 0 | 0 | 20 | 0 | 0 |
| 2001 | 回复药水 | consumable | 是 | 99 | 0 | 0 | 0 | 0 | 30 |
| 2002 | 解毒草 | consumable | 是 | 99 | 0 | 0 | 0 | 0 | 0 |
| 3001 | 木材 | material | 是 | 999 | 0 | 0 | 0 | 0 | 0 |
| 3002 | 铁矿石 | material | 是 | 999 | 0 | 0 | 0 | 0 | 0 |

### 物品类型

| 类型 | 装备槽 | 说明 |
|------|--------|------|
| weapon | 武器 | 主手武器 |
| armor | 护甲 | 身体护甲 |
| boots | 靴子 | 鞋子 |
| accessory | 饰品 | 戒指/项链 |
| consumable | - | 可使用物品（药水等） |
| material | - | 合成材料 |

---

## 3. 技能配置表 (skills.xlsx)

来源：`data/excel/skills.xlsx` → `data/skills.json`

| ID | 名称 | 类型 | 伤害倍率 | 冷却 | 动画 | 射程 | 穿透 | AOE半径 | 命中Buff | 概率 | 自身Buff |
|----|------|------|----------|------|------|------|------|---------|----------|------|----------|
| 1001 | 普攻 | melee | 1.0 | 0.5秒 | attack | 40 | 0 | 0 | 0 | 0 | 0 |
| 1002 | 火球术 | projectile | 1.5 | 3秒 | skill1 | 300 | 0 | 0 | 2001(燃烧) | 100% | 0 |
| 1003 | 旋风斩 | aoe | 2.0 | 5秒 | skill2 | 0 | 0 | 80 | 0 | 0 | 1005(无敌) |
| 1004 | 冰霜箭 | penetrate | 1.2 | 4秒 | skill3 | 400 | 无限 | 0 | 1003(冰冻) | 50% | 0 |
| 1005 | 全屏斩 | fullscreen | 3.0 | 10秒 | skill2 | 0 | 0 | 0 | 0 | 0 | 0 |

### 技能类型

| 类型 | 说明 |
|------|------|
| melee | 角色前方 HitBox，瞬时判定 |
| projectile | 生成弹道场景，向前飞行，命中销毁 |
| penetrate | 穿透弹道，命中后继续飞行（max_pierce=-1 为无限穿透） |
| aoe | 以角色为中心的范围内所有敌人受伤 |
| fullscreen | 场景内所有敌人受伤 |
| self | 对自身施加 Buff/治疗 |

### 伤害公式

```
基础伤害 = 角色攻击力 × 技能伤害倍率
实际伤害 = max(1, 基础伤害 - 目标防御力)
```

---

## 4. Buff配置表 (buffs.xlsx)

来源：`data/excel/buffs.xlsx` → `data/buffs.json`

| ID | 名称 | 类型 | 持续时间 | 跳数间隔 | 每跳伤害 | 减速 | 最大层数 | 特效 |
|----|------|------|----------|----------|----------|------|----------|------|
| 1001 | 中毒 | poison | 5秒 | 1秒 | 5 | - | 5 | poison_fx |
| 1002 | 燃烧 | burn | 3秒 | 0.5秒 | 8 | - | 1 | burn_fx |
| 1003 | 冰冻 | freeze | 2秒 | - | - | - | 1 | freeze_fx |
| 1004 | 麻痹 | paralysis | 1.5秒 | - | - | - | 1 | paralysis_fx |
| 1005 | 无敌 | invincible | 3秒 | - | - | - | 1 | invincible_fx |
| 1006 | 眩晕 | stun | 2秒 | - | - | - | 1 | stun_fx |
| 1007 | 减速 | slow | 4秒 | - | - | 50% | 1 | - |

### Buff 行为

| 类型 | 可移动 | 可行动 | 受到伤害 | 持续伤害 | 叠加规则 |
|------|--------|--------|----------|----------|----------|
| 中毒 | 是 | 是 | 是 | 是(5/跳) | 叠层数 |
| 燃烧 | 是 | 是 | 是 | 是(8/跳) | 刷新时间 |
| 冰冻 | 否 | 否 | 是 | 否 | 刷新时间 |
| 麻痹 | 否 | 是(可放技能) | 是 | 否 | 刷新时间 |
| 无敌 | 是 | 是 | 否(免疫) | 否 | 刷新时间 |
| 眩晕 | 否 | 否 | 是 | 否 | 刷新时间 |
| 减速 | 是* | 是 | 是 | 否 | 取最高值 |

*移动速度按 slow_ratio 降低

### Buff 优先级（行动阻断）

```
死亡 > 眩晕 > 冰冻 > 麻痹 > 正常
```

---

## 5. 关卡配置表 (levels.xlsx)

来源：`data/excel/levels.xlsx` → `data/levels.json`

| ID | 名称 | 场景路径 | 出生点X | 出生点Y |
|----|------|----------|---------|---------|
| 1 | 星地 | res://scenes/xing.tscn | 160 | 350 |
| 2 | 丛林 | res://scenes/jungle_01.tscn | 160 | 350 |

---

## 6. 碰撞层

| 层 | 位 | 用途 |
|----|----|------|
| 1 | 0 | 地图/世界几何体 |
| 2 | 1 | 梯子 (Area2D) |
| 3 | 2 | 玩家身体 |
| 4 | 3 | HitBox（攻击判定） |
| 5 | 4 | HurtBox（受击判定） |

### HitBox / HurtBox 交互

- HitBox：collision_layer=4，collision_mask=8（检测 HurtBox）
- HurtBox：collision_layer=8，collision_mask=4（被 HitBox 检测）

---

## 7. Excel 配置工作流

### 编辑配置

1. 用 Excel 打开 `data/excel/` 下的文件（如 `items.xlsx`）
2. 按表格格式编辑数据
3. 保存文件

### 转换为 JSON

- 双击项目根目录的 `convert_excel.cmd`
- 或在 Godot 中：顶部菜单栏 → 游戏工具 → 转换 Excel → JSON

### 新增配置表

1. 在 `data/excel/` 下创建 `新表名.xlsx`
2. 第一行为表头（支持中文），第一列必须是 `ID`
3. 在 `tools/excel_to_json.py` 的 HEADER_MAP 中添加表头映射
4. 运行转换
5. 在 `scripts/data/` 中创建 GDScript 配置加载器
6. 在 `game_registry.gd` 中注册

### 当前配置文件

| Excel 文件 | JSON 输出 | GDScript 加载器 |
|------------|-----------|-----------------|
| items.xlsx | items.json | item_config.gd |
| skills.xlsx | skills.json | skill_config.gd |
| buffs.xlsx | buffs.json | buff_config.gd |
| levels.xlsx | levels.json | level_config.gd |

---

## 8. 关卡系统

### 更换首个关卡

编辑 `levels.xlsx`：将第一行改为你想用的关卡。

### 在关卡场景中放置传送门

1. 在关卡场景中添加 `Area2D` 节点
2. 挂载脚本 `res://scripts/level/level_portal.gd`
3. 添加 `CollisionShape2D` 定义触发区域
4. 在检查器中设置：
   - `target_level_id`：目标关卡 ID
   - `spawn_position`：目标出生点（0,0 = 使用默认）
   - `require_key`：true = 按 E 触发，false = 走进即触发

### 代码接口

```gdscript
GameRegistry.level_manager.load_level(2)                    # 加载指定关卡
GameRegistry.level_manager.teleport_to(2, Vector2(500, 300)) # 传送到指定坐标
GameRegistry.level_manager.reload_current()                  # 重新加载当前关卡
```

### 信号

```gdscript
level_loading(level_id, level_name)   # 关卡开始加载
level_loaded(level_id, level_name)    # 关卡加载完成
level_unloaded(level_id)              # 关卡卸载
```

---

## 9. 背包与装备

### 穿戴物品

```gdscript
var item: ItemInstance = GameRegistry.inventory_data.get_item_by_id(1001)
GameRegistry.equipment_provider.equip_item(item.uid)
```

### 卸下装备

```gdscript
GameRegistry.equipment_provider.unequip_slot("weapon")
```

### 增删物品

```gdscript
GameRegistry.inventory_provider.add_item(1001)                # 获得铁剑
GameRegistry.inventory_provider.add_item(2001, 5)             # 获得5瓶回复药水
GameRegistry.inventory_provider.remove_item_by_id(2001, 1)    # 使用1瓶药水
```

### 装备槽位

| 槽位 | 可装备类型 |
|------|------------|
| weapon（武器） | weapon |
| armor（护甲） | armor |
| boots（靴子） | boots |
| accessory（饰品） | accessory |

---

## 10. 角色属性

基础属性 + 装备加成，穿戴/卸下装备时自动重算。

| 属性 | 基础值 | 来源 |
|------|--------|------|
| 生命值 | 100 | base_max_hp + 装备(max_hp) |
| 攻击力 | 1 | base_attack + 装备(attack) |
| 防御力 | 0 | base_defense + 装备(defense) |
| 移动速度 | 220 | base_move_speed + 装备(move_speed) |

---

## 11. 战斗系统

### 玩家操作

- J/K/L/U 释放技能
- 技能有冷却时间
- 攻击/受击动画期间无法移动
- 受击硬直：受伤后 0.3 秒
- 受击无敌：受伤后 0.5 秒

### 伤害流程

```
攻击者释放技能
  → SkillExecutor 根据类型执行（近战/弹道/范围/全屏/自身）
  → 计算伤害 = 攻击力 × 技能伤害倍率
  → 目标 HurtBox 接收命中
  → 防御减伤：max(1, 伤害 - 防御)
  → Buff 修正（无敌 = 免疫）
  → 扣血，判断死亡
  → 施加命中 Buff（如果配置了）
```

---

## 12. 编辑器工具

### Godot 菜单栏：游戏工具

| 菜单项 | 功能 |
|--------|------|
| 导入所有场景 | 扫描 `world/stitched/`，生成关卡场景 |
| 导入所有角色 | 扫描 `assets/characters/`，修正路径，生成配置 |
| 导入 UI 场景 Zip... | 导入 GameTool UI 场景包到 `assets/ui/`，并兼容旧版目录结构 |
| 转换 Excel → JSON | 扫描 `data/excel/`，通过 Python 生成 JSON |

### 命令行

| 文件 | 功能 |
|------|------|
| `convert_excel.cmd` | 双击转换所有 Excel 为 JSON |
| `import_worlds.cmd` | 双击导入所有世界场景 |

---

## 13. 文件结构

```
hengban-2/
├── addons/game_tools/          # Godot 编辑器插件
├── assets/characters/          # 角色精灵图
├── data/excel/                 # 配置源文件 (.xlsx)
├── data/*.json                 # 生成的配置 (自动，已 gitignore)
├── docs/                       # 文档
├── scenes/                     # 游戏场景
├── scripts/
│   ├── game_registry.gd        # AutoLoad 全局单例
│   ├── game_root.gd            # 主场景脚本
│   ├── player.gd               # 玩家脚本
│   ├── combat/                 # 战斗系统 (8个文件)
│   ├── data/                   # 数据模型 + 配置加载器 (9个文件)
│   ├── editor/                 # 导入工具 (2个文件)
│   ├── level/                  # 关卡传送门 (1个文件)
│   ├── provider/               # 数据接口层 (2个文件)
│   ├── system/                 # 关卡/存档管理器 (2个文件)
│   └── ui/                     # UI面板 (2个文件)
├── tools/                      # Python 脚本
├── world/stitched/             # 世界地图源数据
├── convert_excel.cmd
└── import_worlds.cmd
```
