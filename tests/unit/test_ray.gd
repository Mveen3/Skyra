# Implements §10.4 T-RAY-01..06 Grid raycast tests.
class_name TestRay
extends RefCounted

func _make_test_grid(solid_char: String = "#") -> TileGrid:
	var rows: Array[String] = []
	for r in range(10):
		var line := ""
		for c in range(10):
			if c == 5 and r == 5:
				line += solid_char
			else:
				line += "."
		rows.append(line)
	var tg := TileGrid.new()
	tg.load_from_ascii(rows)
	return tg

func test_ray_01_dda_vertical_face() -> void:
	var tg := _make_test_grid("#")
	var hit := tg.raycast(Vector2(32, 352), Vector2(600, 352), GridRaycast.MASK_SOLIDS)
	Assertions.assert_true(hit.hit, "Ray hits vertical face")
	Assertions.assert_near(hit.point.x, 320.0, 0.001, "Hits x = 320")
	Assertions.assert_near(hit.point.y, 352.0, 0.001, "Hits y = 352")
	Assertions.assert_eq(hit.normal, Vector2(-1, 0), "Normal is (-1, 0)")

func test_ray_02_dda_horizontal_face() -> void:
	var tg := _make_test_grid("#")
	var hit := tg.raycast(Vector2(352, 32), Vector2(352, 600), GridRaycast.MASK_SOLIDS)
	Assertions.assert_true(hit.hit, "Ray hits horizontal face")
	Assertions.assert_near(hit.point.x, 352.0, 0.001, "Hits x = 352")
	Assertions.assert_near(hit.point.y, 320.0, 0.001, "Hits y = 320")
	Assertions.assert_eq(hit.normal, Vector2(0, -1), "Normal is (0, -1)")

func test_ray_03_one_way() -> void:
	var tg := _make_test_grid("=")
	# Ignored by MASK_PROJECTILE
	var hit_proj := tg.raycast(Vector2(352, 32), Vector2(352, 600), GridRaycast.MASK_PROJECTILE)
	Assertions.assert_false(hit_proj.hit, "One-way ignored by MASK_PROJECTILE")

	# Hit by downward ray with MASK_GRENADE
	var hit_gren := tg.raycast(Vector2(352, 32), Vector2(352, 600), GridRaycast.MASK_GRENADE)
	Assertions.assert_true(hit_gren.hit, "One-way hit by downward MASK_GRENADE")
	Assertions.assert_near(hit_gren.point.y, 320.0, 0.001, "Hits tile top at y = 320")
	Assertions.assert_eq(hit_gren.normal, Vector2(0, -1), "Normal is (0, -1)")

	# Upward ray with MASK_GRENADE ignores one-way
	var hit_up := tg.raycast(Vector2(352, 600), Vector2(352, 32), GridRaycast.MASK_GRENADE)
	Assertions.assert_false(hit_up.hit, "Upward ray ignores one-way")

func test_ray_04_half_tile() -> void:
	var tg := _make_test_grid("h")
	# HALF tile at (5, 5): collision rect is x in [320, 384], y in [352, 384]
	# Ray through top half (y = 336): should pass
	var hit_top := tg.raycast(Vector2(32, 336), Vector2(600, 336), GridRaycast.MASK_SOLIDS)
	Assertions.assert_false(hit_top.hit, "Ray through top half passes")

	# Ray through bottom half (y = 368): should hit at x = 320, local y >= 32
	var hit_bot := tg.raycast(Vector2(32, 368), Vector2(600, 368), GridRaycast.MASK_SOLIDS)
	Assertions.assert_true(hit_bot.hit, "Ray through bottom half hits")
	Assertions.assert_near(hit_bot.point.x, 320.0, 0.001, "Hits x = 320")
	Assertions.assert_near(hit_bot.point.y, 368.0, 0.001, "Hits y = 368")

func test_ray_05_bounds() -> void:
	var tg := TileGrid.new()
	tg.load_from(Data.map)
	# Ray leaving map right (x >= 7680) in open sky (row 2, y = 150)
	var hit_right := tg.raycast(Vector2(7500, 150), Vector2(8000, 150), GridRaycast.MASK_SOLIDS)
	Assertions.assert_true(hit_right.hit, "Ray leaving right boundary hits")
	Assertions.assert_near(hit_right.point.x, 7680.0, 0.01, "Hits at right boundary x = 7680")

func test_ray_06_random_agreement() -> void:
	var tg := TileGrid.new()
	tg.load_from(Data.map)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var total_tests := 5000
	var agreed := 0

	for i in range(total_tests):
		var a := Vector2(rng.randf_range(100, 7500), rng.randf_range(100, 3700))
		var b := a + Vector2(rng.randf_range(-600, 600), rng.randf_range(-600, 600))
		var hit_dda := tg.raycast(a, b, GridRaycast.MASK_SOLIDS)

		# Brute-force 1-wu step sampler
		var d := b - a
		var dist := d.length()
		var dir := d / maxf(dist, 0.0001)
		var bf_hit := false
		var bf_dist := dist

		var step := 1.0
		var curr_d := 0.0
		while curr_d <= dist:
			var p := a + dir * curr_d
			var c := tg.cell_of(p)
			var t := tg.tile_at(c.x, c.y)
			if t == Enums.Tile.ROCK or t == Enums.Tile.METAL or t == Enums.Tile.CRATE:
				bf_hit = true
				bf_dist = curr_d
				break
			elif t == Enums.Tile.HALF:
				var local_y := p.y - c.y * 64.0
				if local_y >= 32.0:
					bf_hit = true
					bf_dist = curr_d
					break
			curr_d += step

		if hit_dda.hit == bf_hit:
			if not hit_dda.hit:
				agreed += 1
			else:
				var dda_dist: float = float(hit_dda.t) * dist
				if absf(dda_dist - bf_dist) <= 2.5:
					agreed += 1

	var agreement_rate := float(agreed) / float(total_tests)
	Assertions.assert_true(agreement_rate >= 0.99, "Agreement rate >= 99%%, got: %.2f%%" % [agreement_rate * 100.0])
