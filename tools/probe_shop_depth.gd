extends SceneTree
## Probe: what lies behind each shop-window pane (distance to the first non-window surface along the inward normal).
var tris:= []
var grid_t:= {}
const CELL:= 2.0

func _walk(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)

func _init() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/layout.json"))
	for c in layout["chunks"]:
		if c["far"]:
			continue
		var inst: Node = load(c["file"]).instantiate()
		var ms:= []
		_walk(inst, ms)
		for mi in ms:
			var xf: Transform3D = mi.transform
			for s in mi.mesh.get_surface_count():
				var mat = mi.mesh.surface_get_material(s)
				var mname: String = mat.resource_name if mat else ""
				if mname == "shopwindow":
					continue
				var a: Array = mi.mesh.surface_get_arrays(s)
				var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var I: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				for t in range(0, I.size(), 3):
					var p0:= xf * V[I[t]]
					var p1:= xf * V[I[t + 1]]
					var p2:= xf * V[I[t + 2]]
					if minf(p0.y, minf(p1.y, p2.y)) > 4.0:
						continue
					var bb:= AABB(p0, Vector3.ZERO).expand(p1).expand(p2)
					var ti:= tris.size()
					tris.append([p0, p1, p2, mname])
					for cx in range(floori(bb.position.x / CELL), floori(bb.end.x / CELL) + 1):
						for cz in range(floori(bb.position.z / CELL), floori(bb.end.z / CELL) + 1):
							var k:= Vector2i(cx, cz)
							if not grid_t.has(k):
								grid_t[k] = PackedInt32Array()
							grid_t[k].append(ti)
		inst.free()
	var rooms: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop_rooms.json"))
	var hist:= {}
	for r in rooms.slice(0, 200):
		var o:= Vector3(r["o"][0], r["o"][1], r["o"][2])
		var right:= Vector3(r["right"][0], r["right"][1], r["right"][2]).normalized()
		var n:= Vector3(r["n"][0], r["n"][1], r["n"][2]).normalized()
		var p: Array = r["panes"][0]
		var from: Vector3 = o + right * ((p[0] + p[1]) * 0.5) + Vector3.UP * ((p[2] + p[3]) * 0.5) + n * 0.3
		var dir:= -n
		var best:= 20.0
		var what:= ""
		var seen:= {}
		for i in 22:
			var q: Vector3 = from + dir * i
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var k:= Vector2i(floori(q.x / CELL) + dx, floori(q.z / CELL) + dz)
					if not grid_t.has(k):
						continue
					for ti in grid_t[k]:
						if seen.has(ti):
							continue
						seen[ti] = true
						var t: Array = tris[ti]
						var h = Geometry3D.ray_intersects_triangle(from, dir, t[0], t[1], t[2])
						if h != null and from.distance_to(h) < best:
							best = from.distance_to(h)
							what = t[3]
		var key:= "%s %.1f" % [what, snappedf(best - 0.3, 0.1)]
		hist[key] = hist.get(key, 0) + 1
		if best - 0.3 < 1.0:
			print("room ", rooms.find(r), " type ", r["type"], " kind ", p[4], " W ", r["W"], " D ", r["D"], " o ", o, " behind: ", what, " at ", best - 0.3, " panes ", r["panes"].size())
	var keys:= hist.keys()
	keys.sort()
	for k in keys:
		print(k, " : ", hist[k])
	quit()
