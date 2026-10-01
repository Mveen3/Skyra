extends RefCounted
var sim: MatchSim
func run(tree: SceneTree) -> int:
	var cfg := MatchConfig.new()
	cfg.mode = &"mini_post"; cfg.bot_count = 7; cfg.rng_seed = 1234; cfg.duration_s = 180.0
	sim = MatchSim.new(); sim.setup(cfg); sim.init_match(); sim.begin_active()
	var auto := Autopilot.new(sim.human_char, 1234)
	EventBus.rocket_boost_spawned.connect(func(s, p): print("%.1f SPAWN %s %s skyra=%s" % [sim.time, s, str(p), str(sim.human_char.pos.round())]))
	EventBus.rocket_boost_collected.connect(func(i, d): print("%.1f COLLECT" % sim.time))
	EventBus.rocket_boost_despawned.connect(func(s): print("%.1f DESPAWN skyra=%s" % [sim.time, str(sim.human_char.pos.round())]))
	var dt := 1.0/60.0
	for t in range(180*60):
		var f := auto.step(t, dt, sim)
		sim.step(dt, f)
		if sim.boost.is_available() and t % 60 == 0:
			var b := auto.brain
			print("  %.0f st=%d bpath=%s idx=%d/%d dist=%.0f pos=%s life=%d sees=%s fuel=%.0f" % [sim.time, b.state, auto.boost_follower.has_path(), auto.boost_follower.current_idx, auto.boost_follower.waypoints.size(), sim.human_char.centre().distance_to(sim.boost.current_pickup_pos), str(sim.human_char.pos.round()), sim.human_char.life_state, b.perception.sees_human, sim.human_char.fuel])
	sim.teardown()
	return 0
