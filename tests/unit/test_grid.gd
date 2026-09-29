# Implements §10.4 T-GRID-01 solid_rects_in test.
class_name TestGrid
extends RefCounted

func test_grid_01_solid_rects_in() -> void:
	var tg := TileGrid.new()
	tg.load_from(Data.map)
	var rng := RandomNumberGenerator.new()
	rng.seed = 98765

	var total_tests := 2000
	for i in range(total_tests):
		var w := rng.randf_range(20, 200)
		var h := rng.randf_range(20, 200)
		var x := rng.randf_range(64, 7500)
		var y := rng.randf_range(64, 3700)
		var box := Rect2(x, y, w, h)

		var query_rects := tg.solid_rects_in(box, false)

		# Brute-force overlap over all candidate cells in the area
		var c0 := int(floor(box.position.x / 64.0))
		var c1 := int(floor(box.end.x / 64.0))
		var r0 := int(floor(box.position.y / 64.0))
		var r1 := int(floor(box.end.y / 64.0))

		var bf_count := 0
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				var t := tg.tile_at(c, r)
				var wx := float(c * 64)
				var wy := float(r * 64)
				if t == Enums.Tile.ROCK or t == Enums.Tile.METAL or t == Enums.Tile.CRATE:
					var r_rect := Rect2(wx, wy, 64.0, 64.0)
					if box.intersects(r_rect):
						bf_count += 1
				elif t == Enums.Tile.HALF:
					var h_rect := Rect2(wx, wy + 32.0, 64.0, 32.0)
					if box.intersects(h_rect):
						bf_count += 1

		if query_rects.size() != bf_count:
			Assertions.assert_eq(query_rects.size(), bf_count, "solid_rects_in count matches brute force")
			break
