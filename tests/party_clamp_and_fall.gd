extends SceneTree

## 回归测试：队友掉坑消失事故的守卫。
## 覆盖两处修复：
##   1. party_manager.gd `_clamp_to_level`：站位/重生坐标必须钳制在关卡宽度内
##      （原 bug：主角贴边时队友偏移位越出关卡，落点无地面直接掉没）
##   2. player.gd `FALL_RECOVER_Y` + `_last_safe_position`：掉出世界的坠落回收
##      （原 bug：角色掉过关卡下界后无限下坠，相机不跟随导致永久消失）
## 运行：godot --headless --path . --script tests/party_clamp_and_fall.gd

const LEVEL_WIDTH := 1536.0
const EDGE_MARGIN := 24.0


func _initialize() -> void:
	var failures: Array[String] = []

	# --- 1. party_manager._clamp_to_level 边界钳制（纯逻辑，无需场景树） ---
	var pm_script = load("res://scripts/system/party_manager.gd")
	if pm_script == null:
		failures.append("无法加载 party_manager.gd")
	else:
		var pm = pm_script.new()
		var cases := [
			# [输入 x, 期望 x]：左越界 / 右越界 / 正常值 / 恰好边界
			[Vector2(-50.0, 100.0), 24.0],
			[Vector2(1700.0, 100.0), LEVEL_WIDTH - EDGE_MARGIN],
			[Vector2(800.0, 100.0), 800.0],
			[Vector2(EDGE_MARGIN, 100.0), EDGE_MARGIN],
			[Vector2(LEVEL_WIDTH - EDGE_MARGIN, 100.0), LEVEL_WIDTH - EDGE_MARGIN],
		]
		for case_value in cases:
			var input: Vector2 = case_value[0]
			var expected_x: float = case_value[1]
			var got: Vector2 = pm._clamp_to_level(input)
			if absf(got.x - expected_x) > 0.01 or not is_equal_approx(got.y, input.y):
				failures.append("_clamp_to_level(%s) 期望 x=%s，实际 %s" % [input, expected_x, got.x])
		pm.free()

	# --- 2. player.gd 坠落回收守卫存在性（源码静态断言） ---
	var player_source := FileAccess.get_file_as_string("res://scripts/player.gd")
	if player_source.is_empty():
		failures.append("无法读取 scripts/player.gd")
	else:
		for token in ["FALL_RECOVER_Y", "_last_safe_position"]:
			if not player_source.contains(token):
				failures.append("player.gd 缺少坠落回收关键实现：%s" % token)
		# 常量与关卡高度的关系：回收阈值必须大于关卡高度（否则正常站位会被误回收）
		var level_match := RegEx.new()
		level_match.compile("LEVEL_SIZE := Vector2i\\((\\d+), (\\d+)\\)")
		var level_result := level_match.search(player_source)
		var recover_match := RegEx.new()
		recover_match.compile("FALL_RECOVER_Y := ([\\d.]+)")
		var recover_result := recover_match.search(player_source)
		if level_result and recover_result:
			var level_h := float(level_result.get_string(2))
			var recover_y := float(recover_result.get_string(1))
			if recover_y <= level_h:
				failures.append("FALL_RECOVER_Y(%s) 必须大于关卡高度(%s)，否则正常站位会被误回收" % [recover_result.get_string(1), level_result.get_string(2)])

	# --- 汇总 ---
	if failures.is_empty():
		print("PARTY_CLAMP_AND_FALL_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
