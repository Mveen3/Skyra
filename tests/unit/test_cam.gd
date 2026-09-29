# Implements §10.3 / Table 10.4 Camera unit tests (T-CAM-01..04).
class_name TestCam
extends RefCounted

func test_cam_01_zoom_per_weapon() -> void:
	var weapons := Data.weapons
	Assertions.assert_eq(weapons.size(), 9, "9 weapons present")

	var expected_scopes := {
		"magnum": 1.0,
		"shotgun": 1.0,
		"flamethrower": 1.0,
		"mp5": 1.5,
		"saw_gun": 1.5,
		"ak47": 2.0,
		"rocket_launcher": 2.5,
		"phasr": 3.0,
		"m93ba": 5.0
	}

	for id in expected_scopes.keys():
		var w: WeaponDef = weapons.get(id)
		Assertions.assert_not_null(w, "Weapon %s found" % id)
		var exp_s: float = expected_scopes[id]
		Assertions.assert_near(w.scope, exp_s, 1e-4, "Weapon %s scope matches" % id)
		
		var z_tgt: float = GameCamera.calc_zoom_target(w.scope)
		var expected_z: float = 1.0 / sqrt(exp_s)
		Assertions.assert_near(z_tgt, expected_z, 1e-4, "Weapon %s zoom target = 1/√S" % id)

func test_cam_02_lookahead() -> void:
	var la_1: float = GameCamera.calc_lookahead(1.0)
	Assertions.assert_near(la_1, 0.25, 1e-4, "Lookahead ratio at S=1 is 0.25")

	var la_5: float = GameCamera.calc_lookahead(5.0)
	Assertions.assert_near(la_5, 0.80, 1e-4, "Lookahead ratio at S=5 is 0.80")

	# Horizontal reach at 1920x1080
	var reach_1: Vector2 = GameCamera.calc_max_reach(1.0, Vector2(1920, 1080))
	Assertions.assert_near(reach_1.x, 1200.0, 0.01, "Horizontal reach at S=1 is 1200 ± 1%")
	Assertions.assert_near(reach_1.y, 675.0, 0.01, "Vertical reach at S=1 is 675 ± 1%")

	var reach_5: Vector2 = GameCamera.calc_max_reach(5.0, Vector2(1920, 1080))
	Assertions.assert_near(reach_5.x, 3864.0, 0.01, "Horizontal reach at S=5 is 3864 ± 1%")
	Assertions.assert_near(reach_5.y, 2173.0, 0.01, "Vertical reach at S=5 is 2173 ± 1%")

func test_cam_03_clamp() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 998877
	var vp := Vector2(1920, 1080)

	for i in range(10000):
		var p := Vector2(rng.randf_range(-1000, 9000), rng.randf_range(-1000, 5000))
		var mouse := Vector2(rng.randf_range(0, 1920), rng.randf_range(0, 1080))
		var scope := rng.randf_range(1.0, 5.0)
		var z := 1.0 / sqrt(scope)

		var target := GameCamera.compute_target(p, mouse, vp, z, scope, true)
		var half_view := (vp * 0.5) / z

		var clamped_inside := target.x >= half_view.x - 1e-3 and target.x <= (7680.0 - half_view.x + 1e-3) and \
		                      target.y >= half_view.y - 1e-3 and target.y <= (3840.0 - half_view.y + 1e-3)
		if not clamped_inside:
			Assertions.assert_true(clamped_inside, "Target inside map rect shrunk by half-view at iteration %d" % i)
			break

	Assertions.assert_true(true, "All 10,000 random clamp queries stayed within map bounds")

func test_cam_04_zoom_smoothing() -> void:
	var start_z: float = 1.0
	var target_z: float = 1.0 / sqrt(5.0)
	var z: float = start_z
	var dt: float = 1.0 / 60.0
	var lambda_val: float = GameCamera.ZOOM_LAMBDA

	var frames_to_95 := 0
	var total_step := absf(target_z - start_z)

	for f in range(120):
		z = target_z + (z - target_z) * exp(-lambda_val * dt)
		var progressed := absf(z - start_z) / total_step
		if progressed >= 0.95 and frames_to_95 == 0:
			frames_to_95 = f + 1

	var time_to_95 := frames_to_95 * dt
	Assertions.assert_between(time_to_95, 0.50 - dt * 1.5, 0.50 + dt * 1.5, "95% zoom step reached in 0.5 s ± 1 frame")
