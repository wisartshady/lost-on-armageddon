class_name PostFX
extends ColorRect

var mat: ShaderMaterial

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/post_symbiote.gdshader")
	mat.set_shader_parameter("veins", load("res://assets/textures/veins.png"))
	material = mat
	apply_settings()
	Settings.changed.connect(func (_s): apply_settings())

func apply_settings() -> void:
	var on: bool = Settings.g.get("post", true)
	visible = on
	var rs: float = Settings.g.get("render_scale", 1.0)
	mat.set_shader_parameter("sharpen", 0.25 + (1.0 - rs) * 1.2)
	mat.set_shader_parameter("brightness", float(Settings.d.get("brightness", 1.0)))
