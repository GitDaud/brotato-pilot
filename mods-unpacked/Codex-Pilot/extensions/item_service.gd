extends "res://singletons/item_service.gd"

func get_player_shop_items(wave: int, player_index: int, args: ItemServiceGetShopItemsArgs) -> Array:
	var pilot = get_node_or_null("/root/ModLoader/Codex-Pilot")
	if pilot != null:
		pilot.seeded.next_scope("shop",wave,player_index)
	return .get_player_shop_items(wave,player_index,args)

func get_upgrades(level: int, number: int, old_upgrades: Array, player_index: int) -> Array:
	var pilot = get_node_or_null("/root/ModLoader/Codex-Pilot")
	if pilot != null:
		pilot.seeded.next_scope("upgrade/" + str(level),RunData.current_wave,player_index)
	return .get_upgrades(level,number,old_upgrades,player_index)

func process_item_box(consumable_data: ConsumableData, wave: int, player_index: int) -> ItemParentData:
	var pilot = get_node_or_null("/root/ModLoader/Codex-Pilot")
	if pilot != null:
		pilot.seeded.next_scope("crate",wave,player_index)
	return .process_item_box(consumable_data,wave,player_index)
