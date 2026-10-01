# Implements §3.10 Dynamic camera and scope system.
class_name GameCamera
extends Camera2D

const ZOOM_LAMBDA: float = 6.0
const POS_LAMBDA: float = 10.0
const DEADZONE: float = 0.08
const LOOKAHEAD_BASE: float = 0.25
const LOOKAHEAD_PER_SCOPE: float = 0.1375
const AIM_HEIGHT: float = -48.0
const DEATH_ZOOM_IN: float = 1.15
const MAP_W: float = 7680.0
const MAP_H: float = 3840.0
const DESIGN_VP: Vector2 = Vector2(1920.0, 1080.0)

const SHAKE_MAX_OFFSET: float = 18.0
const SHAKE_MAX_ROT_DEG: float = 1.2
const TRAUMA_DECAY: float = 1.6
const NOISE_HZ: float = 22.0

var curr_zoom: float = 1.0
var target_zoom: float = 1.0
var curr_cam_pos: Vector2 = Vector2(MAP_W * 0.5, MAP_H * 0.5)
var target_cam_pos: Vector2 = Vector2(MAP_W * 0.5, MAP_H * 0.5)

var trauma: float = 0.0
var noise_time: float = 0.0
var noise1: FastNoiseLite = null
var noise2: FastNoiseLite = null
var noise3: FastNoiseLite = null

var sim: MatchSim = null
var is_human_alive: bool = true
var death_pos: Vector2 = Vector2.ZERO
var s_at_death: float = 1.0
var lookahead_enabled: bool = true

func _init() -> void:
	ignore_rotation = false
	noise1 = FastNoiseLite.new()
	noise1.seed = 101
	noise1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	
	noise2 = FastNoiseLite.new()
	noise2.seed = 202
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	
	noise3 = FastNoiseLite.new()
	noise3.seed = 303
	noise3.noise_type = FastNoiseLite.TYPE_SIMPLEX

static func calc_zoom_target(scope: float, is_alive: bool = true) -> float:
	var s := maxf(1.0, scope)
	var z := 1.0 / sqrt(s)
	if not is_alive:
		z *= DEATH_ZOOM_IN
	return z

static func calc_lookahead(effective_scope: float) -> float:
	return LOOKAHEAD_BASE + LOOKAHEAD_PER_SCOPE * (effective_scope - 1.0)

static func calc_max_reach(scope: float, vp: Vector2 = DESIGN_VP) -> Vector2:
	var z := 1.0 / sqrt(scope)
	var half_view := (vp * 0.5) / z
	var la := calc_lookahead(scope)
	var offset := half_view * la
	return offset + half_view

static func compute_target(human_pos: Vector2, mouse_screen: Vector2, vp: Vector2, zoom_val: float, scope_now: float, la_enabled: bool = true) -> Vector2:
	var half_view := (vp * 0.5) / zoom_val
	var focus := human_pos + Vector2(0.0, AIM_HEIGHT)
	
	var n := Vector2.ZERO
	if la_enabled and vp.x > 0.0 and vp.y > 0.0:
		var half_vp := vp * 0.5
		var raw_n := (mouse_screen - half_vp) / half_vp
		raw_n = raw_n.clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
		if raw_n.length() >= DEADZONE:
			n = raw_n
			
	var la := calc_lookahead(scope_now) if la_enabled else 0.0
	var tgt := focus + n * half_view * la
	
	# Clamp to map rect shrunk by half-view
	tgt.x = clampf(tgt.x, half_view.x, MAP_W - half_view.x)
	tgt.y = clampf(tgt.y, half_view.y, MAP_H - half_view.y)
	return tgt

func snap_to(world_pos: Vector2, scope: float) -> void:
	target_zoom = calc_zoom_target(scope, true)
	curr_zoom = target_zoom
	var vp := get_viewport_rect().size if get_viewport() else DESIGN_VP
	var half_view := (vp * 0.5) / curr_zoom
	var focus := world_pos + Vector2(0.0, AIM_HEIGHT)
	target_cam_pos = Vector2(
		clampf(focus.x, half_view.x, MAP_W - half_view.x),
		clampf(focus.y, half_view.y, MAP_H - half_view.y)
	)
	curr_cam_pos = target_cam_pos
	global_position = curr_cam_pos
	zoom = Vector2(curr_zoom, curr_zoom)

func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func on_human_death(pos: Vector2, last_scope: float) -> void:
	is_human_alive = false
	death_pos = pos
	s_at_death = last_scope
	lookahead_enabled = false
	target_zoom = calc_zoom_target(s_at_death, false)

func on_human_respawn(spawn_pos: Vector2, scope: float) -> void:
	is_human_alive = true
	lookahead_enabled = true
	snap_to(spawn_pos, scope)

## Wires the §3.10.6 trauma sources and the §3.10.3 death / respawn behaviours.
func bind_sim(p_sim: MatchSim) -> void:
	sim = p_sim
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.character_damaged.connect(_on_damaged)
	EventBus.explosion.connect(_on_explosion)
	EventBus.character_landed.connect(_on_landed)
	EventBus.rocket_boost_collected.connect(_on_boost)
	EventBus.character_killed.connect(_on_killed)
	EventBus.character_spawned.connect(_on_spawned)

func _on_weapon_fired(id: int, weapon_id: StringName, _m: Vector2, _d: Vector2) -> void:
	if id == 0 and Data.weapons.has(weapon_id):
		add_trauma((Data.weapons[weapon_id] as WeaponDef).camera_trauma)

func _on_damaged(ev: DamageEvent) -> void:
	if ev.target_id == 0:
		add_trauma(0.12 + ev.amount / 250.0)

func _on_explosion(ev: ExplosionEvent) -> void:
	if sim:
		var d := ev.pos.distance_to(sim.human_char.centre())
		add_trauma(0.6 * clampf(1.0 - d / 900.0, 0.0, 1.0))

func _on_landed(id: int, speed: float, _surface: int) -> void:
	if id == 0 and speed > 900.0:
		add_trauma(0.10)

func _on_boost(by_id: int, _duration: float) -> void:
	if by_id == 0:
		add_trauma(0.20)

func _on_killed(ev: KillEvent) -> void:
	if ev.victim_id == 0 and sim:
		var h := sim.human_char
		on_human_death(h.death_pos, 1.0 / (curr_zoom * curr_zoom))

func _on_spawned(id: int, pos: Vector2, _initial: bool) -> void:
	if id == 0 and sim:
		var w := sim.human_char.inventory.active_weapon()
		on_human_respawn(pos, w.def.scope if w else 1.0)

## Camera view rectangle in world space (spawn rules, off-screen indicators).
func view_rect_world() -> Rect2:
	var vp := get_viewport_rect().size if get_viewport() else DESIGN_VP
	var half := vp * 0.5 / curr_zoom
	return Rect2(curr_cam_pos - half, half * 2.0)

## Effective scope while the zoom glides (§3.10.2 S_now).
func scope_now() -> float:
	return 1.0 / (curr_zoom * curr_zoom)

func update_camera(delta: float, human_state: CharacterState, mouse_screen_pos: Vector2, render_pos: Vector2 = Vector2.INF) -> void:
	var scope_target: float
	var focus_pos: Vector2
	if is_human_alive and human_state and human_state.life_state == Enums.LifeState.ALIVE:
		var inv: Inventory = human_state.inventory
		var w: WeaponInstance = inv.active_weapon() if inv else null
		scope_target = w.def.scope if w else 1.0
		focus_pos = render_pos if render_pos != Vector2.INF else human_state.pos
	else:
		scope_target = s_at_death
		focus_pos = death_pos

	target_zoom = calc_zoom_target(scope_target, is_human_alive)
	curr_zoom = target_zoom + (curr_zoom - target_zoom) * exp(-ZOOM_LAMBDA * delta)

	var vp := get_viewport_rect().size if get_viewport() else DESIGN_VP
	var scope_now_v := 1.0 / (curr_zoom * curr_zoom)
	target_cam_pos = compute_target(focus_pos, mouse_screen_pos, vp, curr_zoom, scope_now_v, lookahead_enabled)

	curr_cam_pos = target_cam_pos + (curr_cam_pos - target_cam_pos) * exp(-POS_LAMBDA * delta)
	global_position = curr_cam_pos
	zoom = Vector2(curr_zoom, curr_zoom)

	# Screen shake (trauma model, §3.10.6)
	if trauma > 0.0:
		noise_time += delta * NOISE_HZ
		var shake := trauma * trauma
		var n1 := noise1.get_noise_1d(noise_time)
		var n2 := noise2.get_noise_1d(noise_time)
		var n3 := noise3.get_noise_1d(noise_time)
		offset = Vector2(n1, n2) * (SHAKE_MAX_OFFSET * shake)
		rotation = deg_to_rad(SHAKE_MAX_ROT_DEG * shake * n3)
		trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
	else:
		offset = Vector2.ZERO
		rotation = 0.0
