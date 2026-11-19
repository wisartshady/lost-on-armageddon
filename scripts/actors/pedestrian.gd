class_name Pedestrian
extends Node3D

var visual: CharacterVisual
var path: PackedVector3Array
var idx:= 0
var speed:= 1.3
var umbrella: Node3D
var arm: ArmPoseModifier
var step_main: AudioStreamPlayer3D
var step_wet: AudioStreamPlayer3D
var _step_t:= 0.0
var _feet: FootPlant

var _u_state:= 0
var _u_t:= 0.0
var _u_open:= 0.0
var _u_open_v:= 0.0
var _u_axis:= Vector3.UP
var _u_axis_v:= Vector3.ZERO
var _u_prev_hand:= Vector3.ZERO
var _u_prev_vel:= Vector3.ZERO
var _u_thresh:= 0.12
var _u_delay:= 0.0
var _gust:= randf() * 100.0

func setup(profile: String, waypoints: Array, start: int, coat: Color, umbrella_col: Color) -> void:
	visual = CharacterVisual.new()
	add_child(visual)
	visual.setup(profile, {"top": coat})
	path = PackedVector3Array()
	for w in waypoints:
		path.append(Vector3(w[0], w[1], w[2]))
	idx = start % path.size()
	var a:= path[idx]
	var b:= path[(idx + 1) % path.size()]
	global_position = a.lerp(b, randf())
	idx = (idx + 1) % path.size()
	speed = randf_range(1.15, 1.45)
	visual.play("Walk_Loop", 0.0, speed / 1.45)
	var scn: PackedScene = load("res://assets/models/props/umbrella.scn")
	umbrella = scn.instantiate()
	for mi in _meshes(umbrella):
		for s in mi.mesh.get_surface_count():
			var m:= ShaderMaterial.new()
			m.shader = preload("res://shaders/character.gdshader")
			m.set_shader_parameter("use_albedo", false)
			m.set_shader_parameter("use_normal", false)
			var src:= mi.mesh.surface_get_material(s)
			var col:= umbrella_col if src and src.resource_name == "canopy" else Color(0.1, 0.1, 0.1)
			m.set_shader_parameter("color", col)
			m.set_shader_parameter("roughness_v", 0.35)
			m.set_shader_parameter("specular_v", 0.6)
			mi.set_surface_override_material(s, m)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(umbrella)
	umbrella.top_level = true

	arm = ArmPoseModifier.new()
	visual.skeleton.add_child(arm)
	arm.capture(visual, "Idle_Torch_Loop", 0.4, "l")
	arm.held = umbrella
	arm.held_offset = Vector3(0.0, -0.05, 0.0)
	_u_thresh = randf_range(0.08, 0.2)
	var raining:= WeatherSim.current != null and WeatherSim.current.rain > _u_thresh
	_u_state = 3 if raining else 0
	_u_open = 1.0 if raining else 0.0
	arm.influence = 1.0 if raining else 0.0
	umbrella.visible = raining
	for k in 2:
		var ap:= AudioStreamPlayer3D.new()
		ap.bus = "SFX"
		ap.max_distance = 16.0
		ap.unit_size = 3.0
		add_child(ap)
		ap.position = Vector3(0, 0.1, 0)
		if k == 0:
			step_main = ap
		else:
			step_wet = ap
	_step_t = randf() * 0.5

	var body:= AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 8
	body.collision_mask = 0
	var cs:= CollisionShape3D.new()
	var cap:= CapsuleShape3D.new()
	cap.radius = 0.27
	cap.height = 1.72
	cs.shape = cap
	cs.position.y = 0.86
	body.add_child(cs)
	add_child(body)

func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out

func _process(delta: float) -> void:
	Prof.b("peds")
	if path.is_empty():
		Prof.e("peds")
		return
	var target:= path[idx]
	var to:= target - global_position
	to.y = 0
	if to.length() < 0.3:
		idx = (idx + 1) % path.size()
		Prof.e("peds")
		return
	var dir:= to.normalized()

	var pl: Node3D = Game.player
	var spd:= speed
	if pl:
		var rel:= pl.global_position - global_position
		rel.y = 0.0
		var d:= rel.length()
		if d < 1.6 and d > 0.01 and dir.dot(rel / d) > 0.2:
			var side:= Vector3(-dir.z, 0, dir.x)
			if side.dot(rel) > 0.0:
				side = -side
			dir = (dir + side * (1.6 - d) * 1.4).normalized()
			if d < 0.75:
				spd *= 0.4
		if d < 12.0 and visual.hitboxes.is_empty():
			visual.build_hitboxes(self)
	global_position += dir * spd * delta
	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-dir.x, -dir.z), clampf(5.0 * delta, 0.0, 1.0))
	arm.sway = sin(Time.get_ticks_msec() * 0.003 + speed * 10.0) * 0.04

	var cam:= get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(global_position) < 14.0:
		if _feet == null:
			_feet = FootPlant.new()
			_feet.setup(visual.skeleton, self)
		if _feet.update(delta) > 0:
			var surf:= "concrete"
			if Game.world and Game.world.get("city"):
				surf = Game.world.city.surface_at(global_position)
			Footsteps.step(step_main, step_wet, surf, false, true, 1.0)
	Prof.e("peds")

func _update_umbrella(delta: float, vel: Vector3) -> void:
	var W:= WeatherSim.current
	var rain:= W.rain if W else 0.0
	_u_t += delta
	match _u_state:
		0:
			if rain > _u_thresh:
				_u_delay -= delta
				if _u_delay <= 0.0:
					_u_state = 1; _u_t = 0.0
			else:
				_u_delay = randf_range(0.5, 6.0)
		1:
			arm.influence = smoothstep(0.0, 0.55, _u_t)
			umbrella.visible = _u_t > 0.3
			if _u_t > 0.55:
				_u_state = 2; _u_t = 0.0; _u_open_v = 0.0
		2, 3:
			_u_open_v += ((1.0 - _u_open) * 90.0 - _u_open_v * 9.0) * delta
			_u_open = clampf(_u_open + _u_open_v * delta, 0.0, 1.08)
			if _u_state == 2 and _u_t > 1.2:
				_u_state = 3
			if rain < _u_thresh - 0.05:
				_u_delay -= delta
				if _u_delay <= -randf_range(1.0, 4.0):
					_u_state = 4; _u_t = 0.0
			else:
				_u_delay = 0.0
		4:
			_u_open = move_toward(_u_open, 0.0, delta * 1.6)
			if _u_open <= 0.0:
				_u_state = 5; _u_t = 0.0
		5:
			arm.influence = 1.0 - smoothstep(0.0, 0.5, _u_t)
			umbrella.visible = _u_t < 0.15
			if _u_t > 0.5:
				_u_state = 0; _u_delay = randf_range(0.5, 6.0)
	if not umbrella.visible:
		return

	var target:= Vector3.UP
	if W and _u_state in [2, 3]:
		var rel:= W.rain_velocity() - vel
		target = (-rel).normalized()
		var lim:= deg_to_rad(24.0)
		var ang:= target.angle_to(Vector3.UP)
		if ang > lim:
			target = Vector3.UP.slerp(target, lim / ang)

	var hand:= umbrella.global_position
	var hv:= (hand - _u_prev_hand) / maxf(delta, 0.001)
	if _u_prev_hand == Vector3.ZERO:
		hv = Vector3.ZERO
	var acc:= (hv - _u_prev_vel) / maxf(delta, 0.001)
	_u_prev_hand = hand
	_u_prev_vel = hv
	_gust += delta * (0.6 + (W.wind if W else 0.3))
	var gust:= Vector3(sin(_gust * 1.7) + sin(_gust * 3.1) * 0.5, 0.0, cos(_gust * 1.3) + sin(_gust * 2.3) * 0.4) * (0.6 + (W.wind if W else 0.0) * 1.8)
	var force:= (target - _u_axis) * 38.0 - _u_axis_v * 7.5 - acc.limit_length(12.0) * 0.06 + gust * 0.5 * _u_open
	_u_axis_v += force * delta
	_u_axis = (_u_axis + _u_axis_v * delta).normalized()
	if _u_axis.y < 0.8:
		_u_axis = Vector3(_u_axis.x, 0.8, _u_axis.z).normalized()
	var axis:= Vector3.UP.cross(_u_axis)
	arm.held_tilt = Basis(axis.normalized(), Vector3.UP.angle_to(_u_axis)) if axis.length() > 0.0001 else Basis.IDENTITY

	var o:= clampf(_u_open, 0.0, 1.1)
	arm.held_scale = Vector3(lerpf(0.11, 1.0, o), lerpf(1.06, 1.0, minf(o, 1.0)), lerpf(0.11, 1.0, o))
	arm.sway = sin(Time.get_ticks_msec() * 0.003 + speed * 10.0) * 0.03
