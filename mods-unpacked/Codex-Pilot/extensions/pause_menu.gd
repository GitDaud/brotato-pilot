extends "res://ui/menus/ingame/pause_menu.gd"

func on_game_lost_focus() -> void:
	var pilot = get_node_or_null("/root/ModLoader/Codex-Pilot")
	if pilot != null and pilot.enabled and not pilot.finished:
		return
	.on_game_lost_focus()
