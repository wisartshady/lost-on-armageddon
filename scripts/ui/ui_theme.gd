class_name UiTheme
extends RefCounted

const ACCENT:= Color(0.86, 0.17, 0.2)
const ACCENT_SOFT:= Color(0.86, 0.17, 0.2, 0.35)
const TEXT:= Color(0.93, 0.92, 0.9)
const TEXT_DIM:= Color(0.56, 0.58, 0.62)
const TEXT_FAINT:= Color(1, 1, 1, 0.32)
const PANEL:= Color(0.025, 0.028, 0.036, 0.9)
const CYAN:= Color(0.35, 0.85, 1.0)

static var _theme: Theme = null
static var font_regular: Font
static var font_bold: Font
static var font_light: Font
static var font_title: Font
static var font_display: Font
static var font_ui: Font
static var font_ui_med: Font
static var font_body: Font
static var font_body_med: Font

static func get_theme() -> Theme:
	if _theme:
		return _theme
	font_regular = load("res://assets/fonts/Inter-Regular.otf")
	font_bold = load("res://assets/fonts/Inter-Bold.otf")
	font_light = load("res://assets/fonts/Inter-Light.otf")
	font_title = load("res://assets/fonts/InterDisplay-Black.otf")
	font_display = load("res://assets/fonts/BebasNeue-Regular.ttf")
	font_ui = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	font_ui_med = load("res://assets/fonts/BarlowCondensed-Medium.ttf")
	font_body = load("res://assets/fonts/Barlow-Regular.ttf")
	font_body_med = load("res://assets/fonts/Barlow-Medium.ttf")
	var t:= Theme.new()
	t.default_font = font_body
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	var bn:= _box(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0))
	bn.content_margin_left = 18
	bn.content_margin_right = 18
	bn.content_margin_top = 8
	bn.content_margin_bottom = 8
	var bh:= _box(Color(1, 1, 1, 0.06), 0, ACCENT)
	bh.border_width_left = 3
	bh.content_margin_left = 24
	bh.content_margin_right = 18
	bh.content_margin_top = 8
	bh.content_margin_bottom = 8
	var bp:= bh.duplicate()
	bp.bg_color = Color(0.78, 0.16, 0.2, 0.2)
	for cls in ["Button", "OptionButton", "CheckBox"]:
		t.set_stylebox("normal", cls, bn)
		t.set_stylebox("hover", cls, bh)
		t.set_stylebox("pressed", cls, bp)
		t.set_stylebox("focus", cls, bh)
		t.set_stylebox("hover_pressed", cls, bp)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color(1, 1, 1))
		t.set_color("font_pressed_color", cls, Color(1, 1, 1))
		t.set_color("font_focus_color", cls, Color(1, 1, 1))
		t.set_font("font", cls, font_bold if cls == "Button" else font_regular)
	var ob:= _box(Color(1, 1, 1, 0.05), 1, Color(1, 1, 1, 0.15))
	ob.content_margin_left = 12
	ob.content_margin_right = 12
	ob.content_margin_top = 6
	ob.content_margin_bottom = 6
	t.set_stylebox("normal", "OptionButton", ob)
	var obh:= ob.duplicate()
	obh.border_color = ACCENT
	t.set_stylebox("hover", "OptionButton", obh)
	t.set_stylebox("focus", "OptionButton", obh)
	t.set_stylebox("pressed", "OptionButton", obh)
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.05, 0.055, 0.07, 0.98), 1, Color(1, 1, 1, 0.12)))
	t.set_stylebox("hover", "PopupMenu", _box(ACCENT_SOFT, 0, ACCENT))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 1, 1))
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 1, Color(1, 1, 1, 0.06)))
	t.set_stylebox("panel", "Panel", _box(PANEL, 0, Color(0, 0, 0, 0)))
	var sl:= _box(Color(1, 1, 1, 0.12), 0, Color(0, 0, 0, 0))
	sl.content_margin_top = 2
	sl.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", sl)
	var fill:= _box(ACCENT, 0, Color(0, 0, 0, 0))
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab:= _grabber()
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)
	var tab_sel:= _box(Color(1, 1, 1, 0.06), 0, ACCENT)
	tab_sel.border_width_bottom = 3
	tab_sel.content_margin_left = 16
	tab_sel.content_margin_right = 16
	tab_sel.content_margin_top = 8
	tab_sel.content_margin_bottom = 8
	var tab_un:= _box(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0))
	tab_un.content_margin_left = 16
	tab_un.content_margin_right = 16
	tab_un.content_margin_top = 8
	tab_un.content_margin_bottom = 8
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_un)
	t.set_stylebox("tab_hovered", "TabBar", tab_un)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_un)
	t.set_stylebox("panel", "TabContainer", _box(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0)))
	t.set_color("font_selected_color", "TabContainer", Color(1, 1, 1))
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_font("font", "TabContainer", font_bold)
	t.set_stylebox("panel", "ScrollContainer", _box(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0)))
	_theme = t
	return t

static func _box(bg: Color, border: int, border_col: Color) -> StyleBoxFlat:
	var s:= StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = border
	s.border_width_right = border
	s.border_width_top = border
	s.border_width_bottom = border
	s.border_color = border_col
	return s

static func _grabber() -> Texture2D:
	var img:= Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 16:
		for x in 16:
			var d:= Vector2(x - 7.5, y - 7.5).length()
			if d < 6.5:
				img.set_pixel(x, y, Color(0.95, 0.95, 0.97))
	return ImageTexture.create_from_image(img)

static func place(c: Control, preset: int, size: Vector2, shift:= Vector2.ZERO) -> void:
	c.size = size
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_KEEP_SIZE)
	c.offset_left += shift.x
	c.offset_right += shift.x
	c.offset_top += shift.y
	c.offset_bottom += shift.y

static func label(text: String, size:= 18, font: Font = null, color:= TEXT) -> Label:
	var l:= Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", color)
	return l

static func tracked(f: Font, spacing: int) -> FontVariation:
	var fv:= FontVariation.new()
	fv.base_font = f
	fv.spacing_glyph = spacing
	return fv

static func keycap(key: String, size:= 15) -> PanelContainer:
	var pc:= PanelContainer.new()
	var sb:= StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.border_color = Color(1, 1, 1, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	pc.add_theme_stylebox_override("panel", sb)
	var l:= label(key, size, font_ui, TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pc

static func shadowed(l: Label, outline:= 5) -> Label:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", outline)
	return l
