extends Node

signal changed(section: String)

const PATH:= "user://settings.cfg"
const SETTINGS_VERSION:= 3
const PRESET_KEYS:= ["render_scale", "dynamic_res", "view_distance", "shadows", "lights", "glow", "fog", "rain",
		"aa", "ssao", "ssr", "windows", "texq", "particles", "post"]

const PRESETS:= [
	{"render_scale": 0.5, "dynamic_res": true, "view_distance": 70.0, "shadows": 0, "lights": 0, "glow": false, "fog": 0,
		"rain": 1, "aa": 0, "ssao": false, "ssr": false, "windows": 0, "texq": 0, "particles": 0, "post": false},
	{"render_scale": 0.67, "dynamic_res": true, "view_distance": 100.0, "shadows": 0, "lights": 2, "glow": true, "fog": 0,
		"rain": 2, "aa": 0, "ssao": false, "ssr": false, "windows": 1, "texq": 1, "particles": 1, "post": true},
	{"render_scale": 0.8, "dynamic_res": true, "view_distance": 140.0, "shadows": 0, "lights": 4, "glow": true, "fog": 0,
		"rain": 2, "aa": 0, "ssao": false, "ssr": false, "windows": 1, "texq": 2, "particles": 1, "post": true},
	{"render_scale": 1.0, "dynamic_res": false, "view_distance": 200.0, "shadows": 2, "lights": 8, "glow": true, "fog": 0,
		"rain": 3, "aa": 2, "ssao": false, "ssr": false, "windows": 1, "texq": 2, "particles": 2, "post": true},
	{"render_scale": 1.0, "dynamic_res": false, "view_distance": 260.0, "shadows": 3, "lights": 12, "glow": true, "fog": 1,
		"rain": 3, "aa": 4, "ssao": true, "ssr": true, "windows": 1, "texq": 2, "particles": 3, "post": true},
]

var g:= {}
var d:= {}
var a:= {}
var c:= {}
var language:= "tr"
var renderer_active:= "gl_compatibility"
var renderer_pending:= ""

func _init() -> void:
	_setup_input()
	_setup_buses()
	reset_all()
	_load()
	renderer_active = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility"))
	if RenderingServer.get_current_rendering_method() != "":
		renderer_active = RenderingServer.get_current_rendering_method()

func _ready() -> void:
	apply_display()
	apply_audio()

func reset_all() -> void:
	reset_graphics()
	d = {"window_mode": 1, "vsync": true, "fps_limit": 0, "show_fps": false, "brightness": 1.0}
	a = {"master": 0.85, "music": 0.55, "sfx": 0.85, "ambience": 0.8, "voice": 1.0, "subtitles": true}
	c = {"mouse_sens": 0.12, "invert_y": false, "fov": 72.0, "head_bob": true, "camera": "tp", "mouse_raw": false, "auto_camera": true, "mouse_smooth": 0.35, "sprint_toggle": false}
	language = "tr"

func reset_graphics() -> void:
	g = PRESETS[2].duplicate()
	g["preset"] = 2
	g["renderer"] = "gl_compatibility"

func set_preset(i: int) -> void:
	for k in PRESET_KEYS:
		g[k] = PRESETS[i][k]
	g["preset"] = i
	if i == 4:
		g["renderer"] = "forward_plus"
	elif g.get("renderer", "") == "forward_plus" and i < 3:
		g["renderer"] = "gl_compatibility"
	_check_renderer()
	save()
	changed.emit("graphics")

func set_graphics(key: String, value) -> void:
	g[key] = value
	if key != "renderer":
		g["preset"] = -1
		for i in PRESETS.size():
			var same:= true
			for k in PRESET_KEYS:
				if PRESETS[i][k] != g[k]:
					same = false
					break
			if same:
				g["preset"] = i
	_check_renderer()
	save()
	changed.emit("graphics")

func _check_renderer() -> void:
	var want: String = g.get("renderer", "gl_compatibility")
	renderer_pending = "" if want == renderer_active else want
	_write_override(want)

func is_vulkan() -> bool:
	return renderer_active != "gl_compatibility"

func set_display(key: String, value) -> void:
	d[key] = value
	apply_display()
	save()
	changed.emit("display")

func set_audio(key: String, value) -> void:
	a[key] = value
	apply_audio()
	save()
	changed.emit("audio")

func set_control(key: String, value) -> void:
	c[key] = value
	save()
	changed.emit("controls")

func set_language(l: String) -> void:
	language = l
	TranslationServer.set_locale(l)
	save()
	changed.emit("language")

func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match int(d["window_mode"]):
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE if d["vsync"] else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(d["fps_limit"])

func apply_audio() -> void:
	_bus_vol("Master", a["master"])
	_bus_vol("Music", a["music"])
	_bus_vol("SFX", a["sfx"])
	_bus_vol("Ambience", a["ambience"])
	_bus_vol("Voice", a["voice"])

func _bus_vol(bus: String, v: float) -> void:
	var i:= AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)

func _setup_buses() -> void:
	for b in ["Music", "SFX", "Ambience", "Voice"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i:= AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")

	var sfx:= AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var r:= AudioEffectReverb.new()
		r.room_size = 0.55
		r.damping = 0.6
		r.wet = 0.12
		r.dry = 1.0
		AudioServer.add_bus_effect(sfx, r)

func _override_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://override.cfg")
	return OS.get_executable_path().get_base_dir().path_join("override.cfg")

func _write_override(method: String) -> void:
	var path:= _override_path()
	if method == "gl_compatibility":
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var f:= FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Cannot write override.cfg at " + path)
		return
	f.store_string("[rendering]\n\nrenderer/rendering_method=\"forward_plus\"\n")
	f.close()

func save() -> void:
	if Benchmark.active:
		return
	var cf:= ConfigFile.new()
	for k in g:
		cf.set_value("graphics", k, g[k])
	for k in d:
		cf.set_value("display", k, d[k])
	for k in a:
		cf.set_value("audio", k, a[k])
	for k in c:
		cf.set_value("controls", k, c[k])
	cf.set_value("general", "language", language)
	cf.set_value("general", "version", SETTINGS_VERSION)
	cf.save(PATH)

func _load() -> void:
	var cf:= ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in g.keys():
		g[k] = cf.get_value("graphics", k, g[k])
	g["renderer"] = cf.get_value("graphics", "renderer", g["renderer"])
	for k in d.keys():
		d[k] = cf.get_value("display", k, d[k])
	for k in a.keys():
		a[k] = cf.get_value("audio", k, a[k])
	for k in c.keys():
		c[k] = cf.get_value("controls", k, c[k])
	language = cf.get_value("general", "language", language)

func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ev:= InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func _joy_button(action: String, b: int) -> void:
	var ev:= InputEventJoypadButton.new()
	ev.button_index = b
	InputMap.action_add_event(action, ev)

func _joy_axis(action: String, axis: int, v: float) -> void:
	var ev:= InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = v
	InputMap.action_add_event(action, ev)

func _mouse(action: String, b: int) -> void:
	var ev:= InputEventMouseButton.new()
	ev.button_index = b
	InputMap.action_add_event(action, ev)

func _setup_input() -> void:
	_key("move_forward", [KEY_W, KEY_UP]); _joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_key("move_back", [KEY_S, KEY_DOWN]); _joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_key("move_left", [KEY_A, KEY_LEFT]); _joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_key("move_right", [KEY_D, KEY_RIGHT]); _joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_key("sprint", [KEY_SHIFT]); _joy_button("sprint", JOY_BUTTON_LEFT_STICK)
	_key("jump", [KEY_SPACE]); _joy_button("jump", JOY_BUTTON_A)
	_key("crouch", [KEY_CTRL, KEY_C]); _joy_button("crouch", JOY_BUTTON_B)
	_key("interact", [KEY_E]); _joy_button("interact", JOY_BUTTON_X)
	_key("camera_toggle", [KEY_V]); _joy_button("camera_toggle", JOY_BUTTON_Y)
	_key("power", [KEY_Q]); _mouse("power", MOUSE_BUTTON_RIGHT); _joy_axis("power", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_key("flashlight", [KEY_F]); _joy_button("flashlight", JOY_BUTTON_DPAD_UP)
	_key("pause", [KEY_ESCAPE]); _joy_button("pause", JOY_BUTTON_START)
	_key("toggle_fps", [KEY_F3])
	_key("dialog_next", [KEY_SPACE, KEY_E, KEY_ENTER, KEY_KP_ENTER]); _mouse("dialog_next", MOUSE_BUTTON_LEFT); _joy_button("dialog_next", JOY_BUTTON_A)
	_key("quick_save", [KEY_F5])
