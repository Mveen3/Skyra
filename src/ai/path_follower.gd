# Implements §5.7.3 Path follower → InputFrame synthesis, refuelling, and stuck recovery.
class_name PathFollower
extends RefCounted

var waypoints: Array[Vector2] = []
var current_idx: int = 0
var stuck_t: float = 0.0
var stuck_start_pos: Vector2 = Vector2.ZERO
var consecutive_stuck: int = 0
var needs_repath: bool = false
var refuel_mode: bool = false

func set_path(new_waypoints: Array[Vector2]) -> void:
	waypoints = new_waypoints
	current_idx = 0
	stuck_t = 0.0
	needs_repath = false

func clear() -> void:
	waypoints.clear()
	current_idx = 0
	stuck_t = 0.0
	needs_repath = false
	refuel_mode = false

func has_path() -> bool:
	return current_idx < waypoints.size()

func step(bot: CharacterState, dt: float, nav_grid: NavGrid) -> InputFrame:
	var frame := InputFrame.new()

	if not has_path():
		return frame

	var wp: Vector2 = waypoints[current_idx]
	var dx := wp.x - bot.pos.x
	var dy := wp.y - bot.pos.y

	# Check waypoint reached or passed along segment
	var reached := (absf(dx) < 32.0 and absf(dy) < 48.0)
	if not reached and current_idx < waypoints.size() - 1:
		var next_wp: Vector2 = waypoints[current_idx + 1]
		var seg := next_wp - wp
		if seg.length_squared() > 1.0:
			var to_bot := bot.pos - wp
			if to_bot.dot(seg) > 0.0:
				reached = true

	if reached:
		current_idx += 1
		if not has_path():
			return frame
		wp = waypoints[current_idx]
		dx = wp.x - bot.pos.x
		dy = wp.y - bot.pos.y

	# Stuck detection (§5.7.3: moved < 16 wu in 1.5 s while following)
	stuck_t += dt
	if stuck_t >= 1.5:
		if bot.pos.distance_to(stuck_start_pos) < 16.0:
			consecutive_stuck += 1
			needs_repath = true
		else:
			consecutive_stuck = 0
		stuck_t = 0.0
		stuck_start_pos = bot.pos

	# Refuel mode: fuel < 12 and next waypoints climb
	if bot.fuel < 12.0 and dy < -24.0 and not bot.in_updraft:
		refuel_mode = true

	if refuel_mode:
		if bot.fuel >= 70.0:
			refuel_mode = false
		else:
			if bot.grounded:
				# Wait on ground
				frame.move_x = 0
				frame.jet_held = false
				return frame

	# Horizontal movement
	frame.move_x = int(signf(dx)) if absf(dx) > 10.0 else 0
	frame.aim_world = wp

	# Vertical / Jetpack logic
	var climb := (dy < -20.0)
	var hover := (not bot.grounded and absf(dy) <= 24.0 and bot.vel.y > 60.0)
	var climb_obstacle := (bot.hit_wall and dy < 0.0)

	frame.jet_held = (climb or hover or climb_obstacle) and not refuel_mode
	if bot.grounded and (climb or climb_obstacle or dy < -16.0):
		frame.jet_pressed = true

	# Crouch / Drop-through / Updraft dive
	frame.crouch = (dy > 40.0 and (bot.ground_is_one_way or bot.in_updraft))

	return frame
