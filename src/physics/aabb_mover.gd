# Implements §3.8 AABB terrain collision mover and step-up.
class_name AabbMover
extends RefCounted

static func move(c: Object, delta: Vector2, grid: TileGrid, dt: float, half_w: float = 22.0, step_up_height: float = 34.0) -> void:
	c.hit_wall = false
	
	# ---- X axis ----
	if delta.x != 0.0:
		var target_x: float = float(c.pos.x) + delta.x
		var box_x: Rect2 = Rect2(target_x - half_w, float(c.pos.y) - float(c.height), half_w * 2.0, float(c.height) - 0.1)
		var rects_x := grid.solid_rects_in(box_x, false)
		
		if rects_x.is_empty():
			c.pos.x = target_x
		else:
			# Find nearest rect in direction of motion
			var nearest_r: Rect2 = rects_x[0]
			var min_dist: float = INF
			for r in rects_x:
				var dist: float = (r.position.x - (c.pos.x + half_w)) if delta.x > 0 else ((c.pos.x - half_w) - r.end.x)
				if dist < min_dist:
					min_dist = dist
					nearest_r = r
			
			# Step-up check (e.g. onto sandbag HALF tile)
			var can_step_up := false
			if c.grounded and (c.pos.y - nearest_r.position.y) <= step_up_height and (c.pos.y - nearest_r.position.y) > 0.0:
				var step_box := Rect2(target_x - half_w, nearest_r.position.y - float(c.height), half_w * 2.0, float(c.height) - 0.1)
				var step_rects := grid.solid_rects_in(step_box, false)
				if step_rects.is_empty():
					can_step_up = true
					c.pos = Vector2(target_x, nearest_r.position.y)
			
			if not can_step_up:
				if delta.x > 0:
					c.pos.x = nearest_r.position.x - half_w - 0.01
				else:
					c.pos.x = nearest_r.end.x + half_w + 0.01
				c.vel.x = 0.0
				c.hit_wall = true

	# ---- Y axis ----
	var old_feet: float = c.pos.y
	var new_feet: float = c.pos.y + delta.y
	
	if delta.y > 0.0: # falling / moving down
		var top: float = INF
		var box_y := Rect2(c.pos.x - half_w, new_feet - c.height, half_w * 2.0, c.height)
		var solid_rects := grid.solid_rects_in(box_y, false)
		for r in solid_rects:
			if r.position.y >= old_feet - 0.5:
				top = minf(top, r.position.y)
				
		var ow_top: float = INF
		var ow_candidate = null
		if c.drop_through_t <= 0.0:
			var ow_rects := grid.one_way_rects_in_x_range(c.pos.x - half_w, c.pos.x + half_w)
			for r in ow_rects:
				if old_feet <= r.position.y + 0.5 and new_feet >= r.position.y:
					if r.position.y < ow_top:
						ow_top = r.position.y
						ow_candidate = r
						
		if ow_top < top:
			top = ow_top
			
		if top < INF:
			c.pos.y = top
			var landing_speed: float = c.vel.y
			c.vel.y = 0.0
			c.grounded = true
			c.ground_is_one_way = (ow_candidate != null and top == ow_top and ow_top < top + 0.01)
			if c is CharacterState:
				c.landing_speed = landing_speed
				if landing_speed > 700.0:
					var srf := grid.surface_at(c.pos + Vector2(0.0, 1.0))
					EventBus.character_landed.emit(c.id, landing_speed, srf)
		else:
			c.pos.y = new_feet
			c.grounded = false
			c.ground_is_one_way = false
			
	elif delta.y < 0.0: # rising
		var box_y := Rect2(c.pos.x - half_w, new_feet - c.height, half_w * 2.0, c.height)
		var rects_y := grid.solid_rects_in(box_y, false)
		if rects_y.is_empty():
			c.pos.y = new_feet
		else:
			var max_bot: float = -INF
			for r in rects_y:
				max_bot = maxf(max_bot, r.end.y)
			c.pos.y = max_bot + c.height + 0.01
			c.vel.y = 0.0 # head bonk
		c.grounded = false
		c.ground_is_one_way = false
		
	c.drop_through_t = maxf(0.0, c.drop_through_t - dt)
