class_name FootPlant
extends RefCounted

var sk: Skeleton3D
var root: Node3D
var ids:= PackedInt32Array([-1, -1])
var lo:= PackedFloat32Array([0.0, 0.0])
var hi:= PackedFloat32Array([0.15, 0.15])
var lifted:= [false, false]
var prev:= PackedFloat32Array([0.0, 0.0])
var ready:= false

func setup(skeleton: Skeleton3D, body: Node3D) -> void:
	sk = skeleton
	root = body
	if sk:
		ids[0] = sk.find_bone("foot_l")
		ids[1] = sk.find_bone("foot_r")
		ready = ids[0] >= 0 and ids[1] >= 0

func update(delta: float) -> int:
	if not ready:
		return 0
	var planted:= 0
	var base:= root.global_position.y
	for k in 2:
		var y:= (sk.global_transform * sk.get_bone_global_pose(ids[k])).origin.y - base

		lo[k] = minf(lo[k] + delta * 0.08, y)
		hi[k] = maxf(hi[k] - delta * 0.15, y)
		var rng:= hi[k] - lo[k]
		if rng > 0.035:
			if lifted[k]:

				if y < lo[k] + rng * 0.22 and y <= prev[k] + 0.002:
					lifted[k] = false
					planted += 1
			elif y > lo[k] + rng * 0.5:
				lifted[k] = true
		prev[k] = y
	return planted

func reset() -> void:
	lifted = [false, false]
