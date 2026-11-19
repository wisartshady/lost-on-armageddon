class_name EdgeScenes
extends Node3D

const NEAR:= 115.0
const FAR:= 150.0

var city: Node
var sites: Array = []
var built:= {}
var queue: Array = []
var _t:= 0.0
var _flicker: Array = []
static var _mats:= {}
static var _tape_uv: Array = []

func setup(c: Node) -> void:
	city = c
	sites = c.layout.get("edge_scenes", [])

	for p in ["cop_m", "cop_f", "firefighter", "csi"]:
		load("res://assets/models/characters/%s.scn" % p)

func _process(delta: float) -> void:
	if not queue.is_empty():
		var job: Array = queue.pop_front()
		if is_instance_valid(job[0]):
			job[1].call()
	var tt:= Time.get_ticks_msec() * 0.001
	for f in _flicker:
		if is_instance_valid(f[0]):
			f[0].light_energy = f[1] * (0.75 + 0.18 * sin(tt * 13.0) + 0.12 * sin(tt * 31.0 + 1.3))
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var cam:= get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp:= cam.global_position
	for i in sites.size():
		var s: Dictionary = sites[i]
		var d:= Vector2(cp.x - float(s["p"][0]), cp.z - float(s["p"][2])).length()
		if d < NEAR and not built.has(i):
			_build(i)
		elif d > FAR and built.has(i):
			built[i].queue_free()
			built.erase(i)

func _at(s: Dictionary, o: float, l: float, y:= 0.0) -> Vector3:
	return Vector3(float(s["p"][0]) + float(s["out"][0]) * o + float(s["side"][0]) * l, y,
		float(s["p"][2]) + float(s["out"][1]) * o + float(s["side"][1]) * l)

func _out(s: Dictionary) -> Vector3:
	return Vector3(float(s["out"][0]), 0, float(s["out"][1]))

func _side(s: Dictionary) -> Vector3:
	return Vector3(float(s["side"][0]), 0, float(s["side"][1]))

static func _face(d: Vector3) -> float:
	return atan2(-d.x, -d.z)

static func _mat(key: String, col: Color, emit:= 0.0, rough:= 0.6) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m:= StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m

func _job(root: Node, f: Callable) -> void:
	queue.append([root, f])

func _car(root: Node3D, model: String, pos: Vector3, facing: Vector3, paint: Color, siren:= true, open_window:= false) -> MeshInstance3D:
	var xf:= Transform3D(Basis(Vector3.UP, _face(facing)), pos)
	var mi:= VehicleLib.spawn(root, model, xf, paint, 0.25)
	VehicleLib.set_param(mi, "siren", 1.0 if siren else 0.0)
	VehicleLib.set_param(mi, "lights_on", 0.0)
	if open_window:
		var m:= VehicleLib.material().duplicate() as ShaderMaterial
		m.shader = load("res://shaders/vehicle_open.gdshader")
		mi.material_override = m
		var near:= mi.get_node_or_null("Near") as GeometryInstance3D
		if near:
			near.set_instance_shader_parameter("window_open", 1.0)
	return mi

func _person(root: Node3D, profile: String, pos: Vector3, facing: Vector3, anim: String, lean:= 0.0, over:= {}) -> CharacterVisual:
	var c:= CharacterVisual.new()
	root.add_child(c)
	c.setup(profile, over)
	c.global_position = pos
	c.rotation.y = _face(facing)
	if lean != 0.0:
		c.rotation.x = lean
	c.play(anim, 0.0, randf_range(0.9, 1.1))
	c.anim.seek(randf() * 3.0, true)
	return c

func _attach(c: CharacterVisual, bone: String, node: Node3D, offset: Vector3, rot:= Vector3.ZERO) -> void:
	var ba:= BoneAttachment3D.new()
	ba.bone_name = bone
	c.skeleton.add_child(ba)
	ba.add_child(node)
	node.position = offset
	node.rotation = rot

func _mesh(m: Mesh, mat: Material) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _cup() -> Node3D:
	var n:= Node3D.new()
	var c:= CylinderMesh.new()
	c.top_radius = 0.04; c.bottom_radius = 0.032; c.height = 0.12; c.radial_segments = 10
	n.add_child(_mesh(c, _mat("cup", Color(0.92, 0.9, 0.86))))
	var l:= CylinderMesh.new()
	l.top_radius = 0.036; l.bottom_radius = 0.042; l.height = 0.016; l.radial_segments = 10
	var lid:= _mesh(l, _mat("lid", Color(0.08, 0.06, 0.05)))
	lid.position.y = 0.066
	n.add_child(lid)
	var s:= CylinderMesh.new()
	s.top_radius = 0.0405; s.bottom_radius = 0.037; s.height = 0.04; s.radial_segments = 10
	n.add_child(_mesh(s, _mat("sleeve", Color(0.45, 0.3, 0.17))))
	return n

func _radio() -> Node3D:
	var n:= Node3D.new()
	var b:= BoxMesh.new()
	b.size = Vector3(0.055, 0.13, 0.035)
	n.add_child(_mesh(b, _mat("radio", Color(0.03, 0.03, 0.03), 0.0, 0.4)))
	var a:= CylinderMesh.new()
	a.top_radius = 0.006; a.bottom_radius = 0.008; a.height = 0.09; a.radial_segments = 6
	var an:= _mesh(a, _mat("radio", Color(0.03, 0.03, 0.03), 0.0, 0.4))
	an.position = Vector3(0.015, 0.11, 0)
	n.add_child(an)
	var led:= BoxMesh.new()
	led.size = Vector3(0.01, 0.01, 0.005)
	var le:= _mesh(led, _mat("led", Color(0.2, 1.0, 0.3), 3.0))
	le.position = Vector3(-0.015, 0.06, 0.019)
	n.add_child(le)
	return n

func _tube(points: PackedVector3Array, r: float, mat: Material, seg:= 6) -> MeshInstance3D:
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings:= []
	for k in points.size():
		var t:= (points[mini(k + 1, points.size() - 1)] - points[maxi(k - 1, 0)]).normalized()
		var a:= t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT).normalized()
		var b:= t.cross(a)
		var ring:= []
		for i in seg + 1:
			var th:= TAU * i / seg
			var n:= a * cos(th) + b * sin(th)
			ring.append([points[k] + n * r, n])
		rings.append(ring)
	for k in points.size() - 1:
		for i in seg:
			var q:= [rings[k][i], rings[k + 1][i], rings[k + 1][i + 1], rings[k][i + 1]]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_normal(q[idx][1])
				st.add_vertex(q[idx][0])
	return _mesh(st.commit(), mat)

func _tape(root: Node3D, pts: PackedVector3Array, strip: int) -> void:

	if _tape_uv.is_empty():
		var g:= JSON.parse_string(FileAccess.get_file_as_string("res://data/atlas_graffiti.json")) as Dictionary
		_tape_uv = g.get("tape", {}).get("uv", [0, 0.8, 0.25, 1.0])
	var uv: Array = _tape_uv
	var v0:= float(uv[1]) + (float(uv[3]) - float(uv[1])) * (strip * 0.25 + 0.02)
	var v1:= float(uv[1]) + (float(uv[3]) - float(uv[1])) * (strip * 0.25 + 0.23)
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in pts.size() - 1:
		var a:= pts[k]
		var b:= pts[k + 1]
		var L:= a.distance_to(b)
		var n:= int(ceil(L / 1.6))
		for j in n:
			var p0:= a.lerp(b, float(j) / n)
			var p1:= a.lerp(b, float(j + 1) / n)
			var sag0:= sin(PI * float(j) / n) * 0.06 * L / 4.0
			var sag1:= sin(PI * float(j + 1) / n) * 0.06 * L / 4.0
			p0.y -= sag0; p1.y -= sag1
			var u1:= float(uv[0]) + (float(uv[2]) - float(uv[0])) * clampf(p0.distance_to(p1) / 2.0, 0.1, 1.0)
			var h:= Vector3(0, 0.07, 0)
			var nrm:= (p1 - p0).cross(Vector3.UP).normalized()
			for face in [1.0, -1.0]:
				var quad:= [[p0, Vector2(float(uv[0]), v1)], [p1, Vector2(u1, v1)], [p1 + h, Vector2(u1, v0)], [p0 + h, Vector2(float(uv[0]), v0)]]
				var order:= [0, 1, 2, 0, 2, 3] if face > 0 else [0, 2, 1, 0, 3, 2]
				for i in order:
					st.set_normal(nrm * face)
					st.set_uv(quad[i][1])
					st.set_color(Color(1, 1, 1, 1))
					st.add_vertex(quad[i][0])
	var mi:= _mesh(st.commit(), Mats.get_mat("graffiti"))
	root.add_child(mi)

func _post(root: Node3D, p: Vector3) -> void:
	var c:= CylinderMesh.new()
	c.top_radius = 0.025; c.bottom_radius = 0.03; c.height = 1.1; c.radial_segments = 6
	var m:= _mesh(c, _mat("post", Color(0.85, 0.5, 0.1)))
	m.position = p + Vector3(0, 0.55, 0)
	root.add_child(m)
	var b:= CylinderMesh.new()
	b.top_radius = 0.12; b.bottom_radius = 0.14; b.height = 0.05; b.radial_segments = 8
	var bm:= _mesh(b, _mat("postbase", Color(0.1, 0.1, 0.1)))
	bm.position = p + Vector3(0, 0.025, 0)
	root.add_child(bm)

func _particles(tex: String, shader: String, amount: int) -> CPUParticles3D:
	return city._make_particles(tex, shader, amount)

func _build(i: int) -> void:
	var s: Dictionary = sites[i]
	var root:= Node3D.new()
	root.name = "Edge%d" % i
	add_child(root)
	built[i] = root
	match str(s["kind"]):
		"patrol":
			_patrol(root, s, i)
		"crime":
			_crime(root, s, i)
		"fire":
			_fire(root, s, i)

func _patrol(root: Node3D, s: Dictionary, i: int) -> void:
	var out:= _out(s)
	var side:= _side(s)
	var road:= float(s["road"])
	var black:= Color(0.02, 0.02, 0.03, 0.3)

	var c1p:= _at(s, 5.2, -road * 0.42)
	var c2p:= _at(s, 5.8, road * 0.42)

	var f1:= Vector3.UP.cross(out)
	_job(root, func (): _car(root, "police", c1p, f1, black, true, true))
	_job(root, func (): _car(root, "police_suv" if i % 2 == 0 else "police", c2p, -f1 if i % 3 else f1, black))
	var cops:= ["cop_m", "cop_m2", "cop_f"]
	var n:= 2 + i % 3

	_job(root, func ():
		var c:= _person(root, cops[i % 3], _at(s, 3.3, -road * 0.42 - 2.4), -out + side * 0.3, "Idle_Torch_Loop")
		_attach(c, "hand_l", _cup(), Vector3(0.0, 0.08, 0.03)))

	_job(root, func ():
		var c:= _person(root, cops[(i + 1) % 3], _at(s, 1.6, 0.0), side, "Walk_Loop")
		var w:= Pacer.new()
		w.visual = c; w.a = _at(s, 1.6, -road * 0.55); w.b = _at(s, 1.6, road * 0.55)
		root.add_child(w)
		var arm:= ArmPoseModifier.new()
		c.skeleton.add_child(arm)
		arm.capture(c, "Idle_TalkingPhone_Loop", 0.6, "r")
		var r:= _radio()
		root.add_child(r)
		r.top_level = true
		arm.held = r
		arm.held_offset = Vector3(0.0, 0.02, 0.0))
	if n >= 3:

		_job(root, func ():
			var p:= c2p - out * (1.0 * VehicleLib.SCALE + 0.32)
			_person(root, cops[(i + 2) % 3], p, -out, "Idle_FoldArms_Loop", 0.1))
	if n >= 4 or i % 2 == 1:

		_job(root, func ():
			var f:= f1
			var lat:= f.cross(Vector3.UP)

			var seat:= c1p + lat * (-0.38 * VehicleLib.SCALE) + f * 0.22 + Vector3(0, 0.0, 0)
			_person(root, "cop_f", seat, f, "Driving_Loop", 0.0, {"height": 1.52}))

func _crime(root: Node3D, s: Dictionary, i: int) -> void:
	var out:= _out(s)
	var side:= _side(s)
	var road:= float(s["road"])
	var black:= Color(0.02, 0.02, 0.03, 0.3)
	var f:= Vector3.UP.cross(out)
	_job(root, func (): _car(root, "police", _at(s, 4.8, -road * 0.45), f, black))
	_job(root, func (): _car(root, "police_suv", _at(s, 5.4, road * 0.45), -f, black))
	_job(root, func (): _car(root, "police", _at(s, 15.5, -road * 0.6), (out + f * 0.6).normalized(), black))
	_job(root, func (): _car(root, "ambulance", _at(s, 16.5, road * 0.55), out, Color(0.92, 0.92, 0.9, 0.2)))
	_job(root, func (): _car(root, "sedan", _at(s, 21.0, -road * 0.1), (out - f * 0.3).normalized(), Color(0.12, 0.12, 0.14, 0.4), false))

	_job(root, func ():
		var pts:= PackedVector3Array()
		for q in [[6.6, -road - 0.5], [7.2, -1.5], [7.0, road + 0.5], [19.5, road + 0.8], [20.0, -road - 0.8], [6.6, -road - 0.5]]:
			var p:= _at(s, q[0], q[1], 1.0)
			pts.append(p)
			_post(root, Vector3(p.x, 0.0, p.z))
		_tape(root, pts, 1))

	var bp:= _at(s, 12.0, 0.5)
	_job(root, func ():
		var sheet:= _mat("sheet", Color(0.9, 0.9, 0.88), 0.0, 0.85)
		var lumps:= [[Vector3(0, 0.1, -0.75), Vector3(0.24, 0.2, 0.26)], [Vector3(0, 0.12, -0.25), Vector3(0.48, 0.24, 0.6)],
			[Vector3(0, 0.1, 0.3), Vector3(0.42, 0.2, 0.4)], [Vector3(-0.12, 0.07, 0.85), Vector3(0.18, 0.14, 0.8)],
			[Vector3(0.14, 0.07, 0.8), Vector3(0.18, 0.14, 0.8)], [Vector3(0, 0.03, 0.0), Vector3(0.95, 0.06, 2.3)]]
		var b:= Node3D.new()
		root.add_child(b)
		b.global_position = bp
		b.rotation.y = _face(side) + 0.4
		for L in lumps:
			var sm:= SphereMesh.new()
			sm.radius = 0.5; sm.height = 1.0; sm.radial_segments = 12; sm.rings = 6
			var m:= _mesh(sm, sheet)
			m.position = L[0]
			m.scale = L[1]
			b.add_child(m)
		var pool:= CylinderMesh.new()
		pool.top_radius = 0.55; pool.bottom_radius = 0.55; pool.height = 0.005; pool.radial_segments = 18
		var pm:= _mesh(pool, _mat("blood", Color(0.16, 0.01, 0.01), 0.0, 0.08))
		pm.position = Vector3(0.35, 0.004, -0.55)
		pm.scale = Vector3(1.0, 1.0, 0.7)
		b.add_child(pm)
		var hand:= SphereMesh.new()
		hand.radius = 0.045; hand.height = 0.09
		var hm:= _mesh(hand, _mat("skinhand", Color(0.55, 0.42, 0.36)))
		hm.position = Vector3(0.52, 0.04, -0.3)
		hm.scale = Vector3(1.0, 0.6, 1.7)
		b.add_child(hm)
		for k in 6:
			var pr:= PrismMesh.new()
			pr.size = Vector3(0.1, 0.12, 0.08)
			var mk:= _mesh(pr, _mat("marker", Color(0.95, 0.75, 0.05), 0.3))
			root.add_child(mk)
			mk.global_position = bp + Vector3(randf_range(-2.2, 2.2), 0.06, randf_range(-2.2, 2.2))
			mk.rotation.y = randf() * TAU)

	_job(root, func (): _person(root, "csi", bp + side * 1.0 + out * 0.3, -side, "Crouch_Idle_Loop"))
	_job(root, func (): _person(root, "csi", bp - side * 1.6 + out * 1.4, (side - out).normalized(), "Idle_Loop"))
	_job(root, func (): _person(root, "cop_m", _at(s, 7.8, -1.0), -out, "Idle_FoldArms_Loop"))
	_job(root, func ():
		var c:= _person(root, "cop_f", _at(s, 8.4, 2.6), -out + side * 0.4, "Idle_TalkingPhone_Loop")
		_attach(c, "hand_r", _radio(), Vector3(0.0, 0.07, 0.02)))

	for q in [[9.0, -2.0], [9.0, 2.5]]:
		var lp:= _at(s, q[0], q[1])
		_job(root, func ():
			var t:= Node3D.new()
			root.add_child(t)
			t.global_position = lp
			for k in 3:
				var a:= TAU * k / 3.0
				var leg:= _tube(PackedVector3Array([Vector3(cos(a) * 0.45, 0, sin(a) * 0.45), Vector3(0, 1.6, 0)]), 0.015, _mat("tripod", Color(0.15, 0.15, 0.15)))
				t.add_child(leg)
			var mast:= _tube(PackedVector3Array([Vector3(0, 1.6, 0), Vector3(0, 2.4, 0)]), 0.02, _mat("tripod", Color(0.15, 0.15, 0.15)))
			t.add_child(mast)
			var hb:= BoxMesh.new()
			hb.size = Vector3(0.45, 0.32, 0.12)
			var head:= _mesh(hb, _mat("flood_body", Color(0.85, 0.7, 0.1)))
			head.position = Vector3(0, 2.5, 0)
			t.add_child(head)
			var lb:= BoxMesh.new()
			lb.size = Vector3(0.4, 0.27, 0.01)
			var lens:= _mesh(lb, _mat("flood_lens", Color(1.0, 0.98, 0.92), 6.0))
			lens.position = Vector3(0, 2.5, 0.065)
			t.add_child(lens)
			t.look_at(Vector3(bp.x, lp.y, bp.z), Vector3.UP)
			t.rotate_object_local(Vector3.UP, PI))
	_job(root, func ():
		var sl:= SpotLight3D.new()
		root.add_child(sl)
		var lp:= _at(s, 9.0, 0.2, 3.2)
		sl.global_position = lp
		sl.look_at(bp, Vector3.UP)
		sl.spot_range = 16.0
		sl.spot_angle = 48.0
		sl.light_energy = 2.2
		sl.light_color = Color(0.95, 0.97, 1.0)
		sl.shadow_enabled = false)

func _fire(root: Node3D, s: Dictionary, i: int) -> void:
	var out:= _out(s)
	var side:= _side(s)
	var road:= float(s["road"])
	var face:= road + float(s["sw"])
	var f:= out.cross(Vector3.UP)
	_job(root, func (): _car(root, "police", _at(s, 4.8, -road * 0.35), f, Color(0.02, 0.02, 0.03, 0.3)))
	_job(root, func (): _car(root, "firetruck", _at(s, 11.0, -road * 0.25), (out + side * 0.25).normalized(), Color(0.6, 0.05, 0.04, 0.6)))

	var flames:= [[10.0, 4.2], [13.5, 4.4], [17.0, 7.6], [12.0, 10.8], [15.5, 11.0]]
	for q in flames:
		var fp:= _at(s, q[0], face - 0.25, q[1])
		_job(root, func ():
			var fl:= _particles("res://assets/textures/flame.png", "res://shaders/particle_add.gdshader", 26)
			fl.lifetime = 1.1
			fl.direction = Vector3.UP
			fl.spread = 18.0
			fl.initial_velocity_min = 1.0
			fl.initial_velocity_max = 2.2
			fl.gravity = Vector3(0, 1.2, 0)
			fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			fl.emission_box_extents = Vector3(0.7, 0.4, 0.7)
			fl.scale_amount_min = 1.2
			fl.scale_amount_max = 2.2
			var c2:= Curve.new()
			c2.add_point(Vector2(0, 1.0)); c2.add_point(Vector2(1, 0.3))
			fl.scale_amount_curve = c2
			var g2:= Gradient.new()
			g2.set_color(0, Color(1, 0.75, 0.35, 0.95))
			g2.set_color(g2.get_point_count() - 1, Color(1, 0.2, 0.03, 0.0))
			fl.color_ramp = g2
			root.add_child(fl)
			fl.global_position = fp
			var sm:= _particles("res://assets/textures/smoke.png", "res://shaders/particle_soft.gdshader", 16)
			sm.lifetime = 7.0
			sm.direction = Vector3.UP
			sm.spread = 14.0
			sm.initial_velocity_min = 1.4
			sm.initial_velocity_max = 2.6
			sm.gravity = Vector3(0.3, 0.5, 0.15)
			sm.scale_amount_min = 2.5
			sm.scale_amount_max = 4.5
			var c3:= Curve.new()
			c3.add_point(Vector2(0, 0.4)); c3.add_point(Vector2(1, 2.4))
			sm.scale_amount_curve = c3
			var g3:= Gradient.new()
			g3.set_color(0, Color(0.12, 0.11, 0.1, 0.0))
			g3.add_point(0.12, Color(0.14, 0.12, 0.11, 0.75))
			g3.set_color(g3.get_point_count() - 1, Color(0.2, 0.19, 0.19, 0.0))
			sm.color_ramp = g3
			root.add_child(sm)
			sm.global_position = fp + Vector3(0, 1.2, 0))
	_job(root, func ():
		var ol:= OmniLight3D.new()
		root.add_child(ol)
		ol.global_position = _at(s, 13.0, face - 2.5, 6.0)
		ol.omni_range = 24.0
		ol.light_color = Color(1.0, 0.5, 0.18)
		ol.light_energy = 2.4
		ol.shadow_enabled = false
		_flicker.append([ol, 2.4]))

	for k in 2:
		var stand:= _at(s, 9.5 + k * 4.0, face - 4.6 - k * 0.6)
		var target:= _at(s, flames[k * 2][0], face, flames[k * 2][1] + 0.5)
		_job(root, func ():
			var dir:= (target - stand)
			dir.y = 0.0
			var c:= _person(root, "firefighter", stand, dir.normalized(), "Pistol_Idle_Loop")
			var nz:= CylinderMesh.new()
			nz.top_radius = 0.03; nz.bottom_radius = 0.045; nz.height = 0.32; nz.radial_segments = 8
			_attach(c, "hand_r", _mesh(nz, _mat("nozzle", Color(0.55, 0.5, 0.42), 0.0, 0.35)), Vector3(0.0, 0.08, 0.06), Vector3(PI / 2, 0, 0))

			var w:= _particles("res://assets/textures/smoke.png", "res://shaders/particle_soft.gdshader", 70)
			var from:= stand + dir.normalized() * 0.65 + Vector3(0, 1.3, 0)
			var to:= target - from
			var t_flight:= 1.0
			var v:= (to - Vector3(0, -9.8, 0) * 0.5 * t_flight * t_flight) / t_flight
			w.direction = v.normalized()
			w.spread = 2.5
			w.initial_velocity_min = v.length() * 0.96
			w.initial_velocity_max = v.length() * 1.04
			w.gravity = Vector3(0, -9.8, 0)
			w.lifetime = t_flight * 1.05
			w.scale_amount_min = 0.12
			w.scale_amount_max = 0.3
			var c4:= Curve.new()
			c4.add_point(Vector2(0, 0.4)); c4.add_point(Vector2(1, 2.8))
			w.scale_amount_curve = c4
			var g4:= Gradient.new()
			g4.set_color(0, Color(0.85, 0.9, 1.0, 0.75))
			g4.set_color(g4.get_point_count() - 1, Color(0.85, 0.9, 1.0, 0.0))
			w.color_ramp = g4
			root.add_child(w)
			w.global_position = from

			var truck:= _at(s, 11.0, -road * 0.25)
			var hp:= PackedVector3Array()
			for j in 7:
				var t:= j / 6.0
				var p:= stand.lerp(truck, t) + side * sin(t * PI) * 1.5 * (1 if k == 0 else -1)
				p.y = 0.05 if j > 0 else 0.9
				hp.append(p)
			root.add_child(_tube(hp, 0.045, _mat("hose", Color(0.75, 0.7, 0.55)))))

	_job(root, func (): _person(root, "cop_m2", _at(s, 2.8, road * 0.3), -out, "Idle_FoldArms_Loop"))
	_job(root, func ():
		var pts:= PackedVector3Array()
		for q in [[3.6, -road - 0.5], [3.6, road + 0.5]]:
			var p:= _at(s, q[0], q[1], 1.0)
			pts.append(p)
			_post(root, Vector3(p.x, 0.0, p.z))
		_tape(root, pts, 2))

class Pacer extends Node:
	var visual: CharacterVisual
	var a: Vector3
	var b: Vector3
	var _to_b:= true
	var _pause:= 0.0

	func _process(delta: float) -> void:
		if not is_instance_valid(visual):
			return
		var target:= b if _to_b else a
		var p:= visual.global_position
		var d:= target - p
		d.y = 0.0
		if _pause > 0.0:
			_pause -= delta
			if _pause <= 0.0:
				visual.play("Walk_Loop", 0.3)
			return
		if d.length() < 0.2:
			_to_b = not _to_b
			_pause = randf_range(1.5, 4.0)
			visual.play("Idle_Loop", 0.3)
			return
		visual.global_position = p + d.normalized() * 1.1 * delta
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-d.x, -d.z), clampf(4.0 * delta, 0.0, 1.0))
