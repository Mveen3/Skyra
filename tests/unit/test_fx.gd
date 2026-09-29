# Implements §10.4 T-FX-01 and T-FX-02.
class_name TestFx
extends RefCounted

func test_fx_01_presets() -> void:
	var presets: Dictionary = Data.particle_presets
	Assertions.assert_true(presets.size() >= 20, "At least 20 presets in particle_presets.json, got %d" % presets.size())

	for preset_name in presets:
		var preset: Dictionary = presets[preset_name]
		var emitter: CPUParticles2D = FxManager.create_emitter_for_preset(preset)
		Assertions.assert_true(emitter != null, "Preset %s creates CPUParticles2D" % str(preset_name))

		if emitter != null:
			Assertions.assert_eq(emitter.amount, int(preset.get("amount", 8)), "Amount matches")
			Assertions.assert_eq(emitter.lifetime, float(preset.get("lifetime", 0.5)), "Lifetime matches")
			
			# Test emission headless
			emitter.restart()
			emitter.emitting = true
			Assertions.assert_true(emitter.emitting, "Emitter %s emits headless without error" % str(preset_name))
			emitter.queue_free()

func test_fx_02_pools() -> void:
	var fx_mgr: FxManager = FxManager.new()
	fx_mgr.load_presets_and_build_pools()

	var presets: Dictionary = Data.particle_presets
	var expected_total_emitters: int = presets.size() * FxManager.POOL_SIZE_PER_PRESET
	Assertions.assert_eq(fx_mgr.get_total_emitters_count(), expected_total_emitters,
		"Initial pool size equals presets * 6 (%d)" % expected_total_emitters)

	# Simulate heavy particle traffic (100 bursts per preset)
	for i in range(100):
		fx_mgr.spawn_particle(&"muzzle_smoke", Vector2(float(i), float(i)))
		fx_mgr.spawn_particle(&"explosion_fireball", Vector2(float(i * 2), float(i * 2)))
		fx_mgr.spawn_particle(&"impact_spark_metal", Vector2(float(i * 3), float(i * 3)))
		fx_mgr.spawn_particle(&"shell_casing", Vector2(float(i * 4), float(i * 4)))

	# Ensure capacity was never exceeded (no dynamic growth)
	Assertions.assert_eq(fx_mgr.get_total_emitters_count(), expected_total_emitters,
		"Pool never exceeds fixed capacity after 400 bursts (%d)" % expected_total_emitters)

	for p_name in fx_mgr._pools:
		var pool: Array = fx_mgr._pools[p_name]
		Assertions.assert_eq(pool.size(), FxManager.POOL_SIZE_PER_PRESET,
			"Pool %s size is strictly %d" % [str(p_name), FxManager.POOL_SIZE_PER_PRESET])

	fx_mgr.free()
