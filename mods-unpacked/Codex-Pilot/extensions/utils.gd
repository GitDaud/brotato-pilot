extends "res://singletons/utils.gd"

# Raising physics frequency for accelerated development must not also multiply
# cooldowns expressed in native ticks (pets and enemy initial attack delays).
func physics_one(delta: float) -> float:
	var pilot = get_node_or_null("/root/ModLoader/Codex-Pilot")
	if pilot != null and pilot.development_speed > 1:
		return pilot.normal_physics_hz * delta
	return .physics_one(delta)
