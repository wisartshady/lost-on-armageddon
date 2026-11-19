class_name World
extends Node3D

var env: Environment
var world_env: WorldEnvironment
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var city: City
var camera: Camera3D
var sun: DirectionalLight3D
var weather:= WeatherSim.new()
var rain_mm: MultiMeshInstance3D
var rain_mat: ShaderMaterial
var _rain_max:= 3200
var _fall:= Vector3.ZERO
var _sent:= {}
var rain_audio: AudioStreamPlayer
var hum_audio: AudioStreamPlayer
var _flash:= 0.0
var _next_flash:= 18.0
var _thunder_queue: Array = []
var _dyn_scale:= 1.0
var _dyn_timer:= 0.0
var _slow_frames:= 0
var _fast_time:= 0.0
var _random_sfx_timer:= 12.0
var _rain_quality:= 1.0
var _cloud_t:= 0.0
var _cloud_off:= Vector2.ZERO
var _base_fog:= 0.016

func _ready() -> void:
	WeatherSim.current = weather
	_build_environment()
	_build_rain()
	Settings.changed.connect(func (_s): apply_settings())

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky:= Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("clouds", load("res://assets/textures/clouds.png"))
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.165, 0.21)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.3
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.115, 0.11, 0.125)
	env.fog_light_energy = 1.0
	env.fog_density = 0.016
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.7)
	env.set_glow_level(4, 0.5)
	env.set_glow_level(5, 0.0)
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.05
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.63, 0.82)
	moon.light_energy = 0.24
	moon.light_specular = 0.6
	moon.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-158.0), 0)
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 60.0
	moon.shadow_enabled = false
	add_child(moon)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 0.0
	sun.light_specular = 0.8
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_enabled = false
	sun.shadow_blur = 1.5
	sun.visible = false
	add_child(sun)

	var h:= OS.get_environment("OXWAG_HOUR")
	weather.hour = float(h) if h != "" else 5.17
	var w:= OS.get_environment("OXWAG_WEATHER")
	weather.set_state(w if w != "" else "drizzle", true)
	if w == "":
		weather.state_left = 170.0
	weather.update(0.0)

func _make_rain_cylinder(radius: float, height: float, segs: int, tiling: float, speed: float, bright: float) -> Array:
	var mi:= MeshInstance3D.new()
	var cm:= CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segs
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m:= ShaderMaterial.new()
	m.shader = load("res://shaders/rain.gdshader")
	m.set_shader_parameter("rain_tex", load("res://assets/textures/rain.png"))
	m.set_shader_parameter("tiling", tiling)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("brightness", bright)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	add_child(mi)
	return [mi, m]

func _build_rain() -> void:

	var q:= QuadMesh.new()
	q.size = Vector2(1, 1)
	rain_mat = ShaderMaterial.new()
	rain_mat.shader = load("res://shaders/rain_drops.gdshader")
	q.material = rain_mat
	var mm:= MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = _rain_max
	var rng:= RandomNumberGenerator.new()
	rng.seed = 7741
	for i in _rain_max:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	mm.custom_aabb = AABB(Vector3(-100000.0, -10000.0, -100000.0), Vector3(200000.0, 20000.0, 200000.0))
	rain_mm = MultiMeshInstance3D.new()
	rain_mm.multimesh = mm
	rain_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rain_mm.custom_aabb = mm.custom_aabb
	add_child(rain_mm)
	rain_audio = AudioStreamPlayer.new()
	rain_audio.stream = load("res://assets/audio/rain_loop.wav")
	rain_audio.bus = "Ambience"
	rain_audio.volume_db = -60.0
	add_child(rain_audio)
	hum_audio = AudioStreamPlayer.new()
	hum_audio.stream = load("res://assets/audio/city_hum_loop.wav")
	hum_audio.bus = "Ambience"
	hum_audio.volume_db = -12.0
	add_child(hum_audio)

func start_ambience() -> void:
	if not rain_audio.playing:
		rain_audio.play()
	if not hum_audio.playing:
		hum_audio.play()

func apply_settings() -> void:
	var g:= Settings.g
	var vp:= get_viewport()
	var vulkan:= Settings.is_vulkan()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if vulkan and g["render_scale"] < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	_dyn_scale = g["render_scale"]
	vp.scaling_3d_scale = _dyn_scale
	var aa: int = g["aa"]
	if vulkan:
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 or aa == 2 else Viewport.SCREEN_SPACE_AA_DISABLED

	var msaa_level:= aa if vulkan else (2 if aa == 1 else aa)
	vp.msaa_3d = Viewport.MSAA_2X if msaa_level == 2 else (Viewport.MSAA_4X if msaa_level >= 3 else Viewport.MSAA_DISABLED)
	vp.use_taa = vulkan and aa == 4
	vp.texture_mipmap_bias = [1.0, 0.5, 0.0][int(g["texq"])]
	env.glow_enabled = g["glow"]
	var shadows: int = g["shadows"]
	moon.shadow_enabled = false
	sun.shadow_enabled = shadows > 0
	sun.directional_shadow_max_distance = [1.0, 35.0, 60.0, 90.0][shadows]
	RenderingServer.directional_shadow_atlas_set_size([1024, 1024, 2048, 4096][shadows], true)
	env.ssao_enabled = vulkan and g["ssao"]
	env.ssr_enabled = vulkan and g["ssr"]
	if env.ssr_enabled:
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.1
		env.ssr_depth_tolerance = 0.3
	env.volumetric_fog_enabled = vulkan and int(g["fog"]) == 1
	var vd: float = g["view_distance"]
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_albedo = Color(0.6, 0.6, 0.65)
		env.volumetric_fog_emission = Color(0.01, 0.01, 0.012)
		_base_fog = maxf(0.008, 1.2 / vd)
	else:
		_base_fog = maxf(0.016, 1.6 / vd)
	env.fog_density = _base_fog
	if camera:
		camera.far = 1600.0

	var rain: int = g["rain"]
	_rain_quality = [0.0, 0.6, 1.0, 1.0][rain]
	env.adjustment_brightness = float(Settings.d["brightness"])
	RenderingServer.global_shader_parameter_set("window_detail", float(g["windows"]))

	var pts:= [[70.0, 6.0], [100.0, 4.0], [140.0, 2.5], [200.0, 1.5], [260.0, 1.0]]
	var lod_px:= 1.0
	for i in pts.size():
		if vd <= pts[i][0]:
			lod_px = pts[i][1] if i == 0 else lerpf(pts[i - 1][1], pts[i][1], (vd - pts[i - 1][0]) / (pts[i][0] - pts[i - 1][0]))
			break
	vp.mesh_lod_threshold = lod_px

func _process(delta: float) -> void:
	Prof.b("world")
	if camera == null or not is_instance_valid(camera):
		Prof.e("world")
		return
	var cp:= camera.global_position
	_update_weather(delta)
	if city:
		city.update(delta, cp)
	_update_lightning(delta)
	_update_dynamic_res(delta)
	_random_sfx_timer -= delta
	if _random_sfx_timer <= 0.0:
		_random_sfx_timer = randf_range(18.0, 40.0)
		var p:= AudioStreamPlayer.new()
		p.stream = load("res://assets/audio/%s.wav" % ["siren_distant", "car_pass", "car_pass"][randi() % 3])
		p.bus = "Ambience"
		p.volume_db = -14.0
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	Prof.e("world")

func flash_now() -> void:
	_next_flash = 0.0

func _update_lightning(delta: float) -> void:
	_next_flash -= delta
	if not weather.lightning:
		_next_flash = maxf(_next_flash, 8.0)
	if _next_flash <= 0.0:
		_next_flash = randf_range(25.0, 60.0)
		_flash = 1.0
		_thunder_queue.append(randf_range(0.8, 3.5))
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.6, 0.0)
	var f:= maxf(_flash * (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.05)), 0.0)
	_global("lightning", snappedf(f, 0.001))
	_param(sky_mat, "lightning_v", snappedf(f, 0.001))
	moon.light_energy = (0.24 + f * 2.0) * (1.0 - weather.daylight)
	moon.visible = weather.daylight < 0.98
	var i:= 0
	while i < _thunder_queue.size():
		_thunder_queue[i] -= delta
		if _thunder_queue[i] <= 0.0:
			var p:= AudioStreamPlayer.new()
			p.stream = load("res://assets/audio/thunder_%d.wav" % (randi() % 3))
			p.bus = "Ambience"
			p.volume_db = -3.0
			add_child(p)
			p.play()
			p.finished.connect(p.queue_free)
			_thunder_queue.remove_at(i)
		else:
			i += 1

func _update_dynamic_res(delta: float) -> void:
	if not Settings.g["dynamic_res"]:
		return
	var target: float = Settings.g["render_scale"]
	var vp:= get_viewport()
	if delta > 1.0 / 52.0:
		_slow_frames += 1
		_fast_time = 0.0
	else:
		_slow_frames = maxi(_slow_frames - 1, 0)
		_fast_time += delta
	_dyn_timer -= delta
	if _dyn_timer > 0.0:
		return
	if _slow_frames > 20:
		_dyn_scale = maxf(_dyn_scale - 0.05, 0.5)
		_slow_frames = 0
		_dyn_timer = 1.0
		vp.scaling_3d_scale = _dyn_scale
	elif _fast_time > 4.0 and _dyn_scale < target:
		_dyn_scale = minf(_dyn_scale + 0.05, target)
		_fast_time = 0.0
		_dyn_timer = 2.0
		vp.scaling_3d_scale = _dyn_scale

func _global(name: String, v) -> void:
	if _sent.get(name) == v:
		return
	_sent[name] = v
	RenderingServer.global_shader_parameter_set(name, v)

func _param(m: ShaderMaterial, name: String, v) -> void:
	var key:= str(m.get_instance_id()) + name
	if _sent.get(key) == v:
		return
	_sent[key] = v
	m.set_shader_parameter(name, v)

const NIGHT_FOG:= Color(0.115, 0.11, 0.125)
const NIGHT_AMB:= Color(0.15, 0.165, 0.21)

func _update_weather(delta: float) -> void:
	weather.update(delta)
	var W:= weather
	var day:= W.daylight
	var sunny:= W.sun_amount
	var cover:= W.cover

	var elev:= -W.sun_dir.y
	var warm:= 1.0 - smoothstep(0.05, 0.5, elev)
	var sun_col:= Color(1.0, 0.96, 0.9).lerp(Color(1.0, 0.68, 0.42), warm)
	sun.visible = day > 0.02 and elev > -0.05
	if sun.visible:
		sun.look_at_from_position(Vector3.ZERO, W.sun_dir, Vector3.UP if absf(W.sun_dir.y) < 0.99 else Vector3.FORWARD)
		sun.light_color = sun_col
		sun.light_energy = snappedf(day * (0.15 + 1.25 * sunny) * smoothstep(-0.05, 0.12, elev), 0.002)
		sun.shadow_opacity = clampf(0.25 + sunny * 0.75, 0.0, 1.0)

	var sky_day:= Color(0.42, 0.55, 0.75).lerp(Color(0.56, 0.58, 0.61), cover)
	var sky_c:= NIGHT_AMB.lerp(sky_day, day)
	env.ambient_light_color = sky_c
	env.ambient_light_energy = lerpf(1.0, 0.75 + 0.25 * (1.0 - sunny), day)

	var fog_day:= Color(0.6, 0.64, 0.7).lerp(Color(0.66, 0.67, 0.69), cover)
	env.fog_light_color = NIGHT_FOG.lerp(fog_day, day)
	env.fog_density = _base_fog * lerpf(1.0, W.fog_mult, 0.75 + 0.25 * day) * lerpf(1.0, 0.75, day * (1.0 - cover))
	env.fog_sky_affect = lerpf(0.35, 0.6 + 0.35 * cover, day)
	env.tonemap_exposure = lerpf(1.3, 0.95 + 0.12 * cover, day)
	env.glow_intensity = lerpf(0.9, 0.35, day)
	_global("daylight", snappedf(day, 0.002))
	_global("lamp_power", snappedf(W.lamp_power, 0.002))
	_global("wetness", snappedf(W.wetness, 0.002))
	_global("rain_amount", snappedf(W.rain, 0.002))
	_global("day_sky", Vector4(snappedf(sky_c.r, 0.004), snappedf(sky_c.g, 0.004), snappedf(sky_c.b, 0.004), snappedf(cover, 0.004)))
	_global("fog_far_color", Vector4(env.fog_light_color.r * 0.9, env.fog_light_color.g * 0.9, env.fog_light_color.b * 0.9, 1.0))
	_param(sky_mat, "daylight", snappedf(day, 0.002))
	_param(sky_mat, "cover", snappedf(cover, 0.004))
	var sd:= -W.sun_dir
	_param(sky_mat, "sun_dir", Vector3(snappedf(sd.x, 0.002), snappedf(sd.y, 0.002), snappedf(sd.z, 0.002)))
	_param(sky_mat, "sun_col", Vector3(snappedf(sun_col.r, 0.01), snappedf(sun_col.g, 0.01), snappedf(sun_col.b, 0.01)))
	_cloud_t += delta
	if _cloud_t > 0.5:
		_cloud_t = 0.0
		_cloud_off += Vector2(0.0008, 0.0003) * (0.5 + W.wind)
		_cloud_off = Vector2(fposmod(_cloud_off.x, 1.0), fposmod(_cloud_off.y, 1.0))
		sky_mat.set_shader_parameter("cloud_offset", _cloud_off)

	var amount:= clampf(W.rain * 1.15, 0.0, 1.0) * _rain_quality
	rain_mm.visible = amount > 0.01
	if rain_mm.visible:
		var rv3:= W.rain_velocity()
		var spd:= -rv3.y
		var wind:= Vector2(rv3.x, rv3.z)
		_fall += rv3 * delta
		var box:= Vector3(30.0, 18.0, 30.0)
		_fall = Vector3(fposmod(_fall.x, box.x), fposmod(_fall.y, box.y), fposmod(_fall.z, box.z))
		rain_mat.set_shader_parameter("fall_offset", _fall)
		_param(rain_mat, "amount", snappedf(amount, 0.01))
		_param(rain_mat, "speed", snappedf(spd, 0.05))
		_param(rain_mat, "wind", Vector2(snappedf(wind.x, 0.05), snappedf(wind.y, 0.05)))
		_param(rain_mat, "streak", snappedf(lerpf(0.16, 0.34, smoothstep(0.2, 0.7, W.rain)), 0.01))

	var rv:= -60.0 if W.rain < 0.02 else lerpf(-30.0, -17.0, clampf(W.rain, 0.0, 1.0))
	rain_audio.volume_db = move_toward(rain_audio.volume_db, rv, delta * 6.0)
