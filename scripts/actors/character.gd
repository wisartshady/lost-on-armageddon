class_name CharacterVisual
extends Node3D

const TEX:= "res://assets/textures/characters/"
const PROFILES:= {
	"vaynara": {"model": "vaynara", "skin": "female_fair", "body": "female", "hair_tex": "hair2", "eye": "eye_teal",
		"hair": Color(0.86, 0.68, 0.42), "brow": Color(0.46, 0.35, 0.23), "skin_tint": Color(1.0, 1.0, 1.0), "hand_tint": Color(1.08, 0.98, 0.9),
		"top": Color(0.15, 0.16, 0.155), "bottom": Color(0.11, 0.13, 0.19),
		"shoes": Color(0.055, 0.05, 0.045), "detail": Color(0.78, 0.77, 0.74), "height": 1.74, "hero": true},
	"gus": {"model": "gus", "skin": "male_light", "body": "male", "hair_tex": "hair1", "eye": "eye_brown",
		"hair": Color(1.15, 1.13, 1.1), "top": Color(0.24, 0.18, 0.12), "bottom": Color(0.17, 0.16, 0.14),
		"shoes": Color(0.08, 0.06, 0.05), "detail": Color(0.13, 0.2, 0.15), "height": 1.74},
	"lin": {"model": "lin", "skin": "female_light", "body": "female", "hair_tex": "hair2", "eye": "eye_brown",
		"hair": Color(0.38, 0.36, 0.36), "top": Color(0.07, 0.27, 0.2), "bottom": Color(0.09, 0.07, 0.07),
		"shoes": Color(0.05, 0.04, 0.04), "detail": Color(0.12, 0.1, 0.1), "height": 1.57},
	"ped_m": {"model": "ped_m", "skin": "male_light", "body": "male", "hair_tex": "hair1", "eye": "eye_brown",
		"hair": Color(0.3, 0.22, 0.15), "top": Color(0.1, 0.11, 0.14), "bottom": Color(0.14, 0.14, 0.15),
		"shoes": Color(0.05, 0.04, 0.04), "detail": Color(0.5, 0.5, 0.5), "height": 1.8},
	"ped_m2": {"model": "ped_m2", "skin": "male_dark", "body": "male", "hair_tex": "hair1", "eye": "eye_brown",
		"hair": Color(0.15, 0.12, 0.1), "top": Color(0.28, 0.22, 0.14), "bottom": Color(0.1, 0.1, 0.12),
		"shoes": Color(0.05, 0.04, 0.04), "detail": Color(0.5, 0.5, 0.5), "height": 1.78},
	"ped_f": {"model": "ped_f", "skin": "female_light", "body": "female", "hair_tex": "hair2", "eye": "eye_brown",
		"hair": Color(0.2, 0.14, 0.1), "top": Color(0.35, 0.08, 0.08), "bottom": Color(0.08, 0.08, 0.1),
		"shoes": Color(0.05, 0.04, 0.04), "detail": Color(0.5, 0.5, 0.5), "height": 1.68},

	"cop_m": {"model": "cop_m", "skin": "male_light", "body": "male", "hair_tex": "hair1", "eye": "eye_brown",
		"hair": Color(0.2, 0.15, 0.1), "top": Color(0.05, 0.07, 0.15), "bottom": Color(0.05, 0.06, 0.12),
		"shoes": Color(0.02, 0.02, 0.02), "detail": Color(0.05, 0.06, 0.13), "height": 1.82},
	"cop_m2": {"model": "cop_m", "skin": "male_dark", "body": "male", "hair_tex": "hair1", "eye": "eye_brown",
		"hair": Color(0.08, 0.06, 0.05), "top": Color(0.05, 0.07, 0.15), "bottom": Color(0.05, 0.06, 0.12),
		"shoes": Color(0.02, 0.02, 0.02), "detail": Color(0.05, 0.06, 0.13), "height": 1.77},
	"cop_f": {"model": "cop_f", "skin": "female_light", "body": "female", "hair_tex": "hair2", "eye": "eye_brown",
		"hair": Color(0.32, 0.22, 0.14), "top": Color(0.05, 0.07, 0.15), "bottom": Color(0.05, 0.06, 0.12),
		"shoes": Color(0.02, 0.02, 0.02), "detail": Color(0.05, 0.06, 0.13), "height": 1.69},
	"firefighter": {"model": "firefighter", "skin": "male_dark", "body": "male", "hair_tex": "hair1", "eye": "eye_brown",
		"hair": Color(0.08, 0.06, 0.05), "top": Color(0.42, 0.34, 0.2), "bottom": Color(0.4, 0.33, 0.2),
		"shoes": Color(0.03, 0.03, 0.03), "detail": Color(0.04, 0.04, 0.04), "height": 1.84},
	"csi": {"model": "csi", "skin": "female_light", "body": "female", "hair_tex": "hair2", "eye": "eye_brown",
		"hair": Color(0.2, 0.14, 0.1), "top": Color(0.86, 0.87, 0.88), "bottom": Color(0.86, 0.87, 0.88),
		"shoes": Color(0.45, 0.55, 0.8), "detail": Color(0.86, 0.87, 0.88), "height": 1.7},
}
const COAT_COLOURS:= [Color(0.1, 0.11, 0.14), Color(0.32, 0.25, 0.16), Color(0.35, 0.08, 0.08), Color(0.16, 0.16, 0.16),
		Color(0.12, 0.2, 0.15), Color(0.42, 0.36, 0.28), Color(0.08, 0.08, 0.09)]
const FP_HIDDEN:= ["Head", "Hair", "Brows", "Eyes", "Lashes", "Beard", "Beanie", "Collar", "Hood", "Strings"]

var profile:= {}
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var current:= ""
var action_lock:= 0.0
var _speed_scale:= 1.0
static var _tex_cache:= {}

static func _tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load(TEX + name + ".png")
	return _tex_cache[name]

func setup(profile_name: String, overrides: Dictionary = {}) -> void:
	profile = PROFILES[profile_name].duplicate()
	for k in overrides:
		profile[k] = overrides[k]
	var scn: PackedScene = load("res://assets/models/characters/%s.scn" % profile["model"])
	model = scn.instantiate()
	add_child(model)
	model.rotation.y = PI
	var s: float = profile["height"] / (1.767 if profile["body"] == "female" else 1.81)
	model.scale = Vector3(s, s, s)
	skeleton = _find_skeleton(model)
	_collect_meshes(model)
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		mi.custom_aabb = AABB(Vector3(-1.2, -0.3, -1.2), Vector3(2.4, 2.6, 2.4))
		for i in mi.mesh.get_surface_count():
			var m:= mi.mesh.surface_get_material(i)
			mi.set_surface_override_material(i, _material(m.resource_name if m else "skin"))
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	model.add_child(anim)
	anim.add_animation_library("", AnimLib.get_library())
	anim.playback_default_blend_time = 0.2

	if not profile.get("hero", false):
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		set_process(true)
		_lod_phase = randf() * 0.2
	else:
		set_process(false)

	for mi in meshes:
		var nm:= str(mi.name).to_lower()
		var mat0:= mi.mesh.surface_get_material(0) if mi.mesh.get_surface_count() > 0 else null
		var slot:= mat0.resource_name if mat0 else ""
		if slot in ["eyes", "brows"] or nm.contains("eye") or nm.contains("brow"):
			mi.visibility_range_end = 15.0
			mi.visibility_range_end_margin = 2.0
		elif not profile.get("hero", false):

			mi.visibility_range_end = clampf(float(Settings.g.get("view_distance", 140.0)) * 0.6, 48.0, 90.0)
			mi.visibility_range_end_margin = 6.0
	play("Idle_Loop")

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r:= _find_skeleton(c)
		if r:
			return r
	return null

func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		meshes.append(n)
	for c in n.get_children():
		_collect_meshes(c)

# separate garments (tools/blender/vaynara_outfit.py): slot -> fabric, colour, inside colour, tiles per metre,
# roughness, specular, metallic, pattern (0 cloth, 1 zip, 2 skin)
const GARMENTS:= {
	"skin_flat": ["", Color(0.72, 0.6, 0.52), Color(0.4, 0.3, 0.26), 1.0, 0.55, 0.35, 0.0, 2],
	"crop": ["crop", Color(0.42, 0.075, 0.08), Color(0.22, 0.04, 0.045), 4.5, 0.85, 0.3, 0.0, 0],
	"hoodie": ["hoodie", Color(0.34, 0.295, 0.25), Color(0.4, 0.36, 0.31), 3.7, 0.9, 0.25, 0.0, 0],
	"zipper": ["", Color(0.3, 0.265, 0.225), Color(0.2, 0.18, 0.16), 1.0, 0.8, 0.3, 0.0, 1],
	"string": ["crop", Color(0.3, 0.3, 0.31), Color(0.2, 0.2, 0.2), 9.0, 0.9, 0.25, 0.0, 0],
	"denim": ["denim", Color(0.075, 0.08, 0.115), Color(0.06, 0.065, 0.08), 3.7, 0.88, 0.3, 0.0, 0],
	"leather": ["leather", Color(0.07, 0.062, 0.056), Color(0.08, 0.07, 0.065), 3.0, 0.72, 0.3, 0.0, 0],
	"metal": ["", Color(0.6, 0.6, 0.62), Color(0.3, 0.3, 0.3), 1.0, 0.35, 0.6, 0.9, 0],
}

func _garment(slot: String) -> ShaderMaterial:
	var g: Array = GARMENTS[slot]
	var m:= ShaderMaterial.new()
	m.shader = preload("res://shaders/garment.gdshader")
	m.set_shader_parameter("detail_tex", _tex("../detail_noise"))
	if g[0] != "":
		m.set_shader_parameter("fabric_tex", _tex("fabric_" + g[0]))
		m.set_shader_parameter("fabric_n", _tex("fabric_" + g[0] + "_n"))
	else:
		m.set_shader_parameter("use_fabric", false)
	m.set_shader_parameter("color", g[1])
	m.set_shader_parameter("inner_color", g[2])
	m.set_shader_parameter("tile", g[3])
	m.set_shader_parameter("roughness_v", g[4])
	m.set_shader_parameter("specular_v", g[5])
	m.set_shader_parameter("metallic_v", g[6])
	m.set_shader_parameter("pattern", g[7])
	if profile.get("hero", false):
		m.set_shader_parameter("rim", 0.85)
		m.set_shader_parameter("fill", 1.8)
		m.set_shader_parameter("view_fill", 0.45)
	return m

# realistic head and body (MakeHuman CC0 assets, tools/blender/vaynara_build.py)
func _mh(slot: String) -> ShaderMaterial:
	var m:= ShaderMaterial.new()
	var hero: bool = profile.get("hero", false)
	if slot in ["mh_hair", "mh_brow", "mh_lash", "mh_eye"]:
		m.shader = preload("res://shaders/hair.gdshader")
		m.set_shader_parameter("albedo_tex", _tex(slot))
		match slot:
			"mh_eye":
				# the cornea is the transparent part of the texture: alpha tested away, the iris shows through
				m.set_shader_parameter("color", Color(1, 1, 1))
				m.set_shader_parameter("desaturate", 0.0)
				m.set_shader_parameter("alpha_cut", 0.5)
				m.set_shader_parameter("highlight", 0.0)
				m.set_shader_parameter("gloss", 1.0)
			"mh_hair":
				m.set_shader_parameter("color", profile.get("hair", Color(0.82, 0.64, 0.38)))
				m.set_shader_parameter("alpha_cut", 0.4)
			"mh_brow":
				m.set_shader_parameter("color", profile.get("brow", Color(0.42, 0.32, 0.2)))
				m.set_shader_parameter("alpha_cut", 0.45)
				m.set_shader_parameter("flat_color", 1.0)
				m.set_shader_parameter("highlight", 0.05)
			"mh_lash":
				m.set_shader_parameter("color", Color(0.12, 0.1, 0.085))
				m.set_shader_parameter("flat_color", 1.0)
				m.set_shader_parameter("alpha_cut", 0.3)
				m.set_shader_parameter("highlight", 0.0)
	else:
		m.shader = preload("res://shaders/character.gdshader")
		m.set_shader_parameter("detail_tex", _tex("../detail_noise"))
		m.set_shader_parameter("use_normal", false)
		m.set_shader_parameter("albedo_tex", _tex("mh_skin"))
		m.set_shader_parameter("color", profile.get("skin_tint", Color(1.0, 1.0, 1.0)))
		m.set_shader_parameter("roughness_v", 0.58)
		m.set_shader_parameter("specular_v", 0.32)
		m.set_shader_parameter("wet_response", 0.7)
	if hero:
		m.set_shader_parameter("rim", 0.85 if slot != "mh_lash" else 0.0)
		m.set_shader_parameter("fill", 1.8)
		m.set_shader_parameter("view_fill", 0.45)
	return m

func _material(slot: String) -> ShaderMaterial:
	if GARMENTS.has(slot):
		return _garment(slot)
	if slot.begins_with("mh_"):
		return _mh(slot)
	var m:= ShaderMaterial.new()
	m.shader = preload("res://shaders/character.gdshader")
	m.set_shader_parameter("detail_tex", _tex("../detail_noise"))
	match slot:
		"skin":
			var b: String = profile["body"]
			m.set_shader_parameter("albedo_tex", _tex(profile["skin"]))
			m.set_shader_parameter("normal_tex", _tex(b + "_n"))
			m.set_shader_parameter("rough_tex", _tex(b + "_r"))
			m.set_shader_parameter("use_rough", true)
			m.set_shader_parameter("specular_v", 0.35)
			m.set_shader_parameter("wet_response", 0.7)
			m.set_shader_parameter("color", profile.get("hand_tint", Color(1, 1, 1)))
		"eyes":
			m.set_shader_parameter("albedo_tex", _tex(profile["eye"]))
			m.set_shader_parameter("normal_tex", _tex("eye_n"))
			m.set_shader_parameter("roughness_v", 0.08)
			m.set_shader_parameter("specular_v", 0.8)
			m.set_shader_parameter("rim", 0.0)
		"hair", "brows":
			m.set_shader_parameter("albedo_tex", _tex(profile["hair_tex"]))
			m.set_shader_parameter("normal_tex", _tex(profile["hair_tex"] + "_n"))
			m.set_shader_parameter("color", profile["hair"])
			m.set_shader_parameter("roughness_v", 0.55)
			m.set_shader_parameter("specular_v", 0.45)
			m.set_shader_parameter("wet_response", 0.9)
		"cloth":
			m.set_shader_parameter("cloth_mode", true)
			m.set_shader_parameter("albedo_tex", _tex(profile["model"] + "_cloth"))
			m.set_shader_parameter("normal_tex", _tex(profile["model"] + "_cloth_n"))
			m.set_shader_parameter("use_normal", true)
			m.set_shader_parameter("top_col", profile["top"])
			m.set_shader_parameter("bottom_col", profile["bottom"])
			m.set_shader_parameter("shoes_col", profile["shoes"])
			m.set_shader_parameter("roughness_v", 0.93)
			m.set_shader_parameter("specular_v", 0.18)
			m.set_shader_parameter("wet_response", 0.8)
		_:
			var key: String = {"cloth_top": "top", "cloth_bottom": "bottom", "cloth_shoes": "shoes", "cloth_detail": "detail"}.get(slot, "top")
			m.set_shader_parameter("use_albedo", false)
			m.set_shader_parameter("use_normal", false)
			m.set_shader_parameter("use_detail", true)
			m.set_shader_parameter("detail_scale", 22.0 if slot != "cloth_shoes" else 8.0)
			m.set_shader_parameter("color", profile[key])
			m.set_shader_parameter("roughness_v", 0.92 if slot != "cloth_shoes" else 0.45)
			m.set_shader_parameter("specular_v", 0.3 if slot != "cloth_shoes" else 0.55)
			m.set_shader_parameter("wet_response", 0.8)
	if profile.get("hero", false) and slot != "eyes":
		m.set_shader_parameter("rim", 0.85)
		m.set_shader_parameter("fill", 1.8)
		m.set_shader_parameter("view_fill", 0.45)
	return m

var _lod_acc:= 0.0
var _lod_phase:= 0.0

func _process(delta: float) -> void:
	_lod_acc += delta
	var interval:= 0.0
	var cam:= get_viewport().get_camera_3d()
	if cam:
		var p:= global_position + Vector3(0, 1.0, 0)
		var d:= cam.global_position.distance_to(p)
		if not cam.is_position_in_frustum(p) and d > 2.5:
			interval = 0.25 if d < 30.0 else 0.5
		elif d > 50.0:
			interval = 1.0 / 10.0
		elif d > 28.0:
			interval = 1.0 / 15.0
		elif d > 14.0:
			interval = 1.0 / 30.0
	if _lod_acc + _lod_phase >= interval:
		anim.advance(_lod_acc)
		_lod_acc = 0.0
		_lod_phase = 0.0

func set_first_person(on: bool) -> void:
	for mi in meshes:
		if mi.name in FP_HIDDEN:
			mi.layers = 2 if on else 1

func play(name: String, blend:= -1.0, speed:= 1.0) -> void:
	if not anim.has_animation(name):
		return
	if current == name:
		anim.speed_scale = speed
		return
	current = name
	anim.play(name, blend)
	anim.speed_scale = speed

func play_action(name: String, lock_time:= -1.0, blend:= 0.15) -> void:
	if not anim.has_animation(name):
		return
	current = name
	anim.play(name, blend)
	anim.speed_scale = 1.0
	action_lock = lock_time if lock_time > 0.0 else anim.get_animation(name).length - 0.15

func locomotion(speed: float, on_floor: bool, crouch: bool, delta: float) -> void:
	if action_lock > 0.0:
		action_lock -= delta
		return
	if not on_floor:

		if not (current.begins_with("MJump") or current.begins_with("MLand") or current == "Jump_Loop"):
			var air:= "MJump_Run_Air" if speed > 1.2 else "MJump_Stand_Air"
			if anim.has_animation(air):
				play(air, 0.25, 0.6)
				anim.seek(anim.get_animation(air).length * 0.45, false)
			else:
				play("Jump_Loop", 0.25)
		return
	if crouch:
		if speed > 0.3:
			play("Crouch_Fwd_Loop", 0.2, clampf(speed / 1.1, 0.6, 1.6))
		else:
			play("Crouch_Idle_Loop", 0.25)
		return
	if speed < 0.25:
		play("Idle_Loop", 0.3)
	elif speed < 2.6:
		play("Walk_Loop", 0.25, clampf(speed / 1.45, 0.6, 1.7))
	elif speed < 4.6:
		play("Jog_Fwd_Loop", 0.25, clampf(speed / 3.4, 0.7, 1.5))
	else:
		play("Sprint_Loop", 0.2, clampf(speed / 6.0, 0.7, 1.4))

const HITBOXES:= [
	["Head", 0.11, 0.0, Vector3(0, 0.09, 0.01)], ["neck_01", 0.06, 0.12, Vector3(0, 0.05, 0)],
	["spine_03", 0.15, 0.3, Vector3(0, 0.1, 0.0)], ["spine_01", 0.14, 0.28, Vector3(0, 0.08, 0)],
	["pelvis", 0.15, 0.3, Vector3(0, 0.0, 0)],
	["upperarm_l", 0.055, 0.3, Vector3(0, 0.14, 0)], ["upperarm_r", 0.055, 0.3, Vector3(0, 0.14, 0)],
	["lowerarm_l", 0.045, 0.28, Vector3(0, 0.13, 0)], ["lowerarm_r", 0.045, 0.28, Vector3(0, 0.13, 0)],
	["hand_l", 0.045, 0.0, Vector3(0, 0.08, 0)], ["hand_r", 0.045, 0.0, Vector3(0, 0.08, 0)],
	["thigh_l", 0.08, 0.44, Vector3(0, 0.21, 0)], ["thigh_r", 0.08, 0.44, Vector3(0, 0.21, 0)],
	["calf_l", 0.06, 0.42, Vector3(0, 0.2, 0)], ["calf_r", 0.06, 0.42, Vector3(0, 0.2, 0)],
	["foot_l", 0.05, 0.2, Vector3(0, 0.07, 0.03)], ["foot_r", 0.05, 0.2, Vector3(0, 0.07, 0.03)],
]
var hitboxes: Array[Area3D] = []

func build_hitboxes(owner_node: Node = null) -> void:
	if not hitboxes.is_empty() or skeleton == null:
		return
	for hb in HITBOXES:
		if skeleton.find_bone(hb[0]) < 0:
			continue
		var ba:= BoneAttachment3D.new()
		ba.bone_name = hb[0]
		skeleton.add_child(ba)
		var area:= Area3D.new()
		area.collision_layer = 16
		area.collision_mask = 0
		area.monitoring = false
		area.set_meta("bone", hb[0])
		area.set_meta("owner", owner_node if owner_node else self)
		var cs:= CollisionShape3D.new()
		if float(hb[2]) <= 0.0:
			var sp:= SphereShape3D.new()
			sp.radius = hb[1]
			cs.shape = sp
		else:
			var cap:= CapsuleShape3D.new()
			cap.radius = hb[1]
			cap.height = maxf(hb[2], hb[1] * 2.0 + 0.01)
			cs.shape = cap
		cs.position = hb[3]
		area.add_child(cs)
		ba.add_child(area)
		hitboxes.append(area)

func bone_global(name: String) -> Transform3D:
	if skeleton == null:
		return global_transform
	var i:= skeleton.find_bone(name)
	if i < 0:
		return global_transform
	return skeleton.global_transform * skeleton.get_bone_global_pose(i)

func attach_to_bone(bone: String, node: Node3D) -> BoneAttachment3D:
	var ba:= BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	ba.add_child(node)
	return ba
