# Implements §10.5 Autopilot: Skyra driven by a BotBrain that ignores Director tokens,
# targets the nearest visible bot, and uses pickups and the Rocket Boost.
class_name Autopilot
extends RefCounted

const BOOST_SEEK_RANGE: float = 9000.0
const BOOST_PREPOSITION_S: float = 12.0
const BOOST_REQUESTER_ID: int = 1000 # nav queue id, distinct from every character id

var skyra: CharacterState
var brain: BotBrain
var rng: RandomNumberGenerator
var target: CharacterState = null
# Rocket Boost run: own path, movement only (aim and fire still come from the brain)
var boost_follower: PathFollower = PathFollower.new()
var boost_goal: Vector2 = Vector2(-1.0, -1.0)
var boost_repath_t: float = 0.0

func _init(human: CharacterState, random_seed: int = 42) -> void:
	skyra = human
	brain = BotBrain.new(human, random_seed)
	rng = RandomNumberGenerator.new()
	rng.seed = random_seed
	brain.rng = rng
	brain.ignores_tokens = true
	# Always grant attack permission to autopilot (§10.5 ignores Director tokens)
	brain.set_director_status(true, Enums.DirectorRole.ATTACKER, false)

## Steps the autopilot brain for this tick and returns Skyra's InputFrame.
func step(tick: int, dt: float, sim: MatchSim) -> InputFrame:
	if skyra.life_state != Enums.LifeState.ALIVE:
		target = null
		return InputFrame.new()

	# Re-pick the target at think rate (or when it died): keep a visible target, else
	# the nearest visible bot, else the nearest living bot.
	if target == null or target.life_state != Enums.LifeState.ALIVE or tick % 6 == 0:
		var keep := target != null and target.life_state == Enums.LifeState.ALIVE and brain.perception.sees_human
		if not keep:
			var picked := _pick_target(sim)
			if picked != target:
				target = picked
				brain.perception.clear_memory()
				brain.aim_model.reset()
				brain.state = Enums.BotState.PATROL

	brain.has_token = true
	brain.is_self_defender = false
	brain.role = Enums.DirectorRole.ATTACKER
	var aim_target: CharacterState = target if target != null else skyra
	var frame := brain.step_tick(tick, dt, aim_target, sim.grid, sim.nav, sim.tac, sim.director, sim.loose_weapons, sim.time, sim.sockets)

	# Rocket Boost: whenever one is available, run for it (shooting on the way). Like a
	# player who knows the drop timer, head for the likely socket shortly before it lands.
	var boost_pos := Vector2(-1.0, -1.0)
	if sim.boost.is_available():
		boost_pos = sim.boost.current_pickup_pos + Vector2(0.0, 40.0)
	elif sim.boost.phase == RocketBoostManager.BoostPhase.SPAWNING_IN:
		boost_pos = sim.boost.current_pickup_pos + Vector2(0.0, 40.0)
	elif sim.boost.phase == RocketBoostManager.BoostPhase.WAITING and sim.boost.timer <= BOOST_PREPOSITION_S \
			and sim.boost.socket_defs.size() == 2:
		var likely := 0 if sim.boost.last_socket_idx == 1 else 1
		if sim.boost.last_socket_idx == -1:
			likely = 0 if skyra.pos.distance_to(sim.boost.socket_defs[0].world) <= skyra.pos.distance_to(sim.boost.socket_defs[1].world) else 1
		boost_pos = sim.boost.socket_defs[likely].world
	if boost_pos.x >= 0.0 and skyra.boost_t <= 0.0 and skyra.pos.distance_to(boost_pos) < BOOST_SEEK_RANGE:
		boost_repath_t -= dt
		if boost_goal != boost_pos or not boost_follower.has_path() or boost_follower.needs_repath or boost_repath_t <= 0.0:
			boost_goal = boost_pos
			boost_repath_t = 3.0
			var a := sim.nav.nearest_node_cell(skyra.pos + Vector2(0.0, -2.0))
			var b := sim.nav.nearest_node_cell(boost_pos + Vector2(0.0, -2.0))
			if a.x >= 0 and b.x >= 0:
				sim.nav.request_path(BOOST_REQUESTER_ID, a, b, false, _on_boost_path.bind(sim.nav, sim.grid))
		var mv := boost_follower.step(skyra, dt, sim.nav)
		frame.move_x = mv.move_x
		frame.jet_pressed = mv.jet_pressed
		frame.jet_held = mv.jet_held
		frame.crouch = mv.crouch
	else:
		boost_goal = Vector2(-1.0, -1.0)
		boost_follower.clear()
	return frame

func _on_boost_path(raw: Array[Vector2i], nav: NavGrid, grid: TileGrid) -> void:
	if boost_goal.x >= 0.0:
		boost_follower.set_path(nav.smooth_path(raw, grid))

func _pick_target(sim: MatchSim) -> CharacterState:
	var shoulder := skyra.shoulder()
	var best_visible: CharacterState = null
	var best_visible_d := INF
	var nearest: CharacterState = null
	var nearest_d := INF
	for b in sim.bot_chars:
		if b.life_state != Enums.LifeState.ALIVE:
			continue
		var d := skyra.pos.distance_squared_to(b.pos)
		if d < nearest_d:
			nearest_d = d
			nearest = b
		if d < best_visible_d and d < 2400.0 * 2400.0:
			var hit: Dictionary = sim.grid.raycast(shoulder, b.centre(), C.MASK_LOS)
			if not bool(hit["hit"]):
				best_visible_d = d
				best_visible = b
	return best_visible if best_visible != null else nearest
