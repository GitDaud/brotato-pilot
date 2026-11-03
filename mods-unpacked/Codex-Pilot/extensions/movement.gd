extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"

func get_movement() -> Vector2:
	var pilot = get_node_or_null("/root/ModLoader/Codex-Pilot")
	if pilot != null and pilot.enabled:
		return pilot.steer(_parent)
	return .get_movement()
