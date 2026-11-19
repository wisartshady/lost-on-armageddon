class_name Benchmark
extends Node

static var active:= false

const VIEWS:= [
	["sokak/street", Vector3(-24.0, 0.15, -9.5), PI * 0.55, -0.06],
	["cadde/avenue", Vector3(-60.0, 0.15, 5.5), -PI * 0.5, -0.04],
	["vitrin/shopfront", Vector3(-30.0, 0.15, -9.8), PI, -0.1],
]

const PASSES:= [
	[2, "rain", 23.0, true],
	[2, "fog", 13.0, false],
	[0, "rain", 23.0, false],
	[3, "rain", 23.0, false],
]
const PRESET_NAMES:= ["cok dusuk/very low", "dusuk/low", "orta/medium", "yuksek/high", "ultra"]
var SETTLE:= 1.2
var WINDOW:= 2.5

var main: Node
var lines: PackedStringArray = []
var t:= 0.0
var step:= 0
var pi:= 0
var vi:= 0
var gi:= -1
var frames:= 0
var acc:= {}
var base:= {}
var groups: Array = []
var undo: Array = []
var saved_g:= {}
var saved_wx:= {}
var label: Label
var hitches:= 0
var worst:= 0.0

func _ready() -> void:
	active = true
	if OS.get_environment("OXWAG_BENCH") == "quick":
		SETTLE = 0.2
		WINDOW = 0.3
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = Label.new()
	label.position = Vector2(30, 30)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	var cl:= CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	cl.add_child(label)
	label.text = "PERFORMANS TESTI hazirlaniyor..."
	saved_g = Settings.g.duplicate()
	_line("LOST ON ARMAGEDDON - performans raporu / performance report  v%s" % str(ProjectSettings.get_setting("application/config/version", "?")))
	_line("tarih/date: " + Time.get_datetime_string_from_system())
	_line("CPU: %s  (%d cekirdek/threads)" % [OS.get_processor_name(), OS.get_processor_count()])
	_line("GPU: %s  (%s)  surucu/driver %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_api_version()])
	_line("renderer: %s   OS: %s %s" % [RenderingServer.get_current_rendering_method(), OS.get_name(), OS.get_version()])
	_line("ekran/screen: %s   pencere/window: %s" % [str(DisplayServer.screen_get_size()), str(DisplayServer.window_get_size())])
	_line("v-sync: kapali/off during test (gercek hiz olculur / measures the real speed)")
	_line("")
	_line("sutunlar / columns: FPS | kare/frame ms | cpu = oyun islemi/game process ms | fizik/physics ms |")
	_line("  render-cpu = cizim komutlari/draw submission ms | gpu = ekran karti/graphics card ms | draw calls | ucgen/triangles")
	_line("  takilma/hitch = 50 ms'den uzun kareler / frames over 50 ms")

func _exit_tree() -> void:
	active = false

func _line(s: String) -> void:
	lines.append(s)
	print(s)

func _write() -> String:
	var path:= OS.get_executable_path().get_base_dir().path_join("benchmark_report.txt")
	if OS.has_feature("editor"):
		path = ProjectSettings.globalize_path("res://benchmark_report.txt")
	var f:= FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		path = ProjectSettings.globalize_path("user://benchmark_report.txt")
		f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("BENCHMARK written ", path)
	return path

func _find(pred: Callable) -> Array:
	var out:= []
	for n in get_tree().root.find_children("*", "", true, false):
		if pred.call(n):
			out.append(n)
	return out

func _shader_file(n: Node) -> String:
	if n is GeometryInstance3D and n.material_override is ShaderMaterial and n.material_override.shader:
		return n.material_override.shader.resource_path.get_file()
	if n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh and n.multimesh.mesh.get_surface_count() > 0:
		var m: Material = n.multimesh.mesh.surface_get_material(0)
		if m is ShaderMaterial and m.shader:
			return m.shader.resource_path.get_file()
	return ""

func _build_groups() -> void:
	var w: Node = main.world
	var city: Node = w.city
	var pl: Node = main.player
	var fx:= ["lamp_halo.gdshader", "lamp_cone.gdshader"]
	groups = [
		["yagmur/rain", [w.rain_mm], "vis"],
		["lamba isiklari/lamp glow", _find(func (n): return n is MultiMeshInstance3D and _shader_file(n) in fx), "vis"],
		["esyalar/props", _find(func (n): return n is MultiMeshInstance3D and n != w.rain_mm and not (_shader_file(n) in fx)), "vis"],
		["karakterler/characters", _find(func (n): return n is CharacterVisual and not pl.is_ancestor_of(n)), "vis"],
		["park arabalar/cars", city.parked.duplicate(), "vis"],
		["bina bloklari/city", city.chunk_nodes.duplicate(), "vis"],
		["isiklar/lights", _find(func (n): return (n is OmniLight3D or n is SpotLight3D) and not pl.is_ancestor_of(n)), "vis"],
		["parcaciklar/particles", _find(func (n): return n is CPUParticles3D or n is GPUParticles3D), "vis"],
		["son efekt/post", [main.post], "vis"],
		["parlama/glow", [], "glow"],
		["pencere ici/windows", [], "windows"],
	]

func _hide_group(g: Array) -> void:
	match g[2]:
		"vis":
			for n in g[1]:
				if is_instance_valid(n) and n.visible:
					n.visible = false
					undo.append(n)
		"glow":
			main.world.env.glow_enabled = false
		"windows":
			RenderingServer.global_shader_parameter_set("window_detail", 0.0)

func _restore() -> void:
	for n in undo:
		if is_instance_valid(n):
			n.visible = true
	undo.clear()
	main.world.env.glow_enabled = bool(Settings.g["glow"])
	RenderingServer.global_shader_parameter_set("window_detail", float(Settings.g["windows"]))

func _set_view(k: int) -> void:
	var p = main.player
	var v: Array = VIEWS[k]
	p.place(v[1], v[2])
	p.yaw_t = v[2]; p.yaw = v[2]
	p.pitch_t = v[3]; p.pitch = v[3]

func _measure(delta: float) -> void:
	frames += 1
	var ms:= delta * 1000.0
	if ms > 50.0:
		hitches += 1
	worst = maxf(worst, ms)
	var vp:= get_viewport().get_viewport_rid()
	acc["dt"] = acc.get("dt", 0.0) + ms
	acc["cpu"] = acc.get("cpu", 0.0) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	acc["phys"] = acc.get("phys", 0.0) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	acc["rcpu"] = acc.get("rcpu", 0.0) + RenderingServer.viewport_get_measured_render_time_cpu(vp)
	acc["gpu"] = acc.get("gpu", 0.0) + RenderingServer.viewport_get_measured_render_time_gpu(vp)
	acc["draws"] = acc.get("draws", 0.0) + RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	acc["prims"] = acc.get("prims", 0.0) + RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)

func _result() -> Dictionary:
	var f:= float(maxi(frames, 1))
	var r:= {}
	for k in acc:
		r[k] = acc[k] / f
	r["hitch"] = hitches
	r["worst"] = worst
	frames = 0
	hitches = 0
	worst = 0.0
	acc.clear()
	return r

func _fmt(r: Dictionary) -> String:
	return "%5.1f FPS  kare %5.1f ms | cpu %5.1f  fizik %4.1f  render-cpu %5.1f  gpu %5.1f | draw %4d  tri %4dk | takilma %d (en kotu %.0f ms)" % [
		1000.0 / maxf(r.get("dt", 1.0), 0.01), r.get("dt", 0.0), r.get("cpu", 0.0), r.get("phys", 0.0), r.get("rcpu", 0.0),
		r.get("gpu", 0.0), int(r.get("draws", 0)), int(r.get("prims", 0)) / 1000, int(r.get("hitch", 0)), r.get("worst", 0.0)]

func _with_groups() -> bool:
	return bool(PASSES[pi][3])

func _process(delta: float) -> void:
	t += delta
	match step:
		0:
			if main.state == "menu":
				main._start(false)
				step = 1; t = 0.0
		1:
			if main.dialogue.active:
				main.dialogue._end()
			if t > 7.0:
				main.player.controls_locked = true
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				Engine.max_fps = 0
				RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
				saved_wx = WeatherSim.current.save_data() if WeatherSim.current else {}
				_start_pass()
		2:
			if main.dialogue.active:
				main.dialogue._end()
			label.text = "PERFORMANS TESTI  %d/%d  -  %s  -  %s\nLutfen bekleyin, bitince oyun kendiliginden kapanir.\nPlease wait, the game closes by itself when done." % [
				pi + 1, PASSES.size(), VIEWS[vi][0], "temel/base" if gi < 0 else groups[gi][0]]
			if t > SETTLE:
				_measure(delta)
			if t > SETTLE + WINDOW:
				var r:= _result()
				if gi < 0:
					base = r
					_line("  [%-16s] temel/base        %s" % [VIEWS[vi][0], _fmt(r)])
				else:
					_line("     -%-26s %s   => kazanc/saves %+.1f ms (gpu %+.1f ms)" % [groups[gi][0], _fmt(r),
						base.get("dt", 0.0) - r.get("dt", 0.0), base.get("gpu", 0.0) - r.get("gpu", 0.0)])
				_restore()
				gi += 1
				if not _with_groups() or gi >= groups.size():
					gi = -1
					vi += 1
					if vi >= VIEWS.size():
						pi += 1
						if pi >= PASSES.size():
							_finish()
							return
						_start_pass()
						return
					_set_view(vi)
				else:
					_hide_group(groups[gi])
				t = 0.0

func _start_pass() -> void:
	step = 3
	var ps: Array = PASSES[pi]
	Settings.set_preset(int(ps[0]))
	Settings.g["dynamic_res"] = false
	Settings.changed.emit("graphics")
	var wx: WeatherSim = WeatherSim.current
	if wx:
		wx.hour = float(ps[2])
		wx.set_state(str(ps[1]), true)
		wx.state_left = 9999.0
	_line("")
	_line("== %s  |  hava/weather %s, saat/hour %02d:00  |  render olcek/scale %.2f, gorus/view %.0f m, golge/shadows %d, isik/lights %d" % [
		PRESET_NAMES[int(ps[0])], ps[1], int(ps[2]), float(Settings.g["render_scale"]), float(Settings.g["view_distance"]),
		int(Settings.g["shadows"]), int(Settings.g["lights"])])
	await get_tree().process_frame
	await get_tree().process_frame
	_build_groups()
	vi = 0
	gi = -1
	_set_view(0)
	t = -1.0
	step = 2

func _finish() -> void:
	step = 99
	_line("")
	_line("bitti / done")
	var path:= _write()

	for k in saved_g:
		Settings.g[k] = saved_g[k]
	active = false
	Settings.save()
	Settings.changed.emit("graphics")
	Settings.apply_display()
	if WeatherSim.current and not saved_wx.is_empty():
		WeatherSim.current.load_data(saved_wx)
	label.text = "PERFORMANS TESTI BITTI\n" + path
	await get_tree().create_timer(3.0).timeout
	get_tree().quit()
