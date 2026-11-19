class_name Footsteps
extends RefCounted

const DIR:= "res://assets/audio/steps2/"
const OLD:= "res://assets/audio/steps/"
static var _cache:= {}
static var _counts:= {}
static var _last:= {}

static func _sound_set(kind: String) -> Array:
	if _cache.has(kind):
		return _cache[kind]
	if _counts.is_empty():
		var f:= FileAccess.open("res://data/steps.json", FileAccess.READ)
		if f:
			var d: Dictionary = JSON.parse_string(f.get_as_text())
			for k in d:
				_counts[k] = int(d[k]["count"])
	var arr:= []
	if _counts.has(kind):
		for i in _counts[kind]:
			var s = load(DIR + "%s_%02d.wav" % [kind, i])
			if s:
				arr.append(s)
	elif kind == "metal":
		for i in 5:
			arr.append(load(OLD + "impactMetal_light_%03d.ogg" % i))
	elif kind == "carpet":
		for i in 5:
			arr.append(load(OLD + "footstep_carpet_%03d.ogg" % i))
	if arr.is_empty():
		arr = _sound_set("concrete") if kind != "concrete" else []
	_cache[kind] = arr
	return arr

static func _route(p: AudioStreamPlayer3D) -> void:
	if p.bus == "Steps":
		return
	var i:= AudioServer.get_bus_index("Steps")
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Steps")
		AudioServer.set_bus_send(i, "SFX")
	else:
		while AudioServer.get_bus_effect_count(i) > 0:
			AudioServer.remove_bus_effect(i, 0)
	p.bus = "Steps"
	p.unit_size = 3.5
	p.max_db = 0.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.attenuation_filter_cutoff_hz = 20500.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED

static func pick(kind: String) -> AudioStream:
	var a:= _sound_set(kind)
	if a.is_empty():
		return null
	var i:= randi() % a.size()
	if a.size() > 2 and _last.get(kind, -1) == i:
		i = (i + 1 + randi() % (a.size() - 1)) % a.size()
	_last[kind] = i
	return a[i]

static func _base_for(surface: String) -> String:
	match surface:
		"asphalt", "concrete":
			return "concrete"
		"stone":
			return "stone"
		"wood":
			return "wood"
		"metal":
			return "metal"
		"carpet":
			return "carpet"
		"grass":
			return "grass"
		"dirt", "gravel":
			return "gravel"
		"mud":
			return "mud"
		"water":
			return "water"
	return "concrete"

static func step(main: AudioStreamPlayer3D, layer: AudioStreamPlayer3D, surface: String, running: bool, crouch: bool, wet: float, pace:= -1.0) -> void:
	var base:= _base_for(surface)
	var p:= pace if pace >= 0.0 else (0.8 if running else 0.25)
	var vol:= lerpf(-11.0, -5.0, clampf(p, 0.0, 1.0))
	var pitch:= randf_range(0.95, 1.05) * lerpf(0.98, 1.03, p)
	match base:
		"metal":
			vol -= 6.0
			pitch *= randf_range(0.9, 1.0)
		"wood":
			vol += 1.0
		"grass", "gravel", "mud":
			vol -= 1.0
		"water":
			vol += 1.0
	if surface == "asphalt":
		vol -= 1.0
		pitch *= 0.97
	if crouch:
		vol -= 9.0
	_route(main)
	_route(layer)
	var s:= pick(base)
	if s == null:
		return
	main.stream = s
	main.volume_db = vol
	main.pitch_scale = pitch
	main.play()
	if base == "water":

		layer.stream = pick("concrete")
		layer.volume_db = vol - 7.0
		layer.pitch_scale = randf_range(0.9, 1.0)
		layer.play()
	elif wet > 0.5 and base in ["concrete", "stone"] and randf() < 0.55:

		layer.stream = pick("water")
		layer.volume_db = vol - 15.0
		layer.pitch_scale = randf_range(1.05, 1.2)
		layer.play()

static func land(main: AudioStreamPlayer3D, layer: AudioStreamPlayer3D, surface: String, vol: float) -> void:
	_route(main)
	_route(layer)
	var base:= _base_for(surface)
	var v:= -4.0 + clampf(vol, -6.0, 0.0) * 0.5
	if base == "water":
		main.stream = pick("water")
		main.volume_db = v + 1.0
		main.pitch_scale = randf_range(0.8, 0.9)
		main.play()
		layer.stream = pick("water")
		layer.volume_db = v - 2.0
		layer.pitch_scale = randf_range(0.95, 1.05)
		layer.play()
		return
	main.stream = pick(base)
	main.volume_db = v
	main.pitch_scale = randf_range(0.8, 0.88)
	main.play()
	layer.stream = pick(base)
	layer.volume_db = v - 5.0
	layer.pitch_scale = randf_range(0.92, 1.0)
	layer.play()
