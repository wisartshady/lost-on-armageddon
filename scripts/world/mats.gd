class_name Mats
extends RefCounted

static var _cache:= {}
static var _layers:= {}

static func _shader(path: String) -> ShaderMaterial:
	var m:= ShaderMaterial.new()
	m.shader = load(path)
	return m

static func _load_layers() -> void:
	if not _layers.is_empty():
		return
	_layers = JSON.parse_string(FileAccess.get_file_as_string("res://data/surface_layers.json"))

static func get_mat(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m:= _build(name)
	_cache[name] = m
	return m

static func _build(name: String) -> Material:
	match name:
		"surf":
			_load_layers()
			var m:= _shader("res://shaders/surf.gdshader")
			m.set_shader_parameter("albedo_arr", load("res://assets/textures/surf_albedo_array.png"))
			m.set_shader_parameter("normal_arr", load("res://assets/textures/surf_normal_array.png"))
			var p0:= PackedVector4Array()
			var p1:= PackedVector4Array()
			for l in _layers["surf"]:
				p0.append(Vector4(l["uv_scale"], l["rough_dry"], l["rough_wet"], l["porosity"]))
				p1.append(Vector4(l["normal_depth"], l["grime"], l["specular"], l["reflect"]))
			while p0.size() < 24:
				p0.append(Vector4(0.5, 0.8, 0.4, 0.5))
				p1.append(Vector4(1, 0, 0.5, 0))
			m.set_shader_parameter("p0", p0)
			m.set_shader_parameter("p1", p1)
			return m
		"facade":
			_load_layers()
			var m:= _shader("res://shaders/facade.gdshader")
			m.set_shader_parameter("albedo_arr", load("res://assets/textures/surf_albedo_array.png"))
			m.set_shader_parameter("normal_arr", load("res://assets/textures/surf_normal_array.png"))
			var q0:= PackedVector4Array()
			var q1:= PackedVector4Array()
			for l in _layers["surf"]:
				q0.append(Vector4(l["uv_scale"], l["rough_dry"], l["rough_wet"], l["porosity"]))
				q1.append(Vector4(l["normal_depth"], l["grime"], l["specular"], l["reflect"]))
			while q0.size() < 24:
				q0.append(Vector4(0.5, 0.8, 0.4, 0.5))
				q1.append(Vector4(1, 0, 0.5, 0))
			m.set_shader_parameter("p0", q0)
			m.set_shader_parameter("p1", q1)
			return m
		"cut":
			_load_layers()
			var m:= _shader("res://shaders/cut.gdshader")
			m.set_shader_parameter("tex_arr", load("res://assets/textures/cut_array.png"))
			var c0:= PackedVector4Array()
			for l in _layers["cut"]:
				c0.append(Vector4(l["uv_scale"], 0, 0, 0))
			while c0.size() < 8:
				c0.append(Vector4(1, 0, 0, 0))
			m.set_shader_parameter("c0", c0)
			return m
		"window":
			var m:= _shader("res://shaders/window.gdshader")
			m.set_shader_parameter("shop", false)
			return m
		"shopwindow":
			var m:= _shader("res://shaders/window.gdshader")
			m.set_shader_parameter("shop", true)
			for k in ["back", "side", "mid", "front", "fc"]:
				m.set_shader_parameter("int_" + k, load("res://assets/textures/int_%s.png" % k))
			return m
		"signs":
			var m:= _shader("res://shaders/signs.gdshader")
			m.set_shader_parameter("atlas", load("res://assets/textures/signs_atlas.png"))
			return m
		"posters":
			var m:= _shader("res://shaders/signs.gdshader")
			m.set_shader_parameter("atlas", load("res://assets/textures/posters.png"))
			m.set_shader_parameter("glow", 0.0)
			return m
		"posters_lit":
			var m:= _shader("res://shaders/signs.gdshader")
			m.set_shader_parameter("atlas", load("res://assets/textures/posters.png"))
			m.set_shader_parameter("glow", 1.1)
			return m
		"graffiti":
			var m:= _shader("res://shaders/graffiti.gdshader")
			m.set_shader_parameter("atlas", load("res://assets/textures/graffiti.png"))
			return m
		"neon":
			var m:= _shader("res://shaders/neon.gdshader")
			m.set_shader_parameter("atlas", load("res://assets/textures/neon_atlas.png"))
			return m
		"lamp_glass":
			return _shader("res://shaders/lamp_glass.gdshader")
		"foliage":
			var m:= _shader("res://shaders/foliage.gdshader")
			m.set_shader_parameter("leaves", load("res://assets/textures/foliage.png"))
			return m
		"puddle":
			return _shader("res://shaders/puddle.gdshader")
		"glass_dark":
			return _shader("res://shaders/glass_dark.gdshader")
		"traffic":
			return _shader("res://shaders/traffic.gdshader")
		"vtech_screen":
			var m:= _shader("res://shaders/vtech_screen.gdshader")
			m.set_shader_parameter("frames", load("res://assets/textures/vtech_billboard.png"))
			return m
		"board":
			var m:= _shader("res://shaders/board.gdshader")
			m.set_shader_parameter("frames", load("res://assets/textures/billboards.png"))
			return m
		"ticker":
			var m:= _shader("res://shaders/ticker.gdshader")
			m.set_shader_parameter("strip", load("res://assets/textures/ticker.png"))
			return m
		"farfacade":
			return _shader("res://shaders/farfacade.gdshader")
		"skyline":
			var m:= _shader("res://shaders/skyline.gdshader")
			m.set_shader_parameter("windows_tex", load("res://assets/textures/skyline.png"))
			return m
		"vtech_glass":
			var m:= _shader("res://shaders/skyline.gdshader")
			m.set_shader_parameter("windows_tex", load("res://assets/textures/skyline.png"))
			m.set_shader_parameter("glass", 1.0)
			m.set_shader_parameter("fog_density", 0.0011)
			return m
		"vtech_logo":
			var m:= _shader("res://shaders/vtech_logo.gdshader")
			m.set_shader_parameter("logo", load("res://assets/textures/vtech_logo.png"))
			return m
		"beacon":
			return _shader("res://shaders/beacon.gdshader")
		"farground":
			return _shader("res://shaders/farground.gdshader")
		"lantern":
			var m:= _shader("res://shaders/lantern.gdshader")
			m.set_shader_parameter("tex", load("res://assets/textures/lantern.png"))
			return m
		"metal", "fabric_red":

			var m:= _shader("res://shaders/character.gdshader")
			m.set_shader_parameter("use_albedo", false)
			m.set_shader_parameter("use_normal", false)
			m.set_shader_parameter("roughness_v", 0.5)
			m.set_shader_parameter("rim", 0.0)
			return m
	push_warning("Unknown material: " + name)
	var sm:= StandardMaterial3D.new()
	sm.albedo_color = Color(1, 0, 1)
	return sm
