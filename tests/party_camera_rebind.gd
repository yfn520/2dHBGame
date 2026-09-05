extends SceneTree

## 守卫：队伍因剧情招募/选角重建后，主控相机必须重新继承当前关卡相机配置。

const PARTY_MANAGER_PATH := "res://scripts/system/party_manager.gd"
const LEVEL_MANAGER_PATH := "res://scripts/system/level_manager.gd"


func _init() -> void:
	var party_source := FileAccess.get_file_as_string(PARTY_MANAGER_PATH)
	var level_source := FileAccess.get_file_as_string(LEVEL_MANAGER_PATH)
	var switched_at := party_source.find("func switch_character")
	var emitted_at := party_source.find("active_character_changed.emit(active_character)", switched_at)
	var refreshed_at := party_source.find("refresh_active_camera", emitted_at)
	if not party_source.is_empty() and not level_source.is_empty() \
		and level_source.contains("func refresh_active_camera") \
		and emitted_at >= 0 and refreshed_at > emitted_at:
		print("PARTY_CAMERA_REBIND_OK")
		quit(0)
	else:
		push_error("party switch did not refresh the active level camera")
		quit(1)
