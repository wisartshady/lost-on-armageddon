class_name DialogueUI
extends Control

signal started(id: String)
signal finished(id: String)
signal line_shown(line: Dictionary)

const VOICE_DIR:= "res://assets/voice/tr/"

var data:= {}
var panel: PanelContainer
var band: TextureRect
var name_label: Label
var text_label: Label
var hint: Label
var choice_box: VBoxContainer
var voice: AudioStreamPlayer
var blip: AudioStreamPlayer
var active:= false
var blocking:= true
var current_id:= ""
var lines: Array = []
var line_idx:= 0
var _chars:= 0.0
var _auto_t:= 0.0
var _choices_up:= false
var _blip_t:= 0.0
var _on_end: Array = []
var _guard:= 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json"))

	band = TextureRect.new()
	var grad:= GradientTexture2D.new()
	var g:= Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0, 0, 0, 0.78))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 1)
	band.texture = grad
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -300
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.visible = false
	add_child(band)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 0)
	UiTheme.place(panel, Control.PRESET_CENTER_BOTTOM, Vector2(1000, 150), Vector2(0, -56))
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var vb:= VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.alignment = BoxContainer.ALIGNMENT_END
	panel.add_child(vb)
	name_label = UiTheme.shadowed(UiTheme.label("", 16, UiTheme.tracked(UiTheme.font_ui, 3), UiTheme.ACCENT.lightened(0.3)), 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name_label)
	text_label = UiTheme.shadowed(UiTheme.label("", 27, UiTheme.font_body_med), 9)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.custom_minimum_size = Vector2(980, 0)
	vb.add_child(text_label)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 4)
	choice_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(choice_box)
	hint = UiTheme.shadowed(UiTheme.label("", 14, UiTheme.tracked(UiTheme.font_ui, 2), UiTheme.TEXT_DIM), 4)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	voice = AudioStreamPlayer.new()
	voice.bus = "Voice"
	add_child(voice)
	blip = AudioStreamPlayer.new()
	blip.bus = "Voice"
	blip.stream = load("res://assets/audio/dialog_blip.wav")
	blip.volume_db = -14.0
	add_child(blip)

func start(id: String, is_blocking:= true) -> void:
	if not data.has(id):
		push_warning("dialogue not found: " + id)
		return
	if not active:
		started.emit(id)
	active = true
	blocking = is_blocking
	current_id = id
	lines = data[id]["lines"]
	_on_end = data[id].get("on_end", [])
	line_idx = 0
	_guard = 0.3
	_show_line()

func _show_line() -> void:
	var l: Dictionary = lines[line_idx]
	panel.visible = Settings.a["subtitles"] or blocking
	band.visible = panel.visible
	name_label.text = tr(l["speaker"]).to_upper()
	text_label.text = tr(l["text"])
	text_label.visible_characters = 0
	_chars = 0.0
	_choices_up = false
	for c in choice_box.get_children():
		c.queue_free()
	hint.text = tr("DLG_CONTINUE").to_upper() if blocking else ""
	var vpath:= ""
	for ext in [".ogg", ".wav", ".mp3"]:
		if ResourceLoader.exists(VOICE_DIR + l["voice"] + ext):
			vpath = VOICE_DIR + l["voice"] + ext
			break
	if vpath != "":
		voice.stream = load(vpath)
		voice.play()
	else:
		voice.stop()
	var plain: String = text_label.text
	_auto_t = 1.6 + plain.length() / 15.0
	if vpath != "":
		_auto_t = maxf(_auto_t, voice.stream.get_length() + 0.4)
	line_shown.emit(l)

func _process(delta: float) -> void:
	if not active:
		return
	var total:= text_label.get_total_character_count()
	if text_label.visible_characters < total:
		_chars += delta * 45.0
		text_label.visible_characters = int(_chars)
		_blip_t -= delta
		if _blip_t <= 0.0 and not voice.playing:
			_blip_t = 0.07
			blip.pitch_scale = randf_range(0.9, 1.15) * (0.85 if lines[line_idx]["speaker"] == "NAME_GUS" else 1.0)
			blip.play()
	elif lines[line_idx].has("choices") and not _choices_up:
		_show_choices()
	_guard -= delta
	if blocking:
		if _guard <= 0.0 and Input.is_action_just_pressed("dialog_next") and not _choices_up:
			if text_label.visible_characters < total:
				text_label.visible_characters = total
				_chars = total
			else:
				_advance()
	else:
		_auto_t -= delta
		if _auto_t <= 0.0:
			_advance()

func _show_choices() -> void:
	_choices_up = true
	hint.text = ""
	Game.capture_mouse(false)
	var first: Button = null
	var n:= 0
	for ch in lines[line_idx]["choices"]:
		n += 1
		var b:= Button.new()
		b.text = "%d   %s" % [n, tr(ch["text"])]
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_font_override("font", UiTheme.font_body_med)
		b.add_theme_font_size_override("font_size", 22)
		var sn:= StyleBoxFlat.new()
		sn.bg_color = Color(0, 0, 0, 0.45)
		sn.content_margin_left = 22
		sn.content_margin_right = 22
		sn.content_margin_top = 6
		sn.content_margin_bottom = 6
		sn.set_corner_radius_all(2)
		var sh:= sn.duplicate()
		sh.bg_color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.55)
		b.add_theme_stylebox_override("normal", sn)
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("focus", sh)
		b.add_theme_stylebox_override("pressed", sh)
		b.add_theme_color_override("font_color", UiTheme.TEXT)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(520, 40)
		b.pressed.connect(_choose.bind(ch["goto"]))
		b.mouse_entered.connect(b.grab_focus)
		b.focus_entered.connect(UiSound.play.bind("hover", -16.0))
		choice_box.add_child(b)
		if first == null:
			first = b
	if first:
		first.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if not _choices_up or not (event is InputEventKey) or not event.pressed:
		return
	var k: int = event.physical_keycode - KEY_1
	if k >= 0 and k < choice_box.get_child_count():
		(choice_box.get_child(k) as Button).pressed.emit()
		get_viewport().set_input_as_handled()

func _choose(goto: String) -> void:
	Game.capture_mouse(true)
	var end_actions:= _on_end
	Game.run_actions(end_actions)
	start(goto, blocking)

func _advance() -> void:
	line_idx += 1
	if line_idx >= lines.size():
		_end()
	else:
		_show_line()

func _end() -> void:
	active = false
	panel.visible = false
	band.visible = false
	voice.stop()
	var id:= current_id
	Game.run_actions(_on_end)
	finished.emit(id)
