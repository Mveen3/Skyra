# Implements §7.6 Phaser beams (white 3-wu core + cyan 12-wu additive glow, jitter,
# 0.08-s fade on release, end sparks), §3.10.4 Black Arrow laser sights (Skyra α 0.55;
# bots α 0.35 while acquiring/engaging her — a fair telegraph) and the dotted grenade
# trajectory preview while Skyra holds the throw button.
class_name BeamView
extends Node2D

const LASER_RANGE: float = 7000.0
const LASER_COLOR := Color("#FF3355")

var sim: MatchSim
var _glow: Node2D
var _fade: Dictionary = {} # shooter id -> {a, b, t}
var _t: float = 0.0

func setup(p_sim: MatchSim) -> void:
	sim = p_sim
	_glow = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	add_child(_glow)
	_glow.draw.connect(_draw_glow)

func _process(delta: float) -> void:
	_t += delta
	if sim:
		for id in sim.beams.beams_by_char_id:
			var b: BeamSystem.BeamState = sim.beams.beams_by_char_id[id]
			if b.active:
				_fade[id] = {"a": b.start_pt, "b": b.end_pt, "t": 0.08}
			elif _fade.has(id):
				_fade[id].t -= delta
				if _fade[id].t <= 0.0:
					_fade.erase(id)
	if sim == null:
		return
	queue_redraw()
	_glow.queue_redraw()

func _zoom() -> float:
	var cam := get_viewport().get_camera_2d()
	return cam.zoom.x if cam else 1.0

func _draw() -> void:
	if sim == null:
		return
	var z := _zoom()
	for id in _fade:
		var f: Dictionary = _fade[id]
		var k: float = clampf(f.t / 0.08, 0.0, 1.0)
		var jitter := Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0)) / z
		draw_line(f.a, f.b + jitter, Color(1, 1, 1, k), 3.0)
	for c in sim.characters:
		if c.life_state != Enums.LifeState.ALIVE:
			continue
		var w := c.inventory.active_weapon()
		if w and w.def.laser_sight:
			_draw_laser(c, z)
	_draw_grenade_preview(z)

func _draw_glow() -> void:
	for id in _fade:
		var f: Dictionary = _fade[id]
		var k: float = clampf(f.t / 0.08, 0.0, 1.0)
		_glow.draw_line(f.a, f.b, Color(0.22, 0.9, 1.0, 0.55 * k), 12.0)
		Palette.draw_glow(_glow, f.b, 26.0 + 6.0 * sin(_t * 60.0), Color(0.6, 1.0, 1.0, 0.9 * k))
		Palette.draw_glow(_glow, f.a, 18.0, Color(0.6, 1.0, 1.0, 0.8 * k))

func _draw_laser(c: CharacterState, z: float) -> void:
	var alpha := 0.55
	if not c.is_human:
		var brain: BotBrain = c.brain as BotBrain
		if brain == null:
			return
		var aiming := brain.state == Enums.BotState.TARGET_ACQUIRE or brain.state == Enums.BotState.ENGAGE
		if not aiming or not brain.perception.sees_human:
			return
		alpha = 0.35
	var a := WeaponLogic.muzzle_of(c)
	var b := a + c.aim_dir * LASER_RANGE
	var hit: Dictionary = sim.grid.raycast(a, b, C.MASK_LASER)
	if bool(hit["hit"]):
		b = hit["point"]
	draw_line(a, b, Color(LASER_COLOR, alpha), 2.0 / z)
	draw_circle(b, 4.0 / z, Color(LASER_COLOR, minf(1.0, alpha + 0.3)))

func _draw_grenade_preview(z: float) -> void:
	var h := sim.human_char
	if h.life_state != Enums.LifeState.ALIVE or not h.inventory.grenade_aiming:
		return
	var launch := WeaponLogic.grenade_launch(h, h.aim_dir)
	var pts := GrenadeBallistics.predict(launch["pos"], launch["vel"], sim.grid, Data.grenade.preview_time_s, 1)
	for i in range(0, pts.size(), 3):
		var k := float(i) / float(maxi(1, pts.size()))
		draw_circle(pts[i], (5.0 - 2.0 * k) / maxf(z, 0.5), Color(1, 1, 1, 0.85 - 0.5 * k))
	if pts.size() > 0:
		draw_arc(pts[pts.size() - 1], 14.0, 0.0, TAU, 20, Color(1.0, 0.3, 0.3, 0.8), 2.5 / z)
