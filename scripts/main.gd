extends Node

const NPC_DEFS:= {
	"gus": {"profile": "gus", "label": "NAME_GUS", "idle": "Idle_Torch_Loop", "talk": "Idle_Talking_Loop"},
	"lin": {"profile": "lin", "label": "NAME_LIN", "idle": "Idle_Loop", "talk": "Idle_Talking_Loop"},
}
const INSPECT_LABELS:= {"poster_eliz": "INT_POSTER", "vtech_screen": "INT_VTECH", "protest": "INT_PROTEST"}
const MENU_PATH:= [Vector3(-118, 3.0, 2.0), Vector3(-60, 4.0, -2.0), Vector3(-5, 6.0, 3.0), Vector3(4, 4.5, 40),
		Vector3(4, 3.5, 90), Vector3(40, 3.2, 96), Vector3(85, 3.0, 96)]

var ui_layer: CanvasLayer
var world: World
var city: City
var menus: Menus
var hud: Hud
var post: PostFX
var dialogue: DialogueUI
var barks: Barks
var player: Player
var npcs:= {}
var peds: Array = []
var menu_cam: Camera3D
var music: AudioStreamPlayer
var state:= "boot"
var _menu_t:= 0.0
var _autosave_t:= 60.0
var _talking_npc: Npc = null
var _collapse_said:= false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	Game.world = self
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	post = PostFX.new()
	ui_layer.add_child(post)
	hud = Hud.new()
	hud.visible = false
	ui_layer.add_child(hud)
	dialogue = DialogueUI.new()
	ui_layer.add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)
	dialogue.line_shown.connect(_on_line_shown)
	menus = Menus.new()
	ui_layer.add_child(menus)
	menus.new_game.connect(func (): _start(false))
	menus.continue_game.connect(func (): _start(true))
	menus.resume.connect(_resume)
	menus.to_main_menu.connect(_to_menu)
	menus.quit_game.connect(_quit)
	menus.show_only("loading")
	menus.set_loading(0.02, "LOADING")
	await get_tree().process_frame
	world = World.new()

	world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	menu_cam = Camera3D.new()
	menu_cam.fov = 62.0
	menu_cam.far = 1600.0
	world.add_child(menu_cam)
	menu_cam.current = true
	world.camera = menu_cam
	city = City.new()
	world.add_child(city)
	world.city = city
	city.progress.connect(menus.set_loading)
	await city.build()
	world.apply_settings()
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	add_child(music)
	world.start_ambience()
	_enter_menu()
	var args:= OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if "--benchmark" in args or OS.get_environment("OXWAG_BENCH") != "":
		var b:= Benchmark.new()
		b.main = self
		add_child(b)
	if OS.get_environment("OXWAG_SHOT") != "":
		var d: Node = load("res://scripts/dev/shot_driver.gd").new()
		d.set("main", self)
		add_child(d)

func marker_pos(name: String) -> Vector3:
	return city.marker(name)

func _enter_menu() -> void:
	state = "menu"
	get_tree().paused = false
	menu_cam.current = true
	world.camera = menu_cam
	hud.visible = false
	menus.show_only("main")
	Game.capture_mouse(false)
	_play_music("music_menu", -8.0)

func _play_music(name: String, vol: float) -> void:
	var s: AudioStream = load("res://assets/audio/%s.wav" % name)
	if music.stream == s and music.playing:
		return
	music.stream = s
	music.volume_db = vol
	music.play()

func _menu_camera(delta: float) -> void:
	_menu_t += delta * 0.018
	var n:= MENU_PATH.size() - 1
	var t:= fmod(_menu_t, 1.0) * n
	var i:= int(t)
	var f:= t - i
	var a: Vector3 = MENU_PATH[i]
	var b: Vector3 = MENU_PATH[mini(i + 1, n)]
	var p:= a.lerp(b, smoothstep(0.0, 1.0, f))
	var ahead: Vector3 = MENU_PATH[mini(i + 2, n)]
	var look:= b.lerp(ahead, f) + Vector3(0, 2.0, 0)
	menu_cam.global_position = menu_cam.global_position.lerp(p, clampf(delta * 1.5, 0.0, 1.0))
	var target_basis:= Transform3D().looking_at(look - menu_cam.global_position, Vector3.UP).basis
	menu_cam.global_basis = menu_cam.global_basis.slerp(target_basis, clampf(delta * 0.8, 0.0, 1.0)).orthonormalized()

func _start(load_save: bool) -> void:
	if load_save:
		if not Game.load_game():
			Game.new_game()
			load_save = false
	else:
		Game.new_game()
	_spawn_actors()
	var pos:= city.marker("spawn")
	var d: Array = city.markers.get("spawn_dir", [1, 0, 0])
	var yaw:= atan2(-float(d[0]), -float(d[2]))
	if load_save and Game.pending_load.has("pos"):
		var p: Array = Game.pending_load["pos"]
		pos = Vector3(p[0], p[1] + 0.1, p[2])
		yaw = float(Game.pending_load.get("yaw", yaw))
	player.place(pos, yaw)
	if load_save:
		player.set_camera_mode(Game.pending_load.get("camera", Settings.c["camera"]), true)
	world.camera = player.camera
	player.camera.current = true
	hud.bind_player(player)
	hud.visible = true
	menus.show_only("")
	Game.capture_mouse(true)
	_play_music("music_ambient", -14.0)
	state = "play"
	_autosave_t = 60.0
	if load_save:
		Game.set_objective(Game.objective_key, Game.objective_target)
		hud.show_hint(10.0)
	else:
		hud.intro_card([tr("INTRO_PLACE"), tr("INTRO_TIME")])
		hud.show_hint(22.0)
		await get_tree().create_timer(5.5).timeout
		if state == "play" and not dialogue.active:
			dialogue.start("intro", false)

func _spawn_actors() -> void:
	_despawn_actors()
	player = Player.new()
	player.name = "Player"
	world.add_child(player)
	player.city = city
	Game.player = player
	var inter: Array = []
	var bark_ids: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/barks.json")).keys()
	for it in city.interactables:
		if it["id"] in bark_ids:
			continue
		var e: Dictionary = it.duplicate()
		e["label"] = INSPECT_LABELS.get(it["id"], "")
		inter.append(e)

	var gm: Array = city.markers["gus"]
	var gpos:= Vector3(gm[0], gm[1], gm[2])
	var fire: Array = city.layout["fires"][0] if city.layout["fires"].size() > 0 else [gm[0] - 1, 0, gm[2] - 1]
	var to_fire:= Vector3(fire[0], 0, fire[2]) - Vector3(gpos.x, 0, gpos.z)
	_add_npc("gus", gpos, atan2(-to_fire.x, -to_fire.z), inter)
	var lm: Array = city.markers["lin"]
	_add_npc("lin", Vector3(lm[0], lm[1], lm[2]), float(lm[3]) + PI, inter)
	player.interactables = inter
	barks = Barks.new()
	add_child(barks)
	barks.setup(player, hud, city)

	var paths: Array = city.layout["walk_paths"]
	var profiles:= ["ped_m", "ped_f", "ped_m2", "ped_f", "ped_m", "ped_m2", "ped_f"]
	var umb:= [Color(0.05, 0.05, 0.06), Color(0.08, 0.1, 0.22), Color(0.45, 0.06, 0.06), Color(0.5, 0.45, 0.35), Color(0.05, 0.05, 0.06)]
	for i in profiles.size():
		var pd:= Pedestrian.new()
		world.add_child(pd)
		pd.setup(profiles[i], paths[i % paths.size()], i * 3, CharacterVisual.COAT_COLOURS[randi() % CharacterVisual.COAT_COLOURS.size()], umb[i % umb.size()])
		peds.append(pd)

func _add_npc(id: String, pos: Vector3, yaw: float, inter: Array) -> void:
	var def: Dictionary = NPC_DEFS[id]
	var n:= Npc.new()
	world.add_child(n)
	n.setup(id, def["profile"], pos, yaw, def["idle"], def["talk"])
	n.player = player
	npcs[id] = n
	inter.append({"id": id, "pos": pos + Vector3(0, 1.6, 0), "r": 2.6, "kind": "npc", "label": def["label"]})

func _despawn_actors() -> void:
	if barks:
		barks.queue_free()
		barks = null
	if player:
		player.queue_free()
		player = null
	for n in npcs.values():
		n.queue_free()
	npcs.clear()
	for p in peds:
		p.queue_free()
	peds.clear()

func _process(delta: float) -> void:
	Prof.b("main")
	match state:
		"menu":
			_menu_camera(delta)
		"play":
			if Input.is_action_just_pressed("pause") and not dialogue._choices_up:
				_pause()
				Prof.e("main")
				return
			if Input.is_action_just_pressed("quick_save"):
				Game.save_game()
				hud.show_toast(tr("HUD_SAVED"), 2.0)
			if not dialogue.active or not dialogue.blocking:
				if Input.is_action_just_pressed("interact") and not player.interact_target.is_empty() and not player.controls_locked:
					_interact(player.interact_target)
			_autosave_t -= delta
			if _autosave_t <= 0.0:
				_autosave_t = 60.0
				Game.save_game()
			if player and player._collapse_t > 0.0 and not _collapse_said:
				_collapse_said = true
				get_tree().create_timer(3.6).timeout.connect(_say_collapse)
			elif player and player._collapse_t <= 0.0:
				_collapse_said = false
		"paused":
			if Input.is_action_just_pressed("pause") and menus.pause_panel.visible:
				_resume()
	Prof.e("main")

func _say_collapse() -> void:
	if state == "play" and not dialogue.active:
		dialogue.start("collapse", false)

func _interact(it: Dictionary) -> void:
	var id: String = it["id"]
	if it.get("kind", "") == "npc":
		var n: Npc = npcs[id]
		_talking_npc = n
		n.set_talking(true)
		player.controls_locked = true
		player.velocity = Vector3.ZERO
		var dlg:= id
		if id == "gus" and Game.has_flag("met_gus"):
			dlg = "gus_repeat"
		elif id == "lin" and Game.has_flag("met_lin"):
			dlg = "lin_repeat"
		dialogue.start(dlg, true)
	else:
		player.controls_locked = true
		player.velocity = Vector3.ZERO
		var p:= AudioStreamPlayer.new()
		p.stream = load("res://assets/audio/inspect.wav")
		p.bus = "SFX"
		p.volume_db = -10.0
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
		dialogue.start(id, true)

func _on_line_shown(line: Dictionary) -> void:
	if _talking_npc:
		_talking_npc.set_talking(true, line.has("npc"))

func _on_dialogue_finished(_id: String) -> void:
	if _talking_npc:
		_talking_npc.set_talking(false)
		_talking_npc = null
	if player:
		player.controls_locked = false
	Game.capture_mouse(state == "play")
	if state == "play":
		Game.save_game()

func _pause() -> void:
	state = "paused"
	get_tree().paused = true
	hud.visible = false
	menus.show_only("pause")
	Game.capture_mouse(false)

func _resume() -> void:
	state = "play"
	get_tree().paused = false
	hud.visible = true
	menus.show_only("")
	Game.capture_mouse(true)

func _to_menu() -> void:
	Game.save_game()
	get_tree().paused = false
	if dialogue.active:
		dialogue._end()
	_despawn_actors()
	Game.player = null
	Game.set_objective("")
	_enter_menu()

func _quit() -> void:
	if state in ["play", "paused"]:
		Game.save_game()
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and state in ["play", "paused"]:
		Game.save_game()
