extends "res://entities/units/player/player.gd"

var pilot_heal_source = "other"

func on_health_regen(loop_count: int) -> void:
	var prior = pilot_heal_source
	pilot_heal_source = "regeneration"
	.on_health_regen(loop_count)
	pilot_heal_source = prior

func on_lifesteal_effect(value: int) -> void:
	var prior = pilot_heal_source
	pilot_heal_source = "lifesteal"
	.on_lifesteal_effect(value)
	pilot_heal_source = prior

func on_healing_effect(value: int, tracking_key: int = Keys.empty_hash, from_torture: bool = false) -> int:
	var actual = .on_healing_effect(value,tracking_key,from_torture)
	var pilot = get_node_or_null("/root/ModLoader/Codex-Pilot")
	if pilot != null and pilot.enabled and player_index == 0:
		var source = pilot_heal_source
		if tracking_key != Keys.empty_hash:
			source = str(Keys.hash_to_string.get(tracking_key,tracking_key))
		pilot.observe_healing(source,value,actual)
	return actual
