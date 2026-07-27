class_name ChapterStateData
extends RefCounted

## 章节运行时状态数据，跟随存档持久化。
## 包装 ChapterService 的 to_dict/from_dict，由 SaveManager 调用。

var chapter_service  # ChapterService 引用，由 GameRegistry 注入


func to_dict() -> Dictionary:
	if chapter_service == null:
		return {}
	return chapter_service.to_dict()


func from_dict(data: Dictionary) -> void:
	if chapter_service == null:
		return
	chapter_service.from_dict(data)
