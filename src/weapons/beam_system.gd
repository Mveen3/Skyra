# Implements §4.6 Phaser beam algorithm.
class_name BeamSystem
extends RefCounted

class BeamState:
	var active: bool = false
	var charging: bool = false
	var warmup_t: float = 0.0
	var beam_time: float = 0.0
	var start_pt: Vector2 = Vector2.ZERO
	var end_pt: Vector2 = Vector2.ZERO

var beams_by_char_id: Dictionary = {}

func get_beam(char_id: int) -> BeamState:
	if not beams_by_char_id.has(char_id):
		beams_by_char_id[char_id] = BeamState.new()
	return beams_by_char_id[char_id]

func step_beam(c: CharacterState, frame: InputFrame, dt: float, grid: TileGrid,
               characters: Array, damage_system: DamageSystem) -> void:
	var beam := get_beam(c.id)
	var inv: Inventory = c.inventory
	var w: WeaponInstance = inv.active_weapon() if inv else null

	if not w or w.def.id != "phasr":
		beam.active = false
		beam.charging = false
		beam.warmup_t = 0.0
		return

	if frame.fire_held and w.state == Enums.WeaponState.IDLE and w.clip > 0:
		beam.warmup_t += dt
		if beam.warmup_t < 0.08:
			beam.charging = true
			beam.active = false
			return

		beam.charging = false
		beam.active = true
		beam.beam_time += dt

		var weave_deg := 0.25 * sin(TAU * 9.0 * beam.beam_time)
		var dir := c.aim_dir.rotated(deg_to_rad(weave_deg))
		var a := c.shoulder() + c.aim_dir * 18.0
		var b := a + dir * 3400.0

		var wall: Dictionary = grid.raycast(a, b, C.MASK_PROJECTILE)
		var stop: Vector2 = wall["point"] if bool(wall["hit"]) else b
		beam.start_pt = a
		beam.end_pt = stop

		# Damage all eligible characters intersecting segment (a, stop)
		for obj in characters:
			var target: CharacterState = obj as CharacterState
			if not ProjectileSystem.is_eligible(c.id, c.team, target):
				continue
			var seg_hit: Dictionary = Shapes.segment_intersects_rect(a, stop, target.aabb())
			if bool(seg_hit["hit"]):
				var head_h := 20.0 if target.crouching else 24.0
				var head_rect := Rect2(target.aabb().position.x, target.aabb().position.y, target.aabb().size.x, head_h)
				var head_hit: Dictionary = Shapes.segment_intersects_rect(a, stop, head_rect)
				var mult := 1.25 if bool(head_hit["hit"]) else 1.0
				var dmg := 75.0 * dt * mult
				damage_system.queue_damage(target, c.id, c.team, "phasr", dmg, seg_hit["point"], dir, bool(head_hit["hit"]))

		# Drain energy ammo (25 units per second)
		w.clip = maxf(0.0, w.clip - 25.0 * dt)
		if w.clip <= 0.0:
			w.clip = 0.0
			beam.active = false
			w.start_reload()
	else:
		beam.active = false
		beam.charging = false
		beam.warmup_t = 0.0
