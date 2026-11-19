class_name MenuItem
extends Button

signal highlighted(item: MenuItem)

var key:= ""
var desc_key:= ""
var _t:= 0.0
var _style:= StyleBoxEmpty.new()

func setup(p_key: String, p_desc:= "", size:= 34) -> MenuItem:
	key = p_key
	desc_key = p_desc
	text = tr(key).to_upper()
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_font_override("font", UiTheme.tracked(UiTheme.font_ui, 2))
	add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(st, _style)
	custom_minimum_size = Vector2(420, size + 18)
	focus_mode = Control.FOCUS_ALL
	return self

func _ready() -> void:
	mouse_entered.connect(grab_focus)
	focus_entered.connect(_on_focus)
	pressed.connect(func (): UiSound.play("click", -8.0))

func _on_focus() -> void:
	UiSound.play("hover", -16.0)
	highlighted.emit(self)

func retranslate() -> void:
	text = tr(key).to_upper()

func _process(delta: float) -> void:
	var target:= 1.0 if (has_focus() or is_hovered()) else 0.0
	if absf(_t - target) > 0.001:
		_t = move_toward(_t, target, delta * 6.0)
		queue_redraw()
	_style.content_margin_left = 26.0 + 16.0 * ease(_t, 0.4)
	var c:= UiTheme.TEXT_DIM.lerp(Color(1, 1, 1), _t)
	add_theme_color_override("font_color", c)
	add_theme_color_override("font_hover_color", c)
	add_theme_color_override("font_focus_color", c)
	add_theme_color_override("font_pressed_color", UiTheme.ACCENT.lightened(0.3))

func _draw() -> void:
	if _t <= 0.001:
		return
	var w:= size.x * (0.35 + 0.65 * _t)
	var steps:= 12
	for i in steps:
		var a:= 0.22 * _t * (1.0 - float(i) / steps)
		draw_rect(Rect2(w * i / steps, 4, w / steps + 1, size.y - 8), Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, a))
	draw_rect(Rect2(0, 4, 4.0 * _t, size.y - 8), UiTheme.ACCENT)
