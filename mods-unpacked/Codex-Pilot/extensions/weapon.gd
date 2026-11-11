extends "res://weapons/weapon.gd"

func get_direction_and_calculate_target() -> float:
	var pilot = get_node_or_null("/root/ModLoader/Codex-Pilot")
	if pilot == null or not pilot.enabled or not _parent is Player or _manual_aim:
		return .get_direction_and_calculate_target()
	if pilot.policy.nightmare:
		if pilot.policy.brawler:
			var bosses = []
			for enemy in _targets_in_range:
				if is_instance_valid(enemy) and enemy is Boss and not enemy.dead:
					bosses.append(enemy)
			var boss_target = pilot.priority_target(bosses,global_position,current_stats.min_range,get_max_range())
			if boss_target[0] != null:
				_current_target = boss_target
				pilot.observe_weapon_target(_current_target,weapon_id)
				return (_current_target[0].global_position-global_position).angle()
		return .get_direction_and_calculate_target()
	_current_target = pilot.priority_target(_targets_in_range, global_position, current_stats.min_range, get_max_range(), _parent.global_position, _parent._integrate_forces_velocity)
	if _current_target[0] == null:
		return .get_direction_and_calculate_target()
	pilot.observe_weapon_target(_current_target,weapon_id,pilot.is_emergency_target(_current_target[0],_parent.global_position,_parent._integrate_forces_velocity))
	return (_current_target[0].global_position - global_position).angle()
