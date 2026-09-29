# Implements §3.1.2 Geometric shape intersection helpers.
class_name Shapes
extends RefCounted

static func point_in_rect(p: Vector2, rect: Rect2) -> bool:
	return p.x >= rect.position.x and p.x <= rect.end.x and p.y >= rect.position.y and p.y <= rect.end.y

static func closest_point_on_aabb(p: Vector2, rect: Rect2) -> Vector2:
	return Vector2(
		clampf(p.x, rect.position.x, rect.end.x),
		clampf(p.y, rect.position.y, rect.end.y)
	)

static func circle_vs_aabb(c: Vector2, r: float, rect: Rect2) -> Dictionary:
	var cp := closest_point_on_aabb(c, rect)
	var diff := c - cp
	var dist_sq := diff.length_squared()
	
	if dist_sq < r * r:
		var dist := sqrt(dist_sq)
		var normal := Vector2.ZERO
		var pen := Vector2.ZERO
		if dist > 0.0001:
			normal = diff / dist
			var depth_val: float = r - dist
			pen = normal * depth_val
			return {"hit": true, "point": cp, "normal": normal, "penetration": pen, "depth": depth_val}
		else:
			# Center is inside the AABB - find minimum pushout to edge
			var left_pen: float = (c.x - rect.position.x) + r
			var right_pen: float = (rect.end.x - c.x) + r
			var top_pen: float = (c.y - rect.position.y) + r
			var bottom_pen: float = (rect.end.y - c.y) + r
			
			var min_pen: float = left_pen
			normal = Vector2(-1, 0)
			if right_pen < min_pen:
				min_pen = right_pen
				normal = Vector2(1, 0)
			if top_pen < min_pen:
				min_pen = top_pen
				normal = Vector2(0, -1)
			if bottom_pen < min_pen:
				min_pen = bottom_pen
				normal = Vector2(0, 1)
			pen = normal * min_pen
			var depth_val: float = min_pen
			return {"hit": true, "point": cp, "normal": normal, "penetration": pen, "depth": depth_val}
		
	return {"hit": false, "point": Vector2.ZERO, "normal": Vector2.ZERO, "penetration": Vector2.ZERO, "depth": 0.0}

static func segment_vs_aabb(a: Vector2, b: Vector2, rect: Rect2) -> Dictionary:
	var d := b - a
	if d.length_squared() < 1e-8:
		if point_in_rect(a, rect):
			return {"hit": true, "t": 0.0, "point": a, "normal": Vector2.UP}
		return {"hit": false, "t": 1.0, "point": b, "normal": Vector2.ZERO}

	var t_near := 0.0
	var t_far := 1.0
	var normal := Vector2.ZERO

	# X axis
	if absf(d.x) < 1e-8:
		if a.x < rect.position.x or a.x > rect.end.x:
			return {"hit": false, "t": 1.0, "point": b, "normal": Vector2.ZERO}
	else:
		var t1: float = (rect.position.x - a.x) / d.x
		var t2: float = (rect.end.x - a.x) / d.x
		var n1 := Vector2(-1, 0)
		var n2 := Vector2(1, 0)
		if t1 > t2:
			var tmp_t := t1; t1 = t2; t2 = tmp_t
			var tmp_n := n1; n1 = n2; n2 = tmp_n
		if t1 > t_near:
			t_near = t1
			normal = n1
		if t2 < t_far:
			t_far = t2
		if t_near > t_far:
			return {"hit": false, "t": 1.0, "point": b, "normal": Vector2.ZERO}

	# Y axis
	if absf(d.y) < 1e-8:
		if a.y < rect.position.y or a.y > rect.end.y:
			return {"hit": false, "t": 1.0, "point": b, "normal": Vector2.ZERO}
	else:
		var t1: float = (rect.position.y - a.y) / d.y
		var t2: float = (rect.end.y - a.y) / d.y
		var n1 := Vector2(0, -1)
		var n2 := Vector2(0, 1)
		if t1 > t2:
			var tmp_t := t1; t1 = t2; t2 = tmp_t
			var tmp_n := n1; n1 = n2; n2 = tmp_n
		if t1 > t_near:
			t_near = t1
			normal = n1
		if t2 < t_far:
			t_far = t2
		if t_near > t_far:
			return {"hit": false, "t": 1.0, "point": b, "normal": Vector2.ZERO}

	if t_near >= 0.0 and t_near <= 1.0:
		return {
			"hit": true,
			"t": t_near,
			"point": a + d * t_near,
			"normal": normal
		}

	return {"hit": false, "t": 1.0, "point": b, "normal": Vector2.ZERO}

static func closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1e-8:
		return a
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return a + ab * t

static func closest_point_on_rect(p: Vector2, rect: Rect2) -> Vector2:
	return closest_point_on_aabb(p, rect)

static func circle_intersects_rect(c: Vector2, r: float, rect: Rect2) -> Dictionary:
	return circle_vs_aabb(c, r, rect)

static func segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> Dictionary:
	return segment_vs_aabb(a, b, rect)
