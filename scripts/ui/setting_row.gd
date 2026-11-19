class_name SettingRow
extends PanelContainer

signal changed(value)
signal focused_row(row: SettingRow)

var id:= ""
var kind:= "choice"
var title_key:= ""
var items: Array = []
var index:= 0
var value:= 0.0
var min_v:= 0.0
var max_v:= 1.0
var step_v:= 0.05
var unit:= ""
var _name: Label
var _val: Label
var _left: Label
var _right: Label
var _slider: HSlider
var _bg: StyleBoxFlat
var _hover:= false

func setup(p_id: String, p_kind: String, p_title: String, p_items: Array = [], p_min:= 0.0, p_max:= 1.0, p_step:= 0.05, p_unit:= "") -> SettingRow:
	id = p_id
	kind = p_kind
	title_key = p_title
	items = p_items
	min_v = p_min
	max_v = p_max
	step_v = p_step
	unit = p_unit
	return self

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, 46)
	_bg = StyleBoxFlat.new()
	_bg.bg_color = Color(1, 1, 1, 0.0)
	_bg.content_margin_left = 18
	_bg.content_margin_right = 14
	add_theme_stylebox_override("panel", _bg)
	var hb:= HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)
	add_child(hb)
	_name = UiTheme.label(tr(title_key), 21, UiTheme.font_body_med, UiTheme.TEXT)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_name)
	var right:= HBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(right)
	if kind == "slider":
		_slider = HSlider.new()
		_slider.min_value = min_v
		_slider.max_value = max_v
		_slider.step = step_v
		_slider.custom_minimum_size = Vector2(230, 24)
		_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_slider.focus_mode = Control.FOCUS_NONE
		_slider.value_changed.connect(_on_slider)
		right.add_child(_slider)
		_val = UiTheme.label("", 20, UiTheme.font_ui, UiTheme.TEXT)
		_val.custom_minimum_size = Vector2(76, 0)
		_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(_val)
	else:
		_left = UiTheme.label("‹", 30, UiTheme.font_ui, UiTheme.TEXT_DIM)
		_left.mouse_filter = Control.MOUSE_FILTER_STOP
		_left.gui_input.connect(_arrow_input.bind(-1))
		right.add_child(_left)
		_val = UiTheme.label("", 21, UiTheme.font_ui, UiTheme.TEXT)
		_val.custom_minimum_size = Vector2(250, 0)
		_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		right.add_child(_val)
		_right = UiTheme.label("›", 30, UiTheme.font_ui, UiTheme.TEXT_DIM)
		_right.mouse_filter = Control.MOUSE_FILTER_STOP
		_right.gui_input.connect(_arrow_input.bind(1))
		right.add_child(_right)
	mouse_entered.connect(_on_mouse_in)
	mouse_exited.connect(_on_mouse_out)
	focus_entered.connect(_on_focus_in)
	focus_exited.connect(_style)
	gui_input.connect(_on_input)
	_refresh()

func _on_mouse_in() -> void:
	_hover = true
	grab_focus()

func _on_mouse_out() -> void:
	_hover = false
	_style()

func _on_focus_in() -> void:
	_style()
	focused_row.emit(self)

func retranslate() -> void:
	_name.text = tr(title_key)
	_refresh()

func set_index(i: int, emit:= false) -> void:
	index = clampi(i, 0, maxi(items.size() - 1, 0))
	_refresh()
	if emit:
		changed.emit(index)

func set_toggle(on: bool, emit:= false) -> void:
	index = 1 if on else 0
	_refresh()
	if emit:
		changed.emit(on)

func set_value(v: float, emit:= false) -> void:
	value = v
	if _slider:
		_slider.set_value_no_signal(v)
	_refresh()
	if emit:
		changed.emit(v)

func _refresh() -> void:
	if _val == null:
		return
	match kind:
		"choice":
			_val.text = tr(items[index]) if index >= 0 and index < items.size() else tr("PRESET_CUSTOM")
		"toggle":
			_val.text = tr("UI_ON") if index == 1 else tr("UI_OFF")
			_val.add_theme_color_override("font_color", UiTheme.TEXT if index == 1 else UiTheme.TEXT_DIM)
		"slider":
			if unit == "%":
				_val.text = "%d%%" % int(round(value * 100.0))
			elif unit == "":
				_val.text = "%.2f" % value
			else:
				_val.text = "%d%s" % [int(round(value)), unit]

func _cycle(dir: int) -> void:
	match kind:
		"choice":
			if items.is_empty():
				return
			index = (maxi(index, 0) + dir + items.size()) % items.size()
			_refresh()
			changed.emit(index)
		"toggle":
			index = 1 - index
			_refresh()
			changed.emit(index == 1)
		"slider":
			var v:= clampf(value + dir * step_v, min_v, max_v)
			set_value(v, true)
	UiSound.play("switch")

func _arrow_input(ev: InputEvent, dir: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_cycle(dir)
		accept_event()

func _on_slider(v: float) -> void:
	value = v
	_refresh()
	changed.emit(v)

func _on_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_left"):
		_cycle(-1)
		accept_event()
	elif ev.is_action_pressed("ui_right"):
		_cycle(1)
		accept_event()
	elif ev.is_action_pressed("ui_accept") and kind != "slider":
		_cycle(1)
		accept_event()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and kind != "slider":
		_cycle(1)
		accept_event()

func _style() -> void:
	var on:= has_focus() or _hover
	_bg.bg_color = Color(1, 1, 1, 0.055) if on else Color(1, 1, 1, 0.0)
	queue_redraw()
	_name.add_theme_color_override("font_color", Color(1, 1, 1) if on else UiTheme.TEXT.darkened(0.12))
	if _left:
		_left.add_theme_color_override("font_color", UiTheme.ACCENT.lightened(0.2) if on else UiTheme.TEXT_FAINT)
		_right.add_theme_color_override("font_color", UiTheme.ACCENT.lightened(0.2) if on else UiTheme.TEXT_FAINT)

func _draw() -> void:
	if has_focus():
		draw_rect(Rect2(0, 3, 3, size.y - 6), UiTheme.ACCENT)
