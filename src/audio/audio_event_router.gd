# Implements §7.10 Audio cue catalogue (event -> sound).
class_name AudioEventRouter
extends RefCounted

var _audio: Object = null

func _init(audio_node: Object = null) -> void:
	_audio = audio_node

func get_audio() -> Object:
	if _audio != null:
		return _audio
	# Fallback to AudioManager autoload or find in tree
	if Engine.has_singleton(&"AudioManager"):
		return Engine.get_singleton(&"AudioManager")
	return null

## Routes weapon fire event to the weapon-specific fire cue.
func on_weapon_fired(weapon_id: StringName, pos: Vector2, is_skyra: bool = false) -> void:
	var cue: StringName = get_weapon_fire_cue(weapon_id)
	if cue != &"":
		var audio = get_audio()
		if audio:
			audio.play(cue, pos, {"is_skyra": is_skyra})
			if weapon_id == &"shotgun":
				# Pump sound at +0.35s
				# Can schedule or play directly if timer available
				pass
			elif weapon_id == &"m93ba":
				# Bolt sound at +0.5s
				pass

## Returns distinct fire cue ID for any of the 9 weapons.
static func get_weapon_fire_cue(weapon_id: StringName) -> StringName:
	match weapon_id:
		&"magnum": return &"sfx.magnum.fire"
		&"mp5": return &"sfx.mp5.fire"
		&"ak47": return &"sfx.ak47.fire"
		&"shotgun": return &"sfx.shotgun.fire"
		&"m93ba": return &"sfx.m93ba.fire"
		&"flame": return &"sfx.flame.start"
		&"phasr": return &"sfx.phasr.start"
		&"rocket_launcher": return &"sfx.rocket.fire"
		&"saw_gun": return &"sfx.saw.fire"
		_: return &""

## Routes kill event to kill stings and death sounds (§7.10).
func on_character_killed(victim_id: int, killer_id: int, is_headshot: bool = false, multikill_count: int = 1, pos: Vector2 = Vector2.INF) -> void:
	var audio = get_audio()
	if audio == null:
		return

	if killer_id == 0 and victim_id != 0:
		# Skyra killed a bot
		if is_headshot:
			audio.play(&"sting.kill_headshot")
		elif multikill_count >= 2:
			var pitch: float = pow(2.0, (2.0 * float(multikill_count - 1)) / 12.0)
			audio.play(&"sting.multikill", Vector2.INF, {"pitch_scale": pitch})
		else:
			audio.play(&"sting.kill_confirm")
		# Bot derez sound at victim position
		audio.play(&"sfx.bot.derez", pos)
	elif victim_id == 0 and killer_id != 0:
		# Bot killed Skyra
		audio.play(&"sting.player_defeated")
		audio.play(&"sfx.player.death")
		audio.duck(&"SFX", 6.0, 1.0)
	elif victim_id == 0 and killer_id == 0:
		# Skyra suicide
		audio.play(&"sting.suicide")
		audio.play(&"sfx.player.death")

func on_character_damaged(victim_id: int, _amount: float, _pos: Vector2 = Vector2.INF) -> void:
	if victim_id == 0:
		var audio = get_audio()
		if audio:
			audio.play(&"sfx.player.hurt")

func on_projectile_impact(surface: int, pos: Vector2, is_character: bool, is_headshot: bool = false) -> void:
	var audio = get_audio()
	if audio == null:
		return

	if is_character:
		audio.play(&"sfx.impact.character", pos)
		if is_headshot:
			audio.play(&"sfx.impact.headshot", pos)
	else:
		match surface:
			0: # ROCK
				audio.play(&"sfx.impact.rock", pos)
			1: # METAL
				audio.play(&"sfx.impact.metal", pos)
			2: # CRATE / WOOD
				audio.play(&"sfx.impact.crate", pos)
			3: # SAND
				audio.play(&"sfx.impact.sand", pos)
			_:
				audio.play(&"sfx.impact.rock", pos)

func on_explosion(pos: Vector2) -> void:
	var audio = get_audio()
	if audio:
		audio.play(&"sfx.explosion.large", pos)

func on_rocket_boost_spawned(pos: Vector2) -> void:
	var audio = get_audio()
	if audio:
		audio.play(&"sfx.boost.spawn", Vector2.INF)
		audio.play_loop(&"sfx.boost.idle_loop", pos)

func on_rocket_boost_collected() -> void:
	var audio = get_audio()
	if audio:
		audio.play(&"sfx.boost.pickup")

func on_rocket_boost_expired() -> void:
	var audio = get_audio()
	if audio:
		audio.play(&"sfx.boost.expire")
