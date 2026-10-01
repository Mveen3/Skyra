extends RefCounted
func run(tree: SceneTree) -> int:
	var cfg := MatchConfig.new()
	cfg.mode = &"mini_post"; cfg.bot_count = 7; cfg.rng_seed = 1234; cfg.duration_s = 180.0
	var sim := MatchSim.new(); sim.setup(cfg); sim.init_match(); sim.begin_active()
	var auto := Autopilot.new(sim.human_char, 1234)
	var dt := 1.0/60.0
	var fires := 0
	for t in range(60*60):
		var f := auto.step(t, dt, sim)
		if f.fire_pressed or f.fire_held: fires += 1
		sim.step(dt, f)
		if t % 60 == 0:
			var h := sim.human_char
			var b := auto.brain
			var w := h.inventory.active_weapon()
			print("t=%d st=%d goal=%s gk=%s path=%s tgt=%s sees=%s react=%.2f fires=%d hp=%.0f pos=%s w=%s clip=%s life=%d ext=%s shots=%d" % [t/60, b.state, str(b.goal_pos.round()), b.goal_kind, b.path_follower.has_path(), auto.target.name if auto.target else "-", b.perception.sees_human, b.perception.reaction_t, fires, h.health, str(h.pos.round()), w.def.id if w else "-", str(w.clip) if w else "-", h.life_state, b.external_goal_active, h.stats.shots_fired if h.stats else 0])
	sim.teardown()
	return 0
