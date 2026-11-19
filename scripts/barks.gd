class_name Barks
extends Node

const VOICE_DIR:= "res://assets/voice/tr/"
var zones:= {}
var player: Node3D
var hud: Hud
var _inside:= {}
var _last_time:= {}
var _recent:= {}
var _global_cd:= 0.0
var _check_t:= 0.0
var _voice: AudioStreamPlayer

func setup(p: Node3D, h: Hud, city: City) -> void:
	player = p
	hud = h
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/barks.json"))
	for id in data:
		var z: Dictionary = data[id]
		var pos: Vector3
		if z.has("marker"):
			if not city.markers.has(z["marker"]):
				continue
			pos = city.marker(z["marker"])
		else:
			pos = Vector3(z["p"][0], z["p"][1], z["p"][2])
		z["pos"] = pos
		zones[id] = z
		_inside[id] = true
		_recent[id] = []
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	add_child(_voice)

func _process(delta: float) -> void:
	Prof.b("barks")
	if player == null:
		Prof.e("barks")
		return
	_global_cd -= delta
	_check_t -= delta
	if _check_t > 0.0:
		Prof.e("barks")
		return
	_check_t = 0.25
	var now:= Time.get_ticks_msec() / 1000.0
	for id in zones:
		var z: Dictionary = zones[id]
		var p: Vector3 = z["pos"]
		var inside:= Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length() < float(z["r"])
		if inside and not _inside[id]:
			_try(id, z, now)
		_inside[id] = inside
	Prof.e("barks")

func _try(id: String, z: Dictionary, now: float) -> void:
	if _global_cd > 0.0:
		return
	if now - float(_last_time.get(id, -9999.0)) < float(z["cooldown"]):
		return
	if randf() > float(z["chance"]):
		return
	var lines: Array = z["lines"]
	var rec: Array = _recent[id]
	var pool:= lines.filter(func (l): return not rec.has(l))
	if pool.is_empty():
		pool = lines.duplicate()
	var key: String = pool[randi() % pool.size()]
	rec.append(key)
	while rec.size() > mini(3, lines.size() - 1):
		rec.pop_front()
	_last_time[id] = now
	_global_cd = 25.0
	var vpath:= VOICE_DIR + key.to_lower() + ".ogg"
	var dur:= 2.2 + tr(key).length() / 16.0
	if ResourceLoader.exists(vpath):
		_voice.stream = load(vpath)
		_voice.play()
		dur = maxf(dur, _voice.stream.get_length() + 0.5)
	hud.show_bark(tr("NAME_VAYNARA_THOUGHT"), tr(key), dur)
