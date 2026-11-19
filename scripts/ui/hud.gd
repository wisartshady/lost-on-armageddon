class_name Hud
extends Control

var objective_box: VBoxContainer
var objective_label: Label
var prompt: HBoxContainer
var prompt_label: Label
var _prompt_on:= false
var strain_box: Control
var strain_bar: Control
var strain_value:= 0.0
var fps_label: Label
var _stat_t:= 0.0
var toast_label: Label
var hint_label: Label
var hint_row: HBoxContainer
var card: VBoxContainer
var crosshair: Control
var waypoint: Control
var waypoint_label: Label
var waypoint_target:= Vector3.ZERO
var has_waypoint:= false
var post_fx: ColorRect
var post_mat: ShaderMaterial
var vignette: ColorRect
var collapse_label: Label
var player: Player
var _toast_t:= 0.0
var _hint_t:= 0.0
var _pulse:= 0.0
var _obj_flash:= 0.0
var _sfx: AudioStreamPlayer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()

	objective_box = VBoxContainer.new()
	objective_box.position = Vector2(48, 38)
	objective_box.add_theme_constant_override("separation", 3)
	var obar:= ColorRect.new()
	obar.color = UiTheme.ACCENT
	obar.custom_minimum_size = Vector2(30, 2)
	obar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	objective_box.add_child(obar)
	var head:= UiTheme.shadowed(UiTheme.label(tr("HUD_OBJECTIVE").to_upper(), 15, UiTheme.tracked(UiTheme.font_ui, 3), UiTheme.ACCENT.lightened(0.15)), 4)
	head.name = "Head"
	objective_box.add_child(head)
	objective_label = UiTheme.shadowed(UiTheme.label("", 23, UiTheme.font_body_med), 6)
	objective_box.add_child(objective_label)
	objective_box.visible = false
	add_child(objective_box)

	prompt = HBoxContainer.new()
	prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt.add_theme_constant_override("separation", 12)
	UiTheme.place(prompt, Control.PRESET_CENTER_BOTTOM, Vector2(700, 34), Vector2(0, -190))
	prompt.add_child(UiTheme.keycap("E", 17))
	prompt_label = UiTheme.shadowed(UiTheme.label("", 23, UiTheme.tracked(UiTheme.font_ui, 1)), 6)
	prompt.add_child(prompt_label)
	prompt.visible = false
	add_child(prompt)

	strain_box = VBoxContainer.new()
	UiTheme.place(strain_box, Control.PRESET_BOTTOM_LEFT, Vector2(270, 40), Vector2(36, -46))
	var sl:= UiTheme.shadowed(UiTheme.label(tr("HUD_SYMBIOTE").to_upper(), 14, UiTheme.tracked(UiTheme.font_ui, 3), UiTheme.CYAN), 4)
	sl.name = "Title"
	strain_box.add_child(sl)
	strain_bar = Control.new()
	strain_bar.custom_minimum_size = Vector2(260, 12)
	strain_bar.draw.connect(_draw_strain)
	strain_box.add_child(strain_bar)
	strain_box.modulate.a = 0.0
	add_child(strain_box)

	fps_label = UiTheme.shadowed(UiTheme.label("", 16, UiTheme.tracked(UiTheme.font_ui, 1), Color(0.7, 1.0, 0.7)), 4)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.place(fps_label, Control.PRESET_TOP_RIGHT, Vector2(420, 70), Vector2(-20, 14))
	add_child(fps_label)

	toast_label = UiTheme.shadowed(UiTheme.label("", 20, UiTheme.font_body_med), 6)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.place(toast_label, Control.PRESET_CENTER_TOP, Vector2(760, 60), Vector2(0, 90))
	toast_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	toast_label.add_theme_constant_override("shadow_offset_y", 2)
	toast_label.modulate.a = 0.0
	add_child(toast_label)

	hint_label = UiTheme.label("", 1)
	hint_label.visible = false
	add_child(hint_label)
	hint_row = HBoxContainer.new()
	hint_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hint_row.add_theme_constant_override("separation", 8)
	UiTheme.place(hint_row, Control.PRESET_CENTER_BOTTOM, Vector2(1200, 28), Vector2(0, -22))
	for h in [["V", "HINT_CAMERA"], ["F", "HINT_LIGHT"], ["Q", "HINT_POWER"], ["SHIFT", "HINT_RUN"], ["CTRL", "HINT_CROUCH"], ["ESC", "HINT_MENU"]]:
		hint_row.add_child(UiTheme.keycap(h[0], 13))
		var hl:= UiTheme.shadowed(UiTheme.label(tr(h[1]).to_upper(), 15, UiTheme.tracked(UiTheme.font_ui, 1), UiTheme.TEXT_DIM), 4)
		hl.set_meta("tr_key", h[1])
		hint_row.add_child(hl)
		var gap:= Control.new()
		gap.custom_minimum_size = Vector2(12, 0)
		hint_row.add_child(gap)
	hint_row.modulate.a = 0.0
	add_child(hint_row)

	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.draw.connect(func (): crosshair.draw_circle(Vector2.ZERO, 2.0, Color(1, 1, 1, 0.7)))
	add_child(crosshair)

	waypoint = Control.new()
	waypoint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	waypoint.draw.connect(_draw_waypoint)
	add_child(waypoint)
	waypoint_label = UiTheme.label("", 13, UiTheme.font_bold)
	waypoint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waypoint_label.size = Vector2(80, 20)
	waypoint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	waypoint_label.add_theme_constant_override("shadow_offset_y", 1)
	waypoint.add_child(waypoint_label)

	card = VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	UiTheme.place(card, Control.PRESET_CENTER, Vector2(800, 120), Vector2(0, -60))
	card.modulate.a = 0.0
	add_child(card)
	collapse_label = UiTheme.shadowed(UiTheme.label("", 28, UiTheme.tracked(UiTheme.font_ui_med, 3)), 6)
	collapse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.place(collapse_label, Control.PRESET_CENTER, Vector2(800, 40), Vector2(0, 60))
	collapse_label.modulate.a = 0.0
	add_child(collapse_label)
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)
	Game.objective_changed.connect(_on_objective)
	Game.toast.connect(func (k): show_toast(tr(k), 6.0))
	_ignore_mouse(self)

func bind_player(p: Player) -> void:
	player = p
	p.interact_changed.connect(_on_interact)
	p.strain_changed.connect(_on_strain)
	p.power_used.connect(_on_power)
	p.collapsed.connect(_on_collapse)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and objective_box:
		(objective_box.get_node("Head") as Label).text = tr("HUD_OBJECTIVE").to_upper()
		(strain_box.get_node("Title") as Label).text = tr("HUD_SYMBIOTE").to_upper()
		if Game.objective_key != "":
			objective_label.text = tr(Game.objective_key)
		if hint_row:
			for c in hint_row.get_children():
				if c.has_meta("tr_key"):
					(c as Label).text = tr(c.get_meta("tr_key")).to_upper()

func _on_strain(v: float) -> void:
	strain_value = v
	strain_bar.queue_redraw()

func _on_objective(key: String, target: String) -> void:
	if key == "":
		objective_box.visible = false
		has_waypoint = false
		return
	objective_box.visible = true
	objective_label.text = tr(key)
	_obj_flash = 1.0
	_sfx.stream = load("res://assets/audio/objective.wav")
	_sfx.volume_db = -6.0
	_sfx.play()
	has_waypoint = target != "" and Game.world != null
	if has_waypoint:
		waypoint_target = Game.world.call("marker_pos", target)

func _on_interact(info: Dictionary) -> void:
	if info.is_empty():
		_prompt_on = false
		return
	var verb:= tr("HUD_TALK") if info.get("kind", "") == "npc" else tr("HUD_INSPECT")
	prompt_label.text = "%s  ·  %s" % [verb.to_upper(), tr(info.get("label", "")).to_upper()]
	_prompt_on = true

func _on_power(first: bool) -> void:
	_pulse = 1.0
	if first:
		show_toast(tr("HUD_SYMBIOTE_NOTE"), 7.0)

func _on_collapse() -> void:
	collapse_label.text = tr("HUD_COLLAPSE")
	var tw:= create_tween()
	tw.tween_property(collapse_label, "modulate:a", 1.0, 0.6)
	tw.tween_interval(2.4)
	tw.tween_property(collapse_label, "modulate:a", 0.0, 0.8)

var _bark_box: VBoxContainer
var _bark_name: Label
var _bark_text: Label
var _bark_t:= 0.0

func _build_bark() -> void:
	_bark_box = VBoxContainer.new()
	_bark_box.alignment = BoxContainer.ALIGNMENT_END
	UiTheme.place(_bark_box, Control.PRESET_CENTER_BOTTOM, Vector2(1000, 90), Vector2(0, -78))
	_bark_box.add_theme_constant_override("separation", 2)
	_bark_name = UiTheme.label("", 15, UiTheme.tracked(UiTheme.font_ui, 3), UiTheme.ACCENT.lightened(0.3))
	_bark_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bark_text = UiTheme.label("", 25, UiTheme.font_body_med)
	_bark_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bark_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for l in [_bark_name, _bark_text]:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_constant_override("shadow_outline_size", 9)
		_bark_box.add_child(l)
	_bark_box.modulate.a = 0.0
	_bark_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bark_box)

func show_bark(speaker: String, text: String, seconds:= 4.0) -> void:
	if _bark_box == null:
		_build_bark()
	_bark_name.text = speaker.to_upper()
	_bark_text.text = text
	_bark_t = seconds

func show_toast(text: String, seconds:= 4.0) -> void:
	toast_label.text = text
	_toast_t = seconds

func show_hint(seconds:= 18.0) -> void:
	hint_label.text = tr("HUD_HINT_START")
	_hint_t = seconds

func intro_card(lines: Array) -> void:
	for c in card.get_children():
		c.queue_free()
	for i in lines.size():
		var l:= UiTheme.shadowed(UiTheme.label(lines[i].to_upper() if i == 0 else lines[i], 72 if i == 0 else 22,
				UiTheme.tracked(UiTheme.font_display, 6) if i == 0 else UiTheme.tracked(UiTheme.font_ui_med, 4),
				UiTheme.TEXT if i == 0 else UiTheme.TEXT_DIM), 8)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(l)
	var tw:= create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 1.5)
	tw.tween_interval(3.0)
	tw.tween_property(card, "modulate:a", 0.0, 1.5)

func _process(delta: float) -> void:
	Prof.b("hud")
	if _bark_box:
		_bark_t -= delta
		var target:= 1.0 if _bark_t > 0.0 else 0.0
		_bark_box.modulate.a = move_toward(_bark_box.modulate.a, target, delta * 3.0)
	fps_label.visible = Settings.d["show_fps"]
	var dlg = Game.world.get("dialogue") if Game.world else null
	prompt.visible = _prompt_on and not (dlg != null and dlg.active)
	if fps_label.visible:
		_stat_t -= get_process_delta_time()
		if _stat_t <= 0.0:
			_stat_t = 0.5
			var vp_rid:= get_viewport().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(vp_rid, true)
			var gpu:= RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
			var cpu_r:= RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu()
			fps_label.text = "FPS %d  ·  %.1f ms\nscript %.1f  fizik %.1f  render-cpu %.1f%s\ndraw %d  tri %dk  ölçek %d%%" % [
				Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				cpu_r, ("  gpu %.1f" % gpu) if gpu > 0.0 else "",
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
				int(round(get_viewport().scaling_3d_scale * 100.0))]
	if Input.is_action_just_pressed("toggle_fps"):
		Settings.set_display("show_fps", not Settings.d["show_fps"])
	_toast_t -= delta
	toast_label.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_hint_t -= delta
	hint_row.modulate.a = clampf(_hint_t * 0.5, 0.0, 0.95)

	if _obj_flash > 0.0 or _obj_flash_sent != 0.0:
		_obj_flash = maxf(_obj_flash - delta * 0.6, 0.0)
		_obj_flash_sent = _obj_flash
		objective_label.add_theme_color_override("font_color", UiTheme.TEXT.lerp(Color(1, 0.85, 0.6), _obj_flash))
	_pulse = maxf(_pulse - delta * 1.8, 0.0)
	if player:
		var s:= strain_value
		strain_box.modulate.a = move_toward(strain_box.modulate.a, 1.0 if (s > 0.01 or player.charging) else 0.0, delta * 2.0)
		_set_post(maxf(s, player.charge * 0.5), _pulse, clampf(player._collapse_t * 0.85, 0.0, 0.85))
		crosshair.visible = player.cam_mode == "fp" and not player.controls_locked
		if player.charging:
			strain_bar.queue_redraw()
		_update_waypoint()
	else:
		_set_post(0.0, 0.0, 0.0)
		crosshair.visible = false
		waypoint.visible = false
	Prof.e("hud")

func _post_mat() -> ShaderMaterial:
	var w = Game.world
	if w and w.get("post") and w.post.mat:
		return w.post.mat
	return null

func _update_waypoint() -> void:
	waypoint.visible = has_waypoint and not player.controls_locked
	if not waypoint.visible:
		return
	var cam:= player.camera
	var p:= waypoint_target + Vector3(0, 2.2, 0)
	var vs:= get_viewport_rect().size
	var behind:= cam.is_position_behind(p)
	var sp:= cam.unproject_position(p)
	if behind:

		var side:= cam.global_transform.basis.x.dot(p - cam.global_position)
		sp = Vector2(50.0 if side < 0.0 else vs.x - 50.0, vs.y * 0.5)
	sp.x = clampf(sp.x, 50, vs.x - 50)
	sp.y = clampf(sp.y, 70, vs.y - 120)
	waypoint.position = sp
	var dist:= player.global_position.distance_to(waypoint_target)
	waypoint_label.text = "%d %s" % [int(dist), tr("HUD_METERS")]
	waypoint_label.position = Vector2(-40, 12)
	waypoint.queue_redraw()

func _draw_waypoint() -> void:
	var c:= Color(1.0, 0.82, 0.45, 0.95)
	var pts:= PackedVector2Array([Vector2(0, -10), Vector2(8, 0), Vector2(0, 10), Vector2(-8, 0)])
	waypoint.draw_colored_polygon(pts, Color(0, 0, 0, 0.5))
	waypoint.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), c, 2.0, true)
	waypoint.draw_circle(Vector2.ZERO, 2.5, c)

func _draw_strain() -> void:
	var w:= strain_bar.size.x
	var h:= strain_bar.size.y
	strain_bar.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.5))
	var segs:= 20
	var s:= strain_value
	for i in segs:
		var f:= float(i) / segs
		if f >= s:
			break
		var col:= UiTheme.CYAN.lerp(Color(1.0, 0.25, 0.2), clampf((f - 0.4) / 0.5, 0.0, 1.0))
		var x:= 2 + i * (w - 4) / segs
		strain_bar.draw_rect(Rect2(x, 2, (w - 4) / segs - 2, h - 4), col)
	if player and player.charging:
		strain_bar.draw_rect(Rect2(0, h - 2, w * player.charge, 2), Color(1, 1, 1, 0.8))

static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)

var _post_sent:= Vector3(-1, -1, -1)
var _obj_flash_sent:= -1.0

func _set_post(strain: float, pulse: float, collapse: float) -> void:
	var v:= Vector3(snappedf(strain, 0.002), snappedf(pulse, 0.002), snappedf(collapse, 0.002))
	if v == _post_sent:
		return
	var pm:= _post_mat()
	if pm == null:
		return
	_post_sent = v
	pm.set_shader_parameter("strain", v.x)
	pm.set_shader_parameter("pulse", v.y)
	pm.set_shader_parameter("collapse", v.z)
