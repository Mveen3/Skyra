# Implements §9.9 debug overlay (F3): collision rects (solid red, one-way yellow, updraft
# cyan), standable nav nodes, bot paths, bot labels "state · role · ★token", perception
# rays, Director phase / intensity / tokens and timings. While open (debug builds only):
# F6 god mode, F7 give the next weapon, F8 spawn the Rocket Boost now, F9 kill all bots.
class_name DebugOverlay
extends CanvasLayer

const STATE_NAMES := ["DEAD", "PATROL", "ACQUIRE", "ENGAGE", "COVER", "RETREAT", "FLANK", "HOLD"]
const ROLE_NAMES := ["ATTACKER", "FLANKER", "HOLDER", "PATROLLER"]
const PHASE_NAMES := ["WARMUP", "BUILD_UP", "PEAK", "RELAX", "RESPAWN_GRACE"]

var flow: GameFlow
var open: bool = false
var god_mode: bool = false
var _screen: Control
var _world: Node2D = null
var _world_owner: WorldView = null
var _weapon_cycle: int = 0

func _init(p_flow: GameFlow) -> void:
	flow = p_flow
	layer = C.LAYER_DEBUG
	process_mode = Node.PROCESS_MODE_ALWAYS
	_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.draw.connect(_draw_screen)
	add_child(_screen)
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	if event.is_action_pressed(&"debug_overlay"):
		open = not open
		visible = open
		get_viewport().set_input_as_handled()
		return
	if not open or not OS.is_debug_build() or flow.sim == null:
		return
	var sim := flow.sim
	match (event as InputEventKey).physical_keycode:
		KEY_F6:
			god_mode = not god_mode
			EventBus.toast_requested.emit("God mode %s" % ("ON" if god_mode else "OFF"), &"debug", 1.5)
		KEY_F7:
			var ids := ["mp5", "ak47", "shotgun", "m93ba", "flamethrower", "phasr", "rocket_launcher", "saw_gun"]
			_weapon_cycle = (_weapon_cycle + 1) % ids.size()
			var h := sim.human_char
			if h.life_state == Enums.LifeState.ALIVE:
				h.inventory.slots[1] = WeaponInstance.new(Data.weapons[ids[_weapon_cycle]])
				h.inventory.set_active_slot(1, true)
		KEY_F8:
			if sim.boost.phase == RocketBoostManager.BoostPhase.WAITING:
				sim.boost.timer = 0.0
		KEY_F9:
			for b in sim.bot_chars:
				if b.life_state == Enums.LifeState.ALIVE:
					sim.damage_system.queue_damage(b, 0, Enums.Team.HUMAN, "magnum", 1000.0, b.centre())
		_:
			return
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if god_mode and flow.sim and flow.sim.human_char.life_state == Enums.LifeState.ALIVE:
		flow.sim.human_char.invuln_t = maxf(flow.sim.human_char.invuln_t, 0.5)
		flow.sim.human_char.health = 100.0
	if not open:
		_free_world_layer()
		return
	var wv: WorldView = get_parent().world_view if get_parent() else null
	if wv != _world_owner:
		_free_world_layer()
		if wv:
			_world_owner = wv
			_world = Node2D.new()
			_world.z_index = 60
			_world.z_as_relative = false
			_world.draw.connect(_draw_world)
			wv.add_child(_world)
	if _world:
		_world.queue_redraw()
	_screen.queue_redraw()

func _free_world_layer() -> void:
	if _world and is_instance_valid(_world):
		_world.queue_free()
	_world = null
	_world_owner = null

func _draw_world() -> void:
	var sim := flow.sim
	if sim == null or _world_owner == null:
		return
	var view := _world_owner.camera.view_rect_world().grow(64.0)
	var c0 := maxi(0, int(view.position.x / 64.0))
	var c1 := mini(sim.grid.width - 1, int(view.end.x / 64.0))
	var r0 := maxi(0, int(view.position.y / 64.0))
	var r1 := mini(sim.grid.height - 1, int(view.end.y / 64.0))
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var t := sim.grid.tile_at(c, r)
			var x := c * 64.0
			var y := r * 64.0
			if MapChunk.is_full(t):
				_world.draw_rect(Rect2(x, y, 64, 64), Color(1, 0.2, 0.2, 0.18))
			elif t == Enums.Tile.HALF:
				_world.draw_rect(Rect2(x, y + 32, 64, 32), Color(1, 0.2, 0.2, 0.25))
			elif t == Enums.Tile.ONE_WAY:
				_world.draw_rect(Rect2(x, y, 64, 16), Color(1, 0.9, 0.2, 0.35))
			elif t == Enums.Tile.UPDRAFT:
				_world.draw_rect(Rect2(x, y, 64, 64), Color(0.2, 0.9, 1, 0.12))
			var n: NavGrid.NavNode = sim.nav.nodes.get(Vector2i(c, r))
			if n and n.standable:
				_world.draw_circle(n.pos, 3.0, Color(0.3, 1, 0.4, 0.7))
	var font := ThemeDB.fallback_font
	var h := sim.human_char
	for b in sim.bot_chars:
		if b.life_state != Enums.LifeState.ALIVE:
			continue
		var brain: BotBrain = b.brain as BotBrain
		if brain == null:
			continue
		var pf := brain.path_follower
		if pf.has_path():
			var pts := PackedVector2Array([b.pos])
			for i in range(pf.current_idx, pf.waypoints.size()):
				pts.append(pf.waypoints[i])
			if pts.size() > 1:
				_world.draw_polyline(pts, Color(b.profile.primary, 0.8), 3.0)
		# Perception ray to Skyra
		if h.life_state == Enums.LifeState.ALIVE and b.pos.distance_to(h.pos) < 2600.0:
			var col := Color(0.2, 1, 0.3, 0.6) if brain.perception.sees_human else Color(1, 0.25, 0.25, 0.35)
			_world.draw_line(b.shoulder(), h.centre(), col, 2.0)
		var label := "%s · %s%s" % [STATE_NAMES[brain.state], ROLE_NAMES[brain.role], " ★" if brain.has_token else ""]
		_world.draw_string_outline(font, b.pos + Vector2(-80, -126), label, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, 4, Color.BLACK)
		_world.draw_string(font, b.pos + Vector2(-80, -126), label, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, Color.WHITE)

func _draw_screen() -> void:
	var sim := flow.sim
	var font := ThemeDB.fallback_font
	var lines: Array[String] = ["DEBUG (F3)  F6 god %s · F7 weapon · F8 boost · F9 kill bots" % ("ON" if god_mode else "off"),
		"FPS %d   Sim %.2f ms" % [Engine.get_frames_per_second(), flow.last_sim_us / 1000.0]]
	if sim:
		var d := sim.director
		var tokens := 0
		for bid in d.bot_data:
			if bool(d.bot_data[bid]["has_token"]):
				tokens += 1
		lines.append("Director %s  intensity %.2f  tokens %d/%d" % [PHASE_NAMES[d.phase], d.intensity, tokens, d.allowed_tokens()])
		lines.append("Projectiles %d   Loose weapons %d   Boost phase %d" % [sim.projectiles.active_projectiles.size(), sim.loose_weapons.size(), sim.boost.phase])
	var y := 140.0
	_screen.draw_rect(Rect2(16, y - 24, 760, lines.size() * 26 + 16), Color(0, 0, 0, 0.6))
	for l in lines:
		_screen.draw_string(font, Vector2(24, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 1, 0.8))
		y += 26.0
	if sim:
		var bar := Rect2(24, y, 300, 10)
		_screen.draw_rect(bar, Color(0.2, 0.2, 0.2, 0.8))
		_screen.draw_rect(Rect2(bar.position, Vector2(bar.size.x * sim.director.intensity, bar.size.y)), Color(1, 0.4, 0.3))
