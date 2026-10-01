# Implements §10.5 soak runs (S-01, S-01b and the short self-test variants): a headless
# accelerated match driven by the Autopilot, with the per-tick invariants and the
# end-of-run statistics checked. `run()` returns {ok, failures, stats}.
class_name SoakRunner
extends RefCounted

const OVERLAP_TOLERANCE: float = 0.5

var mode: StringName
var bots: int
var rng_seed: int
var seconds: int

var failures: Array[String] = []
var stats: Dictionary = {}

# Event tallies (EventBus is global, so the runner listens while it runs)
var _boost_spawns: int = 0
var _picked_ids: Dictionary = {}
var _bot_shots_in_stealth: int = 0
var _bot_damage_in_stealth: float = 0.0
var _sim: MatchSim = null

func _init(p_mode: StringName, p_bots: int, p_seed: int, p_seconds: int) -> void:
	mode = p_mode
	bots = p_bots
	rng_seed = p_seed
	seconds = p_seconds

## `full_checks` adds the end-of-run statistics of S-01 / S-01b (the short self-test
## variants only check the per-tick invariants).
func run(full_checks: bool) -> Dictionary:
	var wall_t0 := Time.get_ticks_usec()
	var cfg := MatchConfig.new()
	cfg.mode = mode
	cfg.bot_count = bots
	cfg.rng_seed = rng_seed
	cfg.duration_s = float(seconds)

	var sim := MatchSim.new()
	_sim = sim
	sim.setup(cfg)
	sim.init_match()
	sim.begin_active()
	var auto := Autopilot.new(sim.human_char, rng_seed)

	EventBus.rocket_boost_spawned.connect(_on_boost_spawned)
	EventBus.weapon_picked_up.connect(_on_picked_up)
	EventBus.socket_item_spawned.connect(_on_socket_item)
	EventBus.character_damaged.connect(_on_damaged)

	var dt := 1.0 / 60.0
	var total_ticks := seconds * 60
	var world := Rect2(0.0, 0.0, float(sim.grid.cols * sim.grid.tile_size), float(sim.grid.rows * sim.grid.tile_size))
	var tick_us := PackedInt64Array()
	tick_us.resize(total_ticks)
	var sum_us := 0
	var last_shots: Dictionary = {}
	for b in sim.bot_chars:
		last_shots[b.id] = 0
	var fire_window: Array = [] # per tick: Array of bot ids that fired
	var max_allowed_window: Array[int] = []
	var bubble_bot_ticks := 0
	var sniper := mode == &"sniper_post"
	var max_tokens_seen := 0
	var inv2_worst := 0

	for t in range(total_ticks):
		var frame := auto.step(t, dt, sim)
		var t0 := Time.get_ticks_usec()
		sim.step(dt, frame)
		var us := Time.get_ticks_usec() - t0
		tick_us[t] = us
		sum_us += us

		var human := sim.human_char
		var stealthed := human.life_state == Enums.LifeState.ALIVE and human.stealth_t > 0.0
		var allowed := sim.director.allowed_tokens()

		# INV-1: token holders <= allowed(phase) <= 2
		var holders := 0
		for bid in sim.director.bot_data:
			if bool(sim.director.bot_data[bid]["has_token"]):
				holders += 1
		max_tokens_seen = maxi(max_tokens_seen, holders)
		if holders > allowed or allowed > 2:
			_fail("INV-1 tick %d: %d token holders, allowed %d" % [t, holders, allowed])

		# INV-2: distinct bots firing at Skyra in any 1.0 s window <= allowed + 1
		var fired_now: Array[int] = []
		for b in sim.bot_chars:
			var shots := b.stats.shots_fired if b.stats else 0
			var beam_on := sim.beams.get_beam(b.id).active
			var w := b.inventory.active_weapon()
			var flaming := w != null and w.flaming
			if shots != int(last_shots[b.id]) or beam_on or flaming:
				fired_now.append(b.id)
			last_shots[b.id] = shots
		fire_window.append(fired_now)
		max_allowed_window.append(allowed)
		if fire_window.size() > 60:
			fire_window.pop_front()
			max_allowed_window.pop_front()
		var distinct := {}
		for ids in fire_window:
			for id in ids:
				distinct[id] = true
		inv2_worst = maxi(inv2_worst, distinct.size())
		if distinct.size() > max_allowed_window.max() + 1:
			_fail("INV-2 tick %d: %d distinct bots fired in 1 s (allowed %d)" % [t, distinct.size(), max_allowed_window.max()])

		# INV-3: during stealth no bot shots, no damage, no bot targeting Skyra
		if stealthed:
			if not fired_now.is_empty():
				_bot_shots_in_stealth += 1
				_fail("INV-3 tick %d: bots %s fired during stealth" % [t, str(fired_now)])
			for b in sim.bot_chars:
				var brain := b.brain as BotBrain
				if brain and b.life_state == Enums.LifeState.ALIVE and (brain.perception.sees_human or brain.perception.has_known_target(sim.time) \
						or brain.state == Enums.BotState.TARGET_ACQUIRE or brain.state == Enums.BotState.ENGAGE):
					_fail("INV-3 tick %d: %s targets Skyra during stealth" % [t, b.name])

		# INV-4: <= 1 live bot grenade
		if sim._count_live_bot_grenades() > 1:
			_fail("INV-4 tick %d: %d live bot grenades" % [t, sim._count_live_bot_grenades()])

		# INV-5 statistic: non-token bots inside the engagement bubble
		if human.life_state == Enums.LifeState.ALIVE:
			for b in sim.bot_chars:
				if b.life_state == Enums.LifeState.ALIVE and not bool(sim.director.bot_data[b.id]["has_token"]) \
						and b.pos.distance_to(human.pos) < sim.director.bubble_radius:
					bubble_bot_ticks += 1

		# Physical invariants
		for c in sim.characters:
			if not (is_finite(c.pos.x) and is_finite(c.pos.y) and is_finite(c.vel.x) and is_finite(c.vel.y)):
				_fail("NaN/INF on %s at tick %d" % [c.name, t])
			if c.pos.x < world.position.x or c.pos.x > world.end.x or c.pos.y < world.position.y or c.pos.y > world.end.y:
				_fail("%s out of bounds at tick %d: %s" % [c.name, t, str(c.pos)])
			if c.life_state == Enums.LifeState.ALIVE:
				var box := c.aabb()
				for r in sim.grid.solid_rects_in(box):
					var ov := box.intersection(r)
					if ov.size.x > OVERLAP_TOLERANCE and ov.size.y > OVERLAP_TOLERANCE:
						_fail("%s overlaps a solid by %s at tick %d" % [c.name, str(ov.size), t])
						break
		if sim.projectiles.projectiles.size() > ProjectileSystem.MAX_PROJECTILES:
			_fail("projectiles > 512 at tick %d" % t)
		if sim.loose_weapons.size() > MatchSim.LOOSE_WEAPON_CAP:
			_fail("loose weapons > 12 at tick %d" % t)
		if sim.boost.active_boost_count() > 1:
			_fail("more than one Rocket Boost at tick %d" % t)
		if sniper:
			for c in sim.characters:
				for w in c.inventory.slots:
					if w and w.def.id != &"m93ba":
						_fail("Sniper Post: %s holds %s at tick %d" % [c.name, w.def.id, t])
			for lw in sim.loose_weapons:
				if lw.def.id != &"m93ba":
					_fail("Sniper Post: loose %s at tick %d" % [lw.def.id, t])
		if failures.size() > 20:
			break

	EventBus.rocket_boost_spawned.disconnect(_on_boost_spawned)
	EventBus.weapon_picked_up.disconnect(_on_picked_up)
	EventBus.socket_item_spawned.disconnect(_on_socket_item)
	EventBus.character_damaged.disconnect(_on_damaged)

	# End-of-run statistics
	var ticks_done := maxi(1, tick_us.size())
	tick_us.sort()
	var human_stats := sim.human_char.stats
	var bot_kills_on_skyra := 0
	for b in sim.bot_chars:
		if b.stats:
			bot_kills_on_skyra += b.stats.kills_on_human
	stats = {
		"skyra_kills": human_stats.kills if human_stats else 0,
		"skyra_deaths": human_stats.deaths if human_stats else 0,
		"bot_kills_on_skyra": bot_kills_on_skyra,
		"boost_spawns": _boost_spawns,
		"weapons_picked": _picked_ids.keys(),
		"inv5": float(bubble_bot_ticks) / float(ticks_done),
		"max_tokens": max_tokens_seen,
		"inv2_worst": inv2_worst,
		"bot_respawns": sim.bot_respawns,
		"spawn_fallbacks": sim.bot_spawn_fallbacks,
		"mean_ms": float(sum_us) / float(ticks_done) / 1000.0,
		"p99_ms": float(tick_us[int(ticks_done * 0.99)]) / 1000.0,
		"wall_s": float(Time.get_ticks_usec() - wall_t0) / 1000000.0,
	}
	if full_checks:
		var min_kills := 2 if sniper else 5
		if stats["skyra_kills"] < min_kills:
			_fail("Skyra kills %d < %d" % [stats["skyra_kills"], min_kills])
		if not sniper:
			if stats["skyra_deaths"] < 1:
				_fail("Skyra deaths %d < 1" % stats["skyra_deaths"])
			if bot_kills_on_skyra < 1:
				_fail("bot kills on Skyra %d < 1" % bot_kills_on_skyra)
			if _boost_spawns < 3:
				_fail("Rocket Boost spawned %d < 3 times" % _boost_spawns)
			if _picked_ids.size() < 6:
				_fail("distinct weapons picked up %d < 6 (%s)" % [_picked_ids.size(), str(_picked_ids.keys())])
			if stats["inv5"] > 0.5:
				_fail("INV-5 %.3f > 0.5" % stats["inv5"])
			if sim.bot_respawns > 0 and float(sim.bot_spawn_fallbacks) / float(sim.bot_respawns) > 0.02:
				_fail("bot spawn fallbacks %d of %d > 2%%" % [sim.bot_spawn_fallbacks, sim.bot_respawns])
		if stats["mean_ms"] > 2.0:
			_fail("mean Sim tick %.3f ms > 2.0" % stats["mean_ms"])
		if stats["p99_ms"] > 4.0:
			_fail("p99 Sim tick %.3f ms > 4.0" % stats["p99_ms"])
		if stats["wall_s"] > 30.0:
			_fail("wall clock %.1f s > 30" % stats["wall_s"])
	sim.teardown()
	_sim = null
	return {"ok": failures.is_empty(), "failures": failures, "stats": stats}

func _fail(msg: String) -> void:
	if failures.size() <= 20:
		failures.append(msg)

func _on_boost_spawned(_socket_id: StringName, _pos: Vector2) -> void:
	_boost_spawns += 1

func _on_picked_up(_id: int, weapon_id: StringName, _socket_id: StringName) -> void:
	_picked_ids[weapon_id] = true
	if mode == &"sniper_post" and weapon_id != &"m93ba":
		_fail("Sniper Post: picked up %s" % weapon_id)

func _on_socket_item(_socket_id: StringName, item_id: StringName) -> void:
	if mode == &"sniper_post" and item_id != &"m93ba" and item_id != &"frag_pack":
		_fail("Sniper Post: socket spawned %s" % item_id)

func _on_damaged(ev: DamageEvent) -> void:
	if _sim == null or ev.target_id != _sim.human_char.id:
		return
	var human := _sim.human_char
	if human.stealth_t > 0.0 and ev.amount > 0.0:
		_bot_damage_in_stealth += ev.amount
		_fail("INV-3: Skyra took %.1f damage during stealth" % ev.amount)
