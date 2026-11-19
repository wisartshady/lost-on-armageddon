extends SceneTree
## Finds see-through gaps in the shop fronts (above doors and shutters) by casting rays into the city meshes, and
## writes data/shop_patches.json: wall patches (centre, size, facing, surface layer and tint copied from the wall
## next to the gap) that city.gd builds as one extra mesh.
## Run: godot --headless --path . --script res://tools/find_shop_gaps.gd

var tris:= []   # [a, b, c, aabb, uv2, color]
var grid_t:= {}  # Vector2i(2 m cell) -> indices into tris
const CELL:= 2.0


func _walk(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _load_city(layout: Dictionary) -> void:
	for c in layout["chunks"]:
		if c["far"]:
			continue
		var inst: Node = load(c["file"]).instantiate()
		var ms:= []
		_walk(inst, ms)
		for mi in ms:
			var xf: Transform3D = mi.transform
			for s in mi.mesh.get_surface_count():
				var a: Array = mi.mesh.surface_get_arrays(s)
				var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var I: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				var U2 = a[Mesh.ARRAY_TEX_UV2]
				var C = a[Mesh.ARRAY_COLOR]
				var mat = mi.mesh.surface_get_material(s)
				var mname: String = mat.resource_name if mat else ""
				for t in range(0, I.size(), 3):
					var p0:= xf * V[I[t]]
					var p1:= xf * V[I[t + 1]]
					var p2:= xf * V[I[t + 2]]
					if maxf(p0.y, maxf(p1.y, p2.y)) < 1.5 or minf(p0.y, minf(p1.y, p2.y)) > 5.0:
						continue
					var bb:= AABB(p0, Vector3.ZERO).expand(p1).expand(p2)
					var ti:= tris.size()
					tris.append([p0, p1, p2, bb, U2[I[t]] if U2 != null else Vector2.ZERO, C[I[t]] if C != null else Color.WHITE, mname])
					for cx in range(floori(bb.position.x / CELL), floori(bb.end.x / CELL) + 1):
						for cz in range(floori(bb.position.z / CELL), floori(bb.end.z / CELL) + 1):
							var k:= Vector2i(cx, cz)
							if not grid_t.has(k):
								grid_t[k] = PackedInt32Array()
							grid_t[k].append(ti)
		inst.free()


func _cast(from: Vector3, dir: Vector3, length: float) -> Array:
	var best:= length
	var hit_t:= []
	var to:= from + dir * length
	var seen:= {}
	# walk the 2 m cells along the (horizontal) ray
	var n:= int(length / (CELL * 0.5)) + 2
	for i in n + 1:
		var q:= from.lerp(to, float(i) / n)
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
					if h != null:
						var d:= from.distance_to(h)
						if d < best:
							best = d
							hit_t = t
	return [best, hit_t]


func _init() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/layout.json"))
	_load_city(layout)
	print("triangles ", tris.size())
	var patches:= []
	for sh in layout["shops"]:
		var p:= Vector3(float(sh[2]), 0.0, float(sh[3]))
		var out:= Vector3(float(sh[4]), 0.0, float(sh[5]))
		var tan:= Vector3(-out.z, 0.0, out.x)
		var w:= float(sh[6])
		# depth of the facade at sign height, for reference
		var ref:= _cast(p + out * 2.0 + Vector3(0, 3.6, 0), -out, 6.0)
		var face_d: float = ref[0]
		var grid:= {}
		var steps_u:= int((w + 3.0) / 0.1)
		for iu in steps_u:
			var u:= -w * 0.5 - 1.5 + iu * 0.1
			for ih in 17:
				var h:= 2.0 + ih * 0.1
				var r:= _cast(p + out * 2.0 + tan * u + Vector3(0, h, 0), -out, 6.0)
				# through the wall line by more than 1.2 m: nothing closes the bay here
				if r[0] > face_d + 1.2:
					grid[Vector2i(iu, ih)] = true
		if grid.is_empty():
			continue
		# bounding box of the gap cells (gaps are rectangular bays)
		var mn:= Vector2i(9999, 9999)
		var mx:= Vector2i(-1, -1)
		for k in grid:
			mn = Vector2i(mini(mn.x, k.x), mini(mn.y, k.y))
			mx = Vector2i(maxi(mx.x, k.x), maxi(mx.y, k.y))
		var u0:= -w * 0.5 - 1.5 + mn.x * 0.1 - 0.06
		var u1:= -w * 0.5 - 1.5 + mx.x * 0.1 + 0.06
		var h0:= 2.0 + mn.y * 0.1 - 0.06
		var h1:= 2.0 + mx.y * 0.1 + 0.06
		# the wall next to the gap gives the surface layer and tint
		var side:= _cast(p + out * 2.0 + tan * (u0 - 0.3) + Vector3(0, (h0 + h1) * 0.5, 0), -out, 6.0)
		if side[1].is_empty():
			side = ref
		var uv2: Vector2 = side[1][4] if not side[1].is_empty() else Vector2(0, 0)
		var col: Color = side[1][5] if not side[1].is_empty() else Color.WHITE
		var centre:= p + out * (2.0 - face_d - 0.06) + tan * ((u0 + u1) * 0.5) + Vector3(0, (h0 + h1) * 0.5, 0)
		# only strips above the shop fronts; a gap the full height of the scan is an alley or a side street
		if h1 - h0 > 0.6:
			continue
		patches.append({"shop": sh[0], "c": [centre.x, centre.y, centre.z], "w": u1 - u0, "h": h1 - h0,
			"out": [out.x, out.z], "uv2": [uv2.x, uv2.y], "col": [col.r, col.g, col.b, col.a], "cells": grid.size()})
		print("GAP ", sh[0], " at ", centre, " w ", snappedf(u1 - u0, 0.01), " h ", snappedf(h1 - h0, 0.01), " cells ", grid.size())
	var f:= FileAccess.open("res://data/shop_patches.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(patches, " "))
	f.close()
	print("PATCHES ", patches.size())
	quit()
