class_name Player
extends CharacterBody3D

signal interact_changed(info: Dictionary)
signal strain_changed(value: float)
signal power_used(first_time: bool)
signal collapsed

const WALK:= 2.0
const RUN:= 5.6
const CROUCH:= 1.1
const ACCEL:= 10.0
const JUMP_V:= 4.4
const GRAVITY:= 15.0
const STEP:= 0.38
const EYE_H:= 1.6
const CLIMB_MIN:= 0.55
const CLIMB_MAX:= 2.3

var visual: CharacterVisual
var cam_yaw_node: Node3D
var cam_pitch_node: Node3D
var spring: SpringArm3D
var camera: Camera3D
var flashlight: SpotLight3D
var hand_light: OmniLight3D
var step_player: AudioStreamPlayer3D
var step_layer: AudioStreamPlayer3D
var sfx_player: AudioStreamPlayer
var charge_player: AudioStreamPlayer
var heart_player: AudioStreamPlayer
var ring_player: AudioStreamPlayer

var yaw:= 0.0
var pitch:= -0.12
var yaw_t:= 0.0
var pitch_t:= -0.12
var _auto_w:= 0.0
var _auto_vel:= 0.0
var _anchor:= Vector3.ZERO
var cam_mode:= "tp"
var _cam_blend:= 0.0
var crouching:= false
var controls_locked:= false
var look_locked:= false
var strain:= 0.0
var charge:= 0.0
var charging:= false
var _strain_idle:= 0.0
var _step_dist:= 0.0
var _air_t:= 0.0
var _jump_t:= -1.0
var _jump_run:= false
var _air_from_run:= false
var _land_t:= -1.0
var _land_amount:= 0.0
var _jpose: JumpPoseModifier
var _land_slow:= 0.0
var _mi:= MoveInput.new()
var _fall: FallPoseModifier
var _posture: PostureModifier
var _air_top:= 0.0
var _warp_ready:= false
var climbing:= false
var _latched_dir:= Vector3.ZERO
var _latched_in:= Vector2.ZERO
var _mouse_turn_t:= 99.0
var _climb:= {}
var _fall_v:= 0.0
var _bob:= 0.0
var _shake:= 0.0
var _collapse_t:= 0.0
var _was_on_floor:= true
var _power_used_once:= false
var interact_target:= {}
var city: City
var interactables: Array = []
var _steps: Array = []
var _feet: FootPlant

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 8
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	var cs:= CollisionShape3D.new()
	var cap:= CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	visual = CharacterVisual.new()
	add_child(visual)
	visual.setup("vaynara")
	cam_yaw_node = Node3D.new()
	cam_yaw_node.position.y = 1.5
	add_child(cam_yaw_node)
	cam_yaw_node.top_level = true

	cam_yaw_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	cam_pitch_node = Node3D.new()
	cam_yaw_node.add_child(cam_pitch_node)
	spring = SpringArm3D.new()
	spring.spring_length = 2.4
	spring.margin = 0.2
	spring.collision_mask = 1
	var sh:= SphereShape3D.new()
	sh.radius = 0.2
	spring.shape = sh
	spring.add_excluded_object(get_rid())
	cam_pitch_node.add_child(spring)
	camera = Camera3D.new()
	camera.current = true
	camera.near = 0.06
	camera.far = 1600.0
	spring.add_child(camera)
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(0.92, 0.96, 1.0)
	flashlight.light_energy = 3.0
	flashlight.spot_range = 22.0
	flashlight.spot_angle = 28.0
	flashlight.spot_attenuation = 1.2
	flashlight.visible = false
	cam_pitch_node.add_child(flashlight)
	flashlight.position = Vector3(0.25, -0.15, -0.3)
	hand_light = OmniLight3D.new()
	hand_light.light_color = Color(0.3, 0.85, 1.0)
	hand_light.omni_range = 3.0
	hand_light.light_energy = 0.0
	add_child(hand_light)
	hand_light.position = Vector3(0.3, 1.1, -0.3)
	step_player = AudioStreamPlayer3D.new()
	step_player.bus = "SFX"
	step_player.volume_db = -8.0
	step_player.max_distance = 20.0
	add_child(step_player)
	step_layer = AudioStreamPlayer3D.new()
	step_layer.bus = "SFX"
	step_layer.max_distance = 20.0
	add_child(step_layer)
	step_layer.position = Vector3(0, 0.1, 0)
	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "SFX"
	add_child(sfx_player)
	charge_player = AudioStreamPlayer.new()
	charge_player.bus = "SFX"
	charge_player.stream = load("res://assets/audio/emp_charge.wav")
	add_child(charge_player)
	heart_player = AudioStreamPlayer.new()
	heart_player.bus = "SFX"
	heart_player.stream = load("res://assets/audio/heartbeat.wav")
	heart_player.volume_db = -80.0
	add_child(heart_player)
	ring_player = AudioStreamPlayer.new()
	ring_player.bus = "SFX"
	ring_player.stream = load("res://assets/audio/tinnitus.wav")
	ring_player.volume_db = -80.0
	add_child(ring_player)
	set_camera_mode(Settings.c["camera"], true)
	Settings.changed.connect(func (_s): camera.fov = Settings.c["fov"])
	camera.fov = Settings.c["fov"]

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_PAUSED:
		_mi.reset()

func get_yaw() -> float:
	return yaw

func get_camera_mode() -> String:
	return cam_mode

func place(pos: Vector3, facing_yaw: float) -> void:
	global_position = pos
	yaw = facing_yaw
	yaw_t = facing_yaw
	pitch_t = pitch
	visual.rotation.y = facing_yaw
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_anchor = global_position + Vector3(0, 1.5, 0)
	cam_yaw_node.global_position = _anchor

func set_camera_mode(mode: String, instant:= false) -> void:
	cam_mode = mode

	visual.set_first_person(true)
	if instant:
		_cam_blend = 1.0 if mode == "fp" else 0.0

func _input(event: InputEvent) -> void:
	_mi.on_event(event)
	if look_locked or get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)

func _look(d: Vector2) -> void:
	if d.length() > 0.5:
		_mouse_turn_t = 0.0
		_auto_w = 0.0
		_auto_vel = 0.0
	var s: float = Settings.c["mouse_sens"] * 0.01
	yaw_t -= d.x * s
	var inv:= -1.0 if Settings.c["invert_y"] else 1.0
	pitch_t = clampf(pitch_t - d.y * s * inv, -1.35, 1.25)

func _smooth_look(delta: float) -> void:
	var tau:= 0.06 * float(Settings.c.get("mouse_smooth", 0.35))
	if tau < 0.002:
		yaw = yaw_t
		pitch = pitch_t
		return
	var k:= 1.0 - exp(-delta / tau)
	yaw = lerpf(yaw, yaw_t, k)
	pitch = lerpf(pitch, pitch_t, k)

func _mouse_compat() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CONFINED_HIDDEN or look_locked or get_tree().paused or not DisplayServer.window_is_focused():
		_warp_ready = false
		return
	var wsize:= Vector2(DisplayServer.window_get_size())
	var center:= (wsize * 0.5).floor()
	var mp:= Vector2(DisplayServer.mouse_get_position() - DisplayServer.window_get_position())
	if _warp_ready:
		var d:= mp - center
		if d.length() < wsize.x * 0.45:
			_look(d)
	Input.warp_mouse(center)
	_warp_ready = true

func _physics_process(delta: float) -> void:
	Prof.b("player_phys")
	if get_tree().paused:
		Prof.e("player_phys")
		return
	if visual.position.y != 0.0:
		visual.position.y = move_toward(visual.position.y, 0.0, delta * maxf(1.8, absf(visual.position.y) * 9.0))
	if climbing:
		_update_climb(delta)
		Prof.e("player_phys")
		return
	_update_strain(delta)

	var look:= Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if look.length() > 0.15 and not look_locked:
		yaw_t -= look.x * 2.6 * delta
		pitch_t = clampf(pitch_t - look.y * 2.0 * delta * (-1.0 if Settings.c["invert_y"] else 1.0), -1.35, 1.25)
		_mouse_turn_t = 0.0
		_auto_w = 0.0

	_mi.sprint_toggle = bool(Settings.c.get("sprint_toggle", false))
	var input:= _mi.read(delta)
	var sprint_key:= _mi.sprint()
	if controls_locked or _collapse_t > 0.0:
		input = Vector2.ZERO
	if not controls_locked and _collapse_t <= 0.0:
		if Input.is_action_just_pressed("crouch"):
			crouching = not crouching
		if Input.is_action_just_pressed("camera_toggle"):
			set_camera_mode("fp" if cam_mode == "tp" else "tp")
		if Input.is_action_just_pressed("flashlight"):
			flashlight.visible = not flashlight.visible
			_sfx("ui_click", -12.0)
	var sprint:= sprint_key and not crouching and input.y < 0.2 and strain < 0.9
	var speed:= CROUCH if crouching else (RUN if sprint and not charging else WALK)
	if charging:
		speed *= 0.75
	if strain > 0.75:
		speed *= 0.8
	if _land_slow > 0.0:
		_land_slow -= delta
		speed *= 0.35
	var basis_yaw:= Basis(Vector3.UP, yaw)
	var dir:= basis_yaw * Vector3(input.x, 0, input.y)

	if input.length() > 0.2:
		if _latched_in.length() < 0.2 or input.distance_to(_latched_in) > 0.12 or _mouse_turn_t < 0.25 or _auto_w < 0.05:
			_latched_dir = dir
			_latched_in = input
		else:
			dir = _latched_dir.normalized() * minf(input.length(), 1.0)
	else:
		_latched_in = Vector2.ZERO
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target:= dir * speed
	var hv:= Vector3(velocity.x, 0, velocity.z)

	var acc:= ACCEL if target.length() >= hv.length() * 0.9 else 16.0
	hv = hv.lerp(target, clampf(acc * delta, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	var can_act:= not controls_locked and not crouching and _collapse_t <= 0.0
	var face:= _climb_dir(dir)
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and can_act and _jump_t < 0.0:
			if not _start_climb(face):
				_begin_jump()
	else:
		velocity.y -= GRAVITY * delta

		if can_act and dir.length() > 0.3 and velocity.y < 2.5 and is_on_wall():
			if _start_climb(face):
				Prof.e("player_phys")
				return

	if _jump_t >= 0.0:
		_jump_t += delta
		if _jump_t >= (JUMP_LOAD_RUN if _jump_run else JUMP_LOAD):
			_jump_t = -1.0
			if is_on_floor():
				velocity.y = JUMP_V
				_launch_air_clip()
	var pre:= global_position
	move_and_slide()

	if (is_on_floor() or _was_on_floor) and is_on_wall() and dir.length() > 0.1:
		_try_step(Vector3(target.x, 0, target.z) * delta)

	if _posture == null and visual.skeleton:
		_posture = PostureModifier.new()
		visual.skeleton.add_child(_posture)
		visual.skeleton.move_child(_posture, 0)
	if _posture:
		var hs:= Vector2(velocity.x, velocity.z).length()
		var lean_deg:= 2.0 if hs < 0.3 else (lerpf(3.0, 5.0, clampf((hs - 0.3) / 2.0, 0.0, 1.0)) if hs < 2.6 else lerpf(6.0, 12.0, clampf((hs - 2.6) / 3.0, 0.0, 1.0)))
		_posture.target_lean = lerp_angle(_posture.target_lean, deg_to_rad(lean_deg), clampf(delta * 6.0, 0.0, 1.0))
		_posture.weight = move_toward(_posture.weight, 0.0 if (crouching or climbing or _collapse_t > 0.0) else 1.0, delta * 4.0)
	if _fall == null and visual.skeleton:
		_fall = FallPoseModifier.new()
		visual.skeleton.add_child(_fall)
	if is_on_floor():
		_air_top = global_position.y
	else:
		_air_top = maxf(_air_top, global_position.y)
	if _fall:
		# only a real fall (well below where the jump peaked) flails the arms; a normal jump keeps its own pose
		var falling:= not is_on_floor() and not climbing and _air_top - global_position.y > 1.6 and velocity.y < -4.0
		_fall.weight = move_toward(_fall.weight, 1.0 if falling else 0.0, delta * (2.6 if falling else 9.0))

	if not is_on_floor():
		if _air_t == 0.0:
			_air_from_run = _jump_run or Vector2(velocity.x, velocity.z).length() > 3.2
		_air_t += delta
		_fall_v = minf(_fall_v, velocity.y)
	else:
		if not _was_on_floor and _air_t > 0.3 and _fall_v < -3.0:
			_play_step(-4.0, "land")
		if not _was_on_floor and _air_t > 0.2:
			_land(dir.length() > 0.1)
		_air_t = 0.0
		_fall_v = 0.0
	_was_on_floor = is_on_floor()

	var moved:= Vector3(global_position.x - pre.x, 0, global_position.z - pre.z).length() / maxf(delta, 0.0001)
	if cam_mode == "fp" or (charging and dir.length() < 0.1):
		visual.rotation.y = lerp_angle(visual.rotation.y, yaw, clampf(14.0 * delta, 0.0, 1.0))
	elif dir.length() > 0.1:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-dir.x, -dir.z), clampf(10.0 * delta, 0.0, 1.0))
	if _collapse_t <= 0.0:
		visual.locomotion(moved, is_on_floor(), crouching, delta)
	_update_jump_pose(delta)
	_update_power_pose(delta)

	if _feet == null or not _feet.ready:
		if is_on_floor() and moved > 0.5:
			_step_dist += moved * delta
			var stride:= 0.75 if moved < 3.0 else 1.15
			if _step_dist > stride:
				_step_dist = 0.0
				_play_step(-8.0 if not crouching else -16.0)
	_bob += moved * delta * 2.2
	_update_power(delta)
	_update_interact()

	Prof.e("player_phys")

func _auto_camera(delta: float) -> void:
	var allowed: bool = cam_mode == "tp" and bool(Settings.c.get("auto_camera", true)) and not controls_locked and not climbing
	var hv:= Vector2(velocity.x, velocity.z)
	var moving:= hv.length() > 1.0 and is_on_floor()
	var want:= 1.0 if allowed and moving and _mouse_turn_t > 1.4 else 0.0

	_auto_w = move_toward(_auto_w, want, delta * (0.8 if want > _auto_w else 3.0))
	var w:= smoothstep(0.0, 1.0, _auto_w)
	var target_vel:= 0.0
	if w > 0.0 and moving:
		var heading:= atan2(-velocity.x, -velocity.z)
		var diff:= wrapf(heading - yaw_t, -PI, PI)

		if absf(diff) > 2.9:
			diff = absf(diff) * (1.0 if wrapf(visual.rotation.y - yaw_t, -PI, PI) >= 0.0 else -1.0)
		var speed_k:= clampf(hv.length() / 2.0, 0.6, 1.6)

		target_vel = clampf(diff * 1.1, -1.0, 1.0) * deg_to_rad(38.0) * speed_k
		if absf(diff) < 0.04:
			target_vel = 0.0
	_auto_vel = lerpf(_auto_vel, target_vel, 1.0 - exp(-delta * 3.0))
	yaw_t += _auto_vel * delta * w
	if w > 0.0:
		pitch_t = lerpf(pitch_t, -0.14, (1.0 - exp(-delta * 0.7)) * w)

const JUMP_LOAD:= 0.14        # standing jump: knees load before take-off
const JUMP_LOAD_RUN:= 0.05    # running jump: one quick dip in stride

func _begin_jump() -> void:
	_jump_run = Vector2(velocity.x, velocity.z).length() > 3.2
	_jump_t = 0.0
	_land_t = -1.0

func _launch_air_clip() -> void:
	var flight:= 2.0 * JUMP_V / GRAVITY
	if _jump_run and visual.anim.has_animation("MJump_Run_Air"):
		# the leap part of the clip only (lead knee up, arms counter-swinging); its later frames fling the arms wide
		var a:= visual.anim.get_animation("MJump_Run_Air")
		visual.play_action("MJump_Run_Air", flight + 0.2, 0.08)
		visual.anim.speed_scale = a.length * 0.42 / flight
	elif visual.anim.has_animation("MJump_Stand_Air"):
		var b:= visual.anim.get_animation("MJump_Stand_Air")
		visual.play_action("MJump_Stand_Air", flight + 0.2, 0.1)
		visual.anim.speed_scale = b.length * 0.8 / flight

func _land(moving: bool) -> void:
	var hv:= Vector2(velocity.x, velocity.z).length()
	_land_t = 0.0
	if _fall_v < -10.5:
		_land_amount = 1.0
		_land_slow = 0.35
		_shake = maxf(_shake, 0.25)
		if visual.anim.has_animation("MLand_Hard"):
			visual.play_action("MLand_Hard", 0.42, 0.07)
	else:
		# knees take the landing: deeper for a high drop, shallow when landing in a run
		_land_amount = clampf(-_fall_v / 11.0, 0.22, 0.8) * (0.55 if hv > 3.0 else 1.0)
		visual.action_lock = 0.0
		visual.anim.speed_scale = 1.0
	_jump_run = false

## Drives the procedural jump layer: load before take-off, tuck and arms in the air, landing absorption.
func _update_jump_pose(delta: float) -> void:
	if _jpose == null and visual.skeleton:
		_jpose = JumpPoseModifier.new()
		visual.skeleton.add_child(_jpose)
	if _jpose == null:
		return
	var c:= 0.0
	var t:= 0.0
	var ar:= 0.0
	if _jump_t >= 0.0:
		var T:= JUMP_LOAD_RUN if _jump_run else JUMP_LOAD
		var k:= smoothstep(0.0, 1.0, _jump_t / T)
		c = k * (0.28 if _jump_run else 0.7)
		ar = -k * (0.0 if _jump_run else 0.8)
	elif not is_on_floor() and not climbing:
		var up_phase:= velocity.y > 0.0
		var near:= _ground_below(0.7) if velocity.y < 0.0 else false
		t = (0.85 if up_phase else 0.45) * (0.3 if _air_from_run else 1.0)
		ar = 0.0 if _air_from_run else (0.6 if up_phase else 0.35)
		if near:
			t = 0.0
			ar *= 0.5
		if _air_top - global_position.y > 1.6:
			t = 0.0
			ar = 0.0
	if _land_t >= 0.0:
		_land_t += delta
		var tau:= 0.075
		var x:= _land_t / tau
		c = maxf(c, _land_amount * x * exp(1.0 - x))
		if _land_t > 0.6:
			_land_t = -1.0
	var rate:= 14.0
	_jpose.crouch = c if _land_t >= 0.0 or _jump_t >= 0.0 else move_toward(_jpose.crouch, c, delta * 6.0)
	_jpose.tuck = lerpf(_jpose.tuck, t, clampf(delta * 9.0, 0.0, 1.0))
	_jpose.arms = lerpf(_jpose.arms, ar, clampf(delta * rate, 0.0, 1.0))
	_jpose.weight = 0.0 if (crouching or _collapse_t > 0.0) else 1.0

func _ground_below(dist: float) -> bool:
	var q:= PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.1, 0), global_position - Vector3(0, dist, 0), 1)
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _climb_dir(move_dir: Vector3) -> Vector3:
	if move_dir.length() > 0.2:
		return Vector3(move_dir.x, 0, move_dir.z).normalized()
	var y:= visual.rotation.y if cam_mode == "tp" else yaw
	return Basis(Vector3.UP, y) * Vector3(0, 0, -1)

func _find_ledge(fwd: Vector3) -> Dictionary:
	var ss:= get_world_3d().direct_space_state
	var feet:= global_position
	var hit:= {}
	for hy in [1.1, 0.6, 1.6]:
		var q:= PhysicsRayQueryParameters3D.create(feet + Vector3(0, hy, 0), feet + Vector3(0, hy, 0) + fwd * 0.85, 1)
		q.exclude = [get_rid()]
		hit = ss.intersect_ray(q)
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.5:
			break
		hit = {}
	if hit.is_empty():
		return {}
	var n: Vector3 = hit["normal"]
	var wall_dir:= Vector3(-n.x, 0, -n.z).normalized()
	if wall_dir.dot(fwd) < 0.45:
		return {}
	var probe: Vector3 = hit["position"] + wall_dir * 0.32
	var q2:= PhysicsRayQueryParameters3D.create(Vector3(probe.x, feet.y + CLIMB_MAX + 0.35, probe.z), Vector3(probe.x, feet.y + CLIMB_MIN - 0.1, probe.z), 1)
	q2.exclude = [get_rid()]
	var top:= ss.intersect_ray(q2)
	if top.is_empty() or (top["normal"] as Vector3).y < 0.75:
		return {}
	var h: float = (top["position"] as Vector3).y - feet.y
	if h < CLIMB_MIN or h > CLIMB_MAX:
		return {}
	var land: Vector3 = top["position"] + wall_dir * 0.18

	var cap:= CapsuleShape3D.new()
	cap.radius = 0.27
	cap.height = 1.6
	var sp:= PhysicsShapeQueryParameters3D.new()
	sp.shape = cap
	sp.transform = Transform3D(Basis(), land + Vector3(0, 0.86, 0))
	sp.collision_mask = 1
	sp.exclude = [get_rid()]
	if not ss.intersect_shape(sp, 1).is_empty():
		return {}

	var q3:= PhysicsRayQueryParameters3D.create(feet + Vector3(0, 1.0, 0), feet + Vector3(0, h + 1.75, 0), 1)
	q3.exclude = [get_rid()]
	if not ss.intersect_ray(q3).is_empty():
		return {}
	return {"land": land, "h": h, "dir": wall_dir, "wall": hit["position"]}

const CLIMB_CLIP_H:= 1.68

func _start_climb(fwd: Vector3) -> bool:
	var l:= _find_ledge(fwd)
	if l.is_empty():
		return false
	var wall: Vector3 = l["wall"]
	var d: Vector3 = l["dir"]
	var h: float = l["h"]
	var kind:= "climb"
	if h < 0.95:
		kind = "step"
	elif h > 1.75 or not is_on_floor():
		kind = "hang"
	var start:= Vector3(wall.x, global_position.y, wall.z) - d * (0.42 if kind == "step" else 0.34)
	var pre:= 0.0
	var dur:= clampf(0.55 + minf(h, CLIMB_CLIP_H) * 0.3, 0.7, 1.15)
	if kind == "step":
		dur = 0.42 + h * 0.18
	elif kind == "hang":
		pre = 0.45 if is_on_floor() else 0.12
	_climb = {"from": global_position, "start": start, "land": l["land"], "h": h, "t": 0.0, "dur": dur, "pre": pre, "kind": kind,
		"anim2": false}
	climbing = true
	velocity = Vector3.ZERO
	visual.rotation.y = atan2(-d.x, -d.z)
	if kind == "step":
		if visual.anim.has_animation("MClimb_Hop_RM"):

			dur = 0.82 + h * 0.12
			_climb["dur"] = dur
			_climb["curve"] = AnimLib.mocap_curve("MClimb_Hop_RM")
			visual.play_action("MClimb_Hop_RM", dur + 0.05, 0.08)
			visual.anim.speed_scale = visual.anim.get_animation("MClimb_Hop_RM").length / dur
		else:
			visual.play_action("Jump_Start", dur + 0.05, 0.08)
			visual.anim.speed_scale = 1.3
	elif kind == "hang":
		if visual.anim.has_animation("MClimb_Reach") and is_on_floor():

			visual.play_action("MClimb_Reach", pre + 0.05, 0.1)
			visual.anim.speed_scale = visual.anim.get_animation("MClimb_Reach").length / maxf(pre, 0.1)
		else:
			visual.play_action("Jump_Start", pre + 0.05, 0.08)
	else:
		visual.play_action("ClimbUp_1m_RM", dur + 0.1, 0.1)
		visual.anim.speed_scale = 0.667 / dur
		_climb["anim2"] = true
	_play_step(-10.0)
	return true

func _climb_curve(u: float) -> Vector2:

	var up:= smoothstep(0.0, 0.62, u)
	var fw:= smoothstep(0.45, 1.0, u)
	var curve: PackedVector3Array = AnimLib.root_curves.get("ClimbUp_1m_RM", PackedVector3Array())
	if curve.size() > 2:
		var i:= u * (curve.size() - 1)
		var a:= curve[int(floor(i))]
		var b:= curve[mini(int(floor(i)) + 1, curve.size() - 1)]
		var p:= a.lerp(b, i - floor(i))
		var e:= curve[curve.size() - 1]
		if absf(e.z) > 0.01:
			up = clampf(p.z / e.z, 0.0, 1.0)
		if absf(e.y) > 0.01:
			fw = clampf(p.y / e.y, 0.0, 1.0)
	return Vector2(up, fw)

func _update_climb(delta: float) -> void:
	_climb["t"] += delta
	var t: float = _climb["t"]
	var kind: String = _climb["kind"]
	var from: Vector3 = _climb["from"]
	var start: Vector3 = _climb["start"]
	var land: Vector3 = _climb["land"]
	var dur: float = _climb["dur"]
	var pre: float = _climb["pre"]
	var done:= false
	if kind == "step":
		var u:= clampf(t / dur, 0.0, 1.0)
		var curve: PackedVector3Array = _climb.get("curve", PackedVector3Array())
		if curve.size() > 2:

			var fi:= u * (curve.size() - 1)
			var a:= curve[int(floor(fi))]
			var bq:= curve[mini(int(floor(fi)) + 1, curve.size() - 1)]
			var c:= a.lerp(bq, fi - floor(fi))
			var e:= curve[curve.size() - 1]
			var upk:= clampf(c.y / maxf(e.y, 0.05), -0.3, 1.25)
			var fwk:= clampf(c.z / maxf(e.z, 0.05), 0.0, 1.0)
			var base:= from.lerp(start, smoothstep(0.0, 0.25, u))
			var hz:= Vector3(land.x - base.x, 0, land.z - base.z) * fwk
			global_position = base + Vector3(0, (land.y - from.y) * upk, 0) + hz
		else:
			var base:= from.lerp(start, smoothstep(0.0, 0.3, u))
			var up:= smoothstep(0.05, 0.6, u) + 0.18 * sin(PI * clampf(u * 1.25, 0.0, 1.0))
			var hz:= Vector3(land.x - base.x, 0, land.z - base.z) * smoothstep(0.3, 1.0, u)
			global_position = base + Vector3(0, (land.y - from.y) * minf(up, 1.12), 0) + hz
			if u > 0.72 and visual.current != "Jump_Land":
				visual.play_action("Jump_Land", 0.3, 0.08)
		done = u >= 1.0
	else:
		var lift:= maxf((land.y - from.y) - CLIMB_CLIP_H, 0.0) if kind == "hang" else 0.0
		if t < pre:

			var u0:= t / pre
			var p0:= from.lerp(start, smoothstep(0.0, 1.0, u0))
			global_position = p0 + Vector3(0, lift * (1.0 - (1.0 - u0) * (1.0 - u0)), 0)
		else:
			if not _climb["anim2"]:
				_climb["anim2"] = true
				visual.play_action("ClimbUp_1m_RM", dur + 0.1, 0.06)
				visual.anim.speed_scale = 0.667 / dur
			var u:= clampf((t - pre) / dur, 0.0, 1.0)
			var c:= _climb_curve(u)
			var base:= (from.lerp(start, smoothstep(0.0, 0.15, u)) if kind == "climb" else start) + Vector3(0, lift, 0)
			var rise:= (land.y - from.y) - lift
			var hz:= Vector3(land.x - base.x, 0, land.z - base.z) * c.y
			global_position = base + Vector3(0, rise * c.x, 0) + hz
			done = u >= 1.0
	if done:
		global_position = land + Vector3(0, 0.02, 0)
		climbing = false
		visual.action_lock = 0.0
		visual.anim.speed_scale = 1.0
		_play_step(-6.0)
		_was_on_floor = true

func _try_step(motion: Vector3) -> void:
	var m:= Vector3(motion.x, 0, motion.z)
	if m.length() < 0.001:
		return
	m = m.normalized() * maxf(m.length(), 0.07)
	var t:= global_transform
	var up:= Vector3.UP * (STEP + 0.02)
	if test_move(t, up):
		return
	var t2:= t.translated(up)
	if test_move(t2, m):
		return
	t2 = t2.translated(m)
	var col:= KinematicCollision3D.new()
	if not test_move(t2, -up, col):
		return
	if col.get_normal().y < 0.72:
		return
	var land:= t2.origin + col.get_travel()
	var dy:= land.y - t.origin.y
	if dy < 0.015 or dy > STEP + 0.01:
		return
	global_position = land + Vector3(0, 0.002, 0)
	velocity.y = 0.0
	visual.position.y = clampf(visual.position.y - dy, -STEP, 0.0)

func _process(delta: float) -> void:
	Prof.b("player_proc")
	_mouse_compat()
	if _feet == null and visual.skeleton:
		_feet = FootPlant.new()
		_feet.setup(visual.skeleton, self)
	if _feet and _feet.ready:
		var n:= _feet.update(delta)
		var hs:= Vector2(velocity.x, velocity.z).length()
		if n > 0 and is_on_floor() and not climbing and hs > 0.35 and visual.current != "Idle_Loop":
			_play_step(0.0)
	_mouse_turn_t += delta
	_auto_camera(delta)
	_smooth_look(delta)

	var target_blend:= 1.0 if cam_mode == "fp" else 0.0
	_cam_blend = move_toward(_cam_blend, target_blend, delta * 4.0)
	var b:= smoothstep(0.0, 1.0, _cam_blend)
	var crouch_h:= 0.5 if crouching else 0.0
	var head_h:= lerpf(1.55, EYE_H, b) - crouch_h
	if _collapse_t > 0.0:
		head_h = lerpf(head_h, 0.5, clampf(_collapse_t, 0.0, 1.0))

	var body:= get_global_transform_interpolated().origin
	var anchor:= body + Vector3(0, head_h, 0)
	if b > 0.5:
		var fwd:= Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.12)
		anchor += fwd
	if b < 0.99:
		var k:= 1.0 - exp(-delta * 16.0)
		_anchor = Vector3(lerpf(_anchor.x, anchor.x, 1.0 - exp(-delta * 30.0)), lerpf(_anchor.y, anchor.y, k), lerpf(_anchor.z, anchor.z, 1.0 - exp(-delta * 30.0)))
		if _anchor.distance_to(anchor) > 3.0:
			_anchor = anchor
	else:
		_anchor = anchor
	cam_yaw_node.global_position = _anchor
	cam_yaw_node.rotation = Vector3(0, yaw, 0)
	var shake:= _shake + strain * strain * 0.02
	var t:= Time.get_ticks_msec() * 0.001
	var tremor:= Vector3(sin(t * 31.0) * sin(t * 7.0), sin(t * 27.0 + 1.3) * sin(t * 5.3), 0) * shake
	cam_pitch_node.rotation = Vector3(pitch + tremor.y, tremor.x, 0)
	spring.spring_length = lerpf(2.5, 0.0, b)

	var off:= Vector3(lerpf(0.42, 0.0, b), lerpf(0.05, 0.0, b), 0)
	if b > 0.5 and Settings.c["head_bob"]:
		off.y += sin(_bob * 3.0) * 0.035 * clampf(velocity.length() / 3.0, 0.0, 1.0)
		off.x += cos(_bob * 1.5) * 0.02 * clampf(velocity.length() / 3.0, 0.0, 1.0)
	spring.position = off

	var hide_head:= b > 0.5 or spring.get_hit_length() < 0.6
	camera.cull_mask = (1048575 & ~2) if hide_head else 1048575
	camera.fov = lerpf(Settings.c["fov"], Settings.c["fov"] - 8.0, clampf(strain - 0.5, 0.0, 0.5) * 2.0) + charge * 6.0
	_shake = maxf(_shake - delta * 1.5, 0.0)

	Prof.e("player_proc")

func _update_interact() -> void:
	var best:= {}
	var best_d:= 999.0
	var fwd:= -camera.global_basis.z
	for it in interactables:
		var p: Vector3 = it["pos"]
		var d:= global_position.distance_to(Vector3(p.x, global_position.y, p.z))
		if d > float(it["r"]):
			continue
		var to:= (p - camera.global_position).normalized()
		if fwd.dot(to) < 0.35 and d > 1.2:
			continue
		if d < best_d:
			best_d = d
			best = it
	if best.get("id", "") != interact_target.get("id", ""):
		interact_target = best
		interact_changed.emit(best)

func _update_power(delta: float) -> void:
	if controls_locked or _collapse_t > 0.0:
		if charging:
			_cancel_charge()
		return
	if Input.is_action_pressed("power"):
		if not charging:
			charging = true
			charge = 0.0
			_ensure_power_pose()
			charge_player.pitch_scale = 1.0
			charge_player.play()
		charge = minf(charge + delta / 1.6, 1.0)
		charge_player.pitch_scale = 0.8 + charge * 0.6
		hand_light.light_energy = charge * 2.5 * (0.7 + 0.3 * randf())
		_shake = maxf(_shake, charge * 0.012)
	elif charging:
		charging = false
		charge_player.stop()
		hand_light.light_energy = 0.0
		if charge > 0.2:
			_release_pulse(charge)
		charge = 0.0

var _pose_l: ArmPoseModifier = null
var _pose_r: ArmPoseModifier = null

func _ensure_power_pose() -> void:
	if _pose_l != null or visual.skeleton == null:
		return
	_pose_l = ArmPoseModifier.new()
	_pose_r = ArmPoseModifier.new()
	visual.skeleton.add_child(_pose_l)
	visual.skeleton.add_child(_pose_r)
	_pose_l.capture(visual, "Spell_Simple_Idle_Loop", 0.3, "l")
	_pose_r.capture(visual, "Spell_Simple_Idle_Loop", 0.3, "r")
	_pose_l.influence = 0.0
	_pose_r.influence = 0.0

func _update_power_pose(delta: float) -> void:
	if _pose_l == null:
		return
	var target:= 1.0 if charging else 0.0
	var k:= clampf(delta * (7.0 if charging else 4.0), 0.0, 1.0)
	_pose_l.influence = lerpf(_pose_l.influence, target, k)
	_pose_r.influence = _pose_l.influence
	_pose_l.active = _pose_l.influence > 0.01
	_pose_r.active = _pose_l.active

func _cancel_charge() -> void:
	charging = false
	charge = 0.0
	charge_player.stop()
	hand_light.light_energy = 0.0

func _release_pulse(c: float) -> void:
	var radius:= 6.0 + 16.0 * c
	if city:
		city.emp(global_position, radius)
	visual.play_action("Spell_Simple_Shoot", 0.7)
	_sfx("emp_release", -2.0)
	_shake = 0.05 + c * 0.05
	strain = minf(strain + 0.16 + 0.3 * c, 1.0)
	_strain_idle = 0.0
	strain_changed.emit(strain)
	power_used.emit(not _power_used_once)
	_power_used_once = true
	if strain >= 0.999:
		_collapse()

func _collapse() -> void:
	_collapse_t = 1.0
	visual.play_action("Death01", 3.2, 0.3)
	_sfx("heartbeat", 0.0)
	collapsed.emit()
	await get_tree().create_timer(3.4).timeout
	_collapse_t = 0.0
	strain = 0.62
	visual.play_action("Crouch_Idle_Loop", 1.2, 0.6)

func _update_strain(delta: float) -> void:
	_strain_idle += delta
	if _strain_idle > 2.5 and strain > 0.0 and not charging:
		strain = maxf(strain - delta * 0.045, 0.0)
		strain_changed.emit(strain)
	if charging:
		strain = minf(strain + delta * 0.03, 1.0)
		strain_changed.emit(strain)
	var hb:= clampf((strain - 0.45) / 0.4, 0.0, 1.0)
	heart_player.volume_db = linear_to_db(maxf(hb * 0.9, 0.0001))
	if hb > 0.0 and not heart_player.playing:
		heart_player.play()
	elif hb <= 0.0 and heart_player.playing:
		heart_player.stop()
	heart_player.pitch_scale = 1.0 + hb * 0.5
	var rv:= clampf((strain - 0.7) / 0.3, 0.0, 1.0)
	ring_player.volume_db = linear_to_db(maxf(rv * 0.35, 0.0001))
	if rv > 0.0 and not ring_player.playing:
		ring_player.play()
	elif rv <= 0.0 and ring_player.playing:
		ring_player.stop()

func _play_step(vol: float, name:= "") -> void:
	step_player.position = Vector3(0, 0.1, 0)
	if name == "land":

		var surf:= "concrete"
		if Game.world and Game.world.get("city"):
			surf = Game.world.city.surface_at(global_position)
		Footsteps.land(step_player, step_layer, surf, vol)
		return
	var surface:= "concrete"
	if Game.world and Game.world.get("city"):
		surface = Game.world.city.surface_at(global_position)
	var hs:= Vector2(velocity.x, velocity.z).length()
	Footsteps.step(step_player, step_layer, surface, hs > 3.2, crouching, 1.0, clampf(hs / RUN, 0.0, 1.0))

func _sfx(name: String, vol: float) -> void:
	var p:= AudioStreamPlayer.new()
	p.stream = load("res://assets/audio/%s.wav" % name)
	p.volume_db = vol
	p.bus = "SFX"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
