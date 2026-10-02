# Implements §7.10 audio cue catalogue (EventBus event -> sound): weapon fire signatures,
# delayed pump/bolt/reload cues, loops that follow their emitters (jetpacks, Blaze, Phaser,
# rockets, saw blades, Rocket Boost), impacts, kill stings, zone ambience crossfades and
# positional landmark loops. Bound per match; process() runs every rendered frame.
class_name AudioEventRouter
extends RefCounted

const AMB_FADE_S: float = 1.5

var _audio: Object = null
var sim: MatchSim = null

var _flame_loops: Dictionary = {} # shooter id -> voice
var _beam_loops: Dictionary = {}
var _jet_loops: Dictionary = {} # character id -> voice
var _proj_loops: Dictionary = {} # projectile id -> voice
var _boost_idle: int = 0
var _boost_active: int = 0
var _amb_voice: int = 0
var _amb_cue: StringName = &""
var _amb_old_voice: int = 0
var _amb_fade_t: float = 0.0
var _landmarks: Array[int] = []
var _last_hurt_ms: int = -1000
var _human_in_updraft: bool = false
var _scheduled: Array = [] # {t, cue, pos, opts, id}
var _connections: Array = [] # [Signal, Callable]

func _init(audio_node: Object = null) -> void:
	_audio = audio_node

func get_audio() -> Object:
	return _audio if _audio != null else Audio

## Returns the distinct fire cue for each of the 9 weapons (§7.10 / T-AUD-05).
static func get_weapon_fire_cue(weapon_id: StringName) -> StringName:
	match weapon_id:
		&"magnum": return &"sfx.magnum.fire"
		&"mp5": return &"sfx.mp5.fire"
		&"ak47": return &"sfx.ak47.fire"
		&"shotgun": return &"sfx.shotgun.fire"
		&"m93ba": return &"sfx.m93ba.fire"
		&"flame", &"flamethrower": return &"sfx.flame.start"
		&"phasr": return &"sfx.phasr.start"
		&"rocket_launcher": return &"sfx.rocket.fire"
		&"saw_gun": return &"sfx.saw.fire"
		_: return &""

# ── Binding ──────────────────────────────────────────────────────────────────────

func bind(p_sim: MatchSim) -> void:
	unbind()
	sim = p_sim
	_link(EventBus.weapon_fired, _on_weapon_fired)
	_link(EventBus.flame_state_changed, _on_flame)
	_link(EventBus.beam_state_changed, _on_beam)
	_link(EventBus.projectile_bounced, _on_bounced)
	_link(EventBus.grenade_thrown, _on_grenade_thrown)
	_link(EventBus.grenade_bounced, _on_grenade_bounced)
	_link(EventBus.explosion, _on_explosion)
	_link(EventBus.weapon_reload_started, _on_reload)
	_link(EventBus.weapon_empty_click, _on_empty)
	_link(EventBus.weapon_switched, _on_switched)
	_link(EventBus.weapon_picked_up, _on_picked_up)
	_link(EventBus.weapon_dropped, _on_dropped)
	_link(EventBus.frag_pack_collected, _on_frag_pack)
	_link(EventBus.launch_pad_used, _on_launch_pad)
	_link(EventBus.med_collected, _on_med_collected)
	_link(EventBus.projectile_impact, _on_impact)
	_link(EventBus.near_miss, _on_near_miss)
	_link(EventBus.jetpack_state_changed, _on_jetpack)
	_link(EventBus.footstep, _on_footstep)
	_link(EventBus.character_landed, _on_landed)
	_link(EventBus.rocket_boost_spawned, _on_boost_spawned)
	_link(EventBus.rocket_boost_collected, _on_boost_collected)
	_link(EventBus.rocket_boost_expired, _on_boost_expired)
	_link(EventBus.rocket_boost_despawned, _on_boost_despawned)
	_link(EventBus.character_spawned, _on_spawned)
	_link(EventBus.stealth_ended, _on_stealth_ended)
	_link(EventBus.character_killed, _on_killed_event)
	_link(EventBus.character_damaged, _on_damaged_event)
	_start_landmark_loops()

func _link(sig: Signal, cb: Callable) -> void:
	sig.connect(cb)
	_connections.append([sig, cb])

func unbind() -> void:
	for pair in _connections:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	_connections.clear()
	var audio = get_audio()
	if audio and audio.has_method("stop"):
		for d in [_flame_loops, _beam_loops, _jet_loops, _proj_loops]:
			for k in d:
				audio.stop(d[k])
			d.clear()
		for v in _landmarks:
			audio.stop(v)
		for v in [_boost_idle, _boost_active, _amb_voice, _amb_old_voice]:
			if v != 0:
				audio.stop(v)
	_landmarks.clear()
	_boost_idle = 0
	_boost_active = 0
	_amb_voice = 0
	_amb_old_voice = 0
	_amb_cue = &""
	_scheduled.clear()
	sim = null

func _char(id: int) -> CharacterState:
	return sim.character(id) if sim else null

func _pos_of(id: int) -> Vector2:
	var c := _char(id)
	return c.centre() if c else Vector2.INF

func _schedule(delay: float, cue: StringName, pos: Vector2, opts: Dictionary = {}, follow_id: int = -1) -> void:
	_scheduled.append({"t": delay, "cue": cue, "pos": pos, "opts": opts, "id": follow_id})

# ── Weapons ──────────────────────────────────────────────────────────────────────

## Routes a weapon shot to its fire cue (and the pump / bolt cycle cues).
func on_weapon_fired(weapon_id: StringName, pos: Vector2, is_skyra: bool = false) -> void:
	var cue: StringName = get_weapon_fire_cue(weapon_id)
	if cue == &"":
		return
	var audio = get_audio()
	if audio == null:
		return
	audio.play(cue, pos, {"is_skyra": is_skyra})
	if weapon_id == &"shotgun":
		_schedule(0.35, &"sfx.shotgun.pump", pos, {"is_skyra": is_skyra})
	elif weapon_id == &"m93ba":
		_schedule(0.5, &"sfx.m93ba.bolt", pos, {"is_skyra": is_skyra})

func _on_weapon_fired(shooter_id: int, weapon_id: StringName, muzzle: Vector2, _dir: Vector2) -> void:
	if weapon_id == &"flamethrower" or weapon_id == &"phasr":
		return # continuous weapons use their start/loop/stop cues
	on_weapon_fired(weapon_id, muzzle, shooter_id == 0)

func _on_flame(shooter_id: int, active: bool) -> void:
	_continuous(_flame_loops, shooter_id, active, &"sfx.flame.start", &"sfx.flame.loop", &"sfx.flame.stop")

func _on_beam(shooter_id: int, active: bool) -> void:
	_continuous(_beam_loops, shooter_id, active, &"sfx.phasr.start", &"sfx.phasr.loop", &"sfx.phasr.stop")

func _continuous(loops: Dictionary, id: int, active: bool, start: StringName, loop: StringName, stop: StringName) -> void:
	var audio = get_audio()
	var pos := _pos_of(id)
	if pos == Vector2.INF:
		return
	var opts := {"is_skyra": id == 0}
	if active:
		audio.play(start, pos, opts)
		if not loops.has(id):
			loops[id] = audio.play_loop(loop, pos, opts)
	else:
		if loops.has(id):
			audio.stop(loops[id])
			loops.erase(id)
		audio.play(stop, pos, opts)

func _on_bounced(kind: int, pos: Vector2, _normal: Vector2, _speed: float) -> void:
	if kind == Projectile.Kind.SAW_BLADE:
		get_audio().play(&"sfx.saw.ricochet", pos)

func _on_grenade_thrown(id: int, pos: Vector2, _vel: Vector2) -> void:
	get_audio().play(&"sfx.grenade.throw", pos, {"is_skyra": id == 0})

func _on_grenade_bounced(pos: Vector2, speed: float) -> void:
	get_audio().play(&"sfx.grenade.bounce", pos, {"pitch_scale": 0.9 + speed / 3000.0,
		"volume_db": linear_to_db(clampf(0.4 + speed / 1200.0, 0.05, 1.0))})

func on_explosion(pos: Vector2) -> void:
	var audio = get_audio()
	if audio:
		audio.play(&"sfx.explosion.large", pos)

func _on_explosion(ev: ExplosionEvent) -> void:
	on_explosion(ev.pos)
	if sim and ev.pos.distance_to(sim.human_char.centre()) < 600.0:
		get_audio().duck(&"Ambient", 4.0, 0.6)

func _on_reload(id: int, weapon_id: StringName, duration: float) -> void:
	var pos := _pos_of(id)
	if pos == Vector2.INF or not Data.weapons.has(weapon_id):
		return
	var audio = get_audio()
	var def: WeaponDef = Data.weapons[weapon_id]
	var opts := {"is_skyra": id == 0}
	match str(weapon_id):
		"phasr":
			audio.play(&"sfx.reload.energy_charge", pos, opts)
		"flamethrower":
			audio.play(&"sfx.reload.fuel_hiss", pos, opts)
		_:
			if def.reload_type == Enums.ReloadType.PER_SHELL:
				var shells := int(round((duration - 0.25) / maxf(0.01, def.shell_reload_s)))
				for i in range(shells):
					_schedule(0.25 + def.shell_reload_s * float(i + 1) - 0.05, &"sfx.reload.shell_insert", pos, opts, id)
			else:
				audio.play(&"sfx.reload.mag_out", pos, opts)
				_schedule(0.7 * duration, &"sfx.reload.mag_in", pos, opts, id)

func _on_empty(id: int, _w: StringName) -> void:
	get_audio().play(&"sfx.weapon.empty_click", _pos_of(id), {"is_skyra": id == 0})

func _on_switched(id: int, _from: StringName, _to: StringName) -> void:
	if id >= 0:
		get_audio().play(&"sfx.weapon.switch", _pos_of(id), {"is_skyra": id == 0})

func _on_picked_up(id: int, _w: StringName, _socket: StringName) -> void:
	get_audio().play(&"sfx.weapon.pickup", _pos_of(id), {"is_skyra": id == 0})

func _on_dropped(id: int, _w: StringName, pos: Vector2) -> void:
	get_audio().play(&"sfx.weapon.drop", pos, {"is_skyra": id == 0})

func _on_launch_pad(id: int, pad_pos: Vector2) -> void:
	get_audio().play(&"sfx.updraft.enter", pad_pos, {"is_skyra": id == 0, "pitch_scale": 0.8})
	get_audio().play(&"sfx.jetpack.start", pad_pos, {"is_skyra": id == 0, "pitch_scale": 0.7})

func _on_med_collected(id: int, station_pos: Vector2, _heal: float) -> void:
	get_audio().play(&"sfx.reload.energy_charge", station_pos, {"is_skyra": id == 0, "pitch_scale": 1.3})

func _on_frag_pack(id: int, _amount: int) -> void:
	get_audio().play(&"sfx.weapon.pickup", _pos_of(id), {"is_skyra": id == 0, "pitch_scale": 1.2})

func on_projectile_impact(surface: int, pos: Vector2, is_character: bool, is_headshot: bool = false) -> void:
	var audio = get_audio()
	if audio == null:
		return
	if is_character:
		audio.play(&"sfx.impact.character", pos)
		if is_headshot:
			audio.play(&"sfx.impact.headshot", pos)
		return
	match surface:
		Enums.Surface.METAL: audio.play(&"sfx.impact.metal", pos)
		Enums.Surface.WOOD: audio.play(&"sfx.impact.crate", pos)
		Enums.Surface.SAND: audio.play(&"sfx.impact.sand", pos)
		_: audio.play(&"sfx.impact.rock", pos)

func _on_impact(kind: int, pos: Vector2, _normal: Vector2, surface: int, _weapon_id: StringName, hit_character: bool, headshot: bool) -> void:
	if kind == Projectile.Kind.FLAME_PUFF:
		return
	on_projectile_impact(surface, pos, hit_character, headshot)

func _on_near_miss(_target_id: int, pos: Vector2, _speed: float) -> void:
	get_audio().play(&"sfx.bullet.whiz", pos)

# ── Movement ─────────────────────────────────────────────────────────────────────

func _on_jetpack(id: int, active: bool, burnout: bool) -> void:
	var audio = get_audio()
	var pos := _pos_of(id)
	if pos == Vector2.INF:
		return
	var opts := {"is_skyra": id == 0, "volume_db": 0.0 if id == 0 else -6.0}
	if active:
		audio.play(&"sfx.jetpack.start", pos, opts)
		if not _jet_loops.has(id):
			_jet_loops[id] = audio.play_loop(&"sfx.jetpack.loop", pos, opts)
	else:
		if _jet_loops.has(id):
			audio.stop(_jet_loops[id])
			_jet_loops.erase(id)
		if burnout:
			audio.play(&"sfx.jetpack.burnout", pos, opts)

func _on_footstep(id: int, surface: int) -> void:
	var c := _char(id)
	if c == null:
		return
	var cue := &"sfx.foot.rock"
	if surface == Enums.Surface.METAL:
		cue = &"sfx.foot.metal"
	elif surface == Enums.Surface.WOOD or surface == Enums.Surface.SAND:
		cue = &"sfx.foot.soft"
	get_audio().play(cue, c.pos, {"is_skyra": id == 0, "volume_db": 0.0 if id == 0 else -4.0})

func _on_landed(id: int, _speed: float, _surface: int) -> void:
	var c := _char(id)
	if c:
		get_audio().play(&"sfx.land.thud", c.pos, {"is_skyra": id == 0})

# ── Rocket Boost ─────────────────────────────────────────────────────────────────

func _on_boost_spawned(_socket: StringName, pos: Vector2) -> void:
	var audio = get_audio()
	audio.play(&"sfx.boost.spawn", Vector2.INF, {"bus": &"UI"})
	if _boost_idle != 0:
		audio.stop(_boost_idle)
	_boost_idle = audio.play_loop(&"sfx.boost.idle_loop", pos)

func _stop_boost_idle() -> void:
	if _boost_idle != 0:
		get_audio().stop(_boost_idle)
		_boost_idle = 0

func _on_boost_collected(_by_id: int, _duration: float) -> void:
	_stop_boost_idle()
	var audio = get_audio()
	audio.play(&"sfx.boost.pickup")
	if _boost_active == 0:
		_boost_active = audio.play_loop(&"sfx.boost.active_loop")

func _on_boost_expired(_id: int) -> void:
	if _boost_active != 0:
		get_audio().stop(_boost_active)
		_boost_active = 0
	get_audio().play(&"sfx.boost.expire")

func _on_boost_despawned(_socket: StringName) -> void:
	_stop_boost_idle()

# ── Lifecycle & stings ───────────────────────────────────────────────────────────

func _on_spawned(id: int, pos: Vector2, _initial: bool) -> void:
	get_audio().play(&"sfx.spawn.materialize", pos + Vector2(0.0, -42.0), {"is_skyra": id == 0})

func _on_stealth_ended(id: int) -> void:
	if id == 0:
		get_audio().play(&"sfx.stealth.end")

func _on_killed_event(ev: KillEvent) -> void:
	var victim := _char(ev.victim_id)
	var pos := victim.centre() if victim else Vector2.INF
	on_character_killed(ev.victim_id, ev.killer_id, ev.headshot, maxi(1, ev.multi_kill_count), pos)
	# A dead character's loops stop with it
	for d in [_jet_loops, _flame_loops, _beam_loops]:
		if d.has(ev.victim_id):
			get_audio().stop(d[ev.victim_id])
			d.erase(ev.victim_id)

## Kill stings: bright arpeggio when Skyra kills a bot, low boom when a bot kills her (§7.10).
func on_character_killed(victim_id: int, killer_id: int, is_headshot: bool = false, multikill_count: int = 1, pos: Vector2 = Vector2.INF) -> void:
	var audio = get_audio()
	if audio == null:
		return
	if killer_id == 0 and victim_id != 0:
		if is_headshot:
			audio.play(&"sting.kill_headshot")
		elif multikill_count >= 2:
			var pitch: float = pow(2.0, (2.0 * float(multikill_count - 1)) / 12.0)
			audio.play(&"sting.multikill", Vector2.INF, {"pitch_scale": pitch})
		else:
			audio.play(&"sting.kill_confirm")
		audio.play(&"sfx.bot.derez", pos)
	elif victim_id == 0 and killer_id != 0:
		audio.play(&"sting.player_defeated")
		audio.play(&"sfx.player.death")
		audio.duck(&"SFX", 6.0, 1.0)
	elif victim_id == 0 and killer_id == 0:
		audio.play(&"sting.suicide")
		audio.play(&"sfx.player.death")
	elif victim_id != 0:
		audio.play(&"sfx.bot.derez", pos)

func on_character_damaged(victim_id: int, _amount: float, _pos: Vector2 = Vector2.INF) -> void:
	if victim_id != 0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hurt_ms < 150:
		return
	_last_hurt_ms = now
	var audio = get_audio()
	if audio:
		audio.play(&"sfx.player.hurt")

func _on_damaged_event(ev: DamageEvent) -> void:
	on_character_damaged(ev.target_id, ev.amount, ev.point)

# ── Ambience & landmarks ─────────────────────────────────────────────────────────

func _start_landmark_loops() -> void:
	var audio = get_audio()
	for spot in [[&"amb.reactor.hum", Vector2(3840, 3300)], [&"amb.furnace.roar", Vector2(600, 2830)],
			[&"amb.boiler.hiss", Vector2(7080, 2830)], [&"amb.updraft.whoosh", Vector2(1216, 2000)],
			[&"amb.updraft.whoosh", Vector2(6464, 2000)], [&"amb.updraft.whoosh", Vector2(3840, 2400)]]:
		var v: int = audio.play_loop(spot[0], spot[1], {"bus": &"Ambient", "volume_db": -4.0})
		if v != 0:
			_landmarks.append(v)

func _zone_ambience(pos: Vector2) -> StringName:
	var z := Data.map.zone_at(Vector2i(int(floor(pos.x / 64.0)), int(floor(pos.y / 64.0))))
	return z.ambience if z else &"amb.wind.low"

func process(delta: float) -> void:
	if sim == null:
		return
	var audio = get_audio()
	# Scheduled cues (pump, bolt, magazine-in, shells)
	for s in _scheduled:
		s.t -= delta
	var due := _scheduled.filter(func(s) -> bool: return s.t <= 0.0)
	_scheduled = _scheduled.filter(func(s) -> bool: return s.t > 0.0)
	for s in due:
		var pos: Vector2 = s.pos
		if s.id >= 0:
			var c := _char(s.id)
			if c == null or c.life_state != Enums.LifeState.ALIVE:
				continue
			pos = c.centre()
		audio.play(s.cue, pos, s.opts)
	# Loops follow their emitters
	for d in [_jet_loops, _flame_loops, _beam_loops]:
		for id in d:
			audio.set_voice_pos(d[id], _pos_of(id))
	_update_projectile_loops(audio)
	# Rocket Boost hum: pitch 1.0 + |vel| / 2000, gliding to 0.8 in the last 2 s
	var h := sim.human_char
	if _boost_active != 0:
		var pitch := 1.0 + h.vel.length() / 2000.0
		if h.boost_t < 2.0:
			pitch = lerpf(0.8, pitch, h.boost_t / 2.0)
		audio.set_voice_pitch(_boost_active, pitch)
	# Skyra enters an updraft
	if h.life_state == Enums.LifeState.ALIVE:
		if h.in_updraft and not _human_in_updraft:
			audio.play(&"sfx.updraft.enter", h.centre(), {"is_skyra": true})
		_human_in_updraft = h.in_updraft
		_update_ambience(audio, delta, h.centre())

func _update_projectile_loops(audio) -> void:
	var seen := {}
	for p in sim.projectiles.active_projectiles:
		var cue := &""
		if p.kind == Projectile.Kind.ROCKET:
			cue = &"sfx.rocket.flight_loop"
		elif p.kind == Projectile.Kind.SAW_BLADE:
			cue = &"sfx.saw.spin_loop"
		if cue == &"":
			continue
		seen[p.id] = true
		if not _proj_loops.has(p.id):
			_proj_loops[p.id] = audio.play_loop(cue, p.pos)
		else:
			audio.set_voice_pos(_proj_loops[p.id], p.pos)
	for id in _proj_loops.keys():
		if not seen.has(id):
			audio.stop(_proj_loops[id])
			_proj_loops.erase(id)

## Zone ambience under Skyra with a 1.5-s crossfade between loops (§7.9).
func _update_ambience(audio, delta: float, pos: Vector2) -> void:
	var want := _zone_ambience(pos)
	if want != _amb_cue:
		if _amb_old_voice != 0:
			audio.stop(_amb_old_voice)
		_amb_old_voice = _amb_voice
		_amb_cue = want
		_amb_voice = audio.play_loop(want, Vector2.INF, {"bus": &"Ambient", "volume_db": -40.0})
		_amb_fade_t = 0.0
	if _amb_fade_t < AMB_FADE_S:
		_amb_fade_t = minf(AMB_FADE_S, _amb_fade_t + delta)
		var k := _amb_fade_t / AMB_FADE_S
		audio.set_voice_volume(_amb_voice, maxf(k, 0.0001))
		if _amb_old_voice != 0:
			audio.set_voice_volume(_amb_old_voice, maxf(1.0 - k, 0.0001))
			if k >= 1.0:
				audio.stop(_amb_old_voice)
				_amb_old_voice = 0
