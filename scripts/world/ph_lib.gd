class_name PHLib
extends RefCounted

static var _meshes:= {}
static var meta:= {}

const FLAT:= {"ph_tyre_flat": Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0.0, 0.08, -0.305)),
		"ph_rim_flat": Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0.0, 0.078, -0.202))}

static func mesh(name: String) -> Mesh:
	if _meshes.has(name):
		return _meshes[name]
	if meta.is_empty():
		meta = JSON.parse_string(FileAccess.get_file_as_string("res://data/ph_props.json"))
	if FLAT.has(name):
		var base:= name.trim_suffix("_flat")
		var src_m: ArrayMesh = mesh(base)
		var xf: Transform3D = FLAT[name]
		var out:= ArrayMesh.new()
		for si in src_m.get_surface_count():
			var arr:= src_m.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in v.size():
				v[i] = xf * v[i]
			arr[Mesh.ARRAY_VERTEX] = v
			if arr[Mesh.ARRAY_NORMAL] != null:
				var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for i in nn.size():
					nn[i] = xf.basis * nn[i]
				arr[Mesh.ARRAY_NORMAL] = nn
			if arr[Mesh.ARRAY_TANGENT] != null:
				var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
				for i in range(0, tg.size(), 4):
					var t3: Vector3 = xf.basis * Vector3(tg[i], tg[i + 1], tg[i + 2])
					tg[i] = t3.x; tg[i + 1] = t3.y; tg[i + 2] = t3.z
				arr[Mesh.ARRAY_TANGENT] = tg
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(si, src_m.surface_get_material(si))
		if not meta.has(name) and meta.has(base):
			var mb: Dictionary = meta[base].duplicate(true)
			var sz: Array = mb["size"]
			mb["size"] = [sz[0], sz[2], sz[1]]
			meta[name] = mb
		_meshes[name] = out
		return out
	var scn: PackedScene = load("res://assets/models/ph/%s.scn" % name)
	var tmp:= scn.instantiate()
	var mis:= tmp.find_children("*", "MeshInstance3D", true, false)
	var src: MeshInstance3D = mis[0]
	var m: ArrayMesh = src.mesh.duplicate()
	for s in m.get_surface_count():
		m.surface_set_material(s, convert_material(m.surface_get_material(s)))
	tmp.free()
	_meshes[name] = m
	return m

static func convert_material(src: Material) -> ShaderMaterial:
	var sm:= ShaderMaterial.new()
	sm.shader = preload("res://shaders/prop_pbr.gdshader")
	var std:= src as BaseMaterial3D
	if std == null:
		return sm
	if std.albedo_texture:
		sm.set_shader_parameter("albedo_tex", std.albedo_texture)
	sm.set_shader_parameter("tint", std.albedo_color)
	if std.normal_enabled and std.normal_texture:
		sm.set_shader_parameter("normal_tex", std.normal_texture)
	else:
		sm.set_shader_parameter("has_normal", false)
	var orm: Texture2D = std.roughness_texture if std.roughness_texture else std.metallic_texture
	if orm:
		sm.set_shader_parameter("orm_tex", orm)
	else:
		sm.set_shader_parameter("has_orm", false)
	var n:= src.resource_name.to_lower()
	if "bulb" in n or "glass" in n:
		sm.set_shader_parameter("emissive", 1.0)
	return sm
