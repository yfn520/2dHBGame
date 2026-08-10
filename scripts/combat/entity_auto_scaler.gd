class_name EntityAutoScaler

## 统一体型自动缩放：让角色 / 敌人 / NPC 的 authored body height 落到统一目标范围。
## 角色原 [110,160] 上调到 [140,200]，使实体相对固定高度 2D 场景更突出、彼此一致。
## 技能特效在 skill_executor / combat_component 中已乘以施法者 visual_root.scale，
## 故 _actor_scale 增大后弹道与 play_effect 特效会等比放大，此处无需关心特效。
const TARGET_BODY_HEIGHT_MIN := 140.0
const TARGET_BODY_HEIGHT_MAX := 200.0


## 按 authored_body_height 把 base_scale clamp 到目标体型范围。
## 返回值满足 authored_body_height * result ∈ [MIN, MAX]（当 authored_body_height > 0）。
## authored_body_height <= 0（无法读取体型）时原样返回 base_scale（不 clamp，交由调用方默认值）。
static func compute_scale(authored_body_height: float, base_scale := 1.0) -> float:
	var safe_base := maxf(0.01, base_scale)
	if authored_body_height <= 0.0:
		return safe_base
	var lo := TARGET_BODY_HEIGHT_MIN / authored_body_height
	var hi := TARGET_BODY_HEIGHT_MAX / authored_body_height
	return clampf(safe_base, lo, hi)
