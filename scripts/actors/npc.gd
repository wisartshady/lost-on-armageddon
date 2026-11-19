class_name Npc
extends Node3D

var id:= ""
var visual: CharacterVisual
var idle_anim:= "Idle_Loop"
var talk_anim:= "Idle_Talking_Loop"
var talking:= false
var _home_yaw:= 0.0
var player: Node3D

func setup(npc_id: String, profile: String, pos: Vector3, yaw: float, idle:= "Idle_Loop", talk:= "Idle_Talking_Loop") -> void:
	id = npc_id
	idle_anim = idle
	talk_anim = talk
	visual = CharacterVisual.new()
	add_child(visual)
	visual.setup(profile)
	global_position = pos
	rotation.y = yaw
	_home_yaw = yaw
	visual.play(idle_anim)
	var body:= StaticBody3D.new()
	body.collision_layer = 1
	var cs:= CollisionShape3D.new()
	var cap:= CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	body.add_child(cs)
	add_child(body)
	visual.build_hitboxes(self)

func set_talking(on: bool, speaking:= false) -> void:
	talking = on
	if on and speaking:
		visual.play(talk_anim, 0.3)
	else:
		visual.play(idle_anim, 0.4)

func _process(delta: float) -> void:
	Prof.b("npcs")
	if player == null:
		Prof.e("npcs")
		return
	var target:= _home_yaw
	var to:= player.global_position - global_position
	if talking or to.length() < 3.5:
		target = atan2(-to.x, -to.z)
	if idle_anim.begins_with("Sitting"):
		Prof.e("npcs")
		return
	rotation.y = lerp_angle(rotation.y, target, clampf(3.0 * delta, 0.0, 1.0))
	Prof.e("npcs")
