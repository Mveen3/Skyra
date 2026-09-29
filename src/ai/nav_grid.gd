# Implements §5.7 Navigation grid, edge costs, A* search, and path smoothing.
class_name NavGrid
extends RefCounted

class NavNode:
	var cell: Vector2i
	var pos: Vector2
	var standable: bool = false
	var updraft: bool = false
	var neighbors: Array[Vector2i] = []
	var neighbor_indices: PackedInt32Array = PackedInt32Array()
	var neighbor_x: PackedFloat32Array = PackedFloat32Array()
	var neighbor_y: PackedFloat32Array = PackedFloat32Array()
	var base_edge_costs: PackedFloat32Array = PackedFloat32Array()

class FastMinHeap:
	var priorities: PackedFloat32Array = PackedFloat32Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var size: int = 0

	func _init(capacity: int = 8192) -> void:
		priorities.resize(capacity)
		indices.resize(capacity)
		size = 0

	func clear() -> void:
		size = 0

	func push(p: float, idx: int) -> void:
		if size >= priorities.size():
			priorities.resize(size * 2)
			indices.resize(size * 2)
		var hole := size
		size += 1
		# Sift up (percolate)
		while hole > 0:
			var parent := (hole - 1) >> 1
			if p < priorities[parent]:
				priorities[hole] = priorities[parent]
				indices[hole] = indices[parent]
				hole = parent
			else:
				break
		priorities[hole] = p
		indices[hole] = idx

	func pop() -> int:
		var top_idx := indices[0]
		size -= 1
		if size > 0:
			var val_p := priorities[size]
			var val_i := indices[size]
			var hole := 0
			var half := size >> 1
			while hole < half:
				var left := (hole << 1) + 1
				var right := left + 1
				var best := left
				if right < size and priorities[right] < priorities[left]:
					best = right
				if priorities[best] >= val_p:
					break
				priorities[hole] = priorities[best]
				indices[hole] = indices[best]
				hole = best
			priorities[hole] = val_p
			indices[hole] = val_i
		return top_idx

	func is_empty() -> bool:
		return size == 0

var nodes: Dictionary = {} # Vector2i -> NavNode
var node_by_idx: Array[NavNode] = []
var socket_nodes: Dictionary = {} # StringName -> Vector2i
var bubble_center: Vector2 = Vector2(-9999, -9999)
var bubble_radius: float = 0.0
var grenade_positions: Array[Vector2] = []

# Reusable flat buffers for ultra-fast A* without allocations
var _g_score: PackedFloat32Array = PackedFloat32Array()
var _came_from: PackedInt32Array = PackedInt32Array()
var _visited_stamp: PackedInt32Array = PackedInt32Array()
var _closed_stamp: PackedInt32Array = PackedInt32Array()
var _current_stamp: int = 0
var _open_heap := FastMinHeap.new(8192)

func build(tile_grid: TileGrid, sockets: Array) -> void:
	nodes.clear()
	socket_nodes.clear()

	var w := tile_grid.width
	var h := tile_grid.height
	var total_cells := w * h

	node_by_idx.resize(total_cells)
	node_by_idx.fill(null)

	_g_score.resize(total_cells)
	_came_from.resize(total_cells)
	_visited_stamp.resize(total_cells)
	_visited_stamp.fill(0)
	_closed_stamp.resize(total_cells)
	_closed_stamp.fill(0)
	_current_stamp = 0

	var is_solid := func(c: int, r: int) -> bool:
		if c < 0 or c >= w or r < 0 or r >= h:
			return true
		var t := tile_grid.tile_at(c, r)
		return (t == Enums.Tile.ROCK or t == Enums.Tile.METAL or t == Enums.Tile.CRATE or t == Enums.Tile.HALF)

	# 1. Identify occupiable nodes (§5.7.1: y >= 1, (x, y) and (x, y-1) not solid)
	for r in range(1, h):
		for c in range(w):
			if not is_solid.call(c, r) and not is_solid.call(c, r - 1):
				var cell := Vector2i(c, r)
				var node := NavNode.new()
				node.cell = cell
				var below_tile := tile_grid.tile_at(c, r + 1)
				node.standable = (below_tile == Enums.Tile.ROCK or below_tile == Enums.Tile.METAL or below_tile == Enums.Tile.CRATE or below_tile == Enums.Tile.HALF or below_tile == Enums.Tile.ONE_WAY)
				node.updraft = (tile_grid.tile_at(c, r) == Enums.Tile.UPDRAFT)
				if node.standable:
					node.pos = Vector2(float(c * 64 + 32), float((r + 1) * 64 - 2))
				else:
					node.pos = Vector2(float(c * 64 + 32), float((r + 1) * 64 - 20))
				nodes[cell] = node
				node_by_idx[r * w + c] = node

	# 2. Add edges and precompute base edge costs
	for cell in nodes:
		var node: NavNode = nodes[cell]
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var next := Vector2i(cell.x + dx, cell.y + dy)
				if nodes.has(next):
					if dx != 0 and dy != 0:
						if not nodes.has(Vector2i(cell.x + dx, cell.y)) or not nodes.has(Vector2i(cell.x, cell.y + dy)):
							continue
					node.neighbors.append(next)
					node.neighbor_indices.append(next.y * w + next.x)
					node.neighbor_x.append(float(next.x))
					node.neighbor_y.append(float(next.y))
					var neighbor_node: NavNode = nodes[next]
					node.base_edge_costs.append(_calc_base_cost(node, neighbor_node, tile_grid))

	# 3. Map sockets to standable nodes
	for s in sockets:
		var sid: String = str(s.id)
		var scell: Vector2i = Vector2i(int(s.cell[0]), int(s.cell[1]))
		if nodes.has(scell) and nodes[scell].standable:
			socket_nodes[sid] = scell
		else:
			var best: Vector2i = scell
			var best_d: float = 999999.0
			for cand in nodes:
				var n: NavNode = nodes[cand]
				if n.standable:
					var d: float = Vector2(scell).distance_to(Vector2(cand))
					if d < best_d:
						best_d = d
						best = cand
			socket_nodes[sid] = best

func _calc_base_cost(from_node: NavNode, to_node: NavNode, tile_grid: TileGrid) -> float:
	var dx := to_node.cell.x - from_node.cell.x
	var dy := to_node.cell.y - from_node.cell.y

	var h_cost := (1.0 * 64.0) if (from_node.standable and to_node.standable) else (1.3 * 64.0)
	var v_cost := 0.0

	if dy == -1: # Up
		v_cost = (0.6 * 64.0) if (from_node.updraft or to_node.updraft) else (1.8 * 64.0)
	elif dy == 1: # Down
		v_cost = (1.6 * 64.0) if (from_node.updraft or to_node.updraft) else (0.8 * 64.0)
		if tile_grid.tile_at(to_node.cell.x, to_node.cell.y) == Enums.Tile.ONE_WAY:
			v_cost += 0.2 * 64.0

	if dx != 0 and dy != 0:
		return maxf(h_cost, v_cost) * 1.414
	elif dx != 0:
		return h_cost
	return v_cost

static func octile_dist(a: Vector2i, b: Vector2i) -> float:
	var dx := float(abs(a.x - b.x))
	var dy := float(abs(a.y - b.y))
	return (maxf(dx, dy) + 0.41421356 * minf(dx, dy)) * 51.2

func find_path(start: Vector2i, goal: Vector2i, is_non_token_bot: bool, tile_grid: TileGrid, max_expansions: int = 4000) -> Array[Vector2i]:
	if not nodes.has(start) or not nodes.has(goal):
		return []

	if start == goal:
		return [start]

	_current_stamp += 1
	var stamp := _current_stamp
	var w := tile_grid.width

	var start_idx := start.y * w + start.x
	var goal_idx := goal.y * w + goal.x

	var gx := float(goal.x)
	var gy := float(goal.y)
	var sx := float(start.x)
	var sy := float(start.y)
	var d_start_x := absf(sx - gx)
	var d_start_y := absf(sy - gy)
	var start_h := (maxf(d_start_x, d_start_y) + 0.41421356 * minf(d_start_x, d_start_y)) * 51.2

	_open_heap.clear()
	_open_heap.push(start_h, start_idx)

	_g_score[start_idx] = 0.0
	_visited_stamp[start_idx] = stamp
	_came_from[start_idx] = -1

	var best_idx := start_idx
	var best_h := start_h
	var expansions := 0

	var has_bubble := is_non_token_bot and (bubble_radius > 0.0)
	var has_grenades := not grenade_positions.is_empty()

	while not _open_heap.is_empty() and expansions < max_expansions:
		var curr_idx := _open_heap.pop()

		if _closed_stamp[curr_idx] == stamp:
			continue
		_closed_stamp[curr_idx] = stamp
		expansions += 1

		if curr_idx == goal_idx:
			# Reconstruct path
			var path: Array[Vector2i] = []
			var trace := curr_idx
			while trace != -1:
				path.append(node_by_idx[trace].cell)
				trace = _came_from[trace]
			path.reverse()
			return path

		var curr_node: NavNode = node_by_idx[curr_idx]
		var curr_g := _g_score[curr_idx]
		var n_indices := curr_node.neighbor_indices
		var n_costs := curr_node.base_edge_costs
		var n_x := curr_node.neighbor_x
		var n_y := curr_node.neighbor_y
		var neighbor_count := n_indices.size()

		for n_i in range(neighbor_count):
			var n_idx := n_indices[n_i]
			if _closed_stamp[n_idx] == stamp:
				continue

			var edge_cost := n_costs[n_i]

			if has_bubble:
				var n_node: NavNode = node_by_idx[n_idx]
				if n_node.pos.distance_to(bubble_center) < bubble_radius:
					edge_cost += 512.0 # 8.0 * 64

			if has_grenades:
				var n_node: NavNode = node_by_idx[n_idx]
				for g_pos in grenade_positions:
					if n_node.pos.distance_to(g_pos) < 300.0:
						edge_cost += 128.0 # 2.0 * 64
						break

			var tentative_g := curr_g + edge_cost

			if _visited_stamp[n_idx] != stamp or tentative_g < _g_score[n_idx]:
				_g_score[n_idx] = tentative_g
				_visited_stamp[n_idx] = stamp
				_came_from[n_idx] = curr_idx
				var nx := n_x[n_i]
				var ny := n_y[n_i]
				var d_x := absf(nx - gx)
				var d_y := absf(ny - gy)
				var h := (d_x + 0.41421356 * d_y) if d_x >= d_y else (d_y + 0.41421356 * d_x)
				var f_score := tentative_g + h * 52.0
				_open_heap.push(f_score, n_idx)

	# Partial path to best expanded node
	var partial_path: Array[Vector2i] = []
	var p_trace := best_idx
	while p_trace != -1:
		partial_path.append(node_by_idx[p_trace].cell)
		p_trace = _came_from[p_trace]
	partial_path.reverse()
	return partial_path

func smooth_path(path: Array[Vector2i], tile_grid: TileGrid) -> Array[Vector2]:
	if path.is_empty():
		return []

	var world_waypoints: Array[Vector2] = []
	for cell in path:
		var n: NavNode = nodes.get(cell)
		if n:
			world_waypoints.append(n.pos)
		else:
			world_waypoints.append(Vector2(float(cell.x * 64 + 32), float((cell.y + 1) * 64 - 2)))

	if world_waypoints.size() <= 2:
		return world_waypoints

	var smoothed: Array[Vector2] = [world_waypoints[0]]
	var i := 0
	var n_pts := world_waypoints.size()

	while i < n_pts - 1:
		var farthest := i + 1
		var max_lookahead: int = mini(i + 6, n_pts - 1)
		for j in range(max_lookahead, i + 1, -1):
			var from_pt: Vector2 = world_waypoints[i]
			var to_pt: Vector2 = world_waypoints[j]

			# Check if drops through a one-way tile
			var has_one_way_drop := false
			for step_idx in range(i, j):
				var c1: Vector2i = path[step_idx]
				var c2: Vector2i = path[step_idx + 1]
				if c2.y > c1.y and tile_grid.tile_at(c2.x, c2.y) == Enums.Tile.ONE_WAY:
					has_one_way_drop = true
					break

			if has_one_way_drop and j > i + 1:
				continue

			# 3 rays: feet + 8, centre, head - 8 with MASK_LOS
			var r1: Dictionary = tile_grid.raycast(from_pt + Vector2(0, -8), to_pt + Vector2(0, -8), C.MASK_LOS)
			var r2: Dictionary = tile_grid.raycast(from_pt + Vector2(0, -42), to_pt + Vector2(0, -42), C.MASK_LOS)
			var r3: Dictionary = tile_grid.raycast(from_pt + Vector2(0, -76), to_pt + Vector2(0, -76), C.MASK_LOS)

			if not bool(r1["hit"]) and not bool(r2["hit"]) and not bool(r3["hit"]):
				farthest = j
				break

		smoothed.append(world_waypoints[farthest])
		i = farthest

	return smoothed
