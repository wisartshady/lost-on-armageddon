class_name AnimLib
extends RefCounted

static var _lib: AnimationLibrary = null

const LOOPS:= ["Idle_Loop", "Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Crouch_Idle_Loop", "Crouch_Fwd_Loop",
		"Idle_Talking_Loop", "Idle_Torch_Loop", "Jump_Loop", "Sitting_Idle_Loop", "Sitting_Talking_Loop",
		"Spell_Simple_Idle_Loop", "Walk_Formal_Loop", "Push_Loop", "Dance_Loop", "Driving_Loop", "Pistol_Idle_Loop",
		"Swim_Idle_Loop", "Swim_Fwd_Loop"]

static var root_curves:= {}
static var _mocap_rm:= {}

static func mocap_curve(clip: String) -> PackedVector3Array:
	if _mocap_rm.is_empty():
		var f:= FileAccess.open("res://data/mocap_rm.json", FileAccess.READ)
		if f:
			_mocap_rm = JSON.parse_string(f.get_as_text())
	var out:= PackedVector3Array()
	var e: Dictionary = _mocap_rm.get(clip, {})
	for v in e.get("rm", []):
		out.append(Vector3(v[0], v[1], v[2]))
	return out
const EXTRA_CLIPS:= ["ClimbUp_1m_RM", "Idle_TalkingPhone_Loop", "Idle_FoldArms_Loop", "Idle_Lantern_Loop", "Idle_Rail_Loop",
		"NinjaJump_Start", "NinjaJump_Land", "Yes", "Consume"]

static func get_library() -> AnimationLibrary:
	if _lib != null:
		return _lib
	_lib = AnimationLibrary.new()
	_load_file("res://assets/models/anim/UAL1_Standard.scn", [])
	_load_file("res://assets/models/anim/UAL2_Standard.scn", EXTRA_CLIPS)

	if ResourceLoader.exists("res://assets/models/anim/Mocap_CMU.scn"):
		_load_file("res://assets/models/anim/Mocap_CMU.scn", [])
	return _lib

static func _load_file(path: String, only: Array) -> void:
	var scn: PackedScene = load(path)
	if scn == null:
		return
	var inst:= scn.instantiate()
	var ap:= _find_player(inst)
	if ap:
		for lib_name in ap.get_animation_library_list():
			var src:= ap.get_animation_library(lib_name)
			for an in src.get_animation_list():
				var a: Animation = src.get_animation(an).duplicate(true)
				var clean:= String(an).get_slice("|", String(an).get_slice_count("|") - 1)

				if a.loop_mode != Animation.LOOP_NONE and not clean.ends_with("_Loop"):
					clean += "_Loop"
				if not only.is_empty() and not clean in only:
					continue
				if _lib.has_animation(clean):
					continue
				a.loop_mode = Animation.LOOP_LINEAR if clean in LOOPS or clean.ends_with("_Loop") else Animation.LOOP_NONE
				if clean.ends_with("_RM"):
					root_curves[clean] = _sample_root(a)
				_strip_root_motion(a)
				_lib.add_animation(clean, a)
	inst.free()

static func _sample_root(a: Animation) -> PackedVector3Array:
	var out:= PackedVector3Array()
	for t in a.get_track_count():
		var p:= String(a.track_get_path(t))
		if p.ends_with(":root") and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			var n:= 32
			for i in n + 1:
				out.append(a.position_track_interpolate(t, a.length * float(i) / n))
			break
	return out

static func _strip_root_motion(a: Animation) -> void:

	for t in range(a.get_track_count() - 1, -1, -1):
		var p:= String(a.track_get_path(t))
		if p.ends_with(":root") and a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			a.remove_track(t)

static func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r:= _find_player(c)
		if r:
			return r
	return null
