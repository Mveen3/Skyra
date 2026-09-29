# Implements §10.5 Autopilot: scripted human driver for soak tests.
class_name Autopilot
extends RefCounted

var skyra: CharacterState
var brain: BotBrain
var rng: RandomNumberGenerator

func _init(human: CharacterState, random_seed: int = 42) -> void:
	skyra = human
	brain = BotBrain.new(human, random_seed)
	rng = RandomNumberGenerator.new()
	rng.seed = random_seed
	brain.rng = rng
	# Always grant attack permission to autopilot (§10.5 ignores Director tokens)
	brain.set_director_status(true, Enums.DirectorRole.ATTACKER, true)

## Steps the autopilot brain for this tick and returns Skyra's InputFrame.
func step(tick: int, dt: float, sim: MatchSim) -> InputFrame:
	if skyra.life_state != Enums.LifeState.ALIVE:
		return InputFrame.new()

	# Find the nearest living bot to target
	var nearest_bot: CharacterState = null
	var min_dist_sq: float = INF
	for b in sim.bot_chars:
		if b.life_state == Enums.LifeState.ALIVE:
			var d_sq: float = skyra.pos.distance_squared_to(b.pos)
			if d_sq < min_dist_sq:
				min_dist_sq = d_sq
				nearest_bot = b

	var target: CharacterState = nearest_bot if nearest_bot != null else skyra

	# Keep token active
	brain.has_token = true
	brain.is_self_defender = true
	brain.role = Enums.DirectorRole.ATTACKER

	var frame: InputFrame = brain.step_tick(
		tick, dt, target, sim.grid, sim.nav, sim.tac, sim.director, [], sim.time
	)

	return frame
