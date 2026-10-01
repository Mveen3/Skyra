# Implements §7.3 ScreenFX (CanvasLayer 5): drives screen_fx.gdshader — low-health
# vignette (40 HP and below, pulsing), damage flash (0.35 decaying at 3/s), death
# desaturation (0.8 over 0.4 s) and the respawn white flash (0.35 -> 0 over 0.15 s).
class_name ScreenFx
extends CanvasLayer

var sim: MatchSim = null
var _rect: ColorRect
var _mat: ShaderMaterial
var _damage: float = 0.0
var _white: float = 0.0
var _desat: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	layer = C.LAYER_SCREEN_FX
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/view/shaders/screen_fx.gdshader")
	_rect.material = _mat
	add_child(_rect)
	_rect.visible = false
	EventBus.character_damaged.connect(func(ev: DamageEvent) -> void:
		if ev.target_id == 0:
			_damage = 0.35)
	EventBus.character_spawned.connect(func(id: int, _p: Vector2, _i: bool) -> void:
		if id == 0:
			_white = 0.35)

func bind(p_sim: MatchSim) -> void:
	sim = p_sim
	_damage = 0.0
	_white = 0.0
	_desat = 0.0

func _process(delta: float) -> void:
	_t += delta
	if sim == null:
		_rect.visible = false
		return
	var h := sim.human_char
	var dead := h.life_state != Enums.LifeState.ALIVE
	_desat = move_toward(_desat, 0.8 if dead else 0.0, delta / (0.4 if dead else 0.2) * 0.8)
	_damage = maxf(0.0, _damage - 3.0 * delta * 0.35)
	_white = maxf(0.0, _white - delta / 0.15 * 0.35)
	var vig := 0.0
	if not dead:
		vig = clampf((40.0 - h.health) / 40.0, 0.0, 1.0) * (0.6 + 0.2 * sin(_t * 6.0))
	var active := vig > 0.001 or _damage > 0.001 or _white > 0.001 or _desat > 0.001
	_rect.visible = active
	if active:
		_mat.set_shader_parameter("vignette", vig)
		_mat.set_shader_parameter("damage_flash", _damage)
		_mat.set_shader_parameter("white_flash", _white)
		_mat.set_shader_parameter("desaturate", _desat)
