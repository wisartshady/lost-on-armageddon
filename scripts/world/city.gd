class_name City
extends Node3D

signal progress(p: float, msg: String)

const LIGHT_RANGE:= 15.0

var layout:= {}
var markers:= {}
var interactables: Array = []
var chunk_nodes: Array[MeshInstance3D] = []
var chunk_radius: Array[float] = []
var lamps: Array = []
var light_pool: Array[OmniLight3D] = []
var steam_nodes: Array[CPUParticles3D] = []
var fire_nodes: Array = []
var ambient_players: Array[AudioStreamPlayer3D] = []
var neon_points: Array[Vector3] = []
var neon_players: Array[AudioStreamPlayer3D] = []
var emp_zones: Array = []
var _light_timer:= 0.0
var _audio_timer:= 0.0
var _sfx_cache:= {}
var _time:= 0.0
var _emp_sent: Array = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]

func build() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/layout.json"))
	markers = layout["markers"]
	RenderingServer.global_shader_parameter_set("light_field_rect", Vector4(layout["light_field"]["rect"][0], layout["light_field"]["rect"][1],
			layout["light_field"]["rect"][2], layout["light_field"]["rect"][3]))
	var chunks: Array = layout["chunks"]
	var n:= chunks.size()
	for i in n:
		var c: Dictionary = chunks[i]
		var scn: PackedScene = load(c["file"])
		var inst:= scn.instantiate()
		add_child(inst)
		for mi in _meshes(inst):
			for s in mi.mesh.get_surface_count():
				var mat:= mi.mesh.surface_get_material(s)
				var mname:= mat.resource_name if mat else ""
				mi.set_surface_override_material(s, Mats.get_mat(mname))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			if not c["far"]:
				chunk_nodes.append(mi)
				chunk_radius.append(float(c.get("radius", 60.0)))
			else:
				mi.extra_cull_margin = 0.0
		if i % 6 == 0:
			progress.emit(0.1 + 0.6 * float(i) / n, "LOADING_CITY")
			await get_tree().process_frame
	_build_instanced()
	_build_vehicles()
	_build_surface_lookup()
	_build_colliders()
	progress.emit(0.8, "LOADING_CITY")
	await get_tree().process_frame
	_build_lamps()
	_build_particles()
	_build_audio()
	edge_scenes = EdgeScenes.new()
	edge_scenes.name = "EdgeScenes"
	add_child(edge_scenes)
	edge_scenes.setup(self)
	for it in layout["interact"]:
		interactables.append({"id": it["id"], "pos": _v3(it["p"]), "r": float(it["r"]), "kind": "inspect"})
	apply_settings()
	Settings.changed.connect(func (_s): apply_settings())
	progress.emit(1.0, "LOADING_CITY")

func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func marker(name: String) -> Vector3:
	return _v3(markers[name]) if markers.has(name) else Vector3.ZERO

func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for ch in n.get_children():
		out.append_array(_meshes(ch))
	return out

const PROP_CELL:= 64.0
var prop_nodes: Array[MultiMeshInstance3D] = []
var prop_range: Array[float] = []

func _build_instanced() -> void:
	for pname in layout["props"]:
		var list: Array = layout["props"][pname]
		var mesh: Mesh
		var vis_end:= 110.0
		var lit_mode:= false
		if pname.begins_with("ph_"):
			mesh = PHLib.mesh(pname)
			var sz: Array = PHLib.meta[pname]["size"]
			var big:= maxf(float(sz[0]), maxf(float(sz[1]), float(sz[2])))
			vis_end = clampf(40.0 + big * 45.0, 45.0, 170.0)
			for e in list:
				if e.size() > 4 and float(e[4]) >= 0.0:
					lit_mode = true
					break
			if lit_mode:
				for s in mesh.get_surface_count():
					var sm:= mesh.surface_get_material(s) as ShaderMaterial
					if sm:
						sm.set_shader_parameter("use_custom", true)
		else:
			var scn: PackedScene = load("res://assets/models/props/%s.scn" % pname)
			var tmp:= scn.instantiate()
			var src: MeshInstance3D = _meshes(tmp)[0]
			mesh = src.mesh
			for s in mesh.get_surface_count():
				var mat:= mesh.surface_get_material(s)
				mesh.surface_set_material(s, Mats.get_mat(mat.resource_name if mat else "lantern"))
			tmp.queue_free()

		var cells:= {}
		for e in list:
			var k:= Vector2i(floori(float(e[0]) / PROP_CELL), floori(float(e[2]) / PROP_CELL))
			if not cells.has(k):
				cells[k] = []
			cells[k].append(e)
		for k in cells:
			var items: Array = cells[k]
			var mm:= MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = lit_mode
			mm.mesh = mesh
			mm.instance_count = items.size()
			for i in items.size():
				var e: Array = items[i]
				var b:= Basis(Vector3.UP, float(e[3]))
				if e.size() >= 8:
					b = b * Basis.from_scale(Vector3(e[5], e[6], e[7]))
				mm.set_instance_transform(i, Transform3D(b, Vector3(e[0], e[1], e[2])))
				if lit_mode:
					var on:= float(e[4]) if e.size() > 4 and float(e[4]) >= 0.0 else 1.0
					var seed:= float(e[8]) if e.size() > 8 else 0.0
					mm.set_instance_custom_data(i, Color(on, seed, 0, 0))
			var mmi:= MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = vis_end
			mmi.visibility_range_end_margin = 8.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			add_child(mmi)
			prop_nodes.append(mmi)
			prop_range.append(vis_end)

var parked: Array[MeshInstance3D] = []
var edge_scenes: EdgeScenes
var _puddle_grid:= {}
var _manhole_grid:= {}

func _grid_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / 8.0), floori(z / 8.0))

func _build_surface_lookup() -> void:
	for p in layout.get("puddles", []):
		var k:= _grid_key(p[0], p[1])
		if not _puddle_grid.has(k):
			_puddle_grid[k] = []
		_puddle_grid[k].append(p)
	for m in layout.get("manholes", []):
		var k:= _grid_key(m[0], m[1])
		if not _manhole_grid.has(k):
			_manhole_grid[k] = []
		_manhole_grid[k].append(m)

func surface_at(p: Vector3) -> String:
	var k:= _grid_key(p.x, p.z)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var kk:= k + Vector2i(dx, dz)
			for pd in _puddle_grid.get(kk, []):
				if Vector2(p.x - pd[0], p.z - pd[1]).length() < float(pd[2]):
					return "water"
			for m in _manhole_grid.get(kk, []):
				if Vector2(p.x - m[0], p.z - m[1]).length() < 0.45:
					return "metal"
	if p.y > 1.8:
		return "metal"
	var pz: Array = layout.get("plaza", [0, 0, 0, 0])
	if p.x > pz[0] and p.x < pz[1] and p.z > pz[2] and p.z < pz[3]:
		return "stone"
	if p.x > 8.5 and absf(p.z - 96.0) < 14.0:
		return "stone"
	return "concrete" if p.y > 0.08 else "asphalt"

func _build_vehicles() -> void:
	VehicleLib.material()
	var shadows:= []
	for v in layout.get("vehicles", []):
		var model: String = v[0]
		var xf:= Transform3D(Basis(Vector3.UP, float(v[4])), Vector3(v[1], v[2], v[3]))
		var mi:= VehicleLib.spawn(self, model, xf, Color(v[5], v[6], v[7], v[8]), float(v[9]))
		parked.append(mi)
		var m: Dictionary = VehicleLib.meta.get(model, {"length": 4.6, "width": 1.9})
		shadows.append([xf, Vector2(float(m["width"]) * VehicleLib.SCALE + 0.45, float(m["length"]) * VehicleLib.SCALE + 0.55)])
	if not shadows.is_empty():
		VehicleLib.shadows(self, shadows)

func _build_colliders() -> void:
	var body:= StaticBody3D.new()
	body.name = "CityColliders"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for b in layout["colliders"]:
		var cs:= CollisionShape3D.new()
		var sh:= BoxShape3D.new()
		sh.size = Vector3(maxf(b[3], 0.05), maxf(b[4], 0.05), maxf(b[5], 0.05))
		cs.shape = sh
		cs.transform = Transform3D(Basis(Vector3.UP, float(b[6])), Vector3(b[0], b[1], b[2]))
		body.add_child(cs)
	_build_hulls(body)

var _hull_db:= {}
var _hull_cache:= {}

func hull_shapes(model: String, sc:= Vector3.ONE) -> Array:
	if _hull_db.is_empty():
		var f:= FileAccess.open("res://data/hulls.json", FileAccess.READ)
		if f:
			_hull_db = JSON.parse_string(f.get_as_text())
	var key:= "%s|%.3f|%.3f|%.3f" % [model, sc.x, sc.y, sc.z]
	if _hull_cache.has(key):
		return _hull_cache[key]
	var arr:= []
	for h in _hull_db.get(model, []):
		var pts:= PackedVector3Array()
		for q in h:
			pts.append(Vector3(float(q[0]) * sc.x, float(q[1]) * sc.y, float(q[2]) * sc.z))
		var shp:= ConvexPolygonShape3D.new()
		shp.points = pts
		shp.margin = 0.01
		arr.append(shp)
	_hull_cache[key] = arr
	return arr

func _build_hulls(body: StaticBody3D) -> void:
	for e in layout.get("hulls", []):
		var sc:= Vector3.ONE
		if e.size() >= 8:
			sc = Vector3(e[5], e[6], e[7])
		var xf:= Transform3D(Basis(Vector3.UP, float(e[4])), Vector3(e[1], e[2], e[3]))
		var owner_id:= body.create_shape_owner(body)
		body.shape_owner_set_transform(owner_id, xf)
		for shp in hull_shapes(String(e[0]), sc):
			body.shape_owner_add_shape(owner_id, shp)

func _build_lamps() -> void:
	for l in layout["lamps"]:
		lamps.append({"p": _v3(l["p"]), "c": Color(l["c"][0], l["c"][1], l["c"][2]), "e": float(l["e"]),
				"broken": bool(l["broken"]), "flicker": bool(l["flicker"]), "seed": randf() * 100.0})
	for i in 16:
		var o:= OmniLight3D.new()
		o.omni_range = LIGHT_RANGE
		o.omni_attenuation = 1.4
		o.light_energy = 0.0
		o.light_specular = 1.0
		o.shadow_enabled = false
		o.light_volumetric_fog_energy = 1.5
		o.visible = false
		add_child(o)
		light_pool.append(o)
	for p in layout["neons"]:
		neon_points.append(_v3(p))
	_build_atmos()

func _build_atmos() -> void:
	var halos: Array = layout.get("halos", [])
	if not halos.is_empty():
		var q:= QuadMesh.new()
		q.size = Vector2(1, 1)
		var hm:= ShaderMaterial.new()
		hm.shader = load("res://shaders/lamp_halo.gdshader")
		q.material = hm
		var mm:= MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = q
		mm.instance_count = halos.size()
		for i in halos.size():
			var h: Array = halos[i]
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * float(h[6])), Vector3(h[0], h[1], h[2])))
			mm.set_instance_color(i, Color(h[3], h[4], h[5], float(h[7]) * 0.5))
			mm.set_instance_custom_data(i, Color(float(h[8]), 0, 0, 0))
		var mmi:= MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-400, -10, -400), Vector3(800, 80, 800))
		add_child(mmi)

	var cone:= _cone_mesh(18)
	var cm:= ShaderMaterial.new()
	cm.shader = load("res://shaders/lamp_cone.gdshader")
	cone.surface_set_material(0, cm)
	var items: Array = []
	for l in layout["lamps"]:
		if not l["broken"]:
			items.append(l)
	var mc:= MultiMesh.new()
	mc.transform_format = MultiMesh.TRANSFORM_3D
	mc.use_colors = true
	mc.use_custom_data = true
	mc.mesh = cone
	mc.instance_count = items.size()
	for i in items.size():
		var l: Dictionary = items[i]
		var p:= _v3(l["p"])
		var h:= maxf(p.y - 0.12, 1.0)
		var r:= h * 0.38
		mc.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, h, r)), p + Vector3(0, -0.12, 0)))
		mc.set_instance_color(i, Color(l["c"][0], l["c"][1], l["c"][2], (0.25 if l["flicker"] else 0.5)))
		mc.set_instance_custom_data(i, Color(float(l.get("seed", 0.0)), 0, 0, 0))
	var mci:= MultiMeshInstance3D.new()
	mci.multimesh = mc
	mci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mci.custom_aabb = AABB(Vector3(-400, -10, -400), Vector3(800, 80, 800))
	add_child(mci)

func _cone_mesh(seg: int) -> ArrayMesh:
	var st:= SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r0:= 0.06
	for i in seg:
		var a0:= TAU * i / seg
		var a1:= TAU * (i + 1) / seg
		var d0:= Vector3(cos(a0), 0, sin(a0))
		var d1:= Vector3(cos(a1), 0, sin(a1))
		var slope:= 1.0 - r0
		var n0:= (d0 + Vector3(0, slope, 0)).normalized()
		var n1:= (d1 + Vector3(0, slope, 0)).normalized()
		var t0:= d0 * r0
		var t1:= d1 * r0
		var b0:= d0 + Vector3(0, -1, 0)
		var b1:= d1 + Vector3(0, -1, 0)
		for v in [[t0, n0, Vector2(float(i) / seg, 0)], [b0, n0, Vector2(float(i) / seg, 1)], [b1, n1, Vector2(float(i + 1) / seg, 1)],
				[t0, n0, Vector2(float(i) / seg, 0)], [b1, n1, Vector2(float(i + 1) / seg, 1)], [t1, n1, Vector2(float(i + 1) / seg, 0)]]:
			st.set_normal(v[1])
			st.set_uv(v[2])
			st.add_vertex(v[0])
	return st.commit()

func _make_particles(tex: String, shader: String, amount: int) -> CPUParticles3D:
	var p:= CPUParticles3D.new()
	p.amount = amount
	var q:= QuadMesh.new()
	q.size = Vector2(1, 1)
	var m:= ShaderMaterial.new()
	m.shader = load(shader)
	m.set_shader_parameter("tex", load(tex))
	q.material = m
	p.mesh = q
	p.local_coords = false
	return p

func _build_particles() -> void:
	for s in layout["steam"]:
		var p:= _make_particles("res://assets/textures/smoke.png", "res://shaders/particle_soft.gdshader", 14)
		var strength:= float(s[3])
		p.lifetime = 4.5
		p.direction = Vector3.UP
		p.spread = 12.0
		p.initial_velocity_min = 0.5 * strength + 0.3
		p.initial_velocity_max = 1.2 * strength + 0.4
		p.gravity = Vector3(0.25, 0.25, 0.1)
		p.damping_min = 0.2
		p.damping_max = 0.4
		p.scale_amount_min = 0.9
		p.scale_amount_max = 1.6
		var curve:= Curve.new()
		curve.add_point(Vector2(0, 0.35))
		curve.add_point(Vector2(1, 2.6))
		p.scale_amount_curve = curve
		var g:= Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.add_point(0.15, Color(1, 1, 1, 0.9))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		p.color_ramp = g
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.3
		p.position = _v3(s)
		add_child(p)
		steam_nodes.append(p)
	for f in layout["fires"]:
		var pos:= _v3(f)
		var fl:= _make_particles("res://assets/textures/flame.png", "res://shaders/particle_add.gdshader", 18)
		fl.lifetime = 0.8
		fl.direction = Vector3.UP
		fl.spread = 10.0
		fl.initial_velocity_min = 0.6
		fl.initial_velocity_max = 1.3
		fl.gravity = Vector3(0, 0.5, 0)
		fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		fl.emission_sphere_radius = 0.18
		fl.scale_amount_min = 0.35
		fl.scale_amount_max = 0.6
		var c2:= Curve.new()
		c2.add_point(Vector2(0, 1.0))
		c2.add_point(Vector2(1, 0.2))
		fl.scale_amount_curve = c2
		var g2:= Gradient.new()
		g2.set_color(0, Color(1, 0.8, 0.4, 0.9))
		g2.set_color(g2.get_point_count() - 1, Color(1, 0.25, 0.05, 0.0))
		fl.color_ramp = g2
		fl.position = pos
		add_child(fl)
		var sp:= _make_particles("res://assets/textures/spark.png", "res://shaders/particle_add.gdshader", 8)
		sp.lifetime = 1.6
		sp.direction = Vector3.UP
		sp.spread = 25.0
		sp.initial_velocity_min = 1.0
		sp.initial_velocity_max = 2.2
		sp.gravity = Vector3(0.2, 0.3, 0)
		sp.scale_amount_min = 0.04
		sp.scale_amount_max = 0.07
		sp.position = pos
		add_child(sp)
		var light:= OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.25)
		light.omni_range = 7.0
		light.light_energy = 1.4
		light.position = pos + Vector3(0, 0.6, 0)
		add_child(light)
		var smoke:= _make_particles("res://assets/textures/smoke.png", "res://shaders/particle_soft.gdshader", 8)
		smoke.lifetime = 3.0
		smoke.direction = Vector3.UP
		smoke.initial_velocity_min = 0.6
		smoke.initial_velocity_max = 1.0
		smoke.scale_amount_min = 0.6
		smoke.scale_amount_max = 1.1
		smoke.position = pos + Vector3(0, 0.5, 0)
		(smoke.mesh.material as ShaderMaterial).set_shader_parameter("base_col", Color(0.08, 0.07, 0.07))
		(smoke.mesh.material as ShaderMaterial).set_shader_parameter("opacity", 0.25)
		add_child(smoke)
		fire_nodes.append({"light": light, "base": 1.4, "parts": [fl, sp, smoke]})

func _stream(name: String) -> AudioStream:
	if not _sfx_cache.has(name):
		_sfx_cache[name] = load("res://assets/audio/%s.wav" % name)
	return _sfx_cache[name]

func _build_audio() -> void:
	var map:= {"fire": ["fire_loop", -4.0, 14.0], "steam": ["steam_loop", -10.0, 12.0], "drips": ["drips_loop", -8.0, 16.0],
			"chinatown_music": ["chinatown_music", -6.0, 30.0]}
	for a in layout["audio"]:
		var info = map.get(a["type"])
		if info == null:
			continue
		var p:= AudioStreamPlayer3D.new()
		p.stream = _stream(info[0])
		p.volume_db = info[1]
		p.max_distance = info[2]
		p.unit_size = info[2] * 0.25
		p.bus = "Music" if a["type"] == "chinatown_music" else "Ambience"
		p.position = _v3(a["p"])
		p.attenuation_filter_cutoff_hz = 3000.0 if a["type"] == "chinatown_music" else 8000.0
		add_child(p)
		ambient_players.append(p)
	for i in 3:
		var n:= AudioStreamPlayer3D.new()
		n.stream = _stream("neon_buzz_loop")
		n.volume_db = -14.0
		n.max_distance = 8.0
		n.unit_size = 1.5
		n.bus = "Ambience"
		add_child(n)
		neon_players.append(n)

func apply_settings() -> void:
	var vd: float = Settings.g["view_distance"]
	for i in chunk_nodes.size():
		chunk_nodes[i].visibility_range_end = vd + chunk_radius[i]
		chunk_nodes[i].visibility_range_end_margin = 10.0

	for i in prop_nodes.size():
		prop_nodes[i].visibility_range_end = minf(prop_range[i], vd * 0.85 + 6.0)
	for mi in parked:
		mi.visibility_range_end = minf(170.0, vd * 0.85 + 6.0)
	var parts: int = Settings.g["particles"]
	for p in steam_nodes:
		p.amount = [4, 10, 14, 20][parts]
	RenderingServer.global_shader_parameter_set("window_detail", float(Settings.g["windows"]))
	var shadows: int = Settings.g["shadows"]
	for i in light_pool.size():
		light_pool[i].shadow_enabled = Settings.is_vulkan() and shadows >= 3 and i < 2

func update(delta: float, focus: Vector3) -> void:
	Prof.b("city_update")
	_time += delta
	_update_emp(delta)
	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 0.2
		_assign_lights(focus)
	_animate_lights()
	_audio_timer -= delta
	if _audio_timer <= 0.0:
		_audio_timer = 0.5
		_update_audio(focus)
	for f in fire_nodes:
		f["light"].light_energy = f["base"] * (0.75 + 0.25 * sin(_time * 13.0) * sin(_time * 7.3 + 1.0))
	Prof.e("city_update")

func _assign_lights(focus: Vector3) -> void:
	var count: int = Settings.g["lights"]
	var cand: Array = []
	for l in lamps:
		if l["broken"]:
			continue
		var d: float = l["p"].distance_squared_to(focus)
		if d < 50.0 * 50.0:
			cand.append([d, l])
	cand.sort_custom(func (a, b): return a[0] < b[0])
	for i in light_pool.size():
		var o:= light_pool[i]
		if i < count and i < cand.size():
			var l: Dictionary = cand[i][1]
			o.position = l["p"] + Vector3(0, -0.25, 0)
			o.light_color = l["c"]
			o.set_meta("lamp", l)
			o.visible = true
		else:
			o.visible = false
			o.set_meta("lamp", null)

func _animate_lights() -> void:
	for o in light_pool:
		if not o.visible:
			continue
		var l = o.get_meta("lamp", null)
		if l == null:
			continue
		var e: float = 0.9
		if l["flicker"]:
			var n:= sin(_time * 23.0 + l["seed"]) * sin(_time * 7.0 + l["seed"] * 2.0)
			e *= 1.0 if n > -0.2 else (0.35 if n > -0.6 else 0.05)
		o.light_energy = e * emp_factor(o.position)

func _update_audio(focus: Vector3) -> void:
	for p in ambient_players:
		var near:= p.position.distance_to(focus) < p.max_distance + 10.0
		if near and not p.playing:
			p.play()
		elif not near and p.playing:
			p.stop()
	var sorted:= neon_points.duplicate()
	sorted.sort_custom(func (a, b): return a.distance_squared_to(focus) < b.distance_squared_to(focus))
	for i in neon_players.size():
		var n:= neon_players[i]
		if i < sorted.size() and sorted[i].distance_to(focus) < 10.0 and emp_factor(sorted[i]) > 0.5:
			n.position = sorted[i]
			if not n.playing:
				n.play()
		elif n.playing:
			n.stop()

func emp(pos: Vector3, radius: float, hold: float = 6.0) -> void:
	if emp_zones.size() >= 4:
		emp_zones.pop_front()
	emp_zones.append({"p": pos, "r": radius, "t": 0.0, "hold": hold})
	var hits:= 0
	for l in lamps:
		if not l["broken"] and l["p"].distance_to(pos) < radius and hits < 4:
			_one_shot("light_off", l["p"], -2.0)
			hits += 1

func emp_factor(p: Vector3) -> float:
	var f:= 1.0
	for z in emp_zones:
		var r: float = z["cur"] if z.has("cur") else 0.0
		if r <= 0.0:
			continue
		var d:= Vector2(p.x - z["p"].x, p.z - z["p"].z).length()
		f = minf(f, smoothstep(r - 2.0, r + 0.5, d))
	return f

func _update_emp(delta: float) -> void:
	var i:= 0
	while i < emp_zones.size():
		var z: Dictionary = emp_zones[i]
		z["t"] += delta
		var t: float = z["t"]
		var r: float = z["r"]
		var cur:= 0.0
		if t < 0.3:
			cur = r * (t / 0.3)
		elif t < 0.3 + z["hold"]:
			cur = r
		elif t < 0.3 + z["hold"] + 2.5:
			var k: float = (t - 0.3 - z["hold"]) / 2.5
			cur = r * (1.0 - k * k)
			if not z.has("restored"):
				z["restored"] = true
				_one_shot("light_on", z["p"] + Vector3(0, 5, 0), -6.0)
		else:
			emp_zones.remove_at(i)
			continue
		z["cur"] = cur
		i += 1
	for k in 4:
		var v:= Vector4(0, -1000, 0, 0)
		if k < emp_zones.size():
			var z: Dictionary = emp_zones[k]
			v = Vector4(z["p"].x, z["p"].y, z["p"].z, z["cur"])

		if _emp_sent[k] != v:
			_emp_sent[k] = v
			RenderingServer.global_shader_parameter_set("emp_zone_%d" % k, v)

func _one_shot(sound: String, pos: Vector3, vol: float) -> void:
	var p:= AudioStreamPlayer3D.new()
	p.stream = _stream(sound)
	p.volume_db = vol
	p.max_distance = 40.0
	p.bus = "SFX"
	p.position = pos
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
