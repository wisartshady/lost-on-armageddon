class_name ArmPoseModifier
extends SkeletonModifier3D

var bone_ids: PackedInt32Array = []
var rots: Array[Quaternion] = []
var hand_id:= -1
var held: Node3D = null
var held_offset:= Vector3(0.0, 0.02, 0.0)
var sway:= 0.0

var held_tilt:= Basis.IDENTITY
var held_scale:= Vector3.ONE

func capture(visual: CharacterVisual, anim_name: String, at_time: float, side:= "r") -> void:
	var sk:= visual.skeleton
	var prev:= visual.current
	visual.anim.play(anim_name, 0.0)
	visual.anim.seek(at_time, true)
	visual.anim.advance(0.0)
	bone_ids.clear()
	rots.clear()
	for i in sk.get_bone_count():
		var n:= sk.get_bone_name(i)
		var is_arm:= n in ["clavicle_" + side, "upperarm_" + side, "lowerarm_" + side, "hand_" + side]
		var is_finger:= n.ends_with("_" + side) and (n.begins_with("index") or n.begins_with("middle") or n.begins_with("ring") or n.begins_with("pinky") or n.begins_with("thumb"))
		if is_arm or is_finger:
			bone_ids.append(i)
			rots.append(sk.get_bone_pose_rotation(i))
	hand_id = sk.find_bone("hand_" + side)
	visual.current = ""
	if prev != "":
		visual.play(prev, 0.0)

func _process_modification() -> void:
	var sk:= get_skeleton()
	if sk == null:
		return
	for k in bone_ids.size():
		sk.set_bone_pose_rotation(bone_ids[k], rots[k])
	if held and hand_id >= 0:
		var g:= sk.global_transform * sk.get_bone_global_pose(hand_id)
		var fwd:= -sk.global_transform.basis.z
		fwd.y = 0.0
		var yaw:= atan2(-fwd.x, -fwd.z) if fwd.length() > 0.01 else 0.0
		var b:= held_tilt * Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, sway) * Basis(Vector3.RIGHT, -0.08)
		held.global_transform = Transform3D(b * Basis.from_scale(held_scale), g.origin + held_offset)
