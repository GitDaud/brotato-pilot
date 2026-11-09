extends "res://weapons/weapon.gd"

func get_direction_and_calculate_target() -> float:
	var pilot = get_node_or_null("/root/ModLoader/Codex-Pilot")
	if pilot == null or not pilot.enabled or not _parent is Player or _manual_aim:
		return .get_direction_and_calculate_target()
	_current_target = pilot.priority_target(_targets_in_range, global_position, current_stats.min_range, get_max_range())
	if _current_target[0] == null:
		return .get_direction_and_calculate_target()
	return (_current_target[0].global_position - global_position).angle()
