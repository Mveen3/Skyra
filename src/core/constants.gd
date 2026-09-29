# Implements §9.1 and §7.3 Constants and layer indices.
class_name C
extends RefCounted

const VERSION: String = "1.0.0"

const TILE_SIZE: int = 64
const MAP_TILES_W: int = 120
const MAP_TILES_H: int = 60
const MAP_WIDTH_WU: float = 7680.0
const MAP_HEIGHT_WU: float = 3840.0

# Raycast Masks
const MASK_SOLIDS: int = 1
const MASK_ONE_WAY: int = 2
const MASK_PROJECTILE: int = 1
const MASK_LOS: int = 1
const MASK_GRENADE: int = 3
const MASK_LASER: int = 1

# CanvasLayers
const LAYER_SKY: int = -10
const LAYER_SCREEN_FX: int = 5
const LAYER_HUD: int = 10
const LAYER_MENUS: int = 20
const LAYER_DEBUG: int = 30

# Node2D Z-indices
const Z_FAR_ISLANDS: int = -90
const Z_CLOUDS_FAR: int = -80
const Z_CLOUDS_NEAR: int = -70
const Z_MAP_BACKDROP: int = -40
const Z_MAP_TILES: int = -20
const Z_DECALS: int = -15
const Z_PICKUPS: int = 0
const Z_CHARACTERS: int = 10
const Z_PROJECTILES: int = 20
const Z_FX: int = 30
const Z_FOREGROUND: int = 40

# File Paths
const PATH_TUNING: String = "res://data/tuning.json"
const PATH_WEAPONS: String = "res://data/weapons.json"
const PATH_MODES: String = "res://data/modes.json"
const PATH_BOTS: String = "res://data/bots.json"
const PATH_DEFAULT_BINDINGS: String = "res://data/input/default_bindings.json"
const PATH_MAP_OUTPOST: String = "res://data/maps/outpost_skyra.json"
const PATH_WEAPONS_ART: String = "res://data/art/weapons_art.json"
const PATH_CHARACTERS_ART: String = "res://data/art/characters_art.json"
const PATH_PARTICLE_PRESETS: String = "res://data/fx/particle_presets.json"
const PATH_AUDIO_CUES: String = "res://data/audio/cues.json"
