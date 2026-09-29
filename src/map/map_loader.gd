# Implements §6.10 and §9.5 MapLoader and map validation.
class_name MapLoader
extends RefCounted

const LEGEND_CHARS: String = ".:^#MCh=PWB"
const SOLID_CHARS: String = "#MCh"

static func load_map(path: String = C.PATH_MAP_OUTPOST) -> MapData:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var text := file.get_as_text()
	file.close()
	
	var json = JSON.parse_string(text)
	if typeof(json) != TYPE_DICTIONARY:
		return null
	
	var map := MapData.new()
	map.id = StringName(json.get("id", "outpost_skyra"))
	map.display_name = json.get("display_name", "Outpost Skyra")
	map.tile_size = int(json.get("tile_size", 64))
	map.width = int(json.get("width", 120))
	map.height = int(json.get("height", 60))
	
	var rows: Array = json.get("rows", [])
	map.tiles.resize(map.width * map.height)
	
	# Parse zones
	for z_dict in json.get("zones", []):
		var z := ZoneDef.new()
		z.id = StringName(z_dict.get("id", ""))
		z.display_name = z_dict.get("display_name", "")
		z.interior = bool(z_dict.get("interior", false))
		z.ambience = StringName(z_dict.get("ambience", ""))
		for r_arr in z_dict.get("rects", []):
			z.rects.append(Rect2i(r_arr[0], r_arr[1], r_arr[2], r_arr[3]))
		map.zones.append(z)
	
	# Parse sockets
	for s_dict in json.get("sockets", []):
		var s := SocketDef.new()
		s.id = StringName(s_dict.get("id", ""))
		var t_str: String = s_dict.get("type", "spawn")
		match t_str:
			"spawn": s.type = Enums.SocketType.SPAWN
			"weapon": s.type = Enums.SocketType.WEAPON
			"boost": s.type = Enums.SocketType.BOOST
		var cell_arr: Array = s_dict.get("cell", [0, 0])
		s.cell = Vector2i(cell_arr[0], cell_arr[1])
		var world_arr: Array = s_dict.get("world", [0, 0])
		s.world = Vector2(world_arr[0], world_arr[1])
		s.zone = StringName(s_dict.get("zone", ""))
		s.tag = StringName(s_dict.get("tag", ""))
		map.sockets.append(s)
	
	# First pass to identify raw chars for socket backdrop resolution
	var raw_grid: Array[String] = []
	for r in rows:
		raw_grid.append(str(r))
	
	# Convert characters to tiles
	for row in range(map.height):
		var line: String = raw_grid[row] if row < raw_grid.size() else ""
		for col in range(map.width):
			var ch: String = line[col] if col < line.length() else "#"
			var tile_type: int = Enums.Tile.ROCK
			match ch:
				".": tile_type = Enums.Tile.AIR_EXTERIOR
				":": tile_type = Enums.Tile.AIR_INTERIOR
				"^": tile_type = Enums.Tile.UPDRAFT
				"#": tile_type = Enums.Tile.ROCK
				"M": tile_type = Enums.Tile.METAL
				"C": tile_type = Enums.Tile.CRATE
				"h": tile_type = Enums.Tile.HALF
				"=": tile_type = Enums.Tile.ONE_WAY
				"P", "W", "B":
					# Backdrop = AIR_INTERIOR if any 4-neighbour is ':' or '^', else AIR_EXTERIOR
					var is_interior := false
					for offset in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
						var nc: int = col + offset.x
						var nr: int = row + offset.y
						if nc >= 0 and nc < map.width and nr >= 0 and nr < map.height:
							var nch: String = raw_grid[nr][nc]
							if nch == ":" or nch == "^":
								is_interior = true
								break
					tile_type = Enums.Tile.AIR_INTERIOR if is_interior else Enums.Tile.AIR_EXTERIOR
				_:
					tile_type = Enums.Tile.ROCK
			map.tiles[row * map.width + col] = tile_type
			
	return map

static func validate(map: MapData, raw_rows: Array) -> PackedStringArray:
	var errors: PackedStringArray = []
	if map == null:
		errors.append("MapData is null")
		return errors
	
	var W := map.width
	var H := map.height
	
	# Rule 1: Exactly 60 rows × 120 characters; only legend characters
	if raw_rows.size() != 60:
		errors.append("Rule 1: Expected 60 rows, got %d" % raw_rows.size())
	for r in range(raw_rows.size()):
		var line := str(raw_rows[r])
		if line.length() != 120:
			errors.append("Rule 1: Row %d has length %d, expected 120" % [r, line.length()])
		for c in range(line.length()):
			var ch := line[c]
			if not LEGEND_CHARS.contains(ch):
				errors.append("Rule 1: Invalid char '%s' at (%d, %d)" % [ch, c, r])
				
	# Rule 2: Row 59 fully solid; columns 0 and 119 solid from row 11 to row 59
	if raw_rows.size() == 60:
		var last_row := str(raw_rows[59])
		for c in range(last_row.length()):
			if not SOLID_CHARS.contains(last_row[c]):
				errors.append("Rule 2: Row 59 col %d is not solid: '%s'" % [c, last_row[c]])
		for r in range(11, 60):
			var row_str := str(raw_rows[r])
			if not SOLID_CHARS.contains(row_str[0]):
				errors.append("Rule 2: Col 0 row %d is not solid" % r)
			if not SOLID_CHARS.contains(row_str[119]):
				errors.append("Rule 2: Col 119 row %d is not solid" % r)
				
	# Helper for collision class
	var col_class := func(ch: String) -> int:
		if SOLID_CHARS.contains(ch): return 1
		if ch == "=": return 2
		return 0 # Air (. : ^ P W B)
		
	# Rule 3: Collision symmetry
	for r in range(raw_rows.size()):
		var line := str(raw_rows[r])
		for c in range(60):
			var c1: int = col_class.call(line[c])
			var c2: int = col_class.call(line[119 - c])
			if c1 != c2:
				errors.append("Rule 3: Collision asymmetry at row %d: (%d)=%d vs (%d)=%d" % [r, c, c1, 119 - c, c2])

	# Rule 4 & 5: Sockets
	var found_markers := {}
	for r in range(raw_rows.size()):
		var line := str(raw_rows[r])
		for c in range(line.length()):
			var ch := line[c]
			if ch == "P" or ch == "W" or ch == "B":
				found_markers[Vector2i(c, r)] = ch
				# Rule 4: cell above is air, below is solid or one-way
				if r > 0:
					var above := line if r == 0 else str(raw_rows[r - 1])[c]
					if SOLID_CHARS.contains(above) or above == "=":
						errors.append("Rule 4: Socket %s at (%d, %d) has non-air above" % [ch, c, r])
				if r < 59:
					var below := str(raw_rows[r + 1])[c]
					if not (SOLID_CHARS.contains(below) or below == "="):
						errors.append("Rule 4: Socket %s at (%d, %d) has no floor below" % [ch, c, r])

	# Check socket table matches found markers
	var expected_counts := {"P": 16, "W": 16, "B": 2}
	var actual_counts := {"P": 0, "W": 0, "B": 0}
	for s in map.sockets:
		var ch := str(s.id)[0]
		actual_counts[ch] = actual_counts.get(ch, 0) + 1
		if not found_markers.has(s.cell):
			errors.append("Rule 5: Socket %s cell (%d, %d) not found in grid" % [s.id, s.cell.x, s.cell.y])
		elif found_markers[s.cell] != ch:
			errors.append("Rule 5: Socket %s marker mismatch: expected %s, got %s" % [s.id, ch, found_markers[s.cell]])
	for k in expected_counts:
		if actual_counts[k] != expected_counts[k]:
			errors.append("Rule 5: Socket count for %s: expected %d, got %d" % [k, expected_counts[k], actual_counts[k]])

	# Rule 6: Reachability (BFS over occupiable nodes from P01)
	var is_solid_cell := func(c: int, r: int) -> bool:
		if c < 0 or c >= W or r < 0 or r >= H: return true
		return SOLID_CHARS.contains(str(raw_rows[r])[c])
		
	var occupiable: Dictionary = {} # Vector2i -> true
	for r in range(1, H):
		for c in range(W):
			if not is_solid_cell.call(c, r) and not is_solid_cell.call(c, r - 1):
				occupiable[Vector2i(c, r)] = true
				
	if occupiable.size() != 3272:
		errors.append("Rule 6: Occupiable nodes expected 3272, got %d" % occupiable.size())
		
	var start_node := Vector2i(5, 10)
	var visited: Dictionary = {start_node: true}
	var queue: Array[Vector2i] = [start_node]
	while not queue.is_empty():
		var curr: Vector2i = queue.pop_front()
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0: continue
				var next := Vector2i(curr.x + dx, curr.y + dy)
				if occupiable.has(next):
					if dx != 0 and dy != 0:
						if not occupiable.has(Vector2i(curr.x + dx, curr.y)) or not occupiable.has(Vector2i(curr.x, curr.y + dy)):
							continue
					if not visited.has(next):
						visited[next] = true
						queue.append(next)
						
	if visited.size() != occupiable.size():
		errors.append("Rule 6: Reachability failure: %d / %d nodes reached" % [visited.size(), occupiable.size()])

	# Rule 7: Every socket lies inside the zone listed for it
	for s in map.sockets:
		var z := map.zone_at(s.cell)
		if z == null or z.id != s.zone:
			errors.append("Rule 7: Socket %s at (%d, %d) resolved to zone '%s', expected '%s'" % [
				s.id, s.cell.x, s.cell.y, "" if z == null else z.id, s.zone
			])

	return errors
