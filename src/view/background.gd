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
