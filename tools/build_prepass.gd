extends SceneTree
## Builds the depth pre-pass meshes for the city chunks (run: godot --headless --path . --script tools/build_prepass.gd).
## Only the big opaque city triangles (walls, roofs, roads: >= MIN_AREA m2) go in: about 7% of the triangles but
## 96% of the surface, so the pre-pass costs little while still hiding nearly all overdraw for the lit city shader.
const MIN_AREA:= 0.8

func _walk(n, out):
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)

func _init():
	var d:= DirAccess.open("res://assets/models/city")
	var total:= 0
	for f in d.get_files():
		if not f.ends_with(".scn") or f == "chunk_far.scn":
			continue
		var inst: Node = load("res://assets/models/city/" + f).instantiate()
		var ms:= []
		_walk(inst, ms)
		var pv:= PackedVector3Array()
		for mi in ms:
			var xf: Transform3D = mi.transform
			for s in mi.mesh.get_surface_count():
				var m = mi.mesh.surface_get_material(s)
				if m == null or m.resource_name != "surf":
					continue
				var a = mi.mesh.surface_get_arrays(s)
				var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				for t in range(0, idx.size(), 3):
					var p0:= xf * v[idx[t]]
					var p1:= xf * v[idx[t + 1]]
					var p2:= xf * v[idx[t + 2]]
					if (p1 - p0).cross(p2 - p0).length() * 0.5 >= MIN_AREA:
						pv.append(p0); pv.append(p1); pv.append(p2)
		inst.free()
		if pv.is_empty():
			continue
		var arr:= []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pv
		var am:= ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		ResourceSaver.save(am, "res://assets/models/city/prepass/" + f.get_basename() + ".res", ResourceSaver.FLAG_COMPRESS)
		total += pv.size() / 3
		print(f, " ", pv.size() / 3)
	print("TOTAL ", total)
	quit()
