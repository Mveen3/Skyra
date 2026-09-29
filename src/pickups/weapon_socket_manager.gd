# Implements §4.11 Weapon sockets and drop distribution.
class_name WeaponSocketManager
extends RefCounted

class SocketState:
	var def: SocketDef
	var current_item: String = ""
	var last_item: String = ""
	var is_available: bool = false
	var respawn_timer: float = 0.0
	var stale_timer: float = 0.0

var sockets: Array[SocketState] = []
var mode_id: String = "mini_post"

func init_sockets(map_data: MapData, selected_mode: String, rng: RandomNumberGenerator) -> void:
	setup(map_data.sockets, selected_mode, rng)

func setup(sockets_data, selected_mode: String, rng: RandomNumberGenerator) -> void:
	mode_id = selected_mode
	sockets.clear()
	var arr: Array = sockets_data.sockets if sockets_data is MapData else (sockets_data as Array)
	for s_def in arr:
		var sock: SocketDef = s_def as SocketDef
		if sock and sock.type == Enums.SocketType.WEAPON:
			var state := SocketState.new()
			state.def = sock
			sockets.append(state)
	fill_all(rng)

func take(socket_id: StringName, by_id: int) -> WeaponInstance:
	for s in sockets:
		if s.def.id == socket_id and s.is_available:
			s.is_available = false
			var mode_data: Dictionary = Data.modes.get(mode_id, {})
			s.respawn_timer = float(mode_data.get("socket_respawn_s", 15.0))
			EventBus.socket_item_taken.emit(socket_id, by_id)
			if Data.weapons.has(s.current_item):
				return WeaponInstance.new(Data.weapons[s.current_item])
	return null

func count_items_on_sockets() -> Dictionary:
	var counts := {}
	for s in sockets:
		if s.is_available and not s.current_item.is_empty():
			counts[s.current_item] = counts.get(s.current_item, 0) + 1
	return counts

static func roll_item(socket_tag: String, last_item: String, current_counts: Dictionary,
                      mode_data: Dictionary, rng: RandomNumberGenerator, apply_caps: bool = true) -> String:
	var base_weights: Dictionary = mode_data.get("drop_weights", {})
	var weights := {}
	for k in base_weights.keys():
		weights[k] = float(base_weights[k])

	# Apply zone affinity
	var affinities: Dictionary = mode_data.get("zone_affinity", {})
	var tag_str := String(socket_tag)
	if affinities.has(tag_str):
		var tag_weights: Dictionary = affinities[tag_str]
		for k in weights.keys():
			if tag_weights.has(k):
				weights[k] *= float(tag_weights[k])

	# Apply socket caps
	if apply_caps:
		var caps: Dictionary = mode_data.get("socket_caps", {})
		for k in caps.keys():
			var cap_val: int = caps[k]
			if current_counts.get(k, 0) >= cap_val:
				weights[k] = 0.0

	# Prevent immediate repeat if more than 1 option remains
	if not last_item.is_empty():
		var positive_count := 0
		for k in weights.keys():
			if weights[k] > 0.0:
				positive_count += 1
		if positive_count > 1 and weights.has(last_item):
			weights[last_item] = 0.0

	# Weighted choice
	var total_w := 0.0
	for k in weights.keys():
		total_w += weights[k]

	if total_w <= 0.0:
		# Fallback if all capped or zeroed
		return "frag_pack" if mode_data.get("drop_weights", {}).has("frag_pack") else "mp5"

	var roll := rng.randf_range(0.0, total_w)
	var accum := 0.0
	for k in weights.keys():
		accum += weights[k]
		if roll <= accum:
			return k

	return weights.keys()[0]

func fill_all(rng: RandomNumberGenerator) -> void:
	var mode_data: Dictionary = Data.modes.get(mode_id, {})
	for s in sockets:
		var counts := count_items_on_sockets()
		var item := roll_item(s.def.tag, s.last_item, counts, mode_data, rng, true)
		s.current_item = item
		s.last_item = item
		s.is_available = true
		s.respawn_timer = 0.0
		s.stale_timer = 0.0

func step(dt: float, characters: Array, rng: RandomNumberGenerator) -> void:
	var mode_data: Dictionary = Data.modes.get(mode_id, {})
	var respawn_s: float = mode_data.get("socket_respawn_s", 15.0)
	var stale_s: float = mode_data.get("socket_stale_reroll_s", 60.0)
	var min_dist: float = mode_data.get("stale_reroll_min_distance", 800.0)

	for s in sockets:
		if s.is_available:
			s.stale_timer += dt
			if s.stale_timer >= stale_s:
				var too_close := false
				for obj in characters:
					var c: CharacterState = obj as CharacterState
					if c and c.pos.distance_to(s.def.world) < min_dist:
						too_close = true
						break
				if not too_close:
					var counts := count_items_on_sockets()
					var item := roll_item(s.def.tag, s.last_item, counts, mode_data, rng, true)
					s.current_item = item
					s.last_item = item
					s.stale_timer = 0.0
		else:
			s.respawn_timer -= dt
			if s.respawn_timer <= 0.0:
				var counts := count_items_on_sockets()
				var item := roll_item(s.def.tag, s.last_item, counts, mode_data, rng, true)
				s.current_item = item
				s.last_item = item
				s.is_available = true
				s.respawn_timer = 0.0
				s.stale_timer = 0.0
