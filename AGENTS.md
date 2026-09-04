# AGENTS.md — hengban-2 Godot 项目规则（AI 必读）

Godot 4.7 的 2D 横版动作 RPG 运行时。工作区根 `../AGENTS.md` 有全工作区地图与跨项目契约，先读它再回来。

## 项目结构

- `scenes/`：`game_root.tscn`（持久根：PartyManager + 关卡容器 + UIRoot）、`player.tscn`（PartyManager 阵容）、`scenes/<地图名>/`（自动生成关卡，含 `images/source.png` 底图与瓦片）
- `scripts/`：`game_registry.gd`（AutoLoad 单例，持全部 config/provider）、`game_root.gd`、`player.gd`（主角+队友 AI）、`system/`（quest/dialogue/level/party/save 等服务）、`data/`（config 数据模型）、`combat/`（战斗组件/弹道）
- `data/*.json`：运行时数据。**由网页工作台（../frontend）编译发布，本侧代码只读**；手工直接编辑内容属于高危操作（曾致剧情失配/损坏，详见根 AGENTS.md 高危契约 1）
- `assets/`：`characters/<slug>/`（角色预制体+combat_actions.json+portrait）、`npcs/<slug>/`（npc_asset.json+portrait）、`skill_fx/<bundle_id>/`（网页特效包，唯一导入器是 addons/game_tools/skill_sequence_editor.gd）
- `tests/`：`extends SceneTree` 的 headless 脚本，统一入口 `python tools/run_tests.py`（内部 `godot --headless --path . --script tests/<文件>`，quit(0)=通过 / quit(1)=失败）
- 详细场景/数据流说明：`docs/STRUCTURE.md`；历史决策与发现：`docs/MEMORY.md`；当前计划：`docs/PLAN.md`

## 高危区（每条都对应一次真实事故，改动前必读）

1. **技能特效朝向/挂点公式**：跨 5 个实现点共享契约（`scripts/combat/projectile.gd`、`scripts/combat/combat_component.gd`、`scripts/combat/hit_box.gd`、addons/game_tools 预览、网页侧 `../frontend/src/lib/skillFxFacing.ts` + 真值表测试）。⚠注意：旧规则引用的 `G:\game\pro\docs\skill-fx-facing-conventions.md` 已失效（路径来自旧机器），权威公式现以网页侧 `skillFxFacing.ts` 与其测试为准；改前跑 `skillFxFacing.test.ts`，改后同步全部消费方。
2. **队友 AI 与关卡边界**：`player.gd` 队友 AI 只跟随 x 轴、不跳跃；`party_manager.gd` 的 `_clamp_to_level` 负责站位不出关卡宽度，`player.gd` 的 `FALL_RECOVER_Y` 负责掉出世界回收。改这两个文件必须跑 `tests/party_clamp_and_fall.gd`（曾致队友掉坑消失事故）。
3. **dialogues.json timeline 片段**：`scripts/system/dialogue_service.gd` 按 clips 数组顺序消费，`kind`/`actions`/`conditions` 结构由网页编译器保证；手改结构会破坏任务链（曾致死锁门/跳词事故）。
4. **资产路径索引**：见根 AGENTS.md 高危契约 3。

## 改动后的强制回路

1. 改 `scripts/`、`data/` 后：跑 `python tools/run_tests.py`（统一 headless 入口，godot 路径取 `tools/godot_bin.txt` / 环境变量 GODOT_BIN / `--godot` 参数）；单跑某个测试：`python tools/run_tests.py <名字子串>`
2. 改 `data/*.json` 后：跑 `python tools/validate_data.py`（JSON 合法性 + timeline 片段结构 + 资产路径悬空 + quest 字段类型；曾出现 trailing-comma 损坏与 npc_9012 portrait 悬空，均由它拦截）
3. 可选风格护栏：`tools/lint.cmd`（需 `pip install gdtoolkit`，未安装自动跳过）
4. 完成后：把新发现的「错误模式」沉淀到 `docs/MEMORY.md`；若可自动化，补一条 tests/ 守卫
