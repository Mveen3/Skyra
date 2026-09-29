# Implements §1.5 Randomness, determinism and time.
class_name RngStreams
extends RefCounted

var rng_spawn: RandomNumberGenerator
var rng_loot: RandomNumberGenerator
var rng_combat: RandomNumberGenerator
var rng_ai: RandomNumberGenerator
var rng_fx: RandomNumberGenerator

func _init(base_seed: int = 0) -> void:
	reseed(base_seed)

func reseed(base_seed: int) -> void:
	rng_spawn = RandomNumberGenerator.new()
	rng_spawn.seed = base_seed ^ 0x51A1

	rng_loot = RandomNumberGenerator.new()
	rng_loot.seed = base_seed ^ 0x10C7

	rng_combat = RandomNumberGenerator.new()
	rng_combat.seed = base_seed ^ 0xC0B7

	rng_ai = RandomNumberGenerator.new()
	rng_ai.seed = base_seed ^ 0xA1A1

	rng_fx = RandomNumberGenerator.new()
	rng_fx.randomize()
