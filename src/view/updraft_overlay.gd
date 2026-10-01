# Implements the §7.3.2 updraft shaft overlay: each column's UPDRAFT cells are merged into
# vertical runs and drawn once with updraft.gdshader; only the `time` uniform changes per
# frame (it stops while the game is paused, like the rest of the world view).
class_name UpdraftOverlay
extends Node2D

const SHADER := preload("res://src/view/shaders/updraft.gdshader")

var _runs: Array[Rect2] = []
var _mat: ShaderMaterial
var _t: float = 0.0

func setup(grid: TileGrid) -> void:
	var ts := float(grid.tile_size)
	for c in range(grid.width):
		var start := -1
		for r in range(grid.height + 1):
			var up := r < grid.height and grid.tile_at(c, r) == Enums.Tile.UPDRAFT
			if up and start < 0:
				start = r
			elif not up and start >= 0:
				_runs.append(Rect2(c * ts, start * ts, ts, (r - start) * ts))
				start = -1
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat

func _process(delta: float) -> void:
	_t = fmod(_t + delta, 1000.0)
	_mat.set_shader_parameter(&"time", _t)

func _draw() -> void:
	for r in _runs:
		draw_rect(r, Color.WHITE)
