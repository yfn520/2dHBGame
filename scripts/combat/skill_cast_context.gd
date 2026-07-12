class_name SkillCastContext
extends RefCounted

## A cast owns its named result streams. Producers such as hit boxes and
## projectiles publish targets, while later nodes subscribe to those results.

class ResultStream:
	extends RefCounted

	var events: Array[Area2D] = []
	var unique_targets: Dictionary = {}
	var _subscribers: Array[Dictionary] = []

	func publish(target: Area2D) -> void:
		if not is_instance_valid(target):
			return
		events.append(target)
		unique_targets[target.get_instance_id()] = target
		for subscriber in _subscribers:
			_deliver(subscriber, target)

	func subscribe(callback: Callable, delivery: String = "each_hit") -> void:
		if not callback.is_valid():
			return
		var subscriber := {
			"callback": callback,
			"delivery": delivery,
			"seen": {},
		}
		_subscribers.append(subscriber)
		var replay: Array = events if delivery == "each_hit" else unique_targets.values()
		for target in replay:
			if target is Area2D:
				_deliver(subscriber, target)

	func get_targets(delivery: String = "each_target") -> Array[Area2D]:
		var source: Array = events if delivery == "each_hit" else unique_targets.values()
		var result: Array[Area2D] = []
		for target in source:
			if target is Area2D and is_instance_valid(target):
				result.append(target)
		return result

	func _deliver(subscriber: Dictionary, target: Area2D) -> void:
		var callback: Callable = subscriber.get("callback", Callable())
		if not callback.is_valid():
			return
		if String(subscriber.get("delivery", "each_hit")) == "each_target":
			var seen: Dictionary = subscriber.get("seen", {})
			var target_id := target.get_instance_id()
			if seen.has(target_id):
				return
			seen[target_id] = true
			subscriber["seen"] = seen
		callback.call(target)


var owner: Node
var skill_id := 0
var current_action := ""
var current_anchor := Vector2.ZERO
var active_window_index := -1
var active_window: Dictionary = {}
var last_result_key := ""
var cancelled := false

var _streams: Dictionary = {}


func _init(caster: Node = null, cast_skill_id: int = 0) -> void:
	owner = caster
	skill_id = cast_skill_id
	if owner is Node2D:
		current_anchor = (owner as Node2D).global_position


func ensure_stream(result_key: String) -> ResultStream:
	var key := result_key.strip_edges()
	if key.is_empty():
		key = "last_result"
	if not _streams.has(key):
		_streams[key] = ResultStream.new()
	last_result_key = key
	return _streams[key] as ResultStream


func publish(result_key: String, target: Area2D) -> void:
	ensure_stream(result_key).publish(target)


func subscribe(result_key: String, callback: Callable, delivery: String = "each_hit") -> void:
	var key := last_result_key if result_key.strip_edges().is_empty() or result_key == "last_result" else result_key
	if key.is_empty():
		return
	ensure_stream(key).subscribe(callback, delivery)


func get_targets(result_key: String, delivery: String = "each_target") -> Array[Area2D]:
	var key := last_result_key if result_key.strip_edges().is_empty() or result_key == "last_result" else result_key
	if key.is_empty() or not _streams.has(key):
		return []
	return (_streams[key] as ResultStream).get_targets(delivery)
