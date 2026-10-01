# Implements §4.6 Phaser beam algorithm: 0.08-s warm-up, then a hitscan beam each tick
# that damages every eligible character along it (pierces), stopped by solid tiles.
class_name BeamSystem
extends RefCounted

const BEAM_RANGE: float = 3400.0
const BEAM_DPS: float = 75.0
const HEAD_MULT: float = 1.25

class BeamState:
	var active: bool = false
	var charging: bool = false
	var warmup_t: float = 0.0
	var beam_time: float = 0.0
	var start_pt: Vector2 = Vector2.ZERO
	var end_pt: Vector2 = Vector2.ZERO
	var hit_wall: bool = false
	var wall_normal: Vector2 = Vector2.ZERO
	var fade_t: float = 0.0 # visual fade after release (view only)

var beams_by_char_id: Dictionary = {}

func get_beam(char_id: int) -> BeamState:
	if not beams_by_char_id.has(char_id):
		beams_by_char_id[char_id] = BeamState.new()
	return beams_by_char_id[char_id]

func _set_active(c: CharacterState, beam: BeamState, on: bool) -> void:
	if beam.active != on:
		beam.active = on
		EventBus.beam_state_changed.emit(c.id, on)

func _stop(c: CharacterState, beam: BeamState) -> void:
	_set_active(c, beam, false)
	beam.charging = false
	beam.warmup_t = 0.0

func step_beam(c: CharacterState, frame: InputFrame, dt: float, grid: TileGrid,
               characters: Array, damage_system: DamageSystem) -> void:
	var beam := get_beam(c.id)
	var inv: Inventory = c.inventory
	var w: WeaponInstance = inv.active_weapon() if inv else null

	if c.life_state != Enums.LifeState.ALIVE or not w or w.def.id != "phasr":
		_stop(c, beam)
		return

	if not (frame.fire_held and w.state == Enums.WeaponState.IDLE and w.clip > 0.0):
		_stop(c, beam)
		return

	var warmup_s := float(w.def.special.get("beam", {}).get("warmup_s", 0.08))
	beam.warmup_t += dt
	if beam.warmup_t < warmup_s:
		beam.charging = true
		return

	beam.charging = false
	_set_active(c, beam, true)
	beam.beam_time += dt
	WeaponLogic._count_continuous_shot(c, w, dt)

	var weave_deg := 0.25 * sin(TAU * 9.0 * beam.beam_time)
	var dir := c.aim_dir.rotated(deg_to_rad(weave_deg))
	var shoulder := c.shoulder()
	var a := WeaponLogic.muzzle_of(c)
	# Muzzle occlusion (§4.5.4): a beam whose emitter is inside a wall starts at the wall
	var occ: Dictionary = grid.raycast(shoulder, a, C.MASK_PROJECTILE)
	if bool(occ["hit"]):
		a = occ["point"]
	var b := a + dir * BEAM_RANGE

	var wall: Dictionary = grid.raycast(a, b, C.MASK_PROJECTILE)
	var stop: Vector2 = wall["point"] if bool(wall["hit"]) else b
	beam.start_pt = a
	beam.end_pt = stop
	beam.hit_wall = bool(wall["hit"])
	beam.wall_normal = wall["normal"] if beam.hit_wall else Vector2.ZERO

	# Damage every eligible character intersecting segment (a, stop)
	for obj in characters:
		var target: CharacterState = obj as CharacterState
		if not ProjectileSystem.is_eligible(c.id, c.team, target):
			continue
		var seg_hit: Dictionary = Shapes.segment_intersects_rect(a, stop, target.aabb())
		if bool(seg_hit["hit"]):
			var head_hit: Dictionary = Shapes.segment_intersects_rect(a, stop, target.head_rect())
			var is_head := bool(head_hit["hit"])
			var dmg := BEAM_DPS * dt * (HEAD_MULT if is_head else 1.0)
			damage_system.queue_damage(target, c.id, c.team, "phasr", dmg, seg_hit["point"], dir, is_head, false, 0.5, c.stats.shots_fired)

	# Drain energy (25 units per second)
	w.clip = maxf(0.0, w.clip - w.def.ammo_per_second * dt)
	if w.clip <= 0.0:
		w.clip = 0.0
		_stop(c, beam)
		w.start_reload(c.id)
