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
## §5.2 / §5.7: at most this many A* searches per Sim tick (extra requests wait a tick).
const MAX_SEARCHES_PER_TICK: int = 1
## Only the first waypoints are line-of-sight smoothed; bots repath long before the rest.
const SMOOTH_WINDOW: int = 28
var _budget_tick: int = -1
var _searches_this_tick: int = 0
var standable_pos: PackedVector2Array = PackedVector2Array() # precomputed for tactical queries
var heuristic_scale: float = 51.2 # §5.7.1: octile distance × 0.8, in cost units (64 per tile)
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
var _h_score: PackedFloat32Array = PackedFloat32Array()
# Flat (CSR) adjacency for the A* hot loop: edges of cell index i are [_nbr_off[i], _nbr_off[i + 1])
var _nbr_off: PackedInt32Array = PackedInt32Array()
var _nbr_to: PackedInt32Array = PackedInt32Array()
var _nbr_cost: PackedFloat32Array = PackedFloat32Array()
var _cell_x: PackedFloat32Array = PackedFloat32Array()
var _cell_y: PackedFloat32Array = PackedFloat32Array()
var _pos_x: PackedFloat32Array = PackedFloat32Array()
var _pos_y: PackedFloat32Array = PackedFloat32Array()

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

	_build_flat_arrays(w, total_cells)
	standable_pos.clear()
	for idx in range(total_cells):
		var nn: NavNode = node_by_idx[idx]
		if nn and nn.standable:
			standable_pos.append(nn.pos)

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

## Reserves one A* search for `tick`; false when this tick's budget is used up.
func try_reserve_search(tick: int) -> bool:
	if tick != _budget_tick:
		_budget_tick = tick
		_searches_this_tick = 0
	if _searches_this_tick >= MAX_SEARCHES_PER_TICK:
		return false
	_searches_this_tick += 1
	return true

## Nav node for a world position: the cell containing `p` if it is a node, else the
## nearest node found by expanding square rings (standable nodes win ties).
func nearest_node_cell(p: Vector2, max_radius: int = 12) -> Vector2i:
	var cell := Vector2i(int(floor(p.x / 64.0)), int(floor(p.y / 64.0)))
	if nodes.has(cell):
		return cell
	var best := Vector2i(-1, -1)
	var best_d := INF
	for r in range(1, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := Vector2i(cell.x + dx, cell.y + dy)
				var n: NavNode = nodes.get(c)
				if n == null:
					continue
				var d := p.distance_squared_to(n.pos) - (1.0 if n.standable else 0.0)
				if d < best_d:
					best_d = d
					best = c
		if best.x >= 0:
			return best
	return best

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

func _build_flat_arrays(w: int, total_cells: int) -> void:
	_h_score.resize(total_cells)
	_cell_x.resize(total_cells)
	_cell_y.resize(total_cells)
	_pos_x.resize(total_cells)
	_pos_y.resize(total_cells)
	_nbr_off.resize(total_cells + 1)
	_nbr_to.clear()
	_nbr_cost.clear()
	for idx in range(total_cells):
		_nbr_off[idx] = _nbr_to.size()
		_cell_x[idx] = float(idx % w)
		_cell_y[idx] = float(idx / w)
		var node: NavNode = node_by_idx[idx]
		if node == null:
			continue
		_pos_x[idx] = node.pos.x
		_pos_y[idx] = node.pos.y
		_nbr_to.append_array(node.neighbor_indices)
		_nbr_cost.append_array(node.base_edge_costs)
	_nbr_off[total_cells] = _nbr_to.size()

## Synchronous A* (§5.7.1): binary heap, octile heuristic, at most `max_expansions`
## expansions; on failure returns a partial path to the expanded node closest to the goal.
func find_path(start: Vector2i, goal: Vector2i, is_non_token_bot: bool, tile_grid: TileGrid, max_expansions: int = 4000) -> Array[Vector2i]:
	if not nodes.has(start) or not nodes.has(goal):
		return []
	if start == goal:
		return [start]
	_search_begin(start, goal, is_non_token_bot, tile_grid.width)
	_search_run(max_expansions, max_expansions)
	return _search_result()

# ── Resumable search state (one search at a time) ────────────────────────────────

var _s_stamp: int = 0
var _s_start_idx: int = -1
var _s_goal_idx: int = -1
var _s_gx: float = 0.0
var _s_gy: float = 0.0
var _s_best_idx: int = -1
var _s_best_h: float = 0.0
var _s_expansions: int = 0
var _s_found: bool = false
var _s_bubble: bool = false
var _s_bubble_r2: float = 0.0
var _s_bcx: float = 0.0
var _s_bcy: float = 0.0
const _K: float = 0.41421356

func _octile_h(cx: float, cy: float) -> float:
	var d_x := absf(cx - _s_gx)
	var d_y := absf(cy - _s_gy)
	return ((d_x + _K * d_y) if d_x >= d_y else (d_y + _K * d_x)) * heuristic_scale

func _search_begin(start: Vector2i, goal: Vector2i, is_non_token_bot: bool, w: int) -> void:
	_current_stamp += 1
	_s_stamp = _current_stamp
	_s_start_idx = start.y * w + start.x
	_s_goal_idx = goal.y * w + goal.x
	_s_gx = float(goal.x)
	_s_gy = float(goal.y)
	_s_expansions = 0
	_s_found = false
	_s_bubble = is_non_token_bot and bubble_radius > 0.0
	_s_bubble_r2 = bubble_radius * bubble_radius
	_s_bcx = bubble_center.x
	_s_bcy = bubble_center.y
	var start_h := _octile_h(float(start.x), float(start.y))
	_open_heap.clear()
	_open_heap.push(start_h, _s_start_idx)
	_g_score[_s_start_idx] = 0.0
	_h_score[_s_start_idx] = start_h
	_visited_stamp[_s_start_idx] = _s_stamp
	_came_from[_s_start_idx] = -1
	_s_best_idx = _s_start_idx
	_s_best_h = start_h

## Expands up to `budget` nodes (and never beyond `cap` in total). True when finished.
func _search_run(budget: int, cap: int) -> bool:
	var stamp := _s_stamp
	var goal_idx := _s_goal_idx
	var gx := _s_gx
	var gy := _s_gy
	var hs := heuristic_scale
	# Move the work buffers into locals (refcount 1, so writes happen in place without
	# copy-on-write) and hand them back before returning.
	var g_score := _g_score; _g_score = PackedFloat32Array()
	var h_score := _h_score; _h_score = PackedFloat32Array()
	var came_from := _came_from; _came_from = PackedInt32Array()
	var visited := _visited_stamp; _visited_stamp = PackedInt32Array()
	var closed := _closed_stamp; _closed_stamp = PackedInt32Array()
	var nbr_off := _nbr_off
	var nbr_to := _nbr_to
	var nbr_cost := _nbr_cost
	var cell_x := _cell_x
	var cell_y := _cell_y
	var heap := _open_heap
	var has_bubble := _s_bubble
	var bubble_r2 := _s_bubble_r2
	var bcx := _s_bcx
	var bcy := _s_bcy
	var has_grenades := not grenade_positions.is_empty()
	var used := 0

	while heap.size > 0 and _s_expansions < cap and used < budget:
		var curr_idx := heap.pop()
		if closed[curr_idx] == stamp:
			continue
		closed[curr_idx] = stamp
		_s_expansions += 1
		used += 1

		if curr_idx == goal_idx:
			_s_found = true
			break

		# Expanded node closest to the goal, for the partial-path fallback (§5.7.1)
		var curr_h := h_score[curr_idx]
		if curr_h < _s_best_h:
			_s_best_h = curr_h
			_s_best_idx = curr_idx

		var curr_g := g_score[curr_idx]
		for k in range(nbr_off[curr_idx], nbr_off[curr_idx + 1]):
			var n_idx := nbr_to[k]
			if closed[n_idx] == stamp:
				continue
			var edge_cost := nbr_cost[k]
			if has_bubble:
				var bx := _pos_x[n_idx] - bcx
				var by := _pos_y[n_idx] - bcy
				if bx * bx + by * by < bubble_r2:
					edge_cost += 512.0 # +8.0 x 64 for non-token bots inside the bubble (§5.4.5)
			if has_grenades:
				var np := Vector2(_pos_x[n_idx], _pos_y[n_idx])
				for g_pos in grenade_positions:
					if np.distance_to(g_pos) < 300.0:
						edge_cost += 128.0 # +2.0 x 64 near a live grenade
						break
			var tentative_g := curr_g + edge_cost
			if visited[n_idx] != stamp or tentative_g < g_score[n_idx]:
				g_score[n_idx] = tentative_g
				visited[n_idx] = stamp
				came_from[n_idx] = curr_idx
				var d_x := absf(cell_x[n_idx] - gx)
				var d_y := absf(cell_y[n_idx] - gy)
				var h := ((d_x + _K * d_y) if d_x >= d_y else (d_y + _K * d_x)) * hs
				h_score[n_idx] = h
				heap.push(tentative_g + h, n_idx)

	_g_score = g_score
	_h_score = h_score
	_came_from = came_from
	_visited_stamp = visited
	_closed_stamp = closed
	return _s_found or heap.size == 0 or _s_expansions >= cap

func _search_result() -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var trace := _s_goal_idx if _s_found else _s_best_idx
	while trace != -1:
		path.append(node_by_idx[trace].cell)
		trace = _came_from[trace]
	path.reverse()
	return path

# ── Request queue (§5.2: FIFO, one pending request per bot, time-sliced) ─────────

## When true (MatchSim), bots queue their path requests and process_queue() advances
## the active search by a fixed expansion budget per tick, bounding the AI cost.
var async_enabled: bool = false
const SEARCH_CAP: int = 4000
var _queue: Array = [] # [requester_id, start, goal, non_token, callback]
var _active_job: Array = []

func request_path(requester_id: int, start: Vector2i, goal: Vector2i, is_non_token_bot: bool, callback: Callable) -> void:
	for i in range(_queue.size()):
		if _queue[i][0] == requester_id:
			_queue[i] = [requester_id, start, goal, is_non_token_bot, callback]
			return
	_queue.append([requester_id, start, goal, is_non_token_bot, callback])

func cancel_requests(requester_id: int) -> void:
	_queue = _queue.filter(func(j: Array) -> bool: return j[0] != requester_id)
	if not _active_job.is_empty() and _active_job[0] == requester_id:
		_active_job = []

func clear_queue() -> void:
	_queue.clear()
	_active_job = []

func has_pending(requester_id: int) -> bool:
	if not _active_job.is_empty() and _active_job[0] == requester_id:
		return true
	for j in _queue:
		if j[0] == requester_id:
			return true
	return false

## Spends at most `budget` node expansions this tick on queued searches.
func process_queue(tile_grid: TileGrid, budget: int = 450) -> void:
	while budget > 0:
		if _active_job.is_empty():
			if _queue.is_empty():
				return
			_active_job = _queue.pop_front()
			var start: Vector2i = _active_job[1]
			var goal: Vector2i = _active_job[2]
			if not nodes.has(start) or not nodes.has(goal) or start == goal:
				var cb0: Callable = _active_job[4]
				_active_job = []
				if cb0.is_valid():
					cb0.call([start] as Array[Vector2i] if nodes.has(start) else ([] as Array[Vector2i]))
				continue
			_search_begin(start, goal, _active_job[3], tile_grid.width)
		var before := _s_expansions
		var done := _search_run(budget, SEARCH_CAP)
		budget -= maxi(1, _s_expansions - before)
		if done:
			var cb: Callable = _active_job[4]
			_active_job = []
			if cb.is_valid():
				cb.call(_search_result())

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
	var smooth_end := mini(n_pts - 1, SMOOTH_WINDOW)

	while i < smooth_end:
		var farthest := i + 1
		var max_lookahead: int = mini(i + 6, smooth_end)
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

	for k in range(smooth_end + 1, n_pts):
		smoothed.append(world_waypoints[k])
	return smoothed
