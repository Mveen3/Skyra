# Implements §9.8 DataRegistry and full JSON validation.
extends Node

var errors: PackedStringArray = []

var tuning: Dictionary = {}
var weapons: Dictionary = {} # StringName -> WeaponDef
var grenade: GrenadeDef = null
var modes: Dictionary = {} # StringName -> Dictionary
var bots: Array[BotProfile] = []
var human_profile: Dictionary = {}
var map: MapData = null
var raw_map_rows: Array = []
var cues: Dictionary = {}
var weapon_art: Dictionary = {}
var character_art: Dictionary = {}
var fx: Dictionary = {}
var particle_presets: Dictionary:
	get: return fx
var input_bindings: Dictionary = {}

func _ready() -> void:
	load_all()

func load_all() -> bool:
	errors.clear()
	
	_load_tuning()
	_load_weapons()
	_load_modes()
	_load_bots()
	_load_map()
	_load_art()
	_load_fx()
	_load_audio()
	_load_input()
	
	if not errors.is_empty():
		for err in errors:
			Log.error("DataRegistry Error: " + err)
		return false
		
	Log.info("DataRegistry: All data loaded and validated successfully.")
	return true

func _read_json(path: String):
	if not FileAccess.file_exists(path):
		errors.append("File not found: " + path)
		return null
	var fa := FileAccess.open(path, FileAccess.READ)
	if not fa:
		errors.append("Cannot open file: " + path)
		return null
	var txt := fa.get_as_text()
	fa.close()
	var json = JSON.parse_string(txt)
	if json == null:
		errors.append("Invalid JSON syntax in file: " + path)
	return json

func _load_tuning() -> void:
	var d = _read_json(C.PATH_TUNING)
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("tuning.json root is not an object")
		return
	tuning = d
	
	# Validate keys
	for section in ["world", "character", "movement", "jetpack", "updraft", "respawn", "rocket_boost", "damage", "camera", "match", "streaks"]:
		if not tuning.has(section):
			errors.append("tuning.json missing section: " + section)
			
	if str(tuning.get("scope_model", "")) not in ["area", "linear"]:
		errors.append("tuning.json scope_model must be 'area' or 'linear'")

func _load_weapons() -> void:
	var d = _read_json(C.PATH_WEAPONS)
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("weapons.json root is not an object")
		return
		
	weapons.clear()
	var w_list: Array = d.get("weapons", [])
	var expected_ids := ["magnum", "mp5", "ak47", "shotgun", "m93ba", "flamethrower", "phasr", "rocket_launcher", "saw_gun"]
	var found_ids := []
	
	for w_dict in w_list:
		var w := WeaponDef.new()
		w.id = StringName(w_dict.get("id", ""))
		found_ids.append(str(w.id))
		w.display_name = w_dict.get("display_name", "")
		w.hud_name = w_dict.get("hud_name", "")
		w.say = w_dict.get("say", "")
		w.basis = w_dict.get("basis", "")
		
		var wc_str: String = w_dict.get("weapon_class", "PISTOL")
		match wc_str:
			"PISTOL": w.weapon_class = Enums.WeaponClass.PISTOL
			"SMG": w.weapon_class = Enums.WeaponClass.SMG
			"RIFLE": w.weapon_class = Enums.WeaponClass.RIFLE
			"SHOTGUN": w.weapon_class = Enums.WeaponClass.SHOTGUN
			"SNIPER": w.weapon_class = Enums.WeaponClass.SNIPER
			"FLAMER": w.weapon_class = Enums.WeaponClass.FLAMER
			"ENERGY": w.weapon_class = Enums.WeaponClass.ENERGY
			"LAUNCHER": w.weapon_class = Enums.WeaponClass.LAUNCHER
			"SPECIAL": w.weapon_class = Enums.WeaponClass.SPECIAL
			_: errors.append("Unknown weapon_class: " + wc_str)
			
		var fm_str: String = w_dict.get("fire_mode", "SEMI")
		match fm_str:
			"SEMI": w.fire_mode = Enums.FireMode.SEMI
			"AUTO": w.fire_mode = Enums.FireMode.AUTO
			"PUMP": w.fire_mode = Enums.FireMode.PUMP
			"BOLT": w.fire_mode = Enums.FireMode.BOLT
			"CONTINUOUS": w.fire_mode = Enums.FireMode.CONTINUOUS
			_: errors.append("Unknown fire_mode: " + fm_str)
			
		var del_str: String = w_dict.get("delivery", "PROJECTILE")
		match del_str:
			"PROJECTILE": w.delivery = Enums.Delivery.PROJECTILE
			"HITSCAN_BEAM": w.delivery = Enums.Delivery.HITSCAN_BEAM
			"FLAME": w.delivery = Enums.Delivery.FLAME
			_: errors.append("Unknown delivery: " + del_str)
			
		var pk_str: String = w_dict.get("projectile_kind", "NONE")
		match pk_str:
			"NONE": w.projectile_kind = Enums.ProjectileKind.NONE
			"BULLET": w.projectile_kind = Enums.ProjectileKind.BULLET
			"PELLET": w.projectile_kind = Enums.ProjectileKind.PELLET
			"SLUG": w.projectile_kind = Enums.ProjectileKind.SLUG
			"ROCKET": w.projectile_kind = Enums.ProjectileKind.ROCKET
			"SAW_BLADE": w.projectile_kind = Enums.ProjectileKind.SAW_BLADE
			"FLAME_PUFF": w.projectile_kind = Enums.ProjectileKind.FLAME_PUFF
			"GRENADE": w.projectile_kind = Enums.ProjectileKind.GRENADE
			_: errors.append("Unknown projectile_kind: " + pk_str)
			
		w.damage = float(w_dict.get("damage", 0))
		w.pellets = int(w_dict.get("pellets", 1))
		w.headshot_mult = float(w_dict.get("headshot_mult", 1.0))
		w.fire_interval_s = float(w_dict.get("fire_interval_s", 0.1))
		w.clip_size = int(w_dict.get("clip_size", 1))
		w.spawn_reserve = int(w_dict.get("spawn_reserve", 0))
		w.max_reserve = int(w_dict.get("max_reserve", 0))
		
		var rt_str: String = w_dict.get("reload_type", "MAGAZINE")
		match rt_str:
			"MAGAZINE": w.reload_type = Enums.ReloadType.MAGAZINE
			"PER_SHELL": w.reload_type = Enums.ReloadType.PER_SHELL
			_: errors.append("Unknown reload_type: " + rt_str)
			
		w.reload_s = float(w_dict.get("reload_s", 1.0))
		w.shell_reload_s = float(w_dict.get("shell_reload_s", 0.0))
		w.ammo_per_second = float(w_dict.get("ammo_per_second", 0.0))
		w.speed = float(w_dict.get("speed", 0))
		w.max_speed = float(w_dict.get("max_speed", 0))
		w.accel = float(w_dict.get("accel", 0))
		w.gravity = float(w_dict.get("gravity", 0))
		w.max_range = float(w_dict.get("range", 0))
		w.radius = float(w_dict.get("radius", 0))
		w.pierce_count = int(w_dict.get("pierce_count", 0))
		w.pierce_damage_mult = float(w_dict.get("pierce_damage_mult", 1.0))
		w.bounces = int(w_dict.get("bounces", 0))
		w.bounce_speed_mult = float(w_dict.get("bounce_speed_mult", 1.0))
		w.falloff_start = float(w_dict.get("falloff_start", 0))
		w.falloff_end = float(w_dict.get("falloff_end", 0))
		w.falloff_min_mult = float(w_dict.get("falloff_min_mult", 1.0))
		w.spread_base_deg = float(w_dict.get("spread_base_deg", 0))
		w.bloom_per_shot_deg = float(w_dict.get("bloom_per_shot_deg", 0))
		w.max_bloom_deg = float(w_dict.get("max_bloom_deg", 0))
		w.bloom_recovery_dps = float(w_dict.get("bloom_recovery_dps", 0))
		w.move_spread_add_deg = float(w_dict.get("move_spread_add_deg", 0))
		w.air_spread_add_deg = float(w_dict.get("air_spread_add_deg", 0))
		w.crouch_spread_mult = float(w_dict.get("crouch_spread_mult", 1.0))
		w.knockback = float(w_dict.get("knockback", 0))
		w.scope = float(w_dict.get("scope", 1.0))
		w.switch_s = float(w_dict.get("switch_s", 0.2))
		w.camera_trauma = float(w_dict.get("camera_trauma", 0))
		w.recoil_kick_wu = float(w_dict.get("recoil_kick_wu", 0))
		w.laser_sight = bool(w_dict.get("laser_sight", false))
		w.special = w_dict.get("special", {})
		
		var bot_dict: Dictionary = w_dict.get("bot", {})
		w.bot_range_min = float(bot_dict.get("range_min", 0))
		w.bot_range_max = float(bot_dict.get("range_max", 1000))
		w.bot_fire_gate_deg = float(bot_dict.get("fire_gate_deg", 5))
		w.bot_burst_min = int(bot_dict.get("burst_min", 1))
		w.bot_burst_max = int(bot_dict.get("burst_max", 1))
		w.bot_pause_min_s = float(bot_dict.get("pause_min_s", 0.3))
		w.bot_pause_max_s = float(bot_dict.get("pause_max_s", 0.5))
		w.bot_value_mini = float(bot_dict.get("value_mini", 10))
		w.bot_value_sniper = float(bot_dict.get("value_sniper", 0))
		
		if w.scope < 1.0 or w.scope > 5.0:
			errors.append("Weapon %s scope out of bounds [1, 5]: %f" % [w.id, w.scope])
		if w.clip_size < 1:
			errors.append("Weapon %s clip_size < 1" % w.id)
		if w.fire_interval_s < 0:
			errors.append("Weapon %s fire_interval_s < 0" % w.id)
		if w.falloff_start > w.falloff_end:
			errors.append("Weapon %s falloff_start > falloff_end" % w.id)
		if w.bot_range_min >= w.bot_range_max:
			errors.append("Weapon %s bot range_min >= range_max" % w.id)
			
		weapons[w.id] = w
		
	for exp_id in expected_ids:
		if exp_id not in found_ids:
			errors.append("Missing expected weapon: " + exp_id)
			
	# Parse grenade
	var g_dict: Dictionary = d.get("grenade", {})
	if g_dict.is_empty():
		errors.append("weapons.json missing 'grenade' section")
		return
	grenade = GrenadeDef.new()
	grenade.id = StringName(g_dict.get("id", "frag_grenade"))
	grenade.display_name = g_dict.get("display_name", "Frag")
	grenade.fuse_s = float(g_dict.get("fuse_s", 3.0))
	grenade.throw_speed = float(g_dict.get("throw_speed", 1150))
	grenade.inherit_velocity = float(g_dict.get("inherit_velocity", 0.5))
	grenade.gravity = float(g_dict.get("gravity", 1800))
	grenade.radius = float(g_dict.get("radius", 10))
	grenade.restitution = float(g_dict.get("restitution", 0.45))
	grenade.friction = float(g_dict.get("friction", 0.8))
	grenade.rest_speed = float(g_dict.get("rest_speed", 40))
	grenade.explosion = g_dict.get("explosion", {})
	grenade.throw_cooldown_s = float(g_dict.get("throw_cooldown_s", 0.6))
	grenade.preview_time_s = float(g_dict.get("preview_time_s", 1.2))
	grenade.bot = g_dict.get("bot", {})

func _load_modes() -> void:
	var d = _read_json(C.PATH_MODES)
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("modes.json root is not an object")
		return
	modes = d.get("modes", {})
	for m_id in ["mini_post", "sniper_post"]:
		if not modes.has(m_id):
			errors.append("modes.json missing mode: " + m_id)
			continue
		var m: Dictionary = modes[m_id]
		var dw: Dictionary = m.get("drop_weights", {})
		var sum_w := 0.0
		for k in dw:
			if k != "frag_pack" and not weapons.has(StringName(k)):
				errors.append("Mode %s drop_weights references unknown weapon: %s" % [m_id, k])
			var weight := float(dw[k])
			if weight < 0:
				errors.append("Mode %s negative drop_weight for %s" % [m_id, k])
			sum_w += weight
		if sum_w <= 0:
			errors.append("Mode %s sum of drop_weights <= 0" % m_id)
		var dir_dict: Dictionary = m.get("director", {})
		var max_tok: Dictionary = dir_dict.get("max_tokens", {})
		for count_str in ["3", "5", "7"]:
			if not max_tok.has(count_str):
				errors.append("Mode %s director max_tokens missing key '%s'" % [m_id, count_str])

func _load_bots() -> void:
	var d = _read_json(C.PATH_BOTS)
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("bots.json root is not an object")
		return
	human_profile = d.get("human", {})
	if human_profile.get("name", "") != "Skyra":
		errors.append("bots.json human name must be 'Skyra'")
		
	bots.clear()
	var b_list: Array = d.get("bots", [])
	var expected_names := ["Alpha", "Beta", "Gamma", "Delta", "Theta", "Phi", "Chi"]
	if b_list.size() != 7:
		errors.append("bots.json expected exactly 7 bots, got %d" % b_list.size())
		
	for i in range(b_list.size()):
		var b_dict: Dictionary = b_list[i]
		var b := BotProfile.new()
		b.id = StringName(b_dict.get("id", ""))
		b.name = b_dict.get("name", "")
		if i < expected_names.size() and b.name != expected_names[i]:
			errors.append("Bot %d expected name %s, got %s" % [i, expected_names[i], b.name])
		b.archetype = b_dict.get("archetype", "")
		b.primary = Color(b_dict.get("primary", "#FFFFFF"))
		b.secondary = Color(b_dict.get("secondary", "#000000"))
		b.visor = Color(b_dict.get("visor", "#00FFFF"))
		b.helmet = StringName(b_dict.get("helmet", ""))
		b.aggression = float(b_dict.get("aggression", 0.5))
		b.accuracy_mult = float(b_dict.get("accuracy_mult", 1.0))
		b.reaction_mult = float(b_dict.get("reaction_mult", 1.0))
		b.range_mult = float(b_dict.get("range_mult", 1.0))
		b.jet_hop_per_min = float(b_dict.get("jet_hop_per_min", 10.0))
		b.grenade_affinity = float(b_dict.get("grenade_affinity", 0.5))
		b.weapon_pref = b_dict.get("weapon_pref", {})
		bots.append(b)

func _load_map() -> void:
	map = MapLoader.load_map(C.PATH_MAP_OUTPOST)
	if map == null:
		errors.append("Failed to load map data from: " + C.PATH_MAP_OUTPOST)
		return
	var raw_d = _read_json(C.PATH_MAP_OUTPOST)
	if typeof(raw_d) == TYPE_DICTIONARY:
		raw_map_rows = raw_d.get("rows", [])
		var val_errors := MapLoader.validate(map, raw_map_rows)
		for e in val_errors:
			errors.append("MapValidation: " + e)

func _load_art() -> void:
	var w_art = _read_json(C.PATH_WEAPONS_ART)
	if typeof(w_art) != TYPE_DICTIONARY:
		errors.append("weapons_art.json invalid")
	else:
		weapon_art = w_art.get("weapons", {})
		for w_id in weapons:
			if not weapon_art.has(str(w_id)):
				errors.append("weapons_art.json missing entry for: " + str(w_id))
			else:
				var art_entry: Dictionary = weapon_art[str(w_id)]
				if not art_entry.has("muzzle"):
					errors.append("weapons_art.json missing 'muzzle' for: " + str(w_id))
					
	var c_art = _read_json(C.PATH_CHARACTERS_ART)
	if typeof(c_art) != TYPE_DICTIONARY:
		errors.append("characters_art.json invalid")
	else:
		character_art = c_art

func _load_fx() -> void:
	var fx_d = _read_json(C.PATH_PARTICLE_PRESETS)
	if typeof(fx_d) != TYPE_DICTIONARY:
		errors.append("particle_presets.json invalid")
	else:
		fx = fx_d.get("presets", {})
		for expected_p in [
			"muzzle_smoke", "shell_casing", "impact_spark_metal", "impact_dust_rock",
			"impact_wood", "impact_sand", "impact_armor", "explosion_fireball",
			"explosion_smoke", "explosion_debris", "jet_exhaust", "jet_smoke",
			"burnout_sputter", "boost_afterburner", "landing_dust", "saw_sparks",
			"phasr_impact", "flame_smoke", "derez_squares", "spark_ring", "embers",
			"steam_puff", "updraft_streaks", "pickup_sparkle"
		]:
			if not fx.has(expected_p):
				errors.append("particle_presets.json missing preset: " + expected_p)

func _load_audio() -> void:
	var a_d = _read_json(C.PATH_AUDIO_CUES)
	if typeof(a_d) != TYPE_DICTIONARY:
		errors.append("cues.json invalid")
	else:
		cues = a_d.get("cues", {})

func _load_input() -> void:
	var in_d = _read_json(C.PATH_DEFAULT_BINDINGS)
	if typeof(in_d) != TYPE_DICTIONARY:
		errors.append("default_bindings.json invalid")
	else:
		var actions: Array = in_d.get("actions", [])
		if actions.size() != 17:
			errors.append("default_bindings.json expected 17 actions, got %d" % actions.size())
		input_bindings.clear()
		for a in actions:
			input_bindings[StringName(a.get("id", ""))] = a
