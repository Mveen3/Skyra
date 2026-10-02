# Map features added to Outpost Skyra for both modes (see docs/DEVIATIONS.md DEV-009):
# launch pads (stand on one -> launched high above the Spire wings) and med stations
# (+45 HP for anyone below full health; respawn after 25 s). Pure Sim, deterministic.
class_name MapFeatures
extends RefCounted

class Pad:
	var id: StringName
	var pos: Vector2 # feet position on the pad's floor (centre)
	var cool_t: float = 0.0 # visual / re-trigger cooldown

class Med:
	var id: StringName
	var pos: Vector2 # feet position (centre of the station's floor)
	var active: bool = true
	var timer: float = 0.0

var pads: Array[Pad] = []
var meds: Array[Med] = []
var launch_speed: float = 1750.0
var launch_lock_s: float = 0.6
var pad_half_width: float = 34.0
var med_heal: float = 45.0
var med_respawn_s: float = 25.0
var med_radius: float = 52.0

func setup(tuning: Dictionary) -> void:
	var t: Dictionary = tuning.get("map_features", {})
	launch_speed = float(t.get("launch_speed", launch_speed))
	launch_lock_s = float(t.get("launch_lock_s", launch_lock_s))
	pad_half_width = float(t.get("pad_half_width", pad_half_width))
	med_heal = float(t.get("med_heal", med_heal))
	med_respawn_s = float(t.get("med_respawn_s", med_respawn_s))
	med_radius = float(t.get("med_radius", med_radius))
	pads.clear()
	meds.clear()
	for d: Dictionary in t.get("launch_pads", []):
		var p := Pad.new()
		p.id = StringName(str(d["id"]))
		p.pos = _cell_feet(d["cell"])
		pads.append(p)
	for d: Dictionary in t.get("med_stations", []):
		var m := Med.new()
		m.id = StringName(str(d["id"]))
		m.pos = _cell_feet(d["cell"])
		meds.append(m)

static func _cell_feet(cell: Array) -> Vector2:
	return Vector2(float(cell[0]) * 64.0 + 32.0, (float(cell[1]) + 1.0) * 64.0)

func step(dt: float, characters: Array) -> void:
	for p in pads:
		p.cool_t = maxf(0.0, p.cool_t - dt)
		for obj in characters:
			var c := obj as CharacterState
			if c.life_state != Enums.LifeState.ALIVE or c.launch_t > 0.0 or c.crouching:
				continue
			if absf(c.pos.x - p.pos.x) <= pad_half_width and absf(c.pos.y - p.pos.y) <= 6.0 and c.vel.y >= -1.0:
				c.vel.y = -launch_speed
				c.grounded = false
				c.launch_t = launch_lock_s
				p.cool_t = 0.35
				EventBus.launch_pad_used.emit(c.id, p.pos)
	for m in meds:
		if not m.active:
			m.timer -= dt
			if m.timer <= 0.0:
				m.active = true
				EventBus.med_respawned.emit(m.pos)
			continue
		for obj in characters:
			var c := obj as CharacterState
			if c.life_state != Enums.LifeState.ALIVE or c.health >= 100.0:
				continue
			if c.centre().distance_to(m.pos + Vector2(0.0, -40.0)) <= med_radius:
				var healed := minf(med_heal, 100.0 - c.health)
				c.health += healed
				m.active = false
				m.timer = med_respawn_s
				EventBus.med_collected.emit(c.id, m.pos, healed)
				break

## Nearest active med station to `p` (for bots that want to heal), or Vector2(-1, -1).
func nearest_active_med(p: Vector2, max_dist: float) -> Vector2:
	var best := Vector2(-1.0, -1.0)
	var best_d := max_dist
	for m in meds:
		if m.active and m.pos.distance_to(p) < best_d:
			best_d = m.pos.distance_to(p)
			best = m.pos
	return best
