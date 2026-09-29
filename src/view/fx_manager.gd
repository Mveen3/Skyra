# Implements §7.6 / §9.6 FxManager: particle pools, emitters, and presets.
class_name FxManager
extends Node2D

const POOL_SIZE_PER_PRESET: int = 6

var _pools: Dictionary = {} # preset_name -> Array[CPUParticles2D]
var _pool_indices: Dictionary = {} # preset_name -> int (round-robin)
var _presets: Dictionary = {}

func _ready() -> void:
	load_presets_and_build_pools()

## Loads particle_presets.json and builds pooled emitters per §7.6.
func load_presets_and_build_pools() -> void:
	_presets = Data.particle_presets
	if _presets.is_empty():
		# Fallback direct read
		var json_path: String = "res://data/fx/particle_presets.json"
		if FileAccess.file_exists(json_path):
			var f: FileAccess = FileAccess.open(json_path, FileAccess.READ)
			if f:
				var parsed = JSON.parse_string(f.get_as_text())
				if typeof(parsed) == TYPE_DICTIONARY:
					_presets = parsed.get("presets", {})

	for preset_name in _presets:
		var preset: Dictionary = _presets[preset_name]
		_build_pool_for_preset(StringName(preset_name), preset)

func _build_pool_for_preset(preset_name: StringName, preset: Dictionary) -> void:
	var pool: Array[CPUParticles2D] = []
	for i in range(POOL_SIZE_PER_PRESET):
		var emitter: CPUParticles2D = create_emitter_for_preset(preset)
		emitter.name = "%s_%d" % [str(preset_name), i]
		add_child(emitter)
		pool.append(emitter)

	_pools[preset_name] = pool
	_pool_indices[preset_name] = 0

## Factory creating and configuring a single CPUParticles2D from preset dictionary.
static func create_emitter_for_preset(preset: Dictionary) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = int(preset.get("amount", 8))
	p.lifetime = float(preset.get("lifetime", 0.5))
	p.explosiveness = float(preset.get("explosiveness", 1.0))
	p.spread = float(preset.get("spread_deg", 45.0))
	p.initial_velocity_min = float(preset.get("speed_min", 50.0))
	p.initial_velocity_max = float(preset.get("speed_max", 150.0))

	var grav_arr = preset.get("gravity", [0, 980])
	if typeof(grav_arr) == TYPE_ARRAY and grav_arr.size() >= 2:
		p.gravity = Vector2(float(grav_arr[0]), float(grav_arr[1]))

	p.scale_amount_min = float(preset.get("scale_start", 1.0))
	p.scale_amount_max = float(preset.get("scale_end", 1.0))

	var col_start_str: String = str(preset.get("color_start", "#FFFFFF"))
	var col_end_str: String = str(preset.get("color_end", "#FFFFFF00"))
	var col_start: Color = Color.from_string(col_start_str, Color.WHITE)
	var col_end: Color = Color.from_string(col_end_str, Color.TRANSPARENT)

	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray([col_start, col_end])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	p.color_ramp = grad

	var blend: String = str(preset.get("blend", "mix"))
	if blend == "add":
		var mat: CanvasItemMaterial = CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = mat

	if preset.has("spin"):
		p.angular_velocity_min = float(preset["spin"])
		p.angular_velocity_max = float(preset["spin"])

	return p

## Spawns / restarts a particle emitter from the preset's pool.
func spawn_particle(preset_name: StringName, pos: Vector2, dir: Vector2 = Vector2.ZERO) -> CPUParticles2D:
	if not _pools.has(preset_name):
		return null

	var pool: Array[CPUParticles2D] = _pools[preset_name]
	if pool.is_empty():
		return null

	var idx: int = _pool_indices[preset_name]
	var emitter: CPUParticles2D = pool[idx]
	_pool_indices[preset_name] = (idx + 1) % pool.size()

	emitter.global_position = pos
	if dir != Vector2.ZERO:
		emitter.direction = dir
	emitter.restart()
	emitter.emitting = true
	return emitter

## Returns the fixed capacity of the pool for any preset (6).
func get_pool_capacity() -> int:
	return POOL_SIZE_PER_PRESET

## Returns the total number of emitter nodes in all pools.
func get_total_emitters_count() -> int:
	var total: int = 0
	for k in _pools:
		total += _pools[k].size()
	return total
