# Implements §6.7 Spawn selection for human and bots with tier evaluation and fallback logging.
class_name SpawnSelector
extends RefCounted

static func select_human_spawn(sockets: Array, bots: Array, last_death_pos: Vector2,
                               tile_grid: TileGrid, rng: RandomNumberGenerator) -> SocketDef:
	var p_sockets: Array[SocketDef] = []
	for s in sockets:
		var sock: SocketDef = s as SocketDef
		if sock and sock.type == Enums.SocketType.SPAWN:
			p_sockets.append(sock)

	if p_sockets.is_empty():
		return null

	var alive_bots: Array[CharacterState] = []
	for b in bots:
		var c: CharacterState = b as CharacterState
		if c and c.life_state == Enums.LifeState.ALIVE:
			alive_bots.append(c)

	var evaluated: Array[Dictionary] = []
	for sock in p_sockets:
		var sock_centre: Vector2 = sock.pos + Vector2(0, -42)
		var d_min: float = 99999.0
		var seen_by: int = 0

		for b in alive_bots:
			var d: float = sock.pos.distance_to(b.centre())
			if d < d_min:
				d_min = d
			# 3 rays LOS from bot shoulder to socket centre
			var shoulder: Vector2 = b.shoulder()
			var r1: Dictionary = tile_grid.raycast(shoulder, sock_centre, C.MASK_LOS)
			var r2: Dictionary = tile_grid.raycast(shoulder, sock_centre + Vector2(0, 30), C.MASK_LOS)
			var r3: Dictionary = tile_grid.raycast(shoulder, sock_centre + Vector2(0, -30), C.MASK_LOS)
			# Visible = a clear ray and within the bot's perception radius (§5.5, §6.7)
			var aw := b.inventory.active_weapon() if b.inventory else null
			var vis_r := 1400.0 * sqrt(aw.def.scope if aw else 1.0)
			var sdx := sock_centre.x - b.pos.x
			if signf(sdx) != float(b.facing) and absf(sdx) > 1.0:
				vis_r *= 0.6
			if (not bool(r1["hit"]) or not bool(r2["hit"]) or not bool(r3["hit"])) and d <= vis_r:
				seen_by += 1

		var near_death: bool = sock.pos.distance_to(last_death_pos) < 1200.0 if last_death_pos.x > -9000.0 else false
		evaluated.append({
			"socket": sock,
			"d_min": d_min,
			"seen_by": seen_by,
			"near_death": near_death
		})

	# Tier evaluation (§6.7-A)
	var tier_predicates: Array[Callable] = [
		func(e: Dictionary) -> bool: return float(e["d_min"]) >= 1600.0 and int(e["seen_by"]) == 0 and not bool(e["near_death"]),
		func(e: Dictionary) -> bool: return float(e["d_min"]) >= 1100.0 and int(e["seen_by"]) == 0,
		func(e: Dictionary) -> bool: return float(e["d_min"]) >= 700.0 and int(e["seen_by"]) <= 1,
		func(_e: Dictionary) -> bool: return true
	]

	for pred in tier_predicates:
		var valid: Array[Dictionary] = []
		for e in evaluated:
			if pred.call(e):
				valid.append(e)
		if not valid.is_empty():
			# Score sockets
			for e in valid:
				e["score"] = float(e["d_min"]) - 600.0 * float(e["seen_by"]) + rng.randf_range(0.0, 300.0)
			valid.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var s_a: float = float(a["score"])
				var s_b: float = float(b["score"])
				if not is_equal_approx(s_a, s_b):
					return s_a > s_b
				return str(a["socket"].id) < str(b["socket"].id)
			)
			var top_count: int = mini(3, valid.size())
			var chosen_idx := rng.randi_range(0, top_count - 1)
			_record_human_eval(evaluated, valid, valid[chosen_idx]["socket"])
			return valid[chosen_idx]["socket"]

	return p_sockets[0]

## Debug overlay (§9.9 "spawn-socket scores of the last selection"): one entry per
## evaluated socket: {pos, text, chosen}.
static var last_eval: Array = []
static var last_eval_kind: String = ""

## Tier (1–4) of the last `select_bot_spawn` result; tier ≥ 3 is a fallback (INV-6, §10.5).
static var last_bot_tier: int = 0

static func select_bot_spawn(sockets: Array, human_pos: Vector2, human_cam_rect: Rect2,
                             last_bot_spawns: Dictionary, now: float, tile_grid: TileGrid,
                             rng: RandomNumberGenerator, min_placed_dist: float = 0.0,
                             placed_bot_positions: Array = []) -> SocketDef:
	var p_sockets: Array[SocketDef] = []
	for s in sockets:
		var sock: SocketDef = s as SocketDef
		if sock and sock.type == Enums.SocketType.SPAWN:
			# Exclude sockets used in the last 3.0 s
			var last_used: float = float(last_bot_spawns.get(sock.id, -99.0))
			if (now - last_used) >= 3.0:
				p_sockets.append(sock)

	if p_sockets.is_empty():
		for s in sockets:
			var sock: SocketDef = s as SocketDef
			if sock and sock.type == Enums.SocketType.SPAWN:
				p_sockets.append(sock)

	# Camera view rect grown by 256 wu on every side
	var grown_view := human_cam_rect.grow(256.0)

	var evaluated: Array[Dictionary] = []
	for sock in p_sockets:
		var d_human: float = sock.pos.distance_to(human_pos)
		var in_view: bool = grown_view.has_point(sock.pos)

		var sock_centre: Vector2 = sock.pos + Vector2(0, -42)
		var r1: Dictionary = tile_grid.raycast(human_pos + Vector2(0, -42), sock_centre, C.MASK_LOS)
		var r2: Dictionary = tile_grid.raycast(human_pos + Vector2(0, -42), sock_centre + Vector2(0, 30), C.MASK_LOS)
		var r3: Dictionary = tile_grid.raycast(human_pos + Vector2(0, -42), sock_centre + Vector2(0, -30), C.MASK_LOS)
		var visible_from_human: bool = (not bool(r1["hit"]) or not bool(r2["hit"]) or not bool(r3["hit"]))

		# Check placed bot distance if initial spawn
		var too_close := false
		if min_placed_dist > 0.0:
			for p_pos in placed_bot_positions:
				if sock.pos.distance_to(p_pos as Vector2) < min_placed_dist:
					too_close = true
					break

		evaluated.append({
			"socket": sock,
			"dist": d_human,
			"in_view": in_view,
			"visible": visible_from_human,
			"too_close": too_close
		})

	# Tier evaluation (§6.7-B)
	var tier_preds: Array[Callable] = [
		func(e: Dictionary) -> bool: return not bool(e["too_close"]) and float(e["dist"]) >= 1400.0 and not bool(e["in_view"]) and not bool(e["visible"]),
		func(e: Dictionary) -> bool: return not bool(e["too_close"]) and float(e["dist"]) >= 1050.0 and not bool(e["in_view"]),
		func(e: Dictionary) -> bool: return not bool(e["too_close"]) and float(e["dist"]) >= 790.0,
		func(e: Dictionary) -> bool: return not bool(e["too_close"])
	]

	var tier_idx := 0
	var tier_of := {}
	for e in evaluated:
		var t := 1
		for pr in tier_preds:
			if pr.call(e):
				break
			t += 1
		tier_of[e["socket"].id] = t
	for pred in tier_preds:
		tier_idx += 1
		var valid: Array[SocketDef] = []
		for e in evaluated:
			if pred.call(e):
				valid.append(e["socket"])
		if not valid.is_empty():
			last_bot_tier = tier_idx
			if tier_idx >= 3:
				Log.warn("bot_spawn_fallback tier=%d" % tier_idx)
			if tier_idx == 4:
				# Farthest socket
				evaluated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
					var d_a: float = float(a["dist"])
					var d_b: float = float(b["dist"])
					if not is_equal_approx(d_a, d_b):
						return d_a > d_b
					return str(a["socket"].id) < str(b["socket"].id)
				)
				_record_bot_eval(evaluated, tier_of, evaluated[0]["socket"])
				return evaluated[0]["socket"]
			var pick: SocketDef = valid[rng.randi_range(0, valid.size() - 1)]
			_record_bot_eval(evaluated, tier_of, pick)
			return pick

	# If all were too close, relax placed constraint
	if min_placed_dist > 0.0:
		return select_bot_spawn(sockets, human_pos, human_cam_rect, last_bot_spawns, now, tile_grid, rng, 0.0, [])

	return p_sockets[0]

static func select_initial_spawns(sockets: Array, bot_count: int, tile_grid: TileGrid,
                                  rng: RandomNumberGenerator) -> Dictionary:
	var result: Dictionary = {} # id (0 for human, 1..N for bots) -> SocketDef
	var p_sockets: Array[SocketDef] = []
	for s in sockets:
		var sock: SocketDef = s as SocketDef
		if sock and sock.type == Enums.SocketType.SPAWN:
			p_sockets.append(sock)

	# 1. Skyra: uniform random P socket
	var skyra_sock: SocketDef = p_sockets[rng.randi_range(0, p_sockets.size() - 1)]
	result[0] = skyra_sock

	var placed_positions: Array[Vector2] = [skyra_sock.pos]
	var last_spawns: Dictionary = {}

	# 2. Bots in id order
	for bid in range(1, bot_count + 1):
		var dummy_cam := Rect2(skyra_sock.pos - Vector2(960, 540), Vector2(1920, 1080))
		var b_sock := select_bot_spawn(sockets, skyra_sock.pos, dummy_cam, last_spawns, 0.0, tile_grid, rng, 500.0, placed_positions)
		result[bid] = b_sock
		placed_positions.append(b_sock.pos)
		last_spawns[b_sock.id] = 0.0

	return result

static func _record_human_eval(evaluated: Array, valid: Array, chosen: SocketDef) -> void:
	last_eval_kind = "human"
	last_eval = []
	for e in evaluated:
		var txt := "d%d seen%d" % [int(minf(float(e["d_min"]), 9999.0)), int(e["seen_by"])]
		if valid.has(e):
			txt += " s%d" % int(float(e.get("score", 0.0)))
		last_eval.append({"pos": (e["socket"] as SocketDef).pos, "text": txt, "chosen": e["socket"] == chosen})

static func _record_bot_eval(evaluated: Array, tier_of: Dictionary, chosen: SocketDef) -> void:
	last_eval_kind = "bot"
	last_eval = []
	for e in evaluated:
		var sock: SocketDef = e["socket"]
		last_eval.append({"pos": sock.pos, "text": "T%s d%d" % [str(tier_of.get(sock.id, 5)) if int(tier_of.get(sock.id, 5)) <= 4 else "–", int(float(e["dist"]))], "chosen": sock == chosen})
