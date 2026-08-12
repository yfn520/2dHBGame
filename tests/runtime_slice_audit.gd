extends SceneTree

const QUEST_PATH := "res://data/quests.json"
const LEVEL_PATH := "res://data/levels.json"
const NPC_PLACEMENTS_PATH := "res://data/npc_placements.json"
const WORLD_CONTENT_PATH := "res://data/runtime_world_content.json"
const ENEMIES_PATH := "res://data/enemies.json"
const ITEMS_PATH := "res://data/items.json"
const CAPABILITIES_PATH := "res://data/runtime_capabilities.json"


func _init() -> void:
	var failures: Array[String] = []
	var quests := _read_json(QUEST_PATH, failures)
	var levels := _read_json(LEVEL_PATH, failures)
	var placements := _read_json(NPC_PLACEMENTS_PATH, failures)
	var world := _read_json(WORLD_CONTENT_PATH, failures)
	var enemies := _read_json(ENEMIES_PATH, failures)
	var items := _read_json(ITEMS_PATH, failures)
	var capabilities := _read_json(CAPABILITIES_PATH, failures)
	var placed_npcs := {}
	for level_entries in placements.get("levels", {}).values():
		for entry in level_entries:
			placed_npcs[int(entry.get("npc_id", 0))] = true
	var spawned_enemies := {}
	for level in levels.values():
		for entry in level.get("enemies", []):
			spawned_enemies[int(entry.get("enemy_id", 0))] = true
	var pickup_items := {}
	var portal_targets := {}
	for level in world.get("levels", {}).values():
		for entry in level.get("enemies", []):
			spawned_enemies[int(entry.get("enemy_id", 0))] = true
		for entry in level.get("interactables", []):
			if str(entry.get("type", "")) == "pickup":
				pickup_items[int(entry.get("item_id", 0))] = true
			if str(entry.get("type", "")) == "portal":
				portal_targets[int(entry.get("target_level_id", -1))] = true
	var supported: Array = capabilities.get("quest_objectives", [])
	for quest_id in range(1001, 1013):
		var quest: Dictionary = quests.get(str(quest_id), {})
		if quest.is_empty():
			failures.append("missing quest %d" % quest_id)
			continue
		for npc_field in ["giver_npc_id", "turn_in_npc_id"]:
			var npc_id := int(quest.get(npc_field, 0))
			if npc_id > 0 and not placed_npcs.has(npc_id):
				failures.append("quest %d %s %d is not placed" % [quest_id, npc_field, npc_id])
		for objective in quest.get("objectives", []):
			var objective_type := str(objective.get("type", ""))
			if not supported.has(objective_type):
				failures.append("quest %d unsupported objective %s" % [quest_id, objective_type])
			if objective_type == "kill":
				var enemy_id := int(objective.get("enemy_id", 0))
				if not enemies.has(str(enemy_id)) or not spawned_enemies.has(enemy_id):
					failures.append("quest %d enemy %d has no reachable spawn" % [quest_id, enemy_id])
			if objective_type == "collect":
				var item_id := int(objective.get("item_id", 0))
				if not items.has(str(item_id)) or not pickup_items.has(item_id):
					failures.append("quest %d item %d has no pickup source" % [quest_id, item_id])
	for level_id in range(1, 4):
		if not portal_targets.has(level_id):
			failures.append("level %d has no configured portal entrance" % level_id)
	if failures.is_empty():
		print("RUNTIME_SLICE_AUDIT_OK quests=12 levels=4")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _read_json(path: String, failures: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		failures.append("missing file %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		failures.append("invalid json %s" % path)
		return {}
	return json.data
