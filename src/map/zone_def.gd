# Implements §9.5 ZoneDef and §6.5 Named zones.
class_name ZoneDef
extends RefCounted

var id: StringName = &""
var display_name: String = ""
var rects: Array[Rect2i] = []
var interior: bool = false
var ambience: StringName = &""
