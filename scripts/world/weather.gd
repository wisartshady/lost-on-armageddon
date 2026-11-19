class_name WeatherSim
extends RefCounted

const SECONDS_PER_HOUR:= 150.0
const BLEND:= 80.0

const STATES:= {
	"clear": [0.0, 0.12, 0.55, 1.0, false, 0.2],
	"cloudy": [0.0, 0.62, 0.9, 0.55, false, 0.35],
	"fog": [0.0, 0.95, 2.6, 0.22, false, 0.1],
	"drizzle": [0.32, 0.92, 1.5, 0.16, false, 0.3],
	"rain": [0.72, 1.0, 1.55, 0.1, false, 0.5],
	"storm": [1.0, 1.0, 1.75, 0.05, true, 0.8],
}
const NEXT_DAY:= {"clear": 30, "cloudy": 26, "fog": 24, "drizzle": 10, "rain": 8, "storm": 2}
const NEXT_NIGHT:= {"clear": 20, "cloudy": 24, "fog": 18, "drizzle": 14, "rain": 16, "storm": 8}

var hour:= 14.5
var state:= "fog"
var prev_state:= "fog"
var blend_t:= BLEND
var state_left:= 260.0

var rain:= 0.72
var cover:= 1.0
var fog_mult:= 1.55
var sun_amount:= 0.1
var lightning:= false
var wind:= 0.5
var wetness:= 1.0
var daylight:= 0.0
var lamp_power:= 1.0
var sun_dir:= Vector3(0, -1, 0)
var moon_dir:= Vector3(-0.3, 0.55, -0.78)

static var current: WeatherSim

func _s(name: String, i: int):
	return STATES[name][i]

func _pick_next() -> String:
	var table: Dictionary = NEXT_DAY if (hour >= 6.0 and hour < 18.0) else NEXT_NIGHT
	var total:= 0
	for k in table:
		if k != state:
			total += int(table[k])
	var r:= randi() % maxi(total, 1)
	for k in table:
		if k == state:
			continue
		r -= int(table[k])
		if r < 0:
			return k
	return "cloudy"

func set_state(name: String, instant:= false) -> void:
	if not STATES.has(name):
		return
	prev_state = name if instant else state
	state = name
	blend_t = BLEND if instant else 0.0
	state_left = randf_range(150.0, 420.0) if name in ["drizzle", "rain", "storm"] else randf_range(200.0, 520.0)

func update(delta: float) -> void:
	hour = fmod(hour + delta / SECONDS_PER_HOUR, 24.0)
	state_left -= delta
	if state_left <= 0.0:
		set_state(_pick_next())
	blend_t = minf(blend_t + delta, BLEND)
	var k:= smoothstep(0.0, 1.0, blend_t / BLEND)
	rain = lerpf(_s(prev_state, 0), _s(state, 0), k)
	cover = lerpf(_s(prev_state, 1), _s(state, 1), k)
	fog_mult = lerpf(_s(prev_state, 2), _s(state, 2), k)
	sun_amount = lerpf(_s(prev_state, 3), _s(state, 3), k)
	wind = lerpf(_s(prev_state, 5), _s(state, 5), k)
	lightning = bool(_s(state, 4)) and k > 0.5

	var wet_target:= clampf(0.55 + rain * 0.6, 0.0, 1.0) if rain > 0.05 else 0.0
	if wet_target > wetness:
		wetness = move_toward(wetness, wet_target, delta / 35.0)
	else:
		var dry:= 1.0 / 260.0 * (1.0 + daylight * sun_amount * 1.5) * (0.6 if fog_mult > 2.0 else 1.0)
		wetness = move_toward(wetness, wet_target, delta * dry)
	daylight = smoothstep(5.0, 7.0, hour) * (1.0 - smoothstep(17.0, 19.0, hour))
	lamp_power = 1.0 - smoothstep(0.25, 0.62, daylight + (1.0 - sun_amount) * 0.12 * daylight)

	var t:= (hour - 6.0) / 12.0
	var elev:= sin(clampf(t, -0.15, 1.15) * PI) * deg_to_rad(58.0)
	var az:= lerpf(-1.15, 1.15, clampf(t, 0.0, 1.0))
	var to_sun:= Vector3(cos(elev) * cos(az + PI / 2.0), sin(elev), -cos(elev) * sin(az + PI / 2.0) * 0.55).normalized()
	sun_dir = -to_sun

func is_day() -> bool:
	return daylight > 0.5

func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]

func save_data() -> Dictionary:
	return {"hour": hour, "state": state, "left": state_left, "wet": wetness}

func load_data(d: Dictionary) -> void:
	hour = float(d.get("hour", hour))
	set_state(String(d.get("state", state)), true)
	state_left = float(d.get("left", state_left))
	wetness = float(d.get("wet", wetness))
	update(0.0)

func rain_velocity() -> Vector3:
	var spd:= lerpf(4.2, 6.6, smoothstep(0.2, 0.7, rain))
	return Vector3(0.4 + wind * 1.6, -spd, 0.2 + wind * 0.6)
