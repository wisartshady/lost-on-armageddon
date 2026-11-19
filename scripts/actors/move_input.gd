class_name MoveInput
extends RefCounted

const DIRS:= {"f": [KEY_W, KEY_UP], "b": [KEY_S, KEY_DOWN], "l": [KEY_A, KEY_LEFT], "r": [KEY_D, KEY_RIGHT]}
const DEADZONE:= 0.24

var sprint_toggle:= false
var keys:= {"f": false, "b": false, "l": false, "r": false}
var _order:= {"f": 0, "b": 0, "l": 0, "r": 0}
var _seq:= 0
var _run_on:= false
var _shift_prev:= false
var _still_t:= 0.0
var _joy_centred:= false
var _joy_live:= false

func _key_down(name: String) -> bool:
	for k in DIRS[name]:
		if Input.is_physical_key_pressed(k):
			return true
	return false

func read(delta: float) -> Vector2:
	for n in DIRS:
		var d:= _key_down(n)
		if d and not keys[n]:
			_seq += 1
			_order[n] = _seq
		keys[n] = d
	var x:= 0.0
	if keys["l"] and keys["r"]:
		x = -1.0 if _order["l"] > _order["r"] else 1.0
	elif keys["l"]:
		x = -1.0
	elif keys["r"]:
		x = 1.0
	var y:= 0.0
	if keys["f"] and keys["b"]:
		y = -1.0 if _order["f"] > _order["b"] else 1.0
	elif keys["f"]:
		y = -1.0
	elif keys["b"]:
		y = 1.0
	var v:= Vector2(x, y)
	if v.length() > 1.0:
		v = v.normalized()
	if v == Vector2.ZERO:
		v = _stick()
	_still_t = 0.0 if v.length() > 0.1 else _still_t + delta
	if _still_t > 0.5:
		_run_on = false
	return v

func _stick() -> Vector2:
	if Input.get_connected_joypads().is_empty():
		return Vector2.ZERO
	var j:= Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	var l:= j.length()
	if l < DEADZONE:
		_joy_centred = true
		return Vector2.ZERO
	if _joy_centred and l > 0.5:
		_joy_live = true
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_STICK]:
		if Input.is_joy_button_pressed(0, b):
			_joy_live = true
	if not _joy_live:
		return Vector2.ZERO
	return j / l * minf((l - DEADZONE) / (1.0 - DEADZONE), 1.0)

func sprint() -> bool:
	var shift:= Input.is_physical_key_pressed(KEY_SHIFT) or (_joy_live and Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK))
	var pressed:= shift and not _shift_prev
	_shift_prev = shift
	if sprint_toggle:
		if pressed:
			_run_on = not _run_on
		return _run_on
	return shift

func held_names() -> PackedStringArray:
	var out:= PackedStringArray()
	for pair in [[KEY_W, "W"], [KEY_A, "A"], [KEY_S, "S"], [KEY_D, "D"], [KEY_SHIFT, "SHIFT"], [KEY_SPACE, "SPACE"], [KEY_CTRL, "CTRL"],
			[KEY_E, "E"], [KEY_Q, "Q"], [KEY_UP, "UP"], [KEY_DOWN, "DOWN"], [KEY_LEFT, "LEFT"], [KEY_RIGHT, "RIGHT"]]:
		if Input.is_physical_key_pressed(pair[0]):
			out.append(pair[1])
	return out
