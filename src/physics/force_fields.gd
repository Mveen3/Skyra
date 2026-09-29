# Implements §3.6 ForceFields (gravity and updraft forces).
class_name ForceFields
extends RefCounted

const DEFAULT_GRAVITY: float = 1800.0
const UPDRAFT_LIFT_CHARACTER: float = 2100.0
const UPDRAFT_LIFT_ITEM: float = 1200.0
const UPDRAFT_LIFT_FLAME: float = 600.0

static func get_character_ay(c, in_updraft: bool, diving: bool, jet_active: bool, thrust: float, boost_thrust: float = 1.0) -> float:
	var g := DEFAULT_GRAVITY * (1.4 if diving else 1.0)
	var ay := g
	if in_updraft and not diving:
		ay -= UPDRAFT_LIFT_CHARACTER
	if jet_active:
		ay -= thrust * boost_thrust
	return ay

static func get_character_rise_cap(in_updraft: bool, diving: bool, jet_active: bool, max_rise: float, boost_rise: float = 1.0) -> float:
	var cap := max_rise * boost_rise
	if in_updraft and not diving:
		cap = (680.0 * boost_rise) if jet_active else 380.0
	return cap
