# Implements §7.3 SkyLayer: a full-screen sunset sky (sky.gdshader) on CanvasLayer −10,
# fixed to the screen behind every world layer.
class_name SkyBackground
extends CanvasLayer

func _ready() -> void:
	layer = C.LAYER_SKY
	follow_viewport_enabled = false
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/view/shaders/sky.gdshader")
	rect.material = mat
	add_child(rect)
	_mat = mat
	if _night:
		_apply_night()

var _mat: ShaderMaterial
var _night: bool = false

## Mode atmosphere: Mini Post keeps the golden sunset; Sniper Post is a moonlit night
## (deep indigo sky, pale moon high on the left) so the two modes feel like two maps.
func apply_theme(night: bool) -> void:
	_night = night
	if _mat != null and night:
		_apply_night()

func _apply_night() -> void:
	_mat.set_shader_parameter("sky_top", Color("#03050F"))
	_mat.set_shader_parameter("sky_mid", Color("#121A3D"))
	_mat.set_shader_parameter("sky_horizon", Color("#2E3570"))
	_mat.set_shader_parameter("sky_bottom", Color("#4B4A86"))
	_mat.set_shader_parameter("sun_color", Color("#E6EEFF"))
	_mat.set_shader_parameter("sun_pos", Vector2(0.2, 0.22))
	_mat.set_shader_parameter("sun_radius", 55.0)
	_mat.set_shader_parameter("star_boost", 1.0)
