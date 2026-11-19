extends SceneTree
## Reads every shop-window pane from the city chunks and reconstructs the room behind it (the frame the old
## interior-mapping shader used): corner at UV (0,0), x along the wall, y up, z into the building, size from UV2.
## Writes data/shop_rooms.json for tools/blender/shop_interiors.py and city.gd.
## Run: godot --headless --path . --script res://tools/extract_shop_rooms.gd

func _walk(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _init() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/layout.json"))
	var rooms:= {}
	for c in layout["chunks"]:
		var inst: Node = load(c["file"]).instantiate()
		var ms:= []
		_walk(inst, ms)
		for mi in ms:
			var xf: Transform3D = mi.transform
			for s in mi.mesh.get_surface_count():
				var mat = mi.mesh.surface_get_material(s)
				if mat == null or mat.resource_name != "shopwindow":
					continue
				var a: Array = mi.mesh.surface_get_arrays(s)
				var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var N: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
				var U: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
				var U2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
				var C: PackedColorArray = a[Mesh.ARRAY_COLOR]
				var I: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				for t in range(0, I.size(), 3):
					var i0:= I[t]
					var i1:= I[t + 1]
					var i2:= I[t + 2]
					var p0:= xf * V[i0]
					var p1:= xf * V[i1]
					var p2:= xf * V[i2]
					var n:= (xf.basis * N[i0]).normalized()
					# solve the affine map uv -> world on this triangle
					var du1:= U[i1] - U[i0]
					var du2:= U[i2] - U[i0]
					var det:= du1.x * du2.y - du1.y * du2.x
					if absf(det) < 1e-6:
						continue
					var e1:= p1 - p0
					var e2:= p2 - p0
					var right:= (e1 * du2.y - e2 * du1.y) / det
					var up:= (e2 * du1.x - e1 * du2.x) / det
					var origin:= p0 - right * U[i0].x - up * U[i0].y
					var key:= "%d_%d_%d" % [roundi(origin.x * 10.0), roundi(origin.y * 10.0), roundi(origin.z * 10.0)]
					if not rooms.has(key):
						rooms[key] = {"o": [origin.x, origin.y, origin.z], "right": [right.x, right.y, right.z], "n": [n.x, n.y, n.z],
							"W": U2[i0].x, "D": U2[i0].y, "type": roundi(C[i0].r * 32.0), "lit": C[i0].g, "var": C[i0].a,
							"panes": []}
					var ux:= [U[i0].x, U[i1].x, U[i2].x]
					var uy:= [U[i0].y, U[i1].y, U[i2].y]
					rooms[key]["panes"].append([ux.min(), ux.max(), uy.min(), uy.max(), C[i0].b])
		inst.free()
	# merge the pane triangles into rectangles per kind
	var out:= []
	for k in rooms:
		var r: Dictionary = rooms[k]
		var merged:= {}
		for p in r["panes"]:
			var pk:= "%.2f" % p[4]
			if not merged.has(pk):
				merged[pk] = []
			merged[pk].append(p)
		var panes:= []
		for pk in merged:
			var list: Array = merged[pk]
			# group overlapping x ranges
			list.sort_custom(func (a, b): return a[0] < b[0])
			var cur: Array = list[0].duplicate()
			for p in list.slice(1):
				if p[0] <= cur[1] + 0.02:
					cur[1] = maxf(cur[1], p[1]); cur[2] = minf(cur[2], p[2]); cur[3] = maxf(cur[3], p[3])
				else:
					panes.append(cur)
					cur = p.duplicate()
			panes.append(cur)
		r["panes"] = panes
		out.append(r)
	var f:= FileAccess.open("res://data/shop_rooms.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("ROOMS ", out.size())
	for r in out.slice(0, 6):
		print(r)
	quit()
