class_name StateMachine

signal state_changed(old_state: StringName, new_state: StringName)

var _states: Dictionary = {}       # StringName -> StateInfo { enter, update, exit }
var _current: StringName = &""
var _owner: Node


func _init(owner: Node) -> void:
	_owner = owner


func add_state(name: StringName, enter: Callable, update: Callable, exit: Callable) -> void:
	_states[name] = { "enter": enter, "update": update, "exit": exit }


func change_to(new_state: StringName) -> void:
	if _current == new_state:
		return
	if not _states.has(new_state):
		push_error("StateMachine: 状态不存在 %s" % new_state)
		return
	if _states.has(_current):
		_states[_current]["exit"].call()
	var old := _current
	_current = new_state
	_states[_current]["enter"].call()
	state_changed.emit(old, new_state)


func update(delta: float) -> void:
	if _states.has(_current):
		_states[_current]["update"].call(delta)


func is_state(name: StringName) -> bool:
	return _current == name


func get_current() -> StringName:
	return _current
