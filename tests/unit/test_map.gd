# Implements §10.4 T-MAP-01..07 Map validation tests.
class_name TestMap
extends RefCounted

func test_map_01_legend_and_size() -> void:
	Assertions.assert_true(Data.map != null, "Map exists")
	Assertions.assert_eq(Data.map.width, 120, "Map width == 120")
	Assertions.assert_eq(Data.map.height, 60, "Map height == 60")
	Assertions.assert_eq(Data.raw_map_rows.size(), 60, "Raw rows size == 60")
	for r in range(Data.raw_map_rows.size()):
		var line := str(Data.raw_map_rows[r])
		Assertions.assert_eq(line.length(), 120, "Row %d length == 120" % r)
		for c in range(line.length()):
			var ch := line[c]
			Assertions.assert_true(MapLoader.LEGEND_CHARS.contains(ch), "Legend contains char: " + ch)

func test_map_02_boundaries_solid() -> void:
	var rows := Data.raw_map_rows
	var last_row := str(rows[59])
	for c in range(last_row.length()):
		Assertions.assert_true(MapLoader.SOLID_CHARS.contains(last_row[c]), "Row 59 col %d solid" % c)
	for r in range(11, 60):
		var line := str(rows[r])
		Assertions.assert_true(MapLoader.SOLID_CHARS.contains(line[0]), "Col 0 row %d solid" % r)
		Assertions.assert_true(MapLoader.SOLID_CHARS.contains(line[119]), "Col 119 row %d solid" % r)

func test_map_03_symmetry() -> void:
	var rows := Data.raw_map_rows
	var col_class := func(ch: String) -> int:
		if MapLoader.SOLID_CHARS.contains(ch): return 1
		if ch == "=": return 2
		return 0
	for r in range(rows.size()):
		var line := str(rows[r])
		for c in range(60):
			var c1: int = col_class.call(line[c])
			var c2: int = col_class.call(line[119 - c])
			Assertions.assert_eq(c1, c2, "Symmetry at (%d, %d)" % [c, r])

func test_map_04_sockets_valid() -> void:
	var rows := Data.raw_map_rows
	for s in Data.map.sockets:
		var c := s.cell.x
		var r := s.cell.y
		var ch := str(rows[r])[c]
		Assertions.assert_true(ch == "P" or ch == "W" or ch == "B", "Socket cell has marker")
		if r > 0:
			var above := str(rows[r - 1])[c]
			Assertions.assert_true(not MapLoader.SOLID_CHARS.contains(above) and above != "=", "Air above socket")
		if r < 59:
			var below := str(rows[r + 1])[c]
			Assertions.assert_true(MapLoader.SOLID_CHARS.contains(below) or below == "=", "Floor below socket")

func test_map_05_socket_table_counts() -> void:
	var p_count := 0
	var w_count := 0
	var b_count := 0
	for s in Data.map.sockets:
		match s.type:
			Enums.SocketType.SPAWN: p_count += 1
			Enums.SocketType.WEAPON: w_count += 1
			Enums.SocketType.BOOST: b_count += 1
	Assertions.assert_eq(p_count, 16, "16 Spawn sockets")
	Assertions.assert_eq(w_count, 16, "16 Weapon sockets")
	Assertions.assert_eq(b_count, 2, "2 Boost sockets")

func test_map_06_reachability_and_occupiable() -> void:
	var W: int = Data.map.width
	var H: int = Data.map.height
	var rows := Data.raw_map_rows
	var is_solid_cell := func(c: int, r: int) -> bool:
		if c < 0 or c >= W or r < 0 or r >= H: return true
		return MapLoader.SOLID_CHARS.contains(str(rows[r])[c])
		
	var occupiable: Dictionary = {}
	for r in range(1, H):
		for c in range(W):
			if not is_solid_cell.call(c, r) and not is_solid_cell.call(c, r - 1):
				occupiable[Vector2i(c, r)] = true
				
	Assertions.assert_eq(occupiable.size(), 3272, "Exactly 3272 occupiable nodes")
	
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
						
	Assertions.assert_eq(visited.size(), 3272, "All 3272 nodes reachable from P01")

func test_map_07_socket_zones() -> void:
	for s in Data.map.sockets:
		var z := Data.map.zone_at(s.cell)
		Assertions.assert_true(z != null, "Socket %s in valid zone" % s.id)
		if z:
			Assertions.assert_eq(z.id, s.zone, "Socket %s zone matches" % s.id)
