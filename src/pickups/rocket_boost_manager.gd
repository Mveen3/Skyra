# Implements §3.11 Rocket Boost power-up spawn manager and buff logic.
class_name RocketBoostManager
extends RefCounted

enum BoostPhase { WAITING, SPAWNING_IN, AVAILABLE, DESPAWNING }

var phase: int = BoostPhase.WAITING
var timer: float = 45.0
var socket_defs: Array[SocketDef] = []
var current_socket: SocketDef = null
var current_socket_id: StringName = &""
var current_pickup_pos: Vector2 = Vector2.ZERO
var last_socket_idx: int = -1
var rng_loot: RandomNumberGenerator = null

# Tuning (Appendix A rocket_boost; defaults match the spec)
var first_spawn_s: float = 45.0
var respawn_min_s: float = 35.0
var respawn_max_s: float = 50.0
var ground_lifetime_s: float = 30.0
var buff_s: float = 10.0
var spawn_in_s: float = 0.6
var despawn_s: float = 0.4
var alternate_chance: float = 0.7

# Invariant tracking
var concurrent_boost_violations: int = 0

func _init() -> void:
	rng_loot = RandomNumberGenerator.new()
	rng_loot.seed = 42

func setup(sockets: Array, rng: RandomNumberGenerator = null) -> void:
	var tb: Dictionary = Data.tuning.get("rocket_boost", {}) if Data.tuning else {}
	first_spawn_s = float(tb.get("first_spawn_s", first_spawn_s))
	respawn_min_s = float(tb.get("respawn_min_s", respawn_min_s))
	respawn_max_s = float(tb.get("respawn_max_s", respawn_max_s))
	ground_lifetime_s = float(tb.get("ground_lifetime_s", ground_lifetime_s))
	buff_s = float(tb.get("buff_s", buff_s))
	spawn_in_s = float(tb.get("spawn_in_s", spawn_in_s))
	despawn_s = float(tb.get("despawn_s", despawn_s))
	alternate_chance = float(tb.get("alternate_socket_chance", alternate_chance))
	if rng:
		rng_loot = rng
	socket_defs.clear()
	for s in sockets:
		var sdef := s as SocketDef
		if sdef and sdef.type == Enums.SocketType.BOOST:
			socket_defs.append(sdef)
		elif s is Dictionary:
			var t = s.get("type", "")
			if (t is String and t == "boost") or (t is int and t == Enums.SocketType.BOOST):
				var d := SocketDef.new()
				d.id = StringName(str(s["id"]))
				d.type = Enums.SocketType.BOOST
				d.cell = Vector2i(int(s["cell"][0]), int(s["cell"][1]))
				d.world = Vector2(float(s["world"][0]), float(s["world"][1]))
				d.zone = StringName(str(s.get("zone", "")))
				socket_defs.append(d)
	reset()

func reset() -> void:
	phase = BoostPhase.WAITING
	timer = first_spawn_s
	current_socket = null
	current_socket_id = &""
	current_pickup_pos = Vector2.ZERO
	last_socket_idx = -1
	concurrent_boost_violations = 0

func is_available() -> bool:
	return phase == BoostPhase.AVAILABLE

func active_boost_count() -> int:
	return 1 if (phase == BoostPhase.SPAWNING_IN or phase == BoostPhase.AVAILABLE) else 0

func _pick_next_socket() -> SocketDef:
	if socket_defs.is_empty():
		return null
	if socket_defs.size() == 1:
		last_socket_idx = 0
		return socket_defs[0]

	var next_idx := 0
	if last_socket_idx == -1:
		# First time 50/50 (§3.11.1)
		next_idx = 0 if rng_loot.randf() < 0.5 else 1
	else:
		# Afterwards the other socket with probability 0.7, the same one with 0.3 (§3.11.1)
		if rng_loot.randf() < alternate_chance:
			next_idx = 1 - last_socket_idx
		else:
			next_idx = last_socket_idx

	last_socket_idx = next_idx
	return socket_defs[next_idx]

func _start_next_delay() -> void:
	phase = BoostPhase.WAITING
	current_socket = null
	current_socket_id = &""
	current_pickup_pos = Vector2.ZERO
	timer = rng_loot.randf_range(respawn_min_s, respawn_max_s)

func step(dt: float, human: CharacterState = null, bots: Array = []) -> void:
	# Invariant check (§3.11.1, hard invariant)
	var count := active_boost_count()
	if count > 1:
		concurrent_boost_violations += 1

	# Tick active human buff
	if human:
		if human.life_state != Enums.LifeState.ALIVE and human.boost_t > 0.0:
			human.boost_t = 0.0
			EventBus.rocket_boost_expired.emit(human.id)
		elif human.boost_t > 0.0:
			human.boost_t = maxf(0.0, human.boost_t - dt)
			if human.boost_t <= 0.0:
				EventBus.rocket_boost_expired.emit(human.id)

	# State machine
	match phase:
		BoostPhase.WAITING:
			timer -= dt
			if timer <= 0.0:
				current_socket = _pick_next_socket()
				if current_socket:
					current_socket_id = current_socket.id
					current_pickup_pos = current_socket.world + Vector2(0, -40)
					phase = BoostPhase.SPAWNING_IN
					timer = spawn_in_s
					EventBus.rocket_boost_spawned.emit(current_socket_id, current_pickup_pos)
				else:
					_start_next_delay()

		BoostPhase.SPAWNING_IN:
			timer -= dt
			if timer <= 0.0:
				phase = BoostPhase.AVAILABLE
				timer = ground_lifetime_s

		BoostPhase.AVAILABLE:
			timer -= dt
			# Check collection: human only (bots cannot collect, §3.11.1)
			if human and human.life_state == Enums.LifeState.ALIVE:
				var dist := human.centre().distance_to(current_pickup_pos)
				if dist <= 56.0:
					# Collected!
					human.boost_t = buff_s
					if human.stats:
						human.stats.boosts_collected += 1
					EventBus.rocket_boost_collected.emit(human.id, buff_s)
					_start_next_delay()
					return

			# Despawn after 30 s
			if timer <= 0.0:
				phase = BoostPhase.DESPAWNING
				timer = despawn_s
				EventBus.rocket_boost_despawned.emit(current_socket_id)

		BoostPhase.DESPAWNING:
			timer -= dt
			if timer <= 0.0:
				_start_next_delay()
