# Implements §3.10.4 grenade preview / §4.5.3 grenade circle mover prediction: simulates a
# throw with the same gravity, updraft lift, restitution and friction as the real grenade.
class_name GrenadeBallistics
extends RefCounted

## Points of the predicted path for `duration` seconds, stopping after `max_bounces` + 1 contacts.
static func predict(origin: Vector2, vel: Vector2, grid: TileGrid, duration: float = 1.2, max_bounces: int = 1) -> PackedVector2Array:
	var g: GrenadeDef = Data.grenade
	var radius := g.radius if g else 10.0
	var restitution := g.restitution if g else 0.45
	var friction := g.friction if g else 0.8
	var pts := PackedVector2Array([origin])
	var pos := origin
	var v := vel
	var dt := 1.0 / 60.0
	var contacts := 0
	var t := 0.0
	while t < duration:
		var substeps := maxi(1, int(ceil(v.length() * dt / maxf(8.0, radius))))
		var sdt := dt / float(substeps)
		for _s in range(substeps):
			var prev := pos
			var in_updraft := grid.is_updraft(pos)
			v.y += (600.0 if in_updraft else 1800.0) * sdt
			pos += v * sdt
			var box := Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
			var rects := grid.solid_rects_in(box, false)
			if v.y > 0.0:
				for ow in grid.one_way_rects_in(box):
					if prev.y + radius <= ow.position.y + 0.5:
						rects.append(ow)
			for r in rects:
				var pen: Dictionary = Shapes.circle_intersects_rect(pos, radius, r)
				if not bool(pen["hit"]):
					continue
				var n: Vector2 = pen["normal"]
				pos += n * float(pen["depth"])
				var vn := v.dot(n)
				if vn < 0.0:
					v -= (1.0 + restitution) * vn * n
					var vt := v - v.dot(n) * n
					v = v.dot(n) * n + friction * vt
					contacts += 1
		pts.append(pos)
		t += dt
		if contacts > max_bounces or v.length() < 5.0:
			break
	return pts
