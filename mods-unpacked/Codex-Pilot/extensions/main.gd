extends "res://main.gd"

func _enter_tree() -> void:
	var pilot = get_node_or_null("/root/ModLoader/Codex-Pilot")
	if pilot != null:
		pilot.seeded.wave_start()

func _handle_manual_aim_visuals() -> void:
	var pilot = get_node_or_null("/root/ModLoader/Codex-Pilot")
	if pilot != null and pilot.enabled:
		_crosshair.hide()
		return
	._handle_manual_aim_visuals()
