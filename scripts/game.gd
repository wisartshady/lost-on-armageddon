extends Node

signal objective_changed(key: String, target: String)
signal toast(key: String)
signal flags_changed

const SAVE_PATH:= "user://save.json"

var objective_key:= ""
var objective_target:= ""
var flags:= {}
var in_game:= false
var player: Node3D = null
var world: Node = null
var pending_load:= {}

func capture_mouse(on: bool) -> void:
	if not on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif Settings.c.get("mouse_raw", false):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN

func mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN

func new_game() -> void:
	flags = {}
	objective_key = ""
	objective_target = ""
	pending_load = {}

func set_objective(key: String, target: String = "") -> void:
	objective_key = key
	objective_target = target
	objective_changed.emit(key, target)

func set_flag(f: String, v = true) -> void:
	flags[f] = v
	flags_changed.emit()

func has_flag(f: String) -> bool:
	return flags.get(f, false)

func run_actions(actions: Array) -> void:
	for act in actions:
		var parts: PackedStringArray = str(act).split(":")
		match parts[0]:
			"objective":
				set_objective(parts[1], parts[2] if parts.size() > 2 else "")
			"flag":
				set_flag(parts[1])
			"toast":
				toast.emit(parts[1])

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	if player == null or Benchmark.active:
		return
	var data:= {
		"version": 1,
		"flags": flags,
		"objective": objective_key,
		"target": objective_target,
		"pos": [player.global_position.x, player.global_position.y, player.global_position.z],
		"yaw": player.call("get_yaw") if player.has_method("get_yaw") else 0.0,
		"camera": player.call("get_camera_mode") if player.has_method("get_camera_mode") else "tp",
		"weather": WeatherSim.current.save_data() if WeatherSim.current else {},
	}
	var f:= FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func load_game() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	flags = data.get("flags", {})
	objective_key = data.get("objective", "")
	objective_target = data.get("target", "")
	pending_load = data
	if WeatherSim.current and typeof(data.get("weather")) == TYPE_DICTIONARY and not data["weather"].is_empty():
		WeatherSim.current.load_data(data["weather"])
	return true
