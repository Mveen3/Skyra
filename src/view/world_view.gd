# Implements §9.2 WorldView: the per-match world node tree (sky, parallax, map, pickups,
# characters, projectiles, FX, camera). Views read the Sim and interpolate between
# ticks; they never mutate it (§9.3). Without a Sim it renders the attract-mode map
# behind the preset menu (§8.2 background).
class_name WorldView
extends Node2D

var sim: MatchSim = null
var grid: TileGrid = null

var sky: SkyBackground
var parallax: ParallaxLayers
var backdrop_root: Node2D
var tiles_root: Node2D
var decor: DecorRenderer
var pickups: PickupView
var characters_root: Node2D
var projectiles: ProjectileView
var beams: BeamView
var fx: FxManager
var foreground: Node2D
var camera: GameCamera

var character_views: Dictionary = {} # id -> CharacterView

var _attract_t: float = 0.0
## Scripted camera (`--bench` sweep): when valid it is called as (camera, delta) instead
## of the follow camera, before culling and parallax read the camera.
var camera_driver: Callable = Callable()

func setup(p_sim: MatchSim, p_grid: TileGrid) -> void:
	sim = p_sim
	grid = p_grid

	sky = SkyBackground.new()
	add_child(sky)

	parallax = ParallaxLayers.new()
	parallax.z_index = C.Z_FAR_ISLANDS
	add_child(parallax)

	backdrop_root = Node2D.new()
	backdrop_root.name = "MapBackdrop"
	backdrop_root.z_index = C.Z_MAP_BACKDROP
	add_child(backdrop_root)

	tiles_root = Node2D.new()
	tiles_root.name = "MapTiles"
	tiles_root.z_index = C.Z_MAP_TILES
	add_child(tiles_root)

	for r0 in range(0, grid.height, MapChunk.CHUNK):
		for c0 in range(0, grid.width, MapChunk.CHUNK):
			var bd := MapChunk.new()
			bd.setup(grid, c0, r0, true)
			backdrop_root.add_child(bd)
			var tc := MapChunk.new()
			tc.setup(grid, c0, r0, false)
			tiles_root.add_child(tc)
	var updraft := UpdraftOverlay.new()
	updraft.name = "UpdraftOverlay"
	updraft.setup(grid)
	backdrop_root.add_child(updraft)

	decor = DecorRenderer.new()
	decor.setup(grid)
	add_child(decor)

	pickups = PickupView.new()
	pickups.z_index = C.Z_PICKUPS
	add_child(pickups)

	characters_root = Node2D.new()
	characters_root.name = "Characters"
	characters_root.z_index = C.Z_CHARACTERS
	add_child(characters_root)

	projectiles = ProjectileView.new()
	projectiles.z_index = C.Z_PROJECTILES
	add_child(projectiles)

	beams = BeamView.new()
	beams.z_index = C.Z_PROJECTILES + 1
	add_child(beams)

	fx = FxManager.new()
	fx.z_index = C.Z_FX
	add_child(fx)

	foreground = Node2D.new()
	foreground.name = "Foreground"
	foreground.z_index = C.Z_FOREGROUND
	add_child(foreground)

	camera = GameCamera.new()
	add_child(camera)

	if sim:
		pickups.setup(sim)
		projectiles.setup(sim)
		beams.setup(sim)
		fx.bind_sim(sim)
		camera.bind_sim(sim)
		# Bots first, Skyra drawn on top (§7.3 layer table)
		for c in sim.bot_chars:
			_add_character_view(c)
		_add_character_view(sim.human_char)
		camera.snap_to(sim.human_char.pos, 1.0)
	else:
		camera.snap_to(Vector2(3840.0, 1100.0), 2.0)

func _ready() -> void:
	camera.make_current()

func _add_character_view(c: CharacterState) -> void:
	var v := CharacterView.new()
	v.setup(c, sim)
	characters_root.add_child(v)
	character_views[c.id] = v

## Interpolation fraction between the previous and the current Sim tick.
static func alpha() -> float:
	return Engine.get_physics_interpolation_fraction()

func human_render_pos() -> Vector2:
	if sim == null:
		return Vector2.ZERO
	var h := sim.human_char
	if h.life_state != Enums.LifeState.ALIVE:
		return h.death_pos
	return h.prev_pos.lerp(h.pos, alpha())

func _process(delta: float) -> void:
	if sim == null:
		_update_attract(delta)
		return
	if camera_driver.is_valid():
		camera_driver.call(camera, delta)
	else:
		var mouse := get_viewport().get_mouse_position()
		camera.update_camera(delta, sim.human_char, mouse, human_render_pos())
	sim.human_view_rect = camera.view_rect_world()
	parallax.update_from_camera(camera.get_screen_center_position())
	Audio.set_listener_pos(human_render_pos())

## Attract mode behind the preset menu: the camera pans slowly between the Beacon Crown
## and the hangars at 40 wu/s (§8.2).
func _update_attract(delta: float) -> void:
	_attract_t += delta
	var a := Vector2(3840.0, 900.0)
	var b := Vector2(2600.0, 1500.0)
	var span := a.distance_to(b) / 40.0
	var k := 0.5 - 0.5 * cos(TAU * _attract_t / (span * 2.0))
	camera.global_position = a.lerp(b, k)
	camera.zoom = Vector2(0.62, 0.62)
	parallax.update_from_camera(camera.global_position)
