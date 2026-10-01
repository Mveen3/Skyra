# Implements §7.6 FxManager: pooled CPUParticles2D emitters per preset (6 each, restarted
# round-robin), plus non-particle FX driven by EventBus events: muzzle flashes, shockwaves,
# Black Arrow slug trails, bullet-hole / scorch decals and the derez / spark-ring deaths.
class_name FxManager
extends Node2D

const POOL_SIZE_PER_PRESET: int = 6
const PARTICLE_TEX_PX: int = 32
const MAX_BULLET_HOLES: int = 160
const MAX_SCORCHES: int = 24

var _pools: Dictionary = {} # preset_name -> Array[CPUParticles2D]
var _pool_indices: Dictionary = {} # preset_name -> int (round-robin)
var _presets: Dictionary = {}
var sim: MatchSim = null

var _flashes: Array = [] # {pos, dir, r, n, rot, age, life, col}
var _rings: Array = [] # {pos, r, age, life, col, w}
var _trails: Array = [] # {a, b, age, life, col, w}
var _holes: Array = [] # {pos, age}
var _scorches: Array = [] # {pos, r, age}
var _decals: Node2D
var _jets: Dictionary = {} # character id -> [exhaust, smoke, afterburner] continuous emitters

static var _soft_tex: Texture2D = null

func _ready() -> void:
	load_presets_and_build_pools()
	_decals = Node2D.new()
	_decals.z_index = C.Z_DECALS
	_decals.z_as_relative = false
	add_child(_decals)
	_decals.draw.connect(_draw_decals)

## Soft round particle sprite shared by every emitter (white, radial alpha falloff).
static func soft_texture() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0)])
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = PARTICLE_TEX_PX
		t.height = PARTICLE_TEX_PX
		_soft_tex = t
	return _soft_tex

## Loads particle_presets.json and builds pooled emitters per §7.6.
func load_presets_and_build_pools() -> void:
	_presets = Data.particle_presets
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

## Factory creating and configuring a single CPUParticles2D from a preset dictionary.
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
	p.texture = soft_texture()
	p.local_coords = false

	var grav_arr = preset.get("gravity", [0, 980])
	if typeof(grav_arr) == TYPE_ARRAY and grav_arr.size() >= 2:
		p.gravity = Vector2(float(grav_arr[0]), float(grav_arr[1]))

	# Size over life: scale_start -> scale_end (relative to the 32-px soft sprite)
	var s0 := float(preset.get("scale_start", 1.0))
	var s1 := float(preset.get("scale_end", 1.0))
	var smax := maxf(maxf(s0, s1), 0.01)
	p.scale_amount_min = smax
	p.scale_amount_max = smax
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, s0 / smax))
	curve.add_point(Vector2(1.0, s1 / smax))
	p.scale_amount_curve = curve

	var col_start: Color = Color.from_string(str(preset.get("color_start", "#FFFFFF")), Color.WHITE)
	var col_end: Color = Color.from_string(str(preset.get("color_end", "#FFFFFF00")), Color.TRANSPARENT)
	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray([col_start, col_end])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	p.color_ramp = grad

	if str(preset.get("blend", "mix")) == "add":
		var mat: CanvasItemMaterial = CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = mat

	if preset.has("spin"):
		p.angular_velocity_min = float(preset["spin"])
		p.angular_velocity_max = float(preset["spin"])
	return p

## Spawns / restarts a particle emitter from the preset's pool.
func spawn_particle(preset_name: StringName, pos: Vector2, dir: Vector2 = Vector2.ZERO, tint: Color = Color.WHITE) -> CPUParticles2D:
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
		emitter.direction = dir.normalized()
	emitter.color = tint
	emitter.restart()
	emitter.emitting = true
	return emitter

func get_pool_capacity() -> int:
	return POOL_SIZE_PER_PRESET

func get_total_emitters_count() -> int:
	var total: int = 0
	for k in _pools:
		total += _pools[k].size()
	return total

# ── Event wiring ─────────────────────────────────────────────────────────────────

func bind_sim(p_sim: MatchSim) -> void:
	sim = p_sim
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.projectile_impact.connect(_on_impact)
	EventBus.projectile_bounced.connect(_on_bounced)
	EventBus.explosion.connect(_on_explosion)
	EventBus.character_killed.connect(_on_killed)
	EventBus.character_landed.connect(_on_landed)
	EventBus.jetpack_state_changed.connect(_on_jetpack)
	EventBus.rocket_boost_collected.connect(_on_boost_collected)

func _char(id: int) -> CharacterState:
	return sim.character(id) if sim else null

func _shooter_tint(id: int) -> Color:
	var c := _char(id)
	if c == null or c.is_human:
		return Color("#FFE08A")
	return c.profile.primary.lightened(0.5)

const FLASH_SPEC := {
	"magnum": [6, 17.0], "mp5": [5, 10.0], "ak47": [6, 15.0], "shotgun": [8, 22.0],
	"m93ba": [6, 26.0], "rocket_launcher": [5, 18.0], "saw_gun": [4, 8.0],
}

func _on_weapon_fired(shooter_id: int, weapon_id: StringName, muzzle: Vector2, dir: Vector2) -> void:
	var spec: Array = FLASH_SPEC.get(str(weapon_id), [5, 12.0])
	_flashes.append({"pos": muzzle, "dir": dir, "n": spec[0], "r": spec[1], "rot": randf() * TAU, "age": 0.0, "life": 0.05,
		"col": Color("#FFE9A8")})
	match str(weapon_id):
		"m93ba":
			_flashes.append({"pos": muzzle, "dir": dir, "n": 2, "r": 30.0, "rot": dir.angle() + PI * 0.5, "age": 0.0, "life": 0.06, "col": Color("#FFF6D6")})
			_trail_from(muzzle, dir, shooter_id)
		"rocket_launcher":
			var c := _char(shooter_id)
			var back := muzzle - dir * 115.0
			if c:
				back = WeaponLogic.weapon_local_to_world(c, Vector2(-52.0, -10.0))
			spawn_particle(&"explosion_smoke", back, -dir)
		"saw_gun":
			spawn_particle(&"saw_sparks", muzzle, dir)
	if str(weapon_id) not in ["saw_gun", "phasr", "flamethrower"]:
		spawn_particle(&"muzzle_smoke", muzzle, dir)
	if str(weapon_id) in ["mp5", "ak47", "shotgun", "m93ba"]:
		var c2 := _char(shooter_id)
		var eject := muzzle
		if c2:
			var art: Dictionary = Data.weapon_art.get(str(weapon_id), {})
			var e: Array = art.get("eject", [10, -12])
			eject = WeaponLogic.weapon_local_to_world(c2, Vector2(float(e[0]), float(e[1])))
		spawn_particle(&"shell_casing", eject, Vector2(-dir.x, -1.0))

## Black Arrow: a white-hot muzzle→impact line that lingers 0.25 s (§7.6 tracers).
func _trail_from(muzzle: Vector2, dir: Vector2, shooter_id: int) -> void:
	if sim == null:
		return
	var end := muzzle + dir * 7000.0
	var hit: Dictionary = sim.grid.raycast(muzzle, end, C.MASK_PROJECTILE)
	if bool(hit["hit"]):
		end = hit["point"]
	_trails.append({"a": muzzle, "b": end, "age": 0.0, "life": 0.25, "col": _shooter_tint(shooter_id), "w": 4.0})

func _on_impact(kind: int, pos: Vector2, normal: Vector2, surface: int, weapon_id: StringName, hit_character: bool, _headshot: bool) -> void:
	if kind == Projectile.Kind.FLAME_PUFF:
		spawn_particle(&"flame_smoke", pos, Vector2.UP)
		return
	if hit_character:
		var tint := Color.WHITE
		spawn_particle(&"impact_armor", pos, normal, tint)
		return
	match surface:
		Enums.Surface.METAL: spawn_particle(&"impact_spark_metal", pos, normal)
		Enums.Surface.WOOD: spawn_particle(&"impact_wood", pos, normal)
		Enums.Surface.SAND: spawn_particle(&"impact_sand", pos, normal)
		_: spawn_particle(&"impact_dust_rock", pos, normal)
	if kind != Projectile.Kind.SAW_BLADE and str(weapon_id) != "flamethrower":
		_holes.append({"pos": pos - normal * 1.0, "age": 0.0})
		if _holes.size() > MAX_BULLET_HOLES:
			_holes.pop_front()
		_decals.queue_redraw()

func _on_bounced(_kind: int, pos: Vector2, normal: Vector2, _speed: float) -> void:
	spawn_particle(&"saw_sparks", pos, normal)

func _on_explosion(ev: ExplosionEvent) -> void:
	spawn_particle(&"explosion_fireball", ev.pos, Vector2.UP)
	spawn_particle(&"explosion_smoke", ev.pos, Vector2.UP)
	spawn_particle(&"explosion_debris", ev.pos, Vector2.UP)
	_rings.append({"pos": ev.pos, "r": ev.radius * 1.3, "age": 0.0, "life": 0.25, "col": Color("#FFE6B0"), "w": 8.0})
	_flashes.append({"pos": ev.pos, "dir": Vector2.RIGHT, "n": 10, "r": ev.radius * 0.45, "rot": randf() * TAU, "age": 0.0, "life": 0.09, "col": Color("#FFF2C4")})
	_scorches.append({"pos": ev.pos, "r": ev.radius * 0.5, "age": 0.0})
	if _scorches.size() > MAX_SCORCHES:
		_scorches.pop_front()
	_decals.queue_redraw()

func _on_killed(ev: KillEvent) -> void:
	var v := _char(ev.victim_id)
	if v == null:
		return
	var at := v.centre()
	if v.is_human:
		spawn_particle(&"spark_ring", at, Vector2.UP)
	else:
		spawn_particle(&"derez_squares", at, Vector2.UP, v.profile.primary.lightened(0.3))

func _on_landed(_id: int, _speed: float, _surface: int) -> void:
	var c := _char(_id)
	if c:
		spawn_particle(&"landing_dust", c.pos, Vector2.UP)

func _on_jetpack(id: int, active: bool, burnout: bool) -> void:
	if burnout and not active:
		var c := _char(id)
		if c:
			spawn_particle(&"burnout_sputter", c.pos + Vector2(-16.0 * c.facing, -30.0), Vector2.DOWN)

func _on_boost_collected(by_id: int, _duration: float) -> void:
	var c := _char(by_id)
	if c:
		_rings.append({"pos": c.centre(), "r": 140.0, "age": 0.0, "life": 0.35, "col": Color("#FFB703"), "w": 10.0})

# ── Continuous jetpack emitters (§7.6 jet_exhaust / jet_smoke / boost_afterburner) ──

func _jet_emitters(c: CharacterState) -> Array:
	if _jets.has(c.id):
		return _jets[c.id]
	var list: Array = []
	for preset_name in ["jet_exhaust", "jet_smoke", "boost_afterburner"]:
		var e := create_emitter_for_preset(_presets.get(preset_name, {}))
		e.one_shot = false
		e.emitting = false
		e.direction = Vector2.DOWN
		if preset_name == "jet_exhaust":
			e.color = Palette.SKYRA_VISOR.lightened(0.4) if c.is_human else c.profile.primary.lightened(0.3)
		add_child(e)
		list.append(e)
	_jets[c.id] = list
	return list

func _update_jets() -> void:
	if sim == null:
		return
	var al := WorldView.alpha()
	for c in sim.characters:
		var alive := c.life_state == Enums.LifeState.ALIVE
		var jetting := alive and c.jet_active
		if not jetting and not _jets.has(c.id):
			continue
		var list := _jet_emitters(c)
		var boosted := c.boost_t > 0.0 and alive and not c.grounded
		var nozzle := c.prev_pos.lerp(c.pos, al) + Vector2(-16.0 * float(c.facing), -30.0)
		for i in range(list.size()):
			var e: CPUParticles2D = list[i]
			var on := (jetting and i < 2 and not boosted) or (boosted and i != 0)
			if e.emitting != on:
				e.emitting = on
			e.global_position = nozzle

# ── Per-frame non-particle FX ────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_update_jets()
	for arr in [_flashes, _rings, _trails]:
		for e in arr:
			e.age += delta
	_flashes = _flashes.filter(func(e): return e.age < e.life)
	_rings = _rings.filter(func(e): return e.age < e.life)
	_trails = _trails.filter(func(e): return e.age < e.life)
	var decal_dirty := false
	for h in _holes:
		h.age += delta
	for s in _scorches:
		s.age += delta
	var nh := _holes.size()
	var ns := _scorches.size()
	_holes = _holes.filter(func(h): return h.age < 20.0)
	_scorches = _scorches.filter(func(s): return s.age < 30.0)
	decal_dirty = nh != _holes.size() or ns != _scorches.size()
	if decal_dirty:
		_decals.queue_redraw()
	queue_redraw()

func _draw() -> void:
	for t in _trails:
		var a: float = 0.7 * (1.0 - t.age / t.life)
		draw_line(t.a, t.b, Color(t.col, a), t.w)
		draw_line(t.a, t.b, Color(1, 1, 1, a), t.w * 0.4)
	for f in _flashes:
		var k: float = 1.0 - f.age / f.life
		var r: float = f.r
		Palette.draw_glow(self, f.pos, r * 2.2, Color(1.0, 0.85, 0.5, 0.6 * k))
		var pts := PackedVector2Array()
		var n: int = f.n
		for i in range(n * 2):
			var ang: float = f.rot + PI * float(i) / float(n)
			var rr := r if i % 2 == 0 else r * 0.45
			pts.append(f.pos + Vector2(cos(ang), sin(ang)) * rr)
		draw_colored_polygon(pts, Color(f.col, k))
		draw_circle(f.pos, r * 0.35, Color(1, 1, 1, k))
	for g in _rings:
		var k: float = g.age / g.life
		draw_arc(g.pos, g.r * k, 0.0, TAU, 48, Color(g.col, 0.8 * (1.0 - k)), lerpf(g.w, 1.0, k))

func _draw_decals() -> void:
	for s in _scorches:
		var a := 0.5 * clampf((30.0 - s.age) / 3.0, 0.0, 1.0)
		_decals.draw_circle(s.pos, s.r, Color(0.1, 0.1, 0.1, a))
		_decals.draw_circle(s.pos, s.r * 0.6, Color(0.05, 0.05, 0.05, a))
	for h in _holes:
		var a := clampf((20.0 - h.age) / 2.0, 0.0, 1.0)
		_decals.draw_circle(h.pos, 4.5, Color("#5A5A64", a))
		_decals.draw_circle(h.pos, 3.0, Color(Palette.OUTLINE, a))
