class_name NpcInteractionDispatcher
extends Node

signal binding_dispatched(binding_key: String, binding_type: String, success: bool)
signal unhandled_binding(binding_key: String, binding: Dictionary)

var binding_config: InteractionBindingConfig
var quest_service: QuestService


func setup(
	p_dialogue_service: DialogueService,
	p_binding_config: InteractionBindingConfig,
	p_quest_service: QuestService
) -> void:
	binding_config = p_binding_config
	quest_service = p_quest_service
	if p_dialogue_service != null and not p_dialogue_service.intent_selected.is_connected(_on_intent_selected):
		p_dialogue_service.intent_selected.connect(_on_intent_selected)


func dispatch(dialogue_id: String, intent_key: String) -> bool:
	if binding_config == null:
		return false
	var binding_key := "%s.%s" % [dialogue_id, intent_key]
	var binding := binding_config.get_binding(dialogue_id, intent_key)
	if binding.is_empty():
		return false
	var binding_type := String(binding.get("type", ""))
	var success := false
	match binding_type:
		"start_quest":
			success = quest_service != null and quest_service.start_quest(int(binding.get("quest_id", 0)))
		"turn_in_quest":
			success = quest_service != null and quest_service.turn_in_quest(int(binding.get("quest_id", 0)))
		"open_shop":
			unhandled_binding.emit(binding_key, binding)
		_:
			push_warning("未知 NPC 交互绑定类型: %s (%s)" % [binding_type, binding_key])
			unhandled_binding.emit(binding_key, binding)
	binding_dispatched.emit(binding_key, binding_type, success)
	return success


func _on_intent_selected(
	_npc_id: int,
	dialogue_id: String,
	_choice_id: String,
	intent_key: String
) -> void:
	dispatch(dialogue_id, intent_key)
