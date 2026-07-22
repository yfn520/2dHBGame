# 技能片段库 v1（方案 A：片段库 + ref + override）

> 范围：仅 skills.json 的运行时压缩。编辑器加载/保存的 skills.json 保持现状（完整版，编辑体验不变）
> 机制：编辑器保存时额外生成 skills.compact.json（含 ref+override），运行时优先加载 compact 版
> 片段库管理：写一次性抽取脚本从现有 skills.json 生成初版 fragments.json，后续手动维护

---

## 一、现状与问题

### 1.1 现状
- `data/skills.json`：39 技能 / ~205 节点 / ~65 KB / 1670 行
- 编辑器内 7 个硬编码"套用模板"按钮（一次性覆盖整组 nodes，不可复用）
- `_default_node` 返回硬编码默认值
- 所有技能节点全量序列化，无引用/继承

### 1.2 主要冗余
| 冗余模式 | 命中次数 | 占比 |
|---|---|---|
| 普攻 5 节点骨架（play_animation+wait_hit_window+wait_animation_end+end_skill）| ~15 技能 | 节点总数 76% |
| 单发直线 spawn_projectile 14 字段块 | 7 技能 | 字段总数 15% |
| 收尾双节点 wait_animation_end+end_skill | 39 技能 | 纯冗余 |
| apply_self_buff + effect_offset 块 | 5 技能 | 中等 |
| play_effect character_local attachment 块 | 3 技能 | 中等 |

### 1.3 预期压缩
- 压缩 skills.json 体积 35~45%（~65 KB → ~36~45 KB）
- 减少运行时解析时间（compact 版字节数更少）
- fragments.json 独立维护，新增同类技能只需 override 几个字段

---

## 二、设计决策

### 2.1 文件结构

| 文件 | 角色 | 编辑器是否加载 | 运行时是否加载 |
|---|---|---|---|
| `data/skills.json` | 完整版（编辑器唯一真源） | 是 | 是（compact 缺失时回退） |
| `data/skills.compact.json` | 压缩版（含 ref+override） | 否 | 是（优先） |
| `data/skill_fragments.json` | 片段库定义 | 是（插入片段时） | 是（展开 ref 时） |

### 2.2 ref 语法

节点级 ref：
```json
{
    "ref": "projectile_straight_single",
    "override": {
        "scene": "res://assets/effects/projectiles/effect-arrow.tscn",
        "scale": 6.51,
        "damage_ratio": 1.2
    }
}
```

骨架级 ref（替换连续多个节点）：
```json
{
    "ref": "melee_basic_skeleton",
    "override": [
        {"index": 2, "set": {"result_key": "kivin_melee_hit", "damage_ratio": 1.8}}
    ]
}
```
- `override` 为数组，每项 `{index, set}` 表示对骨架第 index 个节点的字段覆盖
- `index` 是骨架中的位置（0-based）

### 2.3 fragment 定义格式

`data/skill_fragments.json`：
```json
{
    "melee_basic_skeleton": {
        "type": "skeleton",
        "description": "普攻 4 节点骨架",
        "nodes": [
            {"type": "play_animation", "action": "attack"},
            {"type": "wait_hit_window", "hit_window_index": 0},
            {"type": "wait_animation_end"},
            {"type": "end_skill"}
        ]
    },
    "projectile_straight_single": {
        "type": "node",
        "description": "单发直线弹道",
        "node": {
            "type": "spawn_projectile",
            "ai_min_range": 0.0,
            "ai_max_range": 280.0,
            "aim_mode": "facing_elevation",
            "emission": "single",
            "lifetime": 5.0,
            "origin": "hit_window",
            "result_key": "projectile_hit",
            "scale": 1.0,
            "speed": 300.0,
            "trajectory": "straight",
            "scene": ""
        }
    }
}
```

- `type: "skeleton"`：骨架片段，`nodes` 是节点数组，ref 出现在 nodes 数组中替换连续多个节点
- `type: "node"`：单节点片段，`node` 是单个节点字典，ref 出现在 nodes 数组中替换单个节点

### 2.4 关键决策点

1. **编辑器不感知 ref**：skills.json 始终保持完整展开，编辑器加载/保存逻辑不变
2. **运行时优先 compact**：SkillConfig 优先加载 skills.compact.json，缺失时回退 skills.json（向后兼容）
3. **compact 由编辑器生成**：编辑器保存 skills.json 后调用压缩算法生成 compact 版
4. **fragments 手动维护**：初始由抽取脚本生成，后续手动编辑 skill_fragments.json
5. **source_hash 在展开后计算**：AIRangeCompiler 拿到的是展开后的 nodes，编辑器内已展开无需改动

---

## 三、实施清单

### 3.1 新建文件（4 个）

#### A. `scripts/data/skill_fragments_config.gd`（片段库配置类）
- 读取 `data/skill_fragments.json`
- 提供 `get_fragment(id) -> Dictionary`、`get_all_fragments() -> Dictionary`
- 提供 `expand_nodes(nodes: Array) -> Array`：递归把 ref 节点展开为完整节点
  - 节点含 `ref` 字段：查 fragment
  - skeleton 类型：override 按 `{index, set}` 合并到骨架节点
  - node 类型：override 直接 merge 到 fragment node
  - 递归（fragment 内也可含 ref，但要检测环）

#### B. `scripts/data/skill_compact_writer.gd`（压缩算法）
- 输入：完整 nodes 数组 + fragments 字典
- 输出：compact nodes 数组（含 ref+override）
- 算法：
  1. 遍历 nodes，对每个位置 i 尝试匹配每个 skeleton fragment
  2. 若 nodes[i..i+len(skeleton.nodes)] 与 skeleton.nodes 结构匹配（type 一致 + 字段子集一致），计算 override
  3. override 推导：对每个骨架节点 j，找 nodes[i+j] 与 skeleton.nodes[j] 的差异字段，记为 `{index:j, set:diff}`
  4. 若 override 数量 ≤ 骨架节点数 × 50%，输出 ref；否则原样输出
  5. 单节点位置尝试匹配 node fragment：若节点与 fragment.node 字段子集匹配，输出 ref+override
- 匹配判定：`is_subset(superset, subset)` — subset 的所有字段在 superset 中且值相等
- override 推导：`diff = superset 字段中与 fragment 不同或 fragment 没有的字段`

#### C. `data/skill_fragments.json`（片段库初始版）
- 由抽取脚本生成（见 3.3）
- 至少包含 5 个高频片段：
  - `melee_basic_skeleton`（普攻骨架）
  - `projectile_straight_single`（单发直线弹道）
  - `projectile_straight_sequence`（多发连射弹道，可选）
  - `tail_end`（收尾双节点）
  - `apply_self_buff_with_offset`（自身 buff + 偏移）

#### D. `tools/extract_fragments.gd`（一次性抽取脚本）
- `@tool` 脚本，挂在编辑器某菜单或独立运行
- 读取 skills.json，统计节点序列频率
- 对频率 ≥ 3 的序列，生成 fragment 定义写入 skill_fragments.json
- 生成后人工审核命名与描述

### 3.2 修改文件（2 个）

#### E. `scripts/data/skill_config.gd`（运行时加载）
- [L3] 新增 `const COMPACT_PATH := "res://data/skills.compact.json"`
- [L3] 新增 `const FRAGMENTS_PATH := "res://data/skill_fragments.json"`
- [L9] `load_config()` 改造：
  1. 优先尝试加载 `COMPACT_PATH`，失败回退 `CONFIG_PATH`
  2. 加载 `FRAGMENTS_PATH`（用 SkillFragmentsConfig）
  3. 对每个 skill 的 nodes 调用 `SkillFragmentsConfig.expand_nodes(nodes)` 展开后存入 `_skills`
- [L68] `save_ai_range_cache` 仍写完整版 skills.json（编辑器读取用）
  - **不写 compact 版**：避免运行时把展开后的 cache 写回 compact，污染压缩格式
  - 写入内存 `_skills[id].ai_range_cache` 即可（运行时用）

#### F. `addons/game_tools/skill_sequence_editor.gd`（编辑器保存）
- [L2324] `_save_skills()` 末尾新增：
  ```gdscript
  _generate_compact_file()
  ```
- 新增 `_generate_compact_file()` 方法：
  1. 加载 `skill_fragments.json`（若不存在跳过，不报错）
  2. 对 `_skills` 中每个技能的 nodes 调用 `SkillCompactWriter.compress_nodes(nodes, fragments)`
  3. 生成 compact 字典，写入 `data/skills.compact.json`
  4. 失败时静默跳过（不阻塞 skills.json 保存）

### 3.3 一次性流程
1. 先实现 SkillFragmentsConfig + SkillCompactWriter + extract_fragments.gd
2. 运行 extract_fragments.gd 生成初版 skill_fragments.json
3. 人工审核 fragments 命名与描述
4. 在编辑器保存流程中调用压缩算法生成 skills.compact.json
5. 验证运行时加载 compact 版 + 展开后行为与原版一致

---

## 四、实施步骤（执行顺序）

### 步骤 1：新建片段库配置类
- 创建 `scripts/data/skill_fragments_config.gd`
- 实现 load + get_fragment + expand_nodes（含环检测）

### 步骤 2：新建抽取脚本生成 fragments.json
- 创建 `tools/extract_fragments.gd`
- 运行生成 `data/skill_fragments.json`
- 人工审核命名

### 步骤 3：新建压缩算法
- 创建 `scripts/data/skill_compact_writer.gd`
- 实现 `compress_nodes(nodes, fragments) -> Array`
- 单元测试：对现有 skills.json 跑一遍，验证压缩后展开能还原

### 步骤 4：修改 SkillConfig 加载逻辑
- `scripts/data/skill_config.gd` 改 load_config
- 优先加载 compact + fragments 展开
- 回退到完整版（向后兼容）

### 步骤 5：修改编辑器保存流程
- `addons/game_tools/skill_sequence_editor.gd` 的 _save_skills 末尾调用压缩
- 生成 skills.compact.json

### 步骤 6：验证
- 编译通过
- 运行游戏，技能施放行为与改前一致
- compact 版体积减少 30%+

---

## 五、假设与决策

### 5.1 假设
1. **编辑器不感知 ref**：skills.json 始终完整，编辑器加载/保存逻辑零改动
2. **fragments 手动维护**：初始抽取后人工命名，后续手动编辑 JSON
3. **compact 是构建产物**：可随时删除，下次编辑器保存会重新生成
4. **运行时容错**：compact 缺失或 fragments 缺失时回退到完整版

### 5.2 决策依据
- 用户要求"运行时压缩、编辑时展开"，最干净实现是双文件（full + compact）
- fragments.json 独立便于复用跨技能，且可被未来 buff/level 编辑器借鉴
- 抽取脚本降低初始迁移成本，避免手工写 5+ 个 fragment

### 5.3 不做的事
- **不引入编辑器内片段管理 UI**（用户跳过此问题，默认手动维护）
- **不改运行时 _execute_node**：load_config 展开后运行时无感知
- **不改 AIRangeCompiler**：source_hash 在展开后算，编辑器内已展开
- **不引入技能继承**（方案 C）：与"一技能一 asset"约束有张力

### 5.4 风险与缓解
| 风险 | 缓解 |
|---|---|
| compact 与 full 不同步 | 编辑器保存时自动生成 compact，无需手动同步 |
| fragment 改动影响多技能 | fragment 改动后下次保存重新压缩；运行时展开有环检测 |
| 压缩算法 bug 导致 compact 与 full 不一致 | 抽取后跑单元测试：compress → expand 应等于原 nodes |
| compact 缺失导致运行时崩溃 | load_config 回退到完整版 skills.json |

---

## 六、验证步骤

### 6.1 编译验证
```powershell
$env:HOME="E:\g_selfcustom\tmp_godot"
& "E:\g_selfcustom\Godot_v4.7-stable_win64.exe" --headless --check-only --path "E:\g_selfcustom\server_client\hengban-2" --quit
```

### 6.2 压缩一致性验证（单元测试）
- 对 skills.json 中每个技能：`expand(compress(nodes)) == nodes`
- 验证 compact 版体积 < full 版的 70%

### 6.3 运行时行为验证
- 删除 skills.compact.json，运行游戏 → 应回退到 skills.json 正常工作
- 生成 skills.compact.json，运行游戏 → 技能施放行为应与改前完全一致
- 测试 3 个角色 + 1 个怪物的技能施放：
  - 7001 new_kivin：6001 普攻、6002 技能1、6004 大招
  - 7002 gongshou：6011 普攻、6012 多段穿透、6014 箭雨
  - 7003 newfs：6021 法弹、6022 火球、6024 全屏爆发
  - 8001 史莱姆：50001 普攻

### 6.4 编辑器验证
- 打开技能编辑器，加载/编辑/保存 skills.json → 应正常工作，编辑器无感知 compact
- 保存后检查 data/ 下是否生成 skills.compact.json
- 检查 compact 版体积是否比 full 版小 30%+
