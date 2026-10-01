# Implements §7.2 colour tokens (environment + UI palettes) shared by every view.
class_name Palette
extends RefCounted

# Environment
const SKY_TOP := Color("#0E1B4D")
const SKY_MID := Color("#3A4FA3")
const SKY_HORIZON := Color("#F29E6D")
const SKY_BOTTOM := Color("#FFD1A1")
const SUN := Color("#FFE3A3")
const CLOUD_LIGHT := Color("#F6C9B8")
const CLOUD_SHADE := Color("#C98FA6")
const FAR_ISLAND := Color("#2B3A78")
const ROCK := Color("#3B3A5A")
const ROCK_HI := Color("#4E4C74")
const ROCK_SHADE := Color("#2A2942")
const ROCK_SPECK := Color("#34334F")
const MOSS := Color("#5ED1A8")
const MOSS_HI := Color("#7FE5C0")
const METAL := Color("#5C6B7A")
const METAL_HI := Color("#8FA3B5")
const METAL_SHADE := Color("#36414D")
const METAL_WEST_ACCENT := Color("#B5562B")
const METAL_EAST_ACCENT := Color("#2F7FA8")
const CRATE := Color("#C0843D")
const CRATE_LINE := Color("#8A5A24")
const CRATE_EDGE := Color("#6B4418")
const SANDBAG := Color("#B9A77A")
const SANDBAG_SEAM := Color("#8C7D57")
const GRATE := Color("#9AA7B4")
const GRATE_LINE := Color("#6B7682")
const INTERIOR_BG := Color("#1E2233")
const INTERIOR_GRID := Color("#262B40")
const UPDRAFT_STREAK := Color(0.561, 0.890, 1.0, 0.25) # #8FE3FF α 0.25
const HAZARD_YELLOW := Color("#FFD23F")
const HAZARD_BLACK := Color("#14161C")
const LAMP_WEST := Color("#FFB45E")
const LAMP_EAST := Color("#6FE7FF")
const REACTOR := Color("#7CFF6B")
const FURNACE := Color("#FF7A1A")
const OUTLINE := Color("#14161C")

# UI
const UI_BG := Color(0.043, 0.063, 0.125, 0.80) # #0B1020 α 0.80
const UI_PANEL := Color("#141B34")
const UI_STROKE := Color("#2E3A6B")
const UI_ACCENT := Color("#39E6FF")
const UI_ACCENT2 := Color("#FFC53D")
const UI_DANGER := Color("#FF4D6D")
const UI_OK := Color("#5EE38A")
const UI_TEXT := Color("#EAF2FF")
const UI_SUBTEXT := Color("#9FB0D9")

# Skyra (§5.1)
const SKYRA_ARMOUR := Color("#F4F7FB")
const SKYRA_TRIM := Color("#FFC53D")
const SKYRA_VISOR := Color("#39E6FF")
const SKYRA_SCARF := Color("#FF4D6D")

## Soft radial glow (smooth falloff) instead of a hard-edged translucent disc (§7.2 glows).
static func draw_glow(ci: CanvasItem, center: Vector2, radius: float, col: Color) -> void:
	ci.draw_texture_rect(FxManager.soft_texture(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, col)

static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

## Deterministic per-cell hash in [0, 1) for decoration placement.
static func hash01(x: int, y: int, salt: int = 0) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0
