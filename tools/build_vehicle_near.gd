extends SceneTree
## Near-range vehicle meshes (run: godot --headless --path . --script res://tools/build_vehicle_near.gd).
## For every model: the body without the black blackout panels that sat behind the glass, plus the interior built by
## tools/blender/vehicle_interiors.py, as surface 0 (opaque, vehicle_near.gdshader), and the glass on its own as
## surface 1 (tinted, see-through, vehicle_glass.gdshader). Far away the original one-draw mesh is used.

const INTERIORS:= "/home/claude/work/interiors/"
const OUT:= "res://assets/models/vehicles/near/"

var cab:= {}


func _init() -> void:
	cab = JSON.parse_string(FileAccess.get_file_as_string("res://data/vehicle_cabins.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var d:= DirAccess.open("res://assets/models/vehicles")
	for f in d.get_files():
		if f.ends_with(".scn"):
			_build(f.get_basename())
	quit()


func _interior(model: String) -> Array:
	var doc:= GLTFDocument.new()
	var st:= GLTFState.new()
	if doc.append_from_file(INTERIORS + model + ".glb", st) != OK:
		push_error("no interior for " + model)
		return []
	var root:= doc.generate_scene(st)
	var mis:= root.find_children("*", "ImporterMeshInstance3D", true, false)
	var out:= []
	for n in mis:
		var im: ImporterMesh = n.mesh
		for s in im.get_surface_count():
			out.append([im.get_surface_arrays(s), n.transform])
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = n.mesh
		for s in m.get_surface_count():
			out.append([m.surface_get_arrays(s), n.transform])
	root.free()
	return out


## cut body arrays + the glass triangles of the original, as one array set
func _with_glass(body: Array, orig: Array) -> Array:
	var out:= []
	out.resize(Mesh.ARRAY_MAX)
	var V: PackedVector3Array = body[Mesh.ARRAY_VERTEX].duplicate()
	var N: PackedVector3Array = body[Mesh.ARRAY_NORMAL].duplicate()
	var C: PackedColorArray = body[Mesh.ARRAY_COLOR].duplicate()
	var U: PackedVector2Array = body[Mesh.ARRAY_TEX_UV].duplicate() if body[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	if U.size() != V.size():
		U.resize(V.size())
	var U2: PackedVector2Array = body[Mesh.ARRAY_TEX_UV2].duplicate()
	var I0: PackedInt32Array = body[Mesh.ARRAY_INDEX] if body[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(V.size()))
	# faces the boolean took from the cutter (part 1) are not part of the body
	var I:= PackedInt32Array()
	for t in range(0, I0.size(), 3):
		if int(U2[I0[t]].x + 0.5) != 1:
			I.append_array([I0[t], I0[t + 1], I0[t + 2]])
	var oV: PackedVector3Array = orig[Mesh.ARRAY_VERTEX]
	var oN: PackedVector3Array = orig[Mesh.ARRAY_NORMAL]
	var oC: PackedColorArray = orig[Mesh.ARRAY_COLOR]
	var oU: PackedVector2Array = orig[Mesh.ARRAY_TEX_UV]
	var oU2: PackedVector2Array = orig[Mesh.ARRAY_TEX_UV2]
	var oI: PackedInt32Array = orig[Mesh.ARRAY_INDEX]
	for t in range(0, oI.size(), 3):
		if int(oU2[oI[t]].x + 0.5) != 1:
			continue
		for k in 3:
			var vi:= oI[t + k]
			V.append(oV[vi]); N.append(oN[vi]); C.append(oC[vi]); U.append(oU[vi]); U2.append(oU2[vi])
			I.append(V.size() - 1)
	out[Mesh.ARRAY_VERTEX] = V
	out[Mesh.ARRAY_NORMAL] = N
	out[Mesh.ARRAY_COLOR] = C
	out[Mesh.ARRAY_TEX_UV] = U
	out[Mesh.ARRAY_TEX_UV2] = U2
	out[Mesh.ARRAY_INDEX] = I
	return out


func _covered_by_glass(c: Vector3, n: Vector3, glass: Array) -> bool:
	# a paint / trim face is "backing" when its centre projects inside a glass pane that is parallel to it and
	# less than 8 cm away (faces of the window frames around the panes do not project inside them)
	for g in glass:
		if not (g[3] as AABB).has_point(c):
			continue
		var a: Vector3 = g[0]
		var b: Vector3 = g[1]
		var d: Vector3 = g[2]
		var gn:= (b - a).cross(d - a)
		if gn.length() < 1e-8:
			continue
		gn = gn.normalized()
		if absf(gn.dot(n)) < 0.75:
			continue
		var dist:= (c - a).dot(gn)
		if absf(dist) > 0.13:
			continue
		var q:= c - gn * dist
		# barycentric inside test
		var v0:= b - a
		var v1:= d - a
		var v2:= q - a
		var d00:= v0.dot(v0)
		var d01:= v0.dot(v1)
		var d11:= v1.dot(v1)
		var d20:= v2.dot(v0)
		var d21:= v2.dot(v1)
		var den:= d00 * d11 - d01 * d01
		if absf(den) < 1e-12:
			continue
		var bv:= (d11 * d20 - d01 * d21) / den
		var bw:= (d00 * d21 - d01 * d20) / den
		if bv >= -0.08 and bw >= -0.08 and bv + bw <= 1.08:
			return true
	return false


func _build(model: String) -> void:
	var inst: Node = load("res://assets/models/vehicles/%s.scn" % model).instantiate()
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var a:= mi.mesh.surface_get_arrays(0)
	inst.free()
	# glass from the original mesh; the body from the window-cut copy when there is one (cut_windows.py)
	var ga:= a
	var used_cut:= false
	var cut_path:= "/home/claude/work/veh_cut/" + model + ".glb"
	if FileAccess.file_exists(cut_path):
		var doc:= GLTFDocument.new()
		var st:= GLTFState.new()
		if doc.append_from_file(cut_path, st) == OK:
			var root:= doc.generate_scene(st)
			var ca: Array = []
			var ims:= root.find_children("*", "ImporterMeshInstance3D", true, false)
			if not ims.is_empty():
				ca = (ims[0].mesh as ImporterMesh).get_surface_arrays(0)
			else:
				var mis:= root.find_children("*", "MeshInstance3D", true, false)
				if not mis.is_empty():
					ca = (mis[0].mesh as Mesh).surface_get_arrays(0)
			if not ca.is_empty() and ca[Mesh.ARRAY_COLOR] != null and ca[Mesh.ARRAY_TEX_UV2] != null:
				a = _with_glass(ca, ga)
				used_cut = true
			else:
				print("  cut body missing attributes for ", model, " empty=", ca.is_empty())
			root.free()
	var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var N: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var C: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var U: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var U2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var I: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var c: Dictionary = cab[model]
	var gmin: Array = c["glass_min"]
	var gmax: Array = c["glass_max"]
	var gw:= float(gmax[0]) - 0.012
	var belt:= float(gmin[1])
	var roof:= float(gmax[1])
	var z0:= float(gmin[2]) - 0.3
	var z1:= float(gmax[2]) + 0.3
	var old_interior:= model in ["police", "police_suv"]
	var body_idx:= PackedInt32Array()
	var glass_idx:= PackedInt32Array()
	var dropped:= 0
	var reclass_v:= PackedVector3Array()
	var reclass_n:= PackedVector3Array()
	var reclass_c:= PackedColorArray()
	var reclass_u:= PackedVector2Array()
	var reclass_u2:= PackedVector2Array()
	var glass_tris:= []
	for t in range(0, I.size(), 3):
		if int(U2[I[t]].x + 0.5) == 1:
			var a0:= V[I[t]]
			var a1:= V[I[t + 1]]
			var a2:= V[I[t + 2]]
			var bb:= AABB(a0, Vector3.ZERO).expand(a1).expand(a2).grow(0.1)
			glass_tris.append([a0, a1, a2, bb])
	for t in range(0, I.size(), 3):
		var p:= int(U2[I[t]].x + 0.5)
		var ctr:= (V[I[t]] + V[I[t + 1]] + V[I[t + 2]]) / 3.0
		var inside:= absf(ctr.x) < gw and ctr.z > z0 and ctr.z < z1 and ctr.y < roof + 0.015
		if p == 1:
			glass_idx.append_array([I[t], I[t + 1], I[t + 2]])
			continue
		# blackout panels behind the glass (and the old placeholder cabin of the police cars)
		if inside and p == 3 and ctr.y > belt - 0.3 and (not used_cut or _covered_by_glass(ctr, (N[I[t]] + N[I[t + 1]] + N[I[t + 2]]).normalized(), glass_tris)):
			dropped += 1
			continue
		if old_interior and inside and p in [0, 3, 11] and ctr.y > 0.3 and ctr.y < roof - 0.05 and absf(ctr.x) < gw - 0.08:
			dropped += 1
			continue
		# the closed paint shell behind each window: drop it where a glass pane sits just outside it
		if not used_cut and p in [0, 3, 17] and absf(ctr.x) < gw + 0.04 and ctr.y > belt - 0.04 and ctr.z > float(gmin[2]) - 0.15 and ctr.z < float(gmax[2]) + 0.15:
			var vn:= (N[I[t]] + N[I[t + 1]] + N[I[t + 2]]).normalized()
			if _covered_by_glass(ctr, vn, glass_tris):
				dropped += 1
				continue
		# inner skin of the shell (door frames, pillars, roof, painted on the inside): faces turned towards the
		# cabin become interior trim (29) or headliner (22), so the paint colour does not show through the glass
		var nrm:= (N[I[t]] + N[I[t + 1]] + N[I[t + 2]]).normalized()   # vertex normals (Godot winding is clockwise)
		var cab_c:= Vector3(0.0, (belt + roof) * 0.5, clampf(ctr.z, float(gmin[2]), float(gmax[2])))
		var to_c:= cab_c - ctr
		var in_box:= absf(ctr.x) < gw + 0.03 and ctr.y > belt - 0.35 and ctr.y < roof + 0.03 and ctr.z > float(gmin[2]) - 0.12 and ctr.z < float(gmax[2]) + 0.12
		var side_in:= absf(nrm.x) > 0.55 and signf(nrm.x) == -signf(ctr.x) and absf(ctr.x) > 0.2
		var roof_in:= nrm.y < -0.6 and ctr.y > belt + 0.1
		if p in [0, 3, 17] and in_box and ctr.z > float(gmin[2]) and ctr.z < float(gmax[2]) and (side_in or roof_in) and nrm.dot(to_c.normalized()) > 0.3:
			var np:= 22.0 if nrm.y < -0.6 else 29.0
			for k in 3:
				var vi:= I[t + k]
				reclass_v.append(V[vi]); reclass_n.append(N[vi]); reclass_c.append(C[vi]); reclass_u.append(U[vi])
				reclass_u2.append(Vector2(np, 0.0))
			continue
		body_idx.append_array([I[t], I[t + 1], I[t + 2]])
	# body + interior in one surface
	var bv:= V.duplicate()
	var bn:= N.duplicate()
	var bc:= C.duplicate()
	var bu:= U.duplicate()
	var bu2:= U2.duplicate()
	var bi:= body_idx.duplicate()
	var rb:= bv.size()
	bv.append_array(reclass_v); bn.append_array(reclass_n); bc.append_array(reclass_c); bu.append_array(reclass_u); bu2.append_array(reclass_u2)
	for k in reclass_v.size():
		bi.append(rb + k)
	for e in _interior(model):
		var ia: Array = e[0]
		var xf: Transform3D = e[1]
		var base:= bv.size()
		var iv: PackedVector3Array = ia[Mesh.ARRAY_VERTEX]
		var inn: PackedVector3Array = ia[Mesh.ARRAY_NORMAL]
		var ic = ia[Mesh.ARRAY_COLOR]
		var iu = ia[Mesh.ARRAY_TEX_UV]
		var iu2 = ia[Mesh.ARRAY_TEX_UV2]
		for k in iv.size():
			bv.append(xf * iv[k])
			bn.append((xf.basis * inn[k]).normalized())
			bc.append(ic[k] if ic != null else Color(0.2, 0.2, 0.2, 0.6))
			bu.append(iu[k] if iu != null else Vector2.ZERO)
			bu2.append(iu2[k] if iu2 != null else Vector2(20, 0))
		var ii = ia[Mesh.ARRAY_INDEX]
		if ii == null:
			for k in iv.size():
				bi.append(base + k)
		else:
			for k in ii:
				bi.append(base + k)
	var im:= ImporterMesh.new()
	var arr:= []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = bv
	arr[Mesh.ARRAY_NORMAL] = bn
	arr[Mesh.ARRAY_COLOR] = bc
	arr[Mesh.ARRAY_TEX_UV] = bu
	arr[Mesh.ARRAY_TEX_UV2] = bu2
	arr[Mesh.ARRAY_INDEX] = bi
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	var garr:= []
	garr.resize(Mesh.ARRAY_MAX)
	garr[Mesh.ARRAY_VERTEX] = V
	garr[Mesh.ARRAY_NORMAL] = N
	garr[Mesh.ARRAY_COLOR] = C
	garr[Mesh.ARRAY_TEX_UV] = U
	garr[Mesh.ARRAY_TEX_UV2] = U2
	garr[Mesh.ARRAY_INDEX] = glass_idx
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, garr)
	# automatic LODs (as the imported far meshes have), so a car 30 m away does not draw 40k triangles
	im.generate_lods(25.0, 60.0, [])
	var am:= im.get_mesh()
	var e:= ResourceSaver.save(am, OUT + model + ".res", ResourceSaver.FLAG_COMPRESS)
	print("NEAR ", model, " body tris ", bi.size() / 3, " glass ", glass_idx.size() / 3, " dropped ", dropped, " inner ", reclass_v.size() / 3, " save ", e)
