class_name PostureModifier
extends SkeletonModifier3D
## Keeps the upper body upright on top of the library animations.
## The idle / walk / run clips carry a forward stoop (rounded back, head pushed forward) that reads as hunched on
## a realistic character. Every frame this measures how far the torso leans forward of the hips and how far the head
## sits in front of the neck, and turns the spine and neck back until both match a natural target for the speed
## (upright when standing, a few degrees when walking, a clear forward lean only when sprinting).

## forward lean the torso should keep (radians), set by the owner from the movement speed
var target_lean:= deg_to_rad(2.0)
var weight:= 1.0

var _pelvis:= -1
var _spine: PackedInt32Array = []
var _neck:= -1
var _head:= -1
var _cl:= -1
var _cr:= -1
var _tl:= -1
var _tr:= -1


func _ready() -> void:
	var sk:= get_skeleton()
	if sk == null:
		return
	_pelvis = sk.find_bone("pelvis")
	for n in ["spine_01", "spine_02", "spine_03"]:
		var i:= sk.find_bone(n)
		if i >= 0:
			_spine.append(i)
	_neck = sk.find_bone("neck_01")
	_head = sk.find_bone("Head")
	_cl = sk.find_bone("clavicle_l")
	_cr = sk.find_bone("clavicle_r")
	_tl = sk.find_bone("thigh_l")
	_tr = sk.find_bone("thigh_r")


## Rotates bone `b` by `angle` about `axis` (skeleton space), keeping its parent untouched.
func _turn(sk: Skeleton3D, b: int, axis: Vector3, angle: float) -> void:
	if b < 0 or absf(angle) < 0.0001:
		return
	var g:= sk.get_bone_global_pose(b)
	var nb:= Basis(axis, angle) * g.basis
	var par:= sk.get_bone_parent(b)
	var pb:= sk.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(b, (pb.orthonormalized().inverse() * nb.orthonormalized()).get_rotation_quaternion())


func _pos(sk: Skeleton3D, b: int) -> Vector3:
	return sk.get_bone_global_pose(b).origin


func _process_modification() -> void:
	var sk:= get_skeleton()
	if sk == null or weight <= 0.001 or _pelvis < 0 or _neck < 0 or _spine.is_empty() or _tl < 0 or _tr < 0:
		return
	# body frame in skeleton space: up from the rest skeleton, right from the hips, forward from both
	var up:= Vector3.UP
	var right:= _pos(sk, _tr) - _pos(sk, _tl)
	right -= up * right.dot(up)
	if right.length() < 0.01:
		return
	right = right.normalized()
	var fwd:= up.cross(right)
	# the model is turned 180 degrees in CharacterVisual: make sure fwd points where the toes point
	var foot:= sk.find_bone("ball_l")
	if foot >= 0:
		var toe:= _pos(sk, foot) - _pos(sk, sk.find_bone("foot_l"))
		if toe.dot(fwd) < 0.0:
			fwd = -fwd
			right = -right
	# 1) torso lean: hips -> base of the neck
	var torso:= _pos(sk, _neck) - _pos(sk, _pelvis)
	var lean:= atan2(torso.dot(fwd), torso.dot(up))
	var corr:= clampf(lean - target_lean, -0.06, 0.7) * weight
	# a positive turn about +right tips the chain backwards when fwd = up x right
	var axis:= right
	var shares:= [0.3, 0.35, 0.35]
	for k in _spine.size():
		_turn(sk, _spine[k], axis, corr * shares[mini(k, 2)])
	# 2) head carriage: the head should sit over the neck, chin level
	if _head >= 0:
		var nk:= _pos(sk, _head) - _pos(sk, _neck)
		var hl:= atan2(nk.dot(fwd), nk.dot(up))
		var hc:= clampf(hl - deg_to_rad(6.0), -0.05, 0.5) * weight
		_turn(sk, _neck, axis, hc * 0.6)
		_turn(sk, _head, axis, hc * 0.4)
	# 3) shoulders a little back (rounded shoulders are most of the "hunched" look)
	for c in [_cl, _cr]:
		if c >= 0:
			var side:= signf((_pos(sk, c) - _pos(sk, _neck)).dot(right))
			_turn(sk, c, up, -side * deg_to_rad(5.0) * weight)
