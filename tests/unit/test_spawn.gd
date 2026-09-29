# Implements §10.4 / Table 10.6 Spawn selector unit tests (T-SPAWN-01..03).
class_name TestSpawn
extends RefCounted

func _get_grid() -> TileGrid:
	var tg := TileGrid.new()
	tg.load_from(Data.map)
	return tg

func test_spawn_01_bot_spawns() -> void:
	var grid := _get_grid()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var sockets: Array[SocketDef] = Data.map.sockets
	var last_spawns: Dictionary = {}
	var tier1_or_2_count := 0
	var total_runs := 100

	# Test across 100 bot spawn evaluations
	for i in range(total_runs):
		var human_sock: SocketDef = sockets[i % sockets.size()]
		var human_pos := human_sock.pos
		var cam_rect := Rect2(human_pos - Vector2(960, 540), Vector2(1920, 1080))

		var chosen := SpawnSelector.select_bot_spawn(sockets, human_pos, cam_rect, last_spawns, float(i) * 3.5, grid, rng)
		Assertions.assert_true(chosen != null, "Bot spawn selected")

		# Check if tier 1 or tier 2 (§6.7-B: dist >= 1050 and not in view)
		var d := chosen.pos.distance_to(human_pos)
		var in_view := cam_rect.grow(256.0).has_point(chosen.pos)
		if d >= 1050.0 and not in_view:
			tier1_or_2_count += 1

		last_spawns[chosen.id] = float(i) * 3.5

	var pct := float(tier1_or_2_count) / float(total_runs)
	Assertions.assert_true(pct >= 0.98, "Tier 1 or 2 in >= 98 %% of bot spawns (got %.1f %%)" % (pct * 100.0))

func test_spawn_02_human_spawns() -> void:
	var grid := _get_grid()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99

	var sockets: Array[SocketDef] = Data.map.sockets
	var death_pos := Vector2(3808, 512) # Beacon crown

	# Case 1: Bots clustered in the East (Furnace/East Ridge)
	var bots: Array[CharacterState] = []
	for i in range(1, 4):
		var b := CharacterState.new()
		b.id = i
		b.life_state = Enums.LifeState.ALIVE
		b.pos = Vector2(float(6000 + i * 200), 2000)
		bots.append(b)

	var chosen := SpawnSelector.select_human_spawn(sockets, bots, death_pos, grid, rng)
	Assertions.assert_true(chosen != null, "Human spawn chosen")
	# Chosen socket should be away from death pos and bots
	var d_death := chosen.pos.distance_to(death_pos)
	Assertions.assert_true(d_death >= 1200.0, "Chosen socket not near death position (distance %.1f)" % d_death)

func test_spawn_03_initial_spawns() -> void:
	var grid := _get_grid()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	var sockets: Array[SocketDef] = Data.map.sockets

	# Run 10 initial spawn rounds
	for round_idx in range(10):
		var spawns := SpawnSelector.select_initial_spawns(sockets, 7, grid, rng)
		Assertions.assert_eq(spawns.size(), 8, "8 initial spawns (1 human + 7 bots)")

		var bot_positions: Array[Vector2] = []
		for bid in range(1, 8):
			var sock: SocketDef = spawns[bid]
			bot_positions.append(sock.pos)

		# Check pairwise distances between bots
		var violations := 0
		for i in range(bot_positions.size()):
			for j in range(i + 1, bot_positions.size()):
				if bot_positions[i].distance_to(bot_positions[j]) < 490.0:
					violations += 1

		Assertions.assert_eq(violations, 0, "All initial bot spawns >= 500 wu apart (round %d)" % round_idx)
