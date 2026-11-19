class_name Menus
extends Control

signal new_game
signal continue_game
signal resume
signal to_main_menu
signal quit_game

const IMPACT:= {
	"preset": 2, "renderer": 2, "render_scale": 2, "dynamic_res": 0, "view_distance": 2, "shadows": 2, "lights": 2,
	"glow": 1, "fog": 2, "rain": 1, "aa": 2, "ssao": 2, "ssr": 2, "windows": 1, "texq": 1, "particles": 1, "post": 1,
}

var main_panel: Control
var pause_panel: Control
var settings_panel: Control
var loading_panel: Control
var loading_bar: ColorRect
var loading_fill: ColorRect
var loading_label: Label
var loading_tip: Label
var continue_btn: MenuItem
var _settings_return:= "main"
var _rows:= {}
var _cats: Array = []
var _cat_buttons: Array = []
var _cat_index:= 0
var _row_box: VBoxContainer
var _desc_title: Label
var _desc_text: Label
var _desc_impact: Label
var _restart_note: Label
var _main_desc: Label
var _pause_obj: Label
var _items: Array = []
var _tip_t:= 0.0
var _tip_i:= 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_loading()
	_build_main()
	_build_pause()
	_build_settings()
	show_only("")

func show_only(which: String) -> void:
	main_panel.visible = which == "main"
	pause_panel.visible = which == "pause"
	settings_panel.visible = which == "settings"
	loading_panel.visible = which == "loading"
	mouse_filter = Control.MOUSE_FILTER_STOP if which in ["main", "pause", "settings"] else Control.MOUSE_FILTER_IGNORE
	if which == "main":
		continue_btn.visible = Game.has_save()
		var first: Control = continue_btn if continue_btn.visible else _items[1]
		first.grab_focus.call_deferred()
	elif which == "pause":
		_pause_obj.text = tr(Game.objective_key) if Game.objective_key != "" else ""
		(pause_panel.get_node("Left/VB/Items").get_child(0) as Control).grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if settings_panel.visible and event.is_action_pressed("ui_cancel"):
		_close_settings()
		get_viewport().set_input_as_handled()
	elif settings_panel.visible and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			_select_cat(_cat_index - 1)
		elif event.physical_keycode == KEY_E:
			_select_cat(_cat_index + 1)

func _shade(parent: Control, from_left: bool, width: float, alpha:= 0.92) -> void:
	var grad:= GradientTexture2D.new()
	var g:= Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.0, alpha))
	g.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0) if from_left else Vector2(1, 0)
	grad.fill_to = Vector2(1, 0) if from_left else Vector2(0, 0)
	var tr_:= TextureRect.new()
	tr_.texture = grad
	tr_.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE if from_left else Control.PRESET_RIGHT_WIDE)
	if from_left:
		tr_.offset_right = width
	else:
		tr_.offset_left = -width
	tr_.stretch_mode = TextureRect.STRETCH_SCALE
	tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr_)

func _bottom_bar(parent: Control, hints: Array) -> HBoxContainer:
	var hb:= HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	UiTheme.place(hb, Control.PRESET_BOTTOM_LEFT, Vector2(900, 30), Vector2(96, -40))
	for h in hints:
		hb.add_child(UiTheme.keycap(h[0], 14))
		var l:= UiTheme.label(tr(h[1]).to_upper(), 16, UiTheme.tracked(UiTheme.font_ui, 1), UiTheme.TEXT_DIM)
		l.set_meta("tr_key", h[1])
		l.set_meta("upper", true)
		hb.add_child(l)
		var sp:= Control.new()
		sp.custom_minimum_size = Vector2(14, 0)
		hb.add_child(sp)
	parent.add_child(hb)
	return hb

func _logo(parent: Control, pos: Vector2, scale_f:= 1.0) -> VBoxContainer:
	var vb:= VBoxContainer.new()
	vb.position = pos
	vb.add_theme_constant_override("separation", -6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(vb)
	var l1:= UiTheme.label("LOST ON", int(28 * scale_f), UiTheme.tracked(UiTheme.font_ui_med, 12), Color(0.82, 0.82, 0.84))
	vb.add_child(l1)
	var holder:= Control.new()
	holder.custom_minimum_size = Vector2(560 * scale_f, 112 * scale_f)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(holder)
	var glitch:= UiTheme.label("ARMAGEDDON", int(124 * scale_f), UiTheme.tracked(UiTheme.font_display, 3), Color(0.86, 0.12, 0.16, 0.55))
	glitch.position = Vector2(4 * scale_f, -14 * scale_f)
	holder.add_child(glitch)
	var cyan:= UiTheme.label("ARMAGEDDON", int(124 * scale_f), UiTheme.tracked(UiTheme.font_display, 3), Color(0.3, 0.85, 1.0, 0.22))
	cyan.position = Vector2(-2 * scale_f, -16 * scale_f)
	holder.add_child(cyan)
	var main_t:= UiTheme.label("ARMAGEDDON", int(124 * scale_f), UiTheme.tracked(UiTheme.font_display, 3), Color(0.95, 0.94, 0.92))
	main_t.position = Vector2(0, -16 * scale_f)
	holder.add_child(main_t)
	var row:= HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var bar:= ColorRect.new()
	bar.color = UiTheme.ACCENT
	bar.custom_minimum_size = Vector2(64 * scale_f, 3)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var tag:= UiTheme.label(tr("MENU_TAGLINE"), int(17 * scale_f), UiTheme.tracked(UiTheme.font_ui_med, 5), UiTheme.TEXT_DIM)
	tag.set_meta("tr_key", "MENU_TAGLINE")
	row.add_child(tag)
	vb.add_child(row)
	return vb

func _build_loading() -> void:
	loading_panel = Control.new()
	loading_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(loading_panel)
	var bg:= TextureRect.new()
	bg.texture = load("res://assets/textures/ui/loading_bg.jpg")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.55, 0.55, 0.6)
	loading_panel.add_child(bg)
	_shade(loading_panel, true, 900, 0.95)
	_logo(loading_panel, Vector2(96, 96), 0.75)
	loading_tip = UiTheme.label("", 20, UiTheme.font_body, UiTheme.TEXT)
	loading_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.place(loading_tip, Control.PRESET_BOTTOM_LEFT, Vector2(620, 80), Vector2(96, -104))
	loading_panel.add_child(loading_tip)
	var tiphead:= UiTheme.label(tr("UI_TIP").to_upper(), 15, UiTheme.tracked(UiTheme.font_ui, 3), UiTheme.ACCENT)
	tiphead.set_meta("tr_key", "UI_TIP")
	tiphead.set_meta("upper", true)
	UiTheme.place(tiphead, Control.PRESET_BOTTOM_LEFT, Vector2(300, 22), Vector2(96, -192))
	loading_panel.add_child(tiphead)
	loading_bar = ColorRect.new()
	loading_bar.color = Color(1, 1, 1, 0.1)
	loading_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	loading_bar.offset_top = -3
	loading_panel.add_child(loading_bar)
	loading_fill = ColorRect.new()
	loading_fill.color = UiTheme.CYAN
	loading_fill.position = Vector2.ZERO
	loading_fill.size = Vector2(0, 3)
	loading_bar.add_child(loading_fill)
	loading_label = UiTheme.label("", 16, UiTheme.tracked(UiTheme.font_ui, 2), UiTheme.TEXT_DIM)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.place(loading_label, Control.PRESET_BOTTOM_RIGHT, Vector2(500, 24), Vector2(-60, -24))
	loading_panel.add_child(loading_label)
	_next_tip()

func _next_tip() -> void:
	_tip_i = (_tip_i + 1 + randi() % 5) % 6
	loading_tip.text = tr("TIP_%d" % (_tip_i + 1))

func set_loading(p: float, key: String) -> void:
	loading_fill.size = Vector2(loading_bar.size.x * clampf(p, 0.0, 1.0), 3)
	loading_label.text = "%s   %d%%" % [tr(key).to_upper(), int(p * 100.0)]

var _keytest_row:= ""
var _keytest:= MoveInput.new()

func _process(delta: float) -> void:
	if _keytest_row != "" and _desc_impact and _desc_impact.is_visible_in_tree():
		var held:= _keytest.held_names()
		_desc_impact.text = tr("UI_KEYTEST").to_upper() + ":  " + (" + ".join(held) if held.size() > 0 else "-")
		_desc_impact.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	if loading_panel.visible:
		_tip_t += delta
		if _tip_t > 6.0:
			_tip_t = 0.0
			_next_tip()

func _item(key: String, desc: String, cb: Callable, size:= 34) -> MenuItem:
	var b:= MenuItem.new().setup(key, desc, size)
	b.pressed.connect(cb)
	b.highlighted.connect(_on_highlight)
	_items.append(b)
	return b

func _on_highlight(it: MenuItem) -> void:
	if _main_desc and main_panel.visible:
		_main_desc.text = tr(it.desc_key) if it.desc_key != "" else ""

func _build_main() -> void:
	main_panel = Control.new()
	main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_panel)
	_shade(main_panel, true, 820)
	var bottom:= ColorRect.new()
	bottom.color = Color(0, 0, 0, 0.35)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -64
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_panel.add_child(bottom)
	_logo(main_panel, Vector2(96, 92))
	var items:= VBoxContainer.new()
	items.name = "Items"
	items.position = Vector2(70, 330)
	items.add_theme_constant_override("separation", 2)
	main_panel.add_child(items)
	continue_btn = _item("MENU_CONTINUE", "DESC_MENU_CONTINUE", func (): continue_game.emit())
	items.add_child(continue_btn)
	items.add_child(_item("MENU_NEW", "DESC_MENU_NEW", func (): new_game.emit()))
	items.add_child(_item("MENU_SETTINGS", "DESC_MENU_SETTINGS", func (): open_settings("main")))
	items.add_child(_item("MENU_QUIT", "DESC_MENU_QUIT", func (): quit_game.emit()))
	_main_desc = UiTheme.label("", 18, UiTheme.font_body, UiTheme.TEXT_DIM)
	_main_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.place(_main_desc, Control.PRESET_BOTTOM_LEFT, Vector2(560, 60), Vector2(96, -112))
	main_panel.add_child(_main_desc)
	_bottom_bar(main_panel, [["ENTER", "UI_SELECT"], ["↑↓", "UI_NAVIGATE"]])
	var ver:= UiTheme.label(tr("MENU_SUBTITLE") + "   ·   " + tr("MENU_CREDITS"), 13, UiTheme.font_body, UiTheme.TEXT_FAINT)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiTheme.place(ver, Control.PRESET_BOTTOM_RIGHT, Vector2(900, 20), Vector2(-40, -24))
	main_panel.add_child(ver)

func _build_pause() -> void:
	pause_panel = ColorRect.new()
	(pause_panel as ColorRect).color = Color(0.0, 0.0, 0.01, 0.55)
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pause_panel)
	var left:= Control.new()
	left.name = "Left"
	left.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_panel.add_child(left)
	_shade(left, true, 700)
	var vb:= VBoxContainer.new()
	vb.name = "VB"
	vb.position = Vector2(96, 110)
	vb.add_theme_constant_override("separation", 4)
	left.add_child(vb)
	var t:= UiTheme.label(tr("MENU_PAUSED").to_upper(), 84, UiTheme.tracked(UiTheme.font_display, 3), UiTheme.TEXT)
	t.set_meta("tr_key", "MENU_PAUSED")
	t.set_meta("upper", true)
	vb.add_child(t)
	var oh:= UiTheme.label(tr("HUD_OBJECTIVE").to_upper(), 15, UiTheme.tracked(UiTheme.font_ui, 3), UiTheme.ACCENT)
	oh.set_meta("tr_key", "HUD_OBJECTIVE")
	oh.set_meta("upper", true)
	vb.add_child(oh)
	_pause_obj = UiTheme.label("", 21, UiTheme.font_body_med, UiTheme.TEXT)
	vb.add_child(_pause_obj)
	var sp:= Control.new()
	sp.custom_minimum_size = Vector2(0, 34)
	vb.add_child(sp)
	var items:= VBoxContainer.new()
	items.name = "Items"
	items.add_theme_constant_override("separation", 0)
	vb.add_child(items)
	items.add_child(_item("MENU_RESUME", "", func (): resume.emit(), 30))
	items.add_child(_item("MENU_SETTINGS", "", func (): open_settings("pause"), 30))
	items.add_child(_item("MENU_MAIN", "", func (): to_main_menu.emit(), 30))
	items.add_child(_item("MENU_QUIT", "", func (): quit_game.emit(), 30))

	var card:= PanelContainer.new()
	var sb:= StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.022, 0.03, 0.82)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.border_width_left = 1
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", sb)
	UiTheme.place(card, Control.PRESET_CENTER_RIGHT, Vector2(380, 420), Vector2(-70, 0))
	pause_panel.add_child(card)
	var cv:= VBoxContainer.new()
	cv.add_theme_constant_override("separation", 9)
	card.add_child(cv)
	var ch:= UiTheme.label(tr("UI_CONTROLS").to_upper(), 16, UiTheme.tracked(UiTheme.font_ui, 3), UiTheme.ACCENT)
	ch.set_meta("tr_key", "UI_CONTROLS")
	ch.set_meta("upper", true)
	cv.add_child(ch)
	for k in [["W A S D", "CTL_MOVE"], ["SHIFT", "CTL_RUN"], ["SPACE", "CTL_JUMP"], ["CTRL", "CTL_CROUCH"], ["E", "CTL_INTERACT"],
			["V", "CTL_CAMERA"], ["F", "CTL_FLASHLIGHT"], ["Q", "CTL_POWER"], ["F5", "CTL_SAVE"]]:
		var hb:= HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		var kc:= UiTheme.keycap(k[0], 14)
		kc.custom_minimum_size = Vector2(86, 0)
		hb.add_child(kc)
		var l:= UiTheme.label(tr(k[1]), 17, UiTheme.font_body, UiTheme.TEXT)
		l.set_meta("tr_key", k[1])
		hb.add_child(l)
		cv.add_child(hb)
	_bottom_bar(pause_panel, [["ENTER", "UI_SELECT"], ["ESC", "UI_RESUME"]])

func open_settings(from: String) -> void:
	_settings_return = from
	_refresh_settings()
	show_only("settings")
	_select_cat(_cat_index)

func _close_settings() -> void:
	UiSound.play("back", -10.0)
	show_only(_settings_return)

func _build_settings() -> void:
	settings_panel = ColorRect.new()
	(settings_panel as ColorRect).color = Color(0.01, 0.012, 0.018, 0.88)
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(settings_panel)
	var title:= UiTheme.label(tr("MENU_SETTINGS").to_upper(), 76, UiTheme.tracked(UiTheme.font_display, 3), UiTheme.TEXT)
	title.set_meta("tr_key", "MENU_SETTINGS")
	title.set_meta("upper", true)
	title.position = Vector2(96, 40)
	settings_panel.add_child(title)

	var tabs:= HBoxContainer.new()
	tabs.position = Vector2(96, 132)
	tabs.add_theme_constant_override("separation", 34)
	settings_panel.add_child(tabs)
	var line:= ColorRect.new()
	line.color = Color(1, 1, 1, 0.1)
	line.position = Vector2(96, 172)
	line.size = Vector2(1088, 1)
	settings_panel.add_child(line)
	for c in ["SET_TAB_GRAPHICS", "SET_TAB_DISPLAY", "SET_TAB_AUDIO", "SET_TAB_CONTROLS", "SET_TAB_LANGUAGE"]:
		var b:= Button.new()
		b.text = tr(c).to_upper()
		b.set_meta("tr_key", c)
		b.set_meta("upper", true)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UiTheme.tracked(UiTheme.font_ui, 2))
		b.add_theme_font_size_override("font_size", 22)
		var empty:= StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(st, empty)
		var idx:= _cat_buttons.size()
		b.pressed.connect(_select_cat.bind(idx))
		tabs.add_child(b)
		_cat_buttons.append(b)
		var u:= ColorRect.new()
		u.color = UiTheme.ACCENT
		u.mouse_filter = Control.MOUSE_FILTER_IGNORE
		u.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		u.offset_top = -3
		u.offset_bottom = 1
		u.name = "U"
		b.add_child(u)

	var sc:= ScrollContainer.new()
	sc.position = Vector2(80, 190)
	sc.size = Vector2(700, 440)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_panel.add_child(sc)
	_row_box = VBoxContainer.new()
	_row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row_box.add_theme_constant_override("separation", 2)
	sc.add_child(_row_box)
	var card:= PanelContainer.new()
	var sb:= StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.035)
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.border_width_left = 1
	sb.content_margin_left = 26
	sb.content_margin_right = 22
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", sb)
	card.position = Vector2(820, 196)
	card.size = Vector2(364, 300)
	settings_panel.add_child(card)
	var cv:= VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	card.add_child(cv)
	_desc_title = UiTheme.label("", 26, UiTheme.tracked(UiTheme.font_ui, 1), UiTheme.TEXT)
	_desc_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_title.custom_minimum_size = Vector2(316, 0)
	cv.add_child(_desc_title)
	var bar:= ColorRect.new()
	bar.color = UiTheme.ACCENT
	bar.custom_minimum_size = Vector2(40, 2)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cv.add_child(bar)
	_desc_text = UiTheme.label("", 17, UiTheme.font_body, UiTheme.TEXT_DIM)
	_desc_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_text.custom_minimum_size = Vector2(316, 0)
	cv.add_child(_desc_text)
	_desc_impact = UiTheme.label("", 15, UiTheme.tracked(UiTheme.font_ui, 2), UiTheme.TEXT)
	cv.add_child(_desc_impact)
	_restart_note = UiTheme.label("", 15, UiTheme.font_body_med, Color(1.0, 0.72, 0.4))
	_restart_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_restart_note.custom_minimum_size = Vector2(316, 0)
	cv.add_child(_restart_note)
	var hb:= _bottom_bar(settings_panel, [["← →", "UI_CHANGE"], ["Q / E", "UI_CATEGORY"], ["ESC", "SET_BACK"]])
	var defaults:= Button.new()
	defaults.text = tr("SET_DEFAULTS").to_upper()
	defaults.set_meta("tr_key", "SET_DEFAULTS")
	defaults.set_meta("upper", true)
	defaults.flat = true
	defaults.add_theme_font_override("font", UiTheme.tracked(UiTheme.font_ui, 1))
	defaults.add_theme_font_size_override("font_size", 16)
	defaults.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	defaults.pressed.connect(_on_defaults)
	UiTheme.place(defaults, Control.PRESET_BOTTOM_RIGHT, Vector2(240, 30), Vector2(-60, -40))
	settings_panel.add_child(defaults)
	_build_categories()

func _build_categories() -> void:
	_cats = [
		[["preset", "choice", "SET_PRESET", ["PRESET_0", "PRESET_1", "PRESET_2", "PRESET_3", "PRESET_4"]],
			["renderer", "choice", "SET_RENDERER", ["REND_COMPAT", "REND_VULKAN"]],
			["render_scale", "slider", "SET_RENDER_SCALE", 0.5, 1.0, 0.05, "%"],
			["dynamic_res", "toggle", "SET_DYNRES"],
			["view_distance", "slider", "SET_VIEWDIST", 60.0, 300.0, 10.0, "m"],
			["shadows", "choice", "SET_SHADOWS", ["LVL_0", "LVL_1", "LVL_2", "LVL_3"]],
			["lights", "choice", "SET_LIGHTS", ["0", "2", "4", "8", "12", "16"]],
			["glow", "toggle", "SET_GLOW"],
			["post", "toggle", "SET_POST"],
			["fog", "choice", "SET_FOG", ["FOG_0", "FOG_1"]],
			["rain", "choice", "SET_RAIN", ["RAIN_0", "RAIN_1", "RAIN_2", "RAIN_3"]],
			["aa", "choice", "SET_AA", ["AA_0", "AA_1", "AA_2", "AA_3", "AA_4"]],
			["ssao", "toggle", "SET_SSAO"],
			["ssr", "toggle", "SET_SSR"],
			["windows", "choice", "SET_WINDOWS", ["WIN_0", "WIN_1"]],
			["texq", "choice", "SET_TEXQ", ["LVL_1", "LVL_2", "LVL_3"]],
			["particles", "choice", "SET_PARTICLES", ["LVL_0", "LVL_1", "LVL_2", "LVL_3"]]],
		[["window_mode", "choice", "SET_WINDOW_MODE", ["WM_0", "WM_1", "WM_2"]],
			["vsync", "toggle", "SET_VSYNC"],
			["fps_limit", "choice", "SET_FPS_LIMIT", ["FPS_0", "30", "60", "75", "120", "144"]],
			["show_fps", "toggle", "SET_SHOW_FPS"],
			["brightness", "slider", "SET_BRIGHTNESS", 0.6, 1.6, 0.05, "%"]],
		[["master", "slider", "SET_MASTER", 0.0, 1.0, 0.05, "%"],
			["music", "slider", "SET_MUSIC", 0.0, 1.0, 0.05, "%"],
			["sfx", "slider", "SET_SFX", 0.0, 1.0, 0.05, "%"],
			["ambience", "slider", "SET_AMBIENCE", 0.0, 1.0, 0.05, "%"],
			["voice", "slider", "SET_VOICE", 0.0, 1.0, 0.05, "%"],
			["subtitles", "toggle", "SET_SUBTITLES"]],
		[["mouse_sens", "slider", "SET_SENS", 0.03, 0.4, 0.01, ""],
			["mouse_smooth", "slider", "SET_MOUSE_SMOOTH", 0.0, 1.0, 0.05, "%"],
			["invert_y", "toggle", "SET_INVERT"],
			["mouse_raw", "toggle", "SET_MOUSE_RAW"],
			["auto_camera", "toggle", "SET_AUTOCAM"],
			["sprint_toggle", "toggle", "SET_SPRINT_TOGGLE"],
			["fov", "slider", "SET_FOV", 55.0, 100.0, 1.0, "°"],
			["head_bob", "toggle", "SET_HEADBOB"],
			["camera", "choice", "SET_CAMDEFAULT", ["CAM_TP", "CAM_FP"]]],
		[["language", "choice", "SET_LANGUAGE", ["LANG_TR", "LANG_EN", "LANG_DE"]]],
	]

func _select_cat(i: int) -> void:
	_cat_index = (i + _cats.size()) % _cats.size()
	for k in _cat_buttons.size():
		var b: Button = _cat_buttons[k]
		var on:= k == _cat_index
		b.add_theme_color_override("font_color", Color(1, 1, 1) if on else UiTheme.TEXT_DIM)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		b.get_node("U").visible = on
	for c in _row_box.get_children():
		c.queue_free()
	_rows.clear()
	for def in _cats[_cat_index]:
		var r:= SettingRow.new()
		var kind: String = def[1]
		if kind == "slider":
			r.setup(def[0], kind, def[2], [], def[3], def[4], def[5], def[6])
		elif kind == "choice":
			r.setup(def[0], kind, def[2], def[3])
		else:
			r.setup(def[0], kind, def[2])
		_row_box.add_child(r)
		_rows[def[0]] = r
		r.changed.connect(_on_row_changed.bind(r))
		r.focused_row.connect(_on_row_focus)
	_refresh_settings()
	UiSound.play("scroll", -14.0)
	if _row_box.get_child_count() > 0:
		(_row_box.get_child(0) as Control).grab_focus.call_deferred()

func _on_row_focus(r: SettingRow) -> void:
	_keytest_row = r.id if r.id in ["sprint_toggle", "auto_camera", "mouse_sens", "mouse_smooth", "invert_y", "mouse_raw", "fov", "head_bob", "camera"] else ""
	_desc_title.text = tr(r.title_key)
	var dk:= "DESC_" + r.id.to_upper()
	_desc_text.text = tr(dk) if tr(dk) != dk else ""
	if IMPACT.has(r.id):
		var lv: int = IMPACT[r.id]
		_desc_impact.text = tr("UI_IMPACT").to_upper() + ":  " + tr(["IMPACT_0", "IMPACT_1", "IMPACT_2"][lv]).to_upper()
		_desc_impact.add_theme_color_override("font_color", [Color(0.5, 0.9, 0.6), Color(1.0, 0.82, 0.4), Color(1.0, 0.45, 0.4)][lv])
	else:
		_desc_impact.text = ""

func _on_row_changed(v, r: SettingRow) -> void:
	var id:= r.id
	match id:
		"preset":
			Settings.set_preset(int(v))
		"renderer":
			Settings.set_graphics("renderer", ["gl_compatibility", "forward_plus"][int(v)])
		"lights":
			Settings.set_graphics("lights", [0, 2, 4, 8, 12, 16][int(v)])
		"window_mode", "vsync", "show_fps":
			Settings.set_display(id, v)
		"fps_limit":
			Settings.set_display("fps_limit", [0, 30, 60, 75, 120, 144][int(v)])
		"brightness":
			Settings.set_display("brightness", v)
			Settings.changed.emit("graphics")
		"master", "music", "sfx", "ambience", "voice", "subtitles":
			Settings.set_audio(id, v)
		"mouse_sens", "mouse_smooth", "invert_y", "fov", "head_bob", "mouse_raw", "auto_camera", "sprint_toggle":
			Settings.set_control(id, v)
			if id == "mouse_raw" and Game.in_game and get_tree().paused == false:
				Game.capture_mouse(true)
		"camera":
			Settings.set_control("camera", ["tp", "fp"][int(v)])
		"language":
			Settings.set_language(["tr", "en", "de"][int(v)])
			_retranslate()
			return
		_:
			Settings.set_graphics(id, v)
	_refresh_settings()

func _on_defaults() -> void:
	UiSound.play("confirm", -8.0)
	Settings.reset_all()
	Settings.set_preset(2)
	Settings.apply_display()
	Settings.apply_audio()
	Settings.set_language(Settings.language)
	_retranslate()

func _row_set(id: String, fn: String, v) -> void:
	if _rows.has(id):
		var r: SettingRow = _rows[id]
		r.call(fn, v)

func _refresh_settings() -> void:
	var g:= Settings.g
	_row_set("preset", "set_index", int(g["preset"]))
	_row_set("renderer", "set_index", 0 if g["renderer"] == "gl_compatibility" else 1)
	_row_set("render_scale", "set_value", float(g["render_scale"]))
	_row_set("dynamic_res", "set_toggle", bool(g["dynamic_res"]))
	_row_set("view_distance", "set_value", float(g["view_distance"]))
	_row_set("shadows", "set_index", int(g["shadows"]))
	_row_set("lights", "set_index", maxi([0, 2, 4, 8, 12, 16].find(int(g["lights"])), 0))
	_row_set("glow", "set_toggle", bool(g["glow"]))
	_row_set("post", "set_toggle", bool(g.get("post", true)))
	_row_set("fog", "set_index", int(g["fog"]))
	_row_set("rain", "set_index", int(g["rain"]))
	_row_set("aa", "set_index", int(g["aa"]))
	_row_set("ssao", "set_toggle", bool(g["ssao"]))
	_row_set("ssr", "set_toggle", bool(g["ssr"]))
	_row_set("windows", "set_index", int(g["windows"]))
	_row_set("texq", "set_index", int(g["texq"]))
	_row_set("particles", "set_index", int(g["particles"]))
	var d:= Settings.d
	_row_set("window_mode", "set_index", int(d["window_mode"]))
	_row_set("vsync", "set_toggle", bool(d["vsync"]))
	_row_set("fps_limit", "set_index", maxi([0, 30, 60, 75, 120, 144].find(int(d["fps_limit"])), 0))
	_row_set("show_fps", "set_toggle", bool(d["show_fps"]))
	_row_set("brightness", "set_value", float(d["brightness"]))
	for k in ["master", "music", "sfx", "ambience", "voice"]:
		_row_set(k, "set_value", float(Settings.a[k]))
	_row_set("subtitles", "set_toggle", bool(Settings.a["subtitles"]))
	_row_set("mouse_sens", "set_value", float(Settings.c["mouse_sens"]))
	_row_set("mouse_smooth", "set_value", float(Settings.c.get("mouse_smooth", 0.35)))
	_row_set("invert_y", "set_toggle", bool(Settings.c["invert_y"]))
	_row_set("mouse_raw", "set_toggle", bool(Settings.c.get("mouse_raw", false)))
	_row_set("auto_camera", "set_toggle", bool(Settings.c.get("auto_camera", true)))
	_row_set("sprint_toggle", "set_toggle", bool(Settings.c.get("sprint_toggle", false)))
	_row_set("fov", "set_value", float(Settings.c["fov"]))
	_row_set("head_bob", "set_toggle", bool(Settings.c["head_bob"]))
	_row_set("camera", "set_index", 0 if Settings.c["camera"] == "tp" else 1)
	_row_set("language", "set_index", ["tr", "en", "de"].find(Settings.language))
	if _restart_note:
		_restart_note.text = tr("SET_RESTART_NOTE") if Settings.renderer_pending != "" else ""

func _retranslate() -> void:
	_retranslate_node(self)
	for it in _items:
		(it as MenuItem).retranslate()
	for r in _rows.values():
		(r as SettingRow).retranslate()
	_refresh_settings()

func _retranslate_node(n: Node) -> void:
	if n.has_meta("tr_key"):
		var txt:= tr(n.get_meta("tr_key"))
		if n.has_meta("upper"):
			txt = txt.to_upper()
		if n is Label:
			(n as Label).text = txt
		elif n is Button and not (n is MenuItem):
			(n as Button).text = txt
	for c in n.get_children():
		_retranslate_node(c)
