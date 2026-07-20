class_name InputActions

## 集中管理所有 InputMap 动作名称常量。
## 触屏控件通过 Input.action_press/action_release 注入这些动作；
## 键盘通过 Input.is_action_pressed 读取，统一映射避免散落字符串。
const MOVE_LEFT := "move_left"
const MOVE_RIGHT := "move_right"
const MOVE_UP := "move_up"
const MOVE_DOWN := "move_down"
const JUMP := "jump"
const ATTACK := "attack"
const SKILL1 := "skill1"
const SKILL2 := "skill2"
const SKILL3 := "skill3"
const TOGGLE_INVENTORY := "toggle_inventory"
const TOGGLE_EQUIPMENT := "toggle_equipment"
const SWITCH_CHARACTER := "switch_character"
const RELOAD_LEVEL := "reload_level"
const CANCEL := "cancel"
const TOGGLE_DEBUG := "toggle_debug"
const TOGGLE_MAIN_UI := "toggle_main_ui"

## 技能槽位名称数组，对应 combat_component._try_use_owner_skill 的 slot_name 参数。
## 顺序与 BattleHud 底部 4 个技能按钮一一对应。
const SKILL_SLOTS := ["normal", "skill1", "skill2", "skill3"]

## 对应键盘 J/K/L/U 的可读标签（用于 UI 显示）。
const SKILL_SLOT_LABELS := ["J", "K", "L", "U"]
