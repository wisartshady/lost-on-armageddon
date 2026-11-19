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


func _process(delta: float) -> void:
	if wait > 0.0:
		wait -= delta
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
		if c.has("call"):
			var target: Object = main
			for part in str(c.get("on", "")).split(".", false):
				target = target.get(part)
			target.callv(c["call"], c.get("args", []))
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
		if c.has("quit"):
			get_tree().quit()
			return
