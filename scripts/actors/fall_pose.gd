class_name FallPoseModifier
extends SkeletonModifier3D

var weight:= 0.0
var _t:= 0.0
var _ids:= {}

func _ready() -> void:
	var sk:= get_skeleton()
	if sk == null:
		return
	for n in ["upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r", "thigh_l", "calf_l", "thigh_r", "calf_r", "foot_l", "foot_r"]:
		_ids[n] = sk.find_bone(n)

func _aim(sk: Skeleton3D, bone: int, child: int, want_s: Vector3, w: float) -> void:
	if bone < 0 or child < 0 or w <= 0.001:
		return
	var g:= sk.get_bone_global_pose(bone)
	var cur:= sk.get_bone_global_pose(child).origin - g.origin
	if cur.length() < 0.0001:
		return
	var q:= Quaternion(cur.normalized(), want_s.normalized())
	q = Quaternion.IDENTITY.slerp(q, w)
	var nb:= Basis(q) * g.basis
	var par:= sk.get_bone_parent(bone)
	var pb:= sk.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(bone, (pb.inverse() * nb).get_rotation_quaternion())

func _process_modification() -> void:
	var sk:= get_skeleton()
	if sk == null or weight <= 0.001 or _ids.is_empty():
		return
	_t += get_process_delta_time() if is_inside_tree() else 0.016
	var inv:= sk.global_transform.basis.inverse()
	var ul: int = _ids["upperarm_l"]
	var ur: int = _ids["upperarm_r"]
	if ul < 0 or ur < 0:
		return

	var pl:= sk.global_transform * sk.get_bone_global_pose(ul).origin
	var pr:= sk.global_transform * sk.get_bone_global_pose(ur).origin
	var right:= (pr - pl)
	right.y = 0.0
	if right.length() < 0.001:
		return
	right = right.normalized()
	var up:= Vector3.UP
	var fwd:= up.cross(right)
	var w:= smoothstep(0.0, 1.0, weight)
	for side: float in [-1.0, 1.0]:
		var s:= "l" if side < 0.0 else "r"
		var ph:= _t * (2.1 if side < 0.0 else 1.7) + (0.0 if side < 0.0 else 1.9)
		var lift:= 0.22 + 0.1 * sin(ph)
		var reach:= 0.3 + 0.15 * sin(ph * 0.73 + 0.8)
		var upper_w: Vector3 = right * side * 0.82 + up * lift + fwd * reach
		var fore_w: Vector3 = upper_w.normalized() + up * (0.22 + 0.1 * sin(ph + 1.2)) + fwd * 0.55
		_aim(sk, _ids["upperarm_" + s], _ids["lowerarm_" + s], inv * upper_w, w)
		_aim(sk, _ids["lowerarm_" + s], _ids["hand_" + s], inv * fore_w, w * 0.9)

	var lt: int = _ids["thigh_l"]
	var rt: int = _ids["thigh_r"]
	if lt >= 0 and rt >= 0:
		var lw:= (-up + fwd * 0.8 + right * -0.06).normalized()
		var rw:= (-up + fwd * 0.15 + right * 0.06).normalized()
		_aim(sk, lt, _ids["calf_l"], inv * lw, w * 0.85)
		_aim(sk, rt, _ids["calf_r"], inv * rw, w * 0.85)
		_aim(sk, _ids["calf_l"], _ids["foot_l"], inv * (-up - fwd * 0.75).normalized(), w * 0.85)
		_aim(sk, _ids["calf_r"], _ids["foot_r"], inv * (-up - fwd * 1.0).normalized(), w * 0.85)
