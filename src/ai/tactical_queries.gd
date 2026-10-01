# Implements §5.8 Tactical queries: cover, hold, flank, retreat, and patrol points.
class_name TacticalQueries
extends RefCounted

var cover_nodes: Array[Vector2i] = []
var patrol_nodes: Array[Vector2] = []

static func _shuffle_array(arr: Array, p_rng: RandomNumberGenerator) -> void:
	if not p_rng or arr.is_empty():
		return
	for i in range(arr.size() - 1, 0, -1):
		var j := p_rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func init_cache(nav_grid: NavGrid, tile_grid: TileGrid, map_data: MapData) -> void:
	cover_nodes.clear()
	patrol_nodes.clear()

	var w := tile_grid.width
	var h := tile_grid.height

	var is_solid_col := func(c: int, r: int) -> bool:
		if c < 0 or c >= w: return true
		var t1 := tile_grid.tile_at(c, r)
		var t2 := tile_grid.tile_at(c, r - 1)
		var s1 := (t1 == Enums.Tile.ROCK or t1 == Enums.Tile.METAL or t1 == Enums.Tile.CRATE or t1 == Enums.Tile.HALF)
		var s2 := (t2 == Enums.Tile.ROCK or t2 == Enums.Tile.METAL or t2 == Enums.Tile.CRATE or t2 == Enums.Tile.HALF)
		return s1 and s2

	for cell in nav_grid.nodes:
		var n: NavGrid.NavNode = nav_grid.nodes[cell]
		if not n.standable:
			continue

		var is_interior := (tile_grid.tile_at(cell.x, cell.y) == Enums.Tile.AIR_INTERIOR)
		var adj_solid: bool = bool(is_solid_col.call(cell.x - 1, cell.y)) or bool(is_solid_col.call(cell.x + 1, cell.y))
		if is_interior or adj_solid:
			cover_nodes.append(cell)

	# Patrol points: all W and P sockets plus zone centroids
	for s in map_data.sockets:
		patrol_nodes.append(s.pos)

	for z in map_data.zones:
		for r in z.rects:
			patrol_nodes.append(Vector2(r.get_center()) * 64.0)

func find_cover(bot: CharacterState, human: CharacterState, tile_grid: TileGrid, nav_grid: NavGrid) -> Vector2:
	var bot_pos := bot.pos
	var human_centre := human.centre() if human else Vector2.ZERO

	var candidates: Array[Dictionary] = []
	for cell in cover_nodes:
		var n: NavGrid.NavNode = nav_grid.nodes.get(cell)
		if not n: continue
		var d := bot_pos.distance_to(n.pos)
		if d <= 900.0:
			candidates.append({"cell": cell, "pos": n.pos, "dist": d})

	# Sort by distance to bot, take top 24
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var d_a: float = float(a["dist"])
		var d_b: float = float(b["dist"])
		if not is_equal_approx(d_a, d_b):
			return d_a < d_b
		return a["cell"].x < b["cell"].x if a["cell"].x != b["cell"].x else a["cell"].y < b["cell"].y
	)
	var top_count: int = mini(24, candidates.size())

	var best_pos := bot_pos
	var best_score := 999999.0
	var found := false

	for idx in range(top_count):
		var cand: Dictionary = candidates[idx]
		var c_pos: Vector2 = cand["pos"]
		var cand_centre := c_pos + Vector2(0, -42)

		# Require no LOS from Skyra's centre to candidate's centre (3 rays)
		var r1 := tile_grid.raycast(human_centre, cand_centre, C.MASK_LOS)
		var r2 := tile_grid.raycast(human_centre, cand_centre + Vector2(0, 30), C.MASK_LOS)
		var r3 := tile_grid.raycast(human_centre, cand_centre + Vector2(0, -30), C.MASK_LOS)

		if r1.hit and r2.hit and r3.hit:
			var d_bot := bot_pos.distance_to(c_pos)
			var d_human := human_centre.distance_to(c_pos)
			var score := d_bot - 0.3 * d_human
			if score < best_score:
				best_score = score
				best_pos = c_pos
				found = true

	return best_pos if found else bot_pos

## Hidden from Skyra = all three rays blocked; the first clear ray ends the test early.
static func _hidden_from(human_centre: Vector2, centre: Vector2, tile_grid: TileGrid) -> bool:
	for off in [0.0, 30.0, -30.0]:
		if not bool(tile_grid.raycast(human_centre, centre + Vector2(0.0, off), C.MASK_LOS)["hit"]):
			return false
	return true

## Up to `count` random standable node positions inside the staging ring (§5.8 sampling).
static func _ring_samples(nav_grid: NavGrid, human_pos: Vector2, ring_min: float, ring_max: float,
		count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var in_ring := PackedVector2Array()
	var rmin2 := ring_min * ring_min
	var rmax2 := ring_max * ring_max
	for p in nav_grid.standable_pos:
		var d2 := human_pos.distance_squared_to(p)
		if d2 >= rmin2 and d2 <= rmax2:
			in_ring.append(p)
	var n := in_ring.size()
	var take := mini(count, n)
	# Partial Fisher-Yates with the bot's seeded RNG (deterministic, §1.5)
	for i in range(take):
		var j := rng.randi_range(i, n - 1) if rng else i
		var tmp := in_ring[i]
		in_ring[i] = in_ring[j]
		in_ring[j] = tmp
	return in_ring.slice(0, take)

func find_hold_point(bot: CharacterState, human: CharacterState, ring_min: float, ring_max: float,
                     other_bot_points: Array, nav_grid: NavGrid, tile_grid: TileGrid, rng: RandomNumberGenerator) -> Vector2:
	var human_pos := human.pos if human else Vector2(3840, 2000)
	var human_centre := human.centre() if human else Vector2(3840, 2000)
	var ring_mid := (ring_min + ring_max) * 0.5
	var samples := _ring_samples(nav_grid, human_pos, ring_min, ring_max, 40, rng)
	if samples.is_empty():
		return bot.pos
	var best_pos := bot.pos
	var best_score := -999999.0
	for p in samples:
		var d := human_pos.distance_to(p)
		var score := -0.002 * absf(d - ring_mid)
		if not _hidden_from(human_centre, p + Vector2(0, -42), tile_grid):
			score -= 1.0 # fallback penalty
		for pt in other_bot_points:
			if p.distance_to(pt as Vector2) < 300.0:
				score -= 1.0
				break
		if score > best_score:
			best_score = score
			best_pos = p
	return best_pos

func find_flank_point(bot: CharacterState, human: CharacterState, ring_min: float, ring_max: float,
                      other_attacker_points: Array, nav_grid: NavGrid, tile_grid: TileGrid, rng: RandomNumberGenerator) -> Vector2:
	var human_pos := human.pos if human else Vector2(3840, 2000)
	var human_centre := human.centre() if human else Vector2(3840, 2000)
	var human_aim_dir := human.aim_dir if human else Vector2.RIGHT
	var ring_mid := (ring_min + ring_max) * 0.5
	var samples := _ring_samples(nav_grid, human_pos, ring_min, ring_max, 40, rng)
	if samples.is_empty():
		return bot.pos
	var best_pos := bot.pos
	var best_score := -999999.0
	for p in samples:
		var d := human_pos.distance_to(p)
		var score := -0.002 * absf(d - ring_mid)
		if not _hidden_from(human_centre, p + Vector2(0, -42), tile_grid):
			score -= 1.0
		var to_candidate := (p - human_pos).normalized()
		if to_candidate.dot(human_aim_dir) < 0.3:
			score += 1.0 # Side / behind
		# Angle to nearest attacker > 90 deg
		var min_angle_deg := 180.0
		for atk_pt in other_attacker_points:
			var to_atk := (atk_pt as Vector2 - human_pos).normalized()
			min_angle_deg = minf(min_angle_deg, rad_to_deg(absf(to_candidate.angle_to(to_atk))))
		if min_angle_deg > 90.0:
			score += 0.5
		if score > best_score:
			best_score = score
			best_pos = p
	return best_pos

func retreat_point(bot: CharacterState, human: CharacterState, nav_grid: NavGrid, tile_grid: TileGrid) -> Vector2:
	var human_pos := human.pos if human else Vector2(3840, 2000)
	var human_centre := human.centre() if human else Vector2(3840, 2000)
	var bot_side := signf(bot.pos.x - human_pos.x)
	if bot_side == 0.0: bot_side = 1.0

	var candidates: Array[Dictionary] = []
	for cell in nav_grid.nodes:
		var n: NavGrid.NavNode = nav_grid.nodes[cell]
		if n.standable:
			var d_human := human_pos.distance_to(n.pos)
			if d_human >= 400.0 and d_human <= 700.0:
				var c_side := signf(n.pos.x - human_pos.x)
				if c_side == bot_side:
					var r1: Dictionary = tile_grid.raycast(human_centre, n.pos + Vector2(0, -42), C.MASK_LOS)
					var hidden: bool = bool(r1["hit"])
					var d_bot: float = bot.pos.distance_to(n.pos)
					candidates.append({"pos": n.pos, "dist": d_bot, "hidden": hidden, "cell": cell})

	if candidates.is_empty():
		return bot.pos

	# Prefer no LOS, nearest to bot
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["hidden"]) != bool(b["hidden"]):
			return bool(a["hidden"])
		var d_a: float = float(a["dist"])
		var d_b: float = float(b["dist"])
		if not is_equal_approx(d_a, d_b):
			return d_a < d_b
		return a["cell"].x < b["cell"].x if a["cell"].x != b["cell"].x else a["cell"].y < b["cell"].y
	)

	return candidates[0]["pos"]

func patrol_point(bot: CharacterState, rng: RandomNumberGenerator) -> Vector2:
	if patrol_nodes.is_empty():
		return bot.pos

	var valid: Array[Dictionary] = []
	var total_w := 0.0
	for pt in patrol_nodes:
		var d := bot.pos.distance_to(pt)
		if d >= 800.0:
			var w := 1.0 / (1.0 + d / 2000.0)
			valid.append({"pos": pt, "weight": w})
			total_w += w

	if valid.is_empty():
		return patrol_nodes[rng.randi_range(0, patrol_nodes.size() - 1)]

	var roll := rng.randf_range(0.0, total_w)
	var accum := 0.0
	for entry in valid:
		accum += float(entry["weight"])
		if roll <= accum:
			return entry["pos"]

	return valid.back()["pos"]
