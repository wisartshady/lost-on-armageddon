extends SceneTree
## Converts the furnished shop rooms (tools/shop_interiors.py -> /home/claude/work/shops/interiors.glb) into
## assets/models/shops/interiors.scn: one MeshInstance3D per room with compressed vertex data and automatic LODs.
## Run: godot --headless --path . --script res://tools/build_shop_interiors.gd

const SRC:= "/home/claude/work/shops/interiors.glb"
const OUT:= "res://assets/models/shops/interiors.scn"


func _init() -> void:
	var doc:= GLTFDocument.new()
	var st:= GLTFState.new()
	if doc.append_from_file(SRC, st) != OK:
		push_error("cannot read " + SRC)
		quit(1)
		return
	var src:= doc.generate_scene(st)
	var root:= Node3D.new()
	root.name = "ShopInteriors"
	var tris:= 0
	var lod_tris:= 0
	var nodes:= src.find_children("*", "ImporterMeshInstance3D", true, false)
	nodes.append_array(src.find_children("*", "MeshInstance3D", true, false))
	for n in nodes:
		var out:= ImporterMesh.new()
		if n.mesh is ImporterMesh:
			var im: ImporterMesh = n.mesh
			for s in im.get_surface_count():
				out.add_surface(Mesh.PRIMITIVE_TRIANGLES, im.get_surface_arrays(s), [], {}, null, "", Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		else:
			var m: Mesh = n.mesh
			for s in m.get_surface_count():
				out.add_surface(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(s), [], {}, null, "", Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		out.generate_lods(25.0, 60.0, [])
		var am:= out.get_mesh()
		var mi:= MeshInstance3D.new()
		mi.name = n.name
		mi.mesh = am
		mi.transform = n.transform
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.owner = root
		tris += am.surface_get_array_index_len(0) / 3
		if out.get_surface_lod_count(0) > 0:
			lod_tris += out.get_surface_lod_indices(0, out.get_surface_lod_count(0) - 1).size() / 3
	var ps:= PackedScene.new()
	ps.pack(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/models/shops"))
	var e:= ResourceSaver.save(ps, OUT, ResourceSaver.FLAG_COMPRESS)
	print("ROOMS ", root.get_child_count(), " tris ", tris, " coarsest LODs ", lod_tris, " save ", e)
	src.free()
	root.free()
	quit()
