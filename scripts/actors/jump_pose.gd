class_name JumpPoseModifier
extends SkeletonModifier3D
## Procedural layer for jumps and landings, applied on top of whatever clip is playing.
##   crouch  0..1  knees bend with the feet staying under the hips and the pelvis dropping (take-off load, landing)
##   tuck    0..1  knees drawn up in the air (feet go back, toes point down)
##   arms    -1..1 arms swing back (negative, while loading the jump) or forward and up (positive, in the air)
## The owner animates these numbers; this script only turns them into bone rotations.

var crouch:= 0.0
var tuck:= 0.0
var arms:= 0.0
var weight:= 1.0

var _ids:= {}
var _leg_len:= 0.9


func _ready() -> void:
	var sk:= get_skeleton()
	if sk == null:
		return
	for n in ["pelvis", "spine_01", "spine_02", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r",
			"upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r"]:
		_ids[n] = sk.find_bone(n)
	if _ids["thigh_l"] >= 0 and _ids["calf_l"] >= 0 and _ids["foot_l"] >= 0:
		var a:= sk.get_bone_global_rest(_ids["thigh_l"]).origin
		var b:= sk.get_bone_global_rest(_ids["calf_l"]).origin
		var c:= sk.get_bone_global_rest(_ids["foot_l"]).origin
		_leg_len = a.distance_to(b) + b.distance_to(c)


func _turn(sk: Skeleton3D, b: int, axis: Vector3, angle: float) -> void:
	if b < 0 or absf(angle) < 0.0001:
		return
	var g:= sk.get_bone_global_pose(b)
	var nb:= Basis(axis, angle) * g.basis.orthonormalized()
	var par:= sk.get_bone_parent(b)
	var pb:= sk.get_bone_global_pose(par).basis.orthonormalized() if par >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(b, (pb.inverse() * nb).get_rotation_quaternion())


func _p(sk: Skeleton3D, n: String) -> Vector3:
	return sk.get_bone_global_pose(_ids[n]).origin


func _process_modification() -> void:
	var sk:= get_skeleton()
	if sk == null or _ids.is_empty() or _ids["pelvis"] < 0 or _ids["thigh_l"] < 0 or _ids["thigh_r"] < 0:
		return
	var c:= clampf(crouch, 0.0, 1.0) * weight
	var t:= clampf(tuck, 0.0, 1.0) * weight
	var ar:= clampf(arms, -1.0, 1.0) * weight
	if c < 0.002 and t < 0.002 and absf(ar) < 0.002:
		return
	var up:= Vector3.UP
	var right:= _p(sk, "thigh_r") - _p(sk, "thigh_l")
	right -= up * right.dot(up)
	if right.length() < 0.01:
		return
	right = right.normalized()
	var fwd:= up.cross(right)
	if _ids["ball_l"] >= 0 and (_p(sk, "ball_l") - _p(sk, "foot_l")).dot(fwd) < 0.0:
		fwd = -fwd
		right = -right
	# rotations about +right: positive swings a hanging limb forward (see posture.gd)
	var a:= c * deg_to_rad(36.0)                  # load: thigh forward, shin back by twice that, foot flat
	var tk:= t * deg_to_rad(42.0)                 # tuck: thigh up, shin folded under
	var drop:= _leg_len * (1.0 - cos(a)) * 0.92
	# pelvis down so the feet stay on the ground while the knees bend
	var pel: int = _ids["pelvis"]
	var gp:= sk.get_bone_global_pose(pel)
	gp.origin -= up * drop
	gp.origin -= fwd * drop * 0.15
	var ppar:= sk.get_bone_parent(pel)
	var parent_g:= sk.get_bone_global_pose(ppar) if ppar >= 0 else Transform3D.IDENTITY
	sk.set_bone_pose_position(pel, (parent_g.affine_inverse() * gp).origin)
	# a little forward lean of the trunk to balance the bent knees
	_turn(sk, _ids["spine_01"], right, -(a * 0.45 + tk * 0.15))
	for s in ["l", "r"]:
		_turn(sk, _ids["thigh_" + s], right, a + tk)
		_turn(sk, _ids["calf_" + s], right, -2.0 * a - tk * 1.75)
		_turn(sk, _ids["foot_" + s], right, a - tk * 0.25)
	# arms: back while loading, forward-up in flight, elbows bend with it
	if absf(ar) > 0.002:
		for s in ["l", "r"]:
			var side:= -1.0 if s == "l" else 1.0
			var ua: int = _ids["upperarm_" + s]
			if ua < 0:
				continue
			if ar > 0.0:
				_turn(sk, ua, right, ar * deg_to_rad(38.0))
				_turn(sk, ua, fwd, -side * ar * deg_to_rad(14.0))
				_turn(sk, _ids["lowerarm_" + s], right, ar * deg_to_rad(30.0))
			else:
				_turn(sk, ua, right, ar * deg_to_rad(30.0))
				_turn(sk, _ids["lowerarm_" + s], right, -ar * deg_to_rad(12.0))
