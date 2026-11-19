extends Node
## Development helper (only active when the OXWAG_SHOT environment variable names a JSON command list).
## Drives the game without input: start a game, move the player or a free camera, set the clock and weather,
## hold actions, and save screenshots to OXWAG_SHOT_DIR. Not used by players.

var main: Node
var cmds: Array = []
var i:= 0
var wait:= 0.0
var free_cam: Camera3D
var out_dir:= "/tmp/shots"
var held: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var path:= OS.get_environment("OXWAG_SHOT")
	cmds = JSON.parse_string(FileAccess.get_file_as_string(path))
	if OS.get_environment("OXWAG_SHOT_DIR") != "":
		out_dir = OS.get_environment("OXWAG_SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(out_dir)
	wait = 0.5


func _v(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


var _measure_n:= 0
var _m_label:= ""
var _m_acc:= {}
var _m_frames:= 0


func _sample(delta: float) -> void:
	var vp:= get_viewport().get_viewport_rid()
	var vals:= {"dt": delta * 1000.0, "proc": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"phys": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"rcpu": RenderingServer.viewport_get_measured_render_time_cpu(vp),
		"gpu": RenderingServer.viewport_get_measured_render_time_gpu(vp),
		"draws": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		"tris": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)) / 1000.0}
	for k in vals:
		_m_acc[k] = _m_acc.get(k, 0.0) + vals[k]
	_m_frames += 1
	if _m_frames >= _measure_n:
		var s:= "MEASURE %s:" % _m_label
		for k in _m_acc:
			s += " %s=%.2f" % [k, _m_acc[k] / _m_frames]
		print(s)
		if Prof.on:
			print("PROF ", Prof.report(_m_frames))
		_measure_n = 0


var _follow: Array = []
var _show_car: MeshInstance3D
var _follow_ped:= -1
var _game_time:= true


func _update_follow() -> void:
	if _follow.is_empty() or main.player == null:
		return
	if free_cam == null:
		free_cam = Camera3D.new()
		free_cam.fov = 50.0
		free_cam.far = 1600.0
		main.world.add_child(free_cam)
	var pl: Node3D = main.player if _follow_ped < 0 else main.peds[_follow_ped]
	var b:= Basis(Vector3.UP, pl.visual.global_rotation.y)
	var off:= b * Vector3(float(_follow[0]), float(_follow[1]), float(_follow[2]))
	var target:= pl.global_position + Vector3(0, float(_follow[3]) if _follow.size() > 3 else 1.0, 0)
	if _follow.size() > 4:
		target += b * Vector3(0, 0, -float(_follow[4]))
	free_cam.global_position = target + off
	free_cam.look_at(target, Vector3.UP)
	free_cam.current = true


func _process(delta: float) -> void:
	_update_follow()
	if _measure_n > 0:
		_sample(delta)
		return
	if wait > 0.0:
		wait -= delta / maxf(Engine.time_scale, 0.001) * (Engine.time_scale if _game_time else 1.0)
		return
	while i < cmds.size():
		var c: Dictionary = cmds[i]
		i += 1
		if c.has("wait"):
			wait = float(c["wait"])
			return
		if c.has("start"):
			main._start(false)
			wait = 1.0
			return
		if c.has("place"):
			main.player.place(_v(c["place"]), float(c.get("yaw", 0.0)))
		if c.has("cam_mode"):
			main.player.set_camera_mode(c["cam_mode"], true)
		if c.has("look"):
			main.player.yaw = float(c["look"][0])
			main.player.yaw_t = main.player.yaw
			main.player.pitch = float(c["look"][1])
			main.player.pitch_t = main.player.pitch
		if c.has("cam"):
			if free_cam == null:
				free_cam = Camera3D.new()
				free_cam.fov = float(c.get("fov", 62.0))
				free_cam.far = 1600.0
				main.world.add_child(free_cam)
			free_cam.global_position = _v(c["cam"])
			free_cam.look_at(_v(c["at"]), Vector3.UP)
			free_cam.current = true
			main.world.camera = free_cam
		if c.has("player_cam"):
			main.player.camera.current = true
			main.world.camera = main.player.camera
		if c.has("preset"):
			Settings.set_preset(int(c["preset"]))
			Settings.g["dynamic_res"] = false
			Settings.changed.emit("graphics")
		if c.has("set"):
			for k in c["set"]:
				Settings.g[k] = c["set"][k]
			Settings.changed.emit("graphics")
		if c.has("bench_view"):
			var v: Array = Benchmark.VIEWS[int(c["bench_view"])]
			main.player.place(v[1], v[2])
			main.player.yaw_t = v[2]; main.player.yaw = v[2]
			main.player.pitch_t = v[3]; main.player.pitch = v[3]
			main.player.controls_locked = true
			if main.dialogue.active:
				main.dialogue._end()
		if c.has("hour"):
			main.world.weather.hour = float(c["hour"])
		if c.has("weather"):
			main.world.weather.set_state(c["weather"], true)
		if c.has("press"):
			Input.action_press(c["press"])
			held.append(c["press"])
		if c.has("release"):
			Input.action_release(c["release"])
			held.erase(c["release"])
		if c.has("call") and c["call"] == "dump_counts":
			var counts:= {}
			for n in get_tree().root.find_children("*", "", true, false):
				var k:= n.get_class()
				if n.get_script():
					k += ":" + str(n.get_script().resource_path.get_file())
				counts[k] = counts.get(k, 0) + 1
			var keys:= counts.keys()
			keys.sort_custom(func (a, b): return counts[a] > counts[b])
			for k in keys.slice(0, 45):
				print("COUNT ", k, " ", counts[k])
		elif c.has("call"):
			var target: Object = main
			for part in str(c.get("on", "")).split(".", false):
				target = target.get(part)
			target.callv(c["call"], c.get("args", []))
		if c.has("key"):
			var ev:= InputEventKey.new()
			ev.physical_keycode = OS.find_keycode_from_string(str(c["key"]))
			ev.keycode = ev.physical_keycode
			ev.pressed = bool(c.get("down", true))
			Input.parse_input_event(ev)
		if c.has("showroom"):
			# a single vehicle at a free spot, front towards -z
			if _show_car:
				_show_car.queue_free()
			for pm in main.city.parked:
				pm.visible = false
			var pos: Vector3 = _v(c.get("at", [-70.0, 0.0, 5.5]))
			_show_car = VehicleLib.spawn(main.world, str(c["showroom"]), Transform3D(Basis(Vector3.UP, float(c.get("yaw", 0.0))), pos),
				Color(c.get("paint", [0.2, 0.22, 0.25, 0.4])[0], c.get("paint", [0.2, 0.22, 0.25, 0.4])[1], c.get("paint", [0.2, 0.22, 0.25, 0.4])[2], c.get("paint", [0.2, 0.22, 0.25, 0.4])[3]), 0.15)
		if c.has("glass_tint"):
			VehicleLib.near_materials()[1].set_shader_parameter("tint", float(c["glass_tint"]))
		if c.has("xray_cars"):
			var xm:= (VehicleLib.material().duplicate() as ShaderMaterial)
			xm.shader = load("res://shaders/dev_vehicle_xray.gdshader")
			for mi in main.city.parked:
				mi.material_override = xm
		if c.has("print_cars"):
			for mi in main.city.parked:
				print("CAR ", mi.mesh.resource_path, " ", mi.global_position)
		if c.has("anims"):
			print("ANIMS ", ", ".join(AnimLib.get_library().get_animation_list()))
		if c.has("pose_clip"):
			# freeze the player's skeleton on one frame of a clip: [clip, time]
			var v: CharacterVisual = main.player.visual
			main.player.controls_locked = true
			v.action_lock = 9999.0
			v.anim.play(str(c["pose_clip"][0]), 0.0)
			v.anim.seek(float(c["pose_clip"][1]) * v.anim.get_animation(str(c["pose_clip"][0])).length, true)
			print("CLIPLEN ", c["pose_clip"][0], " ", v.anim.get_animation(str(c["pose_clip"][0])).length)
			v.anim.speed_scale = 0.0
		if c.has("timescale"):
			Engine.time_scale = float(c["timescale"])
		if c.has("follow"):
			# free camera placed relative to the player: [right, up, back] offsets in the player's facing frame
			_follow = c["follow"]
		if c.has("follow_ped"):
			_follow_ped = int(c["follow_ped"])
		if c.has("unfollow"):
			_follow = []
		if c.has("cam_rel"):
			# one-shot: like follow, but the camera then stays where it is
			_follow = c["cam_rel"]
			_update_follow()
			_follow = []
		if c.has("disable"):
			# class name or script file name; "hide:" prefix hides instead of stopping processing
			var what: String = c["disable"]
			var hide:= what.begins_with("hide:")
			what = what.trim_prefix("hide:")
			var n_hit:= 0
			for n in get_tree().root.find_children("*", "", true, false):
				var sc: Script = n.get_script()
				if n.get_class() == what or (sc and sc.resource_path.get_file() == what):
					if hide and n is Node3D:
						n.visible = false
					elif n is Area3D:
						n.monitoring = false
						n.monitorable = false
						n.process_mode = Node.PROCESS_MODE_DISABLED
					else:
						n.process_mode = Node.PROCESS_MODE_DISABLED
					n_hit += 1
			print("DISABLED ", what, " x", n_hit)
		if c.has("eval"):
			var e:= Expression.new()
			e.parse(c["eval"], ["main"])
			print("EVAL ", c["eval"], " = ", e.execute([main], self))
		if c.has("shot"):
			await RenderingServer.frame_post_draw
			var img:= get_viewport().get_texture().get_image()
			img.save_png(out_dir.path_join(str(c["shot"]) + ".png"))
			print("SHOT ", c["shot"], " fps=", Engine.get_frames_per_second())
			return
		if c.has("measure"):
			_measure_n = int(c["measure"])
			_m_label = str(c.get("label", "m"))
			_m_acc = {}
			_m_frames = 0
			Prof.acc.clear()
			Prof.cnt.clear()
			RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
			return
		if c.has("quit"):
			get_tree().quit()
			return
