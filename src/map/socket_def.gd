# Implements §9.5 SocketDef and §6.6 Sockets.
class_name SocketDef
extends RefCounted

var id: StringName = &""
var type: int = Enums.SocketType.SPAWN
var cell: Vector2i = Vector2i.ZERO
var world: Vector2 = Vector2.ZERO
var pos: Vector2:
	get:
		return world
	set(v):
		world = v
var zone: StringName = &""
var tag: StringName = &""
