# Implements §10.4 / Table 10.6 Navigation unit tests (T-NAV-01..04).
class_name TestNav
extends RefCounted

const DT: float = 1.0 / 60.0

func _get_grid() -> TileGrid:
	var tg := TileGrid.new()
	tg.load_from(Data.map)
	return tg

func test_nav_01_nav_build() -> void:
	var grid := _get_grid()
	var nav := NavGrid.new()
	nav.build(grid, Data.map.sockets)

	Assertions.assert_eq(nav.nodes.size(), 3272, "Nav build produces exactly 3272 nodes")

	for s in Data.map.sockets:
		Assertions.assert_true(nav.socket_nodes.has(s.id), "Socket %s has a mapped nav node" % s.id)
		var cell: Vector2i = nav.socket_nodes[s.id]
		Assertions.assert_true(nav.nodes.has(cell), "Socket node exists in nav grid")
		var node: NavGrid.NavNode = nav.nodes[cell]
		Assertions.assert_true(node.standable, "Socket %s node is standable" % s.id)

func test_nav_02_all_pairs_paths() -> void:
	var grid := _get_grid()
	var nav := NavGrid.new()
	nav.build(grid, Data.map.sockets)

	var sockets: Array[SocketDef] = Data.map.sockets
	var total_pairs := 0
	var total_time_usec := 0

	for i in range(sockets.size()):
		var s1: SocketDef = sockets[i]
		var c1: Vector2i = nav.socket_nodes[s1.id]
		for j in range(sockets.size()):
			if i == j: continue
			var s2: SocketDef = sockets[j]
			var c2: Vector2i = nav.socket_nodes[s2.id]

			var t0 := Time.get_ticks_usec()
			var path := nav.find_path(c1, c2, false, grid, 4000)
			var elapsed := Time.get_ticks_usec() - t0
			total_time_usec += elapsed
			total_pairs += 1

			Assertions.assert_true(not path.is_empty(), "Path found from %s to %s" % [s1.id, s2.id])
			Assertions.assert_eq(path[0], c1, "Path starts at s1")
			Assertions.assert_eq(path.back(), c2, "Path ends at s2")

			# Consecutive nodes 8-adjacent
			for step_idx in range(path.size() - 1):
				var curr: Vector2i = path[step_idx]
				var nxt: Vector2i = path[step_idx + 1]
				var d_step: int = maxi(abs(nxt.x - curr.x), abs(nxt.y - curr.y))
				Assertions.assert_true(d_step == 1, "Consecutive nodes are 8-adjacent")

	var mean_ms := float(total_time_usec) / float(total_pairs) / 1000.0
	Assertions.assert_true(mean_ms <= 3.0, "Mean search time <= 3.0 ms (got %.2f ms)" % mean_ms)

func test_nav_03_bubble_avoidance() -> void:
	var grid := _get_grid()
	var nav := NavGrid.new()
	nav.build(grid, Data.map.sockets)

	# Test path along the sky bridge / ridge
	# s1 = W04 (west hangar, 46, 21), s2 = W12 (east hangar, 73, 21)
	var c1 := Vector2i(46, 21)
	var c2 := Vector2i(73, 21)

	# Direct path without bubble
	nav.bubble_radius = 0.0
	var direct_path := nav.find_path(c1, c2, false, grid)
	Assertions.assert_true(not direct_path.is_empty(), "Direct path found")

	# Place bubble at midpoint (spire center, 60 * 64, 21 * 64) with radius 500
	var bubble_pt := Vector2(60 * 64, 21 * 64)
	nav.bubble_center = bubble_pt
	nav.bubble_radius = 500.0

	# Non-token path should avoid the bubble
	var detour_path := nav.find_path(c1, c2, true, grid)
	Assertions.assert_true(not detour_path.is_empty(), "Detour path found")

	var direct_cost := float(direct_path.size())
	var detour_cost := float(detour_path.size())
	Assertions.assert_true(detour_cost <= direct_cost * 1.5 + 10.0, "Detour <= 1.5x exists")

	# Check that detour path does not traverse the bubble center
	var min_dist_to_center := 9999.0
	for cell in detour_path:
		var n: NavGrid.NavNode = nav.nodes.get(cell)
		if n:
			var d := n.pos.distance_to(bubble_pt)
			if d < min_dist_to_center:
				min_dist_to_center = d
	Assertions.assert_true(min_dist_to_center >= 300.0, "Detour avoids bubble center (min dist %.1f)" % min_dist_to_center)

func test_nav_04_follow_long_path() -> void:
	var grid := _get_grid()
	var nav := NavGrid.new()
	nav.build(grid, Data.map.sockets)

	var p07_cell: Vector2i = nav.socket_nodes["P07"]
	var b01_cell: Vector2i = nav.socket_nodes["B01"]

	var raw_path := nav.find_path(p07_cell, b01_cell, false, grid)
	Assertions.assert_true(not raw_path.is_empty(), "Path found from P07 to B01")

	var smoothed := nav.smooth_path(raw_path, grid)
	var follower := PathFollower.new()
	follower.set_path(smoothed)

	var bot := CharacterState.new()
	bot.id = 1
	bot.pos = nav.nodes[p07_cell].pos
	bot.vel = Vector2.ZERO
	bot.fuel = 100.0

	var goal_pos: Vector2 = nav.nodes[b01_cell].pos
	var ticks := 0
	var max_ticks := 30 * 60 # 30 simulated seconds
	var stuck_count := 0

	while ticks < max_ticks and bot.pos.distance_to(goal_pos) > 120.0:
		if follower.needs_repath:
			stuck_count += 1
			var curr_cell := grid.cell_of(bot.pos)
			if not nav.nodes.has(curr_cell):
				var best_c: Vector2i = curr_cell
				var best_d := 9999.0
				for c in nav.nodes:
					var d: float = Vector2(curr_cell).distance_to(Vector2(c))
					if d < best_d:
						best_d = d
						best_c = c
				curr_cell = best_c
			var repath := nav.find_path(curr_cell, b01_cell, false, grid)
			follower.set_path(nav.smooth_path(repath, grid))

		var frame := follower.step(bot, DT, nav)
		CharacterMotor.step(bot, frame, DT, grid)
		ticks += 1

	Assertions.assert_true(bot.pos.distance_to(goal_pos) <= 120.0, "Reached B01 in <= 30 s (distance %.1f)" % bot.pos.distance_to(goal_pos))
	Assertions.assert_true(stuck_count <= 3, "Stuck recoveries <= 3 (got %d)" % stuck_count)
