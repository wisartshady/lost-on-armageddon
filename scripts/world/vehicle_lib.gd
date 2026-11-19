class_name VehicleLib
extends RefCounted

static var _meshes:= {}
static var _mat: ShaderMaterial = null
static var _shadow_mat: ShaderMaterial = null
static var meta:= {}

const SCALE:= 0.92

static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/vehicle.gdshader")
		_mat.set_shader_parameter("atlas", load("res://assets/textures/vehicles/vehicle_atlas.png"))
		meta = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicles.json"))
	return _mat

static func mesh(model: String) -> Mesh:
	if not _meshes.has(model):
		var scn: PackedScene = load("res://assets/models/vehicles/%s.scn" % model)
		var tmp:= scn.instantiate()
		var mi: MeshInstance3D = tmp.find_children("*", "MeshInstance3D", true, false)[0]
		_meshes[model] = mi.mesh
		tmp.free()
	return _meshes[model]

static func spawn(parent: Node, model: String, xf: Transform3D, paint: Color, dirt:= 0.3) -> MeshInstance3D:
	var mi:= MeshInstance3D.new()
	mi.mesh = mesh(model)
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = 170.0
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	mi.global_transform = Transform3D(xf.basis * Basis.from_scale(Vector3.ONE * SCALE), xf.origin)
	mi.set_instance_shader_parameter("paint", paint)
	mi.set_instance_shader_parameter("dirt", dirt)
	mi.set_instance_shader_parameter("siren", 1.0 if model == "police" else 0.0)
	return mi

static func shadow_material() -> ShaderMaterial:
	if _shadow_mat == null:
		_shadow_mat = ShaderMaterial.new()
		_shadow_mat.shader = load("res://shaders/blob_shadow.gdshader")
	return _shadow_mat

static func shadows(parent: Node, items: Array) -> MultiMeshInstance3D:
	var q:= PlaneMesh.new()
	q.size = Vector2(1, 1)
	var mm:= MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = items.size()
	for i in items.size():
		var xf: Transform3D = items[i][0]
		var sz: Vector2 = items[i][1]
		var b:= xf.basis.orthonormalized() * Basis.from_scale(Vector3(sz.x, 1.0, sz.y))
		mm.set_instance_transform(i, Transform3D(b, xf.origin + Vector3(0, 0.025, 0)))
	var mmi:= MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = shadow_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi
