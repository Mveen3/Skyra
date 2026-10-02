# Implements §7.5 weapon art: draws the weapon DSL from data/art/weapons_art.json
# (rect / poly / circle / line / polyline / arc in weapon-local wu, origin = grip,
# +x toward the muzzle). An outline pass (dark, thick) is drawn under the fills so every
# weapon gets the 2.5-wu silhouette outline. Tagged parts animate through `anim`.
class_name WeaponPainter
extends RefCounted

const OUTLINE_W: float = 2.5

class Prim:
	var type: String
	var tag: String = ""
	var fill: Color = Color.TRANSPARENT
	var has_fill: bool = false
	var stroke: Color = Color.TRANSPARENT
	var has_stroke: bool = false
	var width: float = 1.0
	var pts: PackedVector2Array = PackedVector2Array() # polygon / polyline / arc points
	var center: Vector2 = Vector2.ZERO
	var radius: float = 0.0
	var detail: bool = false # fine detail: no thick outline, no auto-shading

static var _cache: Dictionary = {} # weapon id -> Array[Prim]
static var _bounds: Dictionary = {} # weapon id -> Rect2

static func _color(hex: String, alpha: float) -> Color:
	var c := Color.from_string(hex, Color.MAGENTA)
	c.a *= alpha
	return c

static func _rounded_rect(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	r = minf(r, minf(w, h) * 0.5)
	if r <= 0.01:
		return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])
	var corners := [Vector2(x + w - r, y + r), Vector2(x + w - r, y + h - r), Vector2(x + r, y + h - r), Vector2(x + r, y + r)]
	var start_angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for i in range(4):
		for k in range(5):
			var a: float = start_angles[i] + (PI * 0.5) * float(k) / 4.0
			pts.append(corners[i] + Vector2(cos(a), sin(a)) * r)
	return pts

static func _circle_pts(c: Vector2, r: float, n: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

static func prims(weapon_id: StringName) -> Array:
	var key := str(weapon_id)
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var art: Dictionary = Data.weapon_art.get(key, {})
	var bounds := Rect2()
	var first := true
	for d: Dictionary in art.get("primitives", []):
		var p := Prim.new()
		p.type = str(d.get("type", ""))
		p.tag = str(d.get("tag", ""))
		p.detail = bool(d.get("detail", false))
		var alpha := float(d.get("alpha", 1.0))
		if d.has("fill"):
			p.fill = _color(str(d["fill"]), alpha)
			p.has_fill = true
		if d.has("stroke"):
			p.stroke = _color(str(d["stroke"]), alpha)
			p.has_stroke = true
		p.width = float(d.get("w", 1.0))
		match p.type:
			"rect":
				p.pts = _rounded_rect(float(d["x"]), float(d["y"]), float(d["w"]), float(d["h"]), float(d.get("r", 0.0)))
				p.width = 1.0
			"poly":
				for q in d["pts"]:
					p.pts.append(_v(q))
			"circle":
				p.center = _v(d["c"])
				p.radius = float(d["r"])
				p.pts = _circle_pts(p.center, p.radius)
			"line":
				p.pts = PackedVector2Array([_v(d["a"]), _v(d["b"])])
			"polyline":
				for q in d["pts"]:
					p.pts.append(_v(q))
			"arc":
				p.center = _v(d["c"])
				p.radius = float(d["r"])
				var a0 := deg_to_rad(float(d["from_deg"]))
				var a1 := deg_to_rad(float(d["to_deg"]))
				for i in range(13):
					var a := lerpf(a0, a1, float(i) / 12.0)
					p.pts.append(p.center + Vector2(cos(a), sin(a)) * p.radius)
		for q in p.pts:
			if first:
				bounds = Rect2(q, Vector2.ZERO)
				first = false
			else:
				bounds = bounds.expand(q)
		out.append(p)
	_cache[key] = out
	_bounds[key] = bounds.grow(OUTLINE_W)
	return out

static func bounds(weapon_id: StringName) -> Rect2:
	prims(weapon_id)
	return _bounds.get(str(weapon_id), Rect2(-10, -10, 20, 20))

## Local transform of a tagged part for the current animation state.
static func _tag_xform(p: Prim, anim: Dictionary) -> Transform2D:
	match p.tag:
		"pump":
			return Transform2D(0.0, Vector2(float(anim.get("pump_offset", 0.0)), 0.0))
		"mag":
			var drop: Vector2 = anim.get("mag_offset", Vector2.ZERO)
			return Transform2D(0.0, drop)
		"disk":
			var a := float(anim.get("disk_angle", 0.0))
			var c := Vector2(46.0, -10.0)
			return Transform2D(a, c) * Transform2D(0.0, -c)
	return Transform2D.IDENTITY

static func _tag_visible(p: Prim, anim: Dictionary) -> bool:
	match p.tag:
		"mag": return bool(anim.get("mag_visible", true))
		"warhead": return bool(anim.get("warhead_visible", true))
		"pin": return bool(anim.get("pin_visible", true))
		"pilot": return bool(anim.get("pilot_visible", true))
	return true

static func _tag_color(p: Prim, base: Color, anim: Dictionary) -> Color:
	match p.tag:
		"coils":
			return Color(base, base.a * float(anim.get("coils_alpha", 1.0)))
		"led":
			return base if bool(anim.get("led_on", true)) else base.darkened(0.7)
	return base

## Draws `weapon_id` with transform `xf` (weapon-local -> canvas-local) from cached
## textures: the untagged art is one sprite, each animated tag group another (§7.5).
## `tint` multiplies every colour; `silhouette` falls back to the vector painter.
static func draw(canvas: CanvasItem, weapon_id: StringName, xf: Transform2D, anim: Dictionary = {},
		tint: Color = Color.WHITE, silhouette: bool = false, _outline: bool = true) -> void:
	if silhouette:
		draw_vector(canvas, weapon_id, xf, anim, tint, true)
		return
	var groups := textures(weapon_id)
	for key in groups:
		var g: Dictionary = groups[key]
		var tag: String = g.tag
		if not _group_visible(tag, anim):
			continue
		var col := tint
		match tag:
			"coils":
				col.a *= float(anim.get("coils_alpha", 1.0))
			"led":
				if not bool(anim.get("led_on", true)):
					col = Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, col.a)
		var part_xf := xf * _group_xform(tag, anim)
		if tag == "pilot":
			var sc := float(anim.get("pilot_scale", 1.0))
			var c := Vector2(74.0, -10.0)
			part_xf = part_xf * Transform2D(0.0, Vector2(sc, sc), 0.0, c - c * sc)
		canvas.draw_set_transform_matrix(part_xf)
		canvas.draw_texture_rect(g.tex, g.rect, false, col)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

static func _group_visible(tag: String, anim: Dictionary) -> bool:
	match tag:
		"mag": return bool(anim.get("mag_visible", true))
		"warhead": return bool(anim.get("warhead_visible", true))
		"pin": return bool(anim.get("pin_visible", true))
		"pilot": return bool(anim.get("pilot_visible", true))
	return true

static func _group_xform(tag: String, anim: Dictionary) -> Transform2D:
	match tag:
		"pump":
			return Transform2D(0.0, Vector2(float(anim.get("pump_offset", 0.0)), 0.0))
		"mag":
			var drop: Vector2 = anim.get("mag_offset", Vector2.ZERO)
			return Transform2D(0.0, drop)
		"disk":
			var a := float(anim.get("disk_angle", 0.0))
			var c := Vector2(46.0, -10.0)
			return Transform2D(a, c) * Transform2D(0.0, -c)
	return Transform2D.IDENTITY

# ── SVG rasterization (§7.4 raster scale, mipmapped) ─────────────────────────────

static var _tex_cache: Dictionary = {} # weapon id -> {group key -> {tag, tex, rect}}

static func raster_scale() -> float:
	var h := 1080.0
	if DisplayServer.get_name() != "headless":
		h = float(DisplayServer.screen_get_size().y)
	return clampf(ceilf(2.0 * h / 1080.0), 2.0, 4.0)

## Cached textures for every part group of a weapon ("" = untagged base art).
static func textures(weapon_id: StringName) -> Dictionary:
	var key := str(weapon_id)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var groups := {}
	var order: Array[String] = [""]
	for p: Prim in prims(weapon_id):
		if not order.has(p.tag):
			order.append(p.tag)
	var scale := raster_scale()
	for tag in order:
		var list: Array = prims(weapon_id).filter(func(p: Prim) -> bool: return p.tag == tag)
		if list.is_empty():
			continue
		var r := _group_bounds(list)
		r.size = Vector2(ceilf(r.size.x * scale), ceilf(r.size.y * scale)) / scale
		var svg := _svg(list, r, scale)
		var img := Image.new()
		if img.load_svg_from_string(svg, 1.0) != OK or img.is_empty():
			continue
		img.generate_mipmaps()
		groups[tag if tag != "" else "_base"] = {"tag": tag, "tex": ImageTexture.create_from_image(img), "rect": r}
	_tex_cache[key] = groups
	return groups

static func _group_bounds(list: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for p: Prim in list:
		var pts := p.pts
		if p.tag == "disk" and p.radius >= 10.0:
			pts = _circle_pts(p.center, p.radius + 4.0)
		for q in pts:
			if first:
				r = Rect2(q, Vector2.ZERO)
				first = false
			else:
				r = r.expand(q)
	var margin := OUTLINE_W + 2.0
	for p: Prim in list:
		if p.type in ["line", "polyline", "arc"]:
			margin = maxf(margin, p.width * 0.5 + OUTLINE_W + 2.0)
	return r.grow(margin)

static func _pts_bounds(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	return r

static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)

static func _pts_attr(pts: PackedVector2Array) -> String:
	var parts := PackedStringArray()
	for q in pts:
		parts.append("%.2f,%.2f" % [q.x, q.y])
	return " ".join(parts)

static func _svg(list: Array, r: Rect2, scale: float) -> String:
	var w := int(round(r.size.x * scale))
	var h := int(round(r.size.y * scale))
	var out := PackedStringArray()
	out.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%.3f %.3f %.3f %.3f">' % [w, h, r.position.x, r.position.y, float(w) / scale, float(h) / scale])
	var oc := _hex(Palette.OUTLINE)
	# Outline pass: every filled shape stroked 2 x 2.5 wu underneath, thick strokes widened
	for p: Prim in list:
		if p.detail:
			continue
		match p.type:
			"rect", "poly", "circle":
				if p.has_fill:
					out.append('<polygon points="%s" fill="%s" stroke="%s" stroke-width="%.2f" stroke-linejoin="round"/>' % [_pts_attr(p.pts), oc, oc, OUTLINE_W * 2.0])
			"line", "polyline", "arc":
				if p.width >= 2.0:
					out.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="%.2f" stroke-linecap="round" stroke-linejoin="round"/>' % [_pts_attr(p.pts), oc, p.width + OUTLINE_W * 2.0])
		if p.tag == "disk" and p.radius >= 10.0 and p.has_fill:
			out.append('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/>' % [p.center.x, p.center.y, p.radius + 3.0 + OUTLINE_W, oc])
	# Fill pass. Solid shapes get a top-lit gradient (bright top edge, shadowed
	# underside) and a thin specular line, so metal, wood and polymer read as 3-D.
	var gi := 0
	for p: Prim in list:
		match p.type:
			"rect", "poly", "circle":
				var fill_attr := 'fill="%s" fill-opacity="%.3f"' % [_hex(p.fill), p.fill.a] if p.has_fill else 'fill="none"'
				var bb := _pts_bounds(p.pts)
				if not p.detail and p.has_fill and p.fill.a > 0.6 and bb.size.y >= 2.5 and bb.size.x >= 2.5:
					gi += 1
					var gid := "g%d" % gi
					var top := p.fill.lightened(0.38)
					var mid := p.fill
					var low := p.fill.darkened(0.42)
					out.append('<defs><linearGradient id="%s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="0.22" stop-color="%s"/><stop offset="0.55" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>' % [gid, _hex(top), _hex(p.fill.lightened(0.12)), _hex(mid), _hex(low)])
					fill_attr = 'fill="url(#%s)" fill-opacity="%.3f"' % [gid, p.fill.a]
				var stroke_attr := ' stroke="%s" stroke-opacity="%.3f" stroke-width="%.2f"' % [_hex(p.stroke), p.stroke.a, p.width] if p.has_stroke else ""
				out.append('<polygon points="%s" %s%s/>' % [_pts_attr(p.pts), fill_attr, stroke_attr])
				if not p.detail and p.has_fill and p.fill.a > 0.6 and bb.size.x >= 8.0 and bb.size.y >= 4.0:
					# specular glint along the upper edge
					var y := bb.position.y + minf(1.6, bb.size.y * 0.2)
					out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#FFFFFF" stroke-opacity="0.32" stroke-width="0.9" stroke-linecap="round"/>' % [bb.position.x + bb.size.x * 0.12, y, bb.position.x + bb.size.x * 0.82, y])
			"line", "polyline", "arc":
				out.append('<polyline points="%s" fill="none" stroke="%s" stroke-opacity="%.3f" stroke-width="%.2f" stroke-linecap="round" stroke-linejoin="round"/>' % [_pts_attr(p.pts), _hex(p.stroke), p.stroke.a, p.width])
		if p.tag == "disk" and p.radius >= 10.0 and p.has_fill:
			for i in range(10):
				var a := TAU * float(i) / 10.0
				var tri := PackedVector2Array([p.center + Vector2(cos(a), sin(a)) * (p.radius - 0.5),
					p.center + Vector2(cos(a + TAU / 20.0), sin(a + TAU / 20.0)) * (p.radius + 3.0),
					p.center + Vector2(cos(a + TAU / 10.0), sin(a + TAU / 10.0)) * (p.radius - 0.5)])
				out.append('<polygon points="%s" fill="%s"/>' % [_pts_attr(tri), _hex(p.fill)])
		if p.tag == "pilot":
			out.append('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="#FF9F1C" fill-opacity="0.3"/>' % [p.center.x, p.center.y, p.radius * 1.8])
	out.append("</svg>")
	return "\n".join(out)

## Vector path (per-frame primitives); used for white silhouettes.
static func draw_vector(canvas: CanvasItem, weapon_id: StringName, xf: Transform2D, anim: Dictionary = {},
		tint: Color = Color.WHITE, silhouette: bool = false, outline: bool = true) -> void:
	var list := prims(weapon_id)
	var outline_col := Color(Palette.OUTLINE, tint.a)
	# Outline pass (under everything)
	if outline:
		for p: Prim in list:
			if p.detail or not _tag_visible(p, anim):
				continue
			canvas.draw_set_transform_matrix(xf * _tag_xform(p, anim))
			_draw_outline(canvas, p, outline_col)
	# Fill / stroke pass
	for p: Prim in list:
		if not _tag_visible(p, anim):
			continue
		canvas.draw_set_transform_matrix(xf * _tag_xform(p, anim))
		var fill := Color(1, 1, 1, p.fill.a) if silhouette else _tag_color(p, p.fill, anim)
		var stroke := Color(1, 1, 1, p.stroke.a) if silhouette else _tag_color(p, p.stroke, anim)
		fill *= tint
		stroke *= tint
		match p.type:
			"rect", "poly", "circle":
				if p.has_fill:
					canvas.draw_colored_polygon(p.pts, fill)
				if p.has_stroke:
					var closed: PackedVector2Array = p.pts.duplicate()
					closed.append(p.pts[0])
					canvas.draw_polyline(closed, stroke, p.width, true)
			"line", "polyline", "arc":
				canvas.draw_polyline(p.pts, stroke, p.width, true)
		if p.tag == "disk" and p.radius >= 10.0 and p.has_fill:
			_draw_saw_teeth(canvas, p.center, p.radius, fill)
		if p.tag == "pilot":
			var s := float(anim.get("pilot_scale", 1.0))
			canvas.draw_circle(p.center, p.radius * 1.8 * s, Color(1.0, 0.62, 0.11, 0.25 * tint.a))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

static func _draw_outline(canvas: CanvasItem, p: Prim, col: Color) -> void:
	match p.type:
		"rect", "poly", "circle":
			if p.has_fill:
				var closed: PackedVector2Array = p.pts.duplicate()
				closed.append(p.pts[0])
				canvas.draw_polyline(closed, col, OUTLINE_W * 2.0, true)
		"line", "polyline", "arc":
			if p.width >= 2.0:
				canvas.draw_polyline(p.pts, col, p.width + OUTLINE_W * 2.0, true)

static func _draw_saw_teeth(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	for i in range(10):
		var a := TAU * float(i) / 10.0
		var a2 := a + TAU / 20.0
		canvas.draw_colored_polygon(PackedVector2Array([
			c + Vector2(cos(a), sin(a)) * (r - 0.5),
			c + Vector2(cos(a2), sin(a2)) * (r + 3.0),
			c + Vector2(cos(a + TAU / 10.0), sin(a + TAU / 10.0)) * (r - 0.5)]), col)

## Draws the weapon scaled to fit `rect` (HUD / kill-feed icons, §7.5).
static func draw_icon(canvas: CanvasItem, weapon_id: StringName, rect: Rect2, tint: Color = Color.WHITE,
		silhouette: bool = false, flip: bool = false) -> void:
	var b := bounds(weapon_id)
	if b.size.x <= 0.0 or b.size.y <= 0.0:
		return
	var s := minf(rect.size.x / b.size.x, rect.size.y / b.size.y)
	var sx := -s if flip else s
	var xf := Transform2D(Vector2(sx, 0.0), Vector2(0.0, s), rect.get_center() - Vector2(b.get_center().x * sx, b.get_center().y * s))
	draw(canvas, weapon_id, xf, {}, tint, silhouette)
