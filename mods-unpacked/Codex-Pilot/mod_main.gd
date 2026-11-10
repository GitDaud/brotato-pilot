extends Node

var policy = preload("res://mods-unpacked/Codex-Pilot/strategy.gd").new()
var boss_model = preload("res://mods-unpacked/Codex-Pilot/boss_model.gd").new()
var focused_boss_id = 0
var boss_warnings = []
var next_boss_report = 0.0
var orbit_segments_count = 0
var healing_totals = {}
var enabled = true
var development_speed = 1
var normal_physics_hz = 60
var finished = false
var challenge_difficulty = -1
var gun_profile = "smg_shotgun"
var settlement_at = -1.0
var recent_combat = []
var adaptation = {}
var direction = Vector2.RIGHT
var decision = "Starting"
var clock = 0.0
var next_action = 0.0
var next_report = 0.0
var next_preview = 0.0
var last_scene = ""
var scene_age = 0.0
var pending_shop_buy = null
var shop_rolls = 0
var upgrade_roll_wave = -1
var upgrade_rolls = 0
var upgrade_roll_spent = 0
var shop_opening_gold = -1
var shop_reroll_spent = 0
var label
var evidence = "F:/codex-project/tudou/run"
var log_file = File.new()
var cached_frame = -1
var observed_hp = -1
var observed_position = Vector2.ZERO
var next_loot_scan = 0.0
var loot_target = Vector2.ZERO
var has_loot_target = false
var has_healing_target = false
var steer_us = 0
var steer_peak_us = 0
var threat_cells = 0
var slash_zones = 0
var nearby_bosses = 0
var combat_target_id = ""
var next_aim_report = 0.0
var loot_cells = 0
var directions = []
var body_forecasts = {}
var forecast_msec = 0
var forecast_player_position = Vector2.ZERO
var recording_id = ""
var recording_enabled = false
var selected_character = "character_well_rounded"
var selected_weapon = "weapon_smg"
var recording_ended = false
var recording_end_at = -1.0
var recording_label
var previous_wave = -1
var recording_status_at = 0.0

func _init():
	ModLoaderMod.install_script_extension("res://mods-unpacked/Codex-Pilot/extensions/player.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/Codex-Pilot/extensions/utils.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/Codex-Pilot/extensions/weapon.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/Codex-Pilot/extensions/movement.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/Codex-Pilot/extensions/pause_menu.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/Codex-Pilot/extensions/main.gd")

func _ready():
	normal_physics_hz = Engine.iterations_per_second
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--pilot-speed="):
			var requested = int(argument.get_slice("=",1))
			if requested in [1,2,4]:
				development_speed = requested
		if argument == "--pilot-record=1":
			recording_enabled = true
	if "--pilot-profile=brawler" in OS.get_cmdline_args():
		gun_profile = "brawler_fists"
		policy.brawler = true
		selected_character = "character_brawler"
		selected_weapon = "weapon_fist"
	get_viewport().hdr = false
	OS.set_window_size(Vector2(1920,1080))
	var challenge_file = File.new()
	if challenge_file.open(evidence + "/challenge.json", File.READ) == OK:
		var challenge = parse_json(challenge_file.get_as_text())
		challenge_file.close()
		if challenge is Dictionary and challenge.get("enabled", false):
			challenge_difficulty = int(clamp(challenge.get("difficulty", 1), 0, 5))
			selected_character = str(challenge.get("character",selected_character))
			selected_weapon = str(challenge.get("weapon",selected_weapon))
	if selected_character == "character_crazy":
		policy.brawler = true
		gun_profile = "crazy_knives"
	if selected_character == "character_mage":
		gun_profile = "mage_tasers"
	if selected_character == "character_chunky":
		gun_profile = "chunky_shotguns"
	if selected_character == "character_old":
		gun_profile = "old_shotguns"
	policy.character = selected_character
	var settings_file = File.new()
	if settings_file.open(evidence + "/adaptation.json", File.READ) == OK:
		var saved = parse_json(settings_file.get_as_text())
		settings_file.close()
		if saved is Dictionary:
			adaptation = saved
	policy.armor_bias = float(adaptation.get("armor_bias", 1.0))
	InputService.set_process_input(false)
	var cursor_manager = get_node_or_null("/root/CursorManager")
	if cursor_manager != null:
		cursor_manager.set_process(false)
	pause_mode = Node.PAUSE_MODE_PROCESS
	for i in 24:
		directions.append(Vector2.RIGHT.rotated(TAU * i / 24.0))
	var d = Directory.new()
	d.make_dir_recursive(evidence)
	d.make_dir_recursive("F:/codex-project/tudou/recordings")
	log_file.open(evidence + "/events.jsonl", File.WRITE)
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var box = VBoxContainer.new()
	box.rect_position = Vector2(16, 90)
	layer.add_child(box)
	label = Label.new()
	label.add_color_override("font_color", Color(1, 1, 0.4))
	box.add_child(label)
	recording_label = Label.new()
	recording_label.add_color_override("font_color", Color(1, 0.4, 0.4))
	box.add_child(recording_label)
	var button = Button.new()
	button.text = "Codex Pilot ON / OFF"
	button.connect("pressed", self, "toggle")
	box.add_child(button)
	record("loaded", {"version":"0.6.17-dev","profile":gun_profile,"development_speed":development_speed})
	verify_recovery()

func toggle():
	enabled = not enabled
	record("toggle", {"enabled":enabled})

func record(kind, data):
	data["event"] = kind
	data["seconds"] = OS.get_ticks_msec() / 1000.0
	log_file.store_line(JSON.print(data))
	log_file.flush()

func nodes(root):
	var result = [root]
	for child in root.get_children():
		result += nodes(child)
	return result

func _process(delta):
	clock += delta
	var scene = get_tree().current_scene
	if scene == null:
		return
	var speed = development_speed if enabled and not finished and scene.filename == "res://main.tscn" else 1
	Engine.iterations_per_second = normal_physics_hz * speed
	Engine.time_scale = speed
	update_recording(scene)
	var path = scene.filename
	if path != last_scene:
		last_scene = path
		scene_age = 0.0
		shop_rolls = 0
		shop_opening_gold = -1
		shop_reroll_spent = 0
		next_loot_scan = 0.0
		has_loot_target = false
		record("scene", {"path":path,"wave":RunData.current_wave})
	else:
		scene_age += delta
	label.text = "CODEX PILOT | " + ("ON" if enabled else "OFF") + " | Wave " + str(RunData.current_wave) + "\n" + decision
	if clock >= next_report:
		next_report = clock + 1.0
		report(scene)
	if finished:
		decision = "Run complete - controller authorization required"
		return
	if not enabled or scene_age < 1.5 or clock < next_action:
		return
	next_action = clock + 0.7
	if scene is BaseEndRun:
		finished = true
		decision = "VICTORY" if RunData.run_won else "DEFEAT"
		record("settlement", {"won":RunData.run_won,"wave":RunData.current_wave,"difficulty":RunData.current_difficulty})
		save_image("settlement.png")
		settlement_at = clock
		analyze_run()
	elif scene is CharacterSelection:
		if not scene._has_player_selected[0]:
			select_element(scene, selected_character)
	elif scene is WeaponSelection:
		if not scene._has_player_selected[0]:
			select_element(scene, selected_weapon)
	elif scene is DifficultySelection:
		if not scene.difficulty_selected:
			select_element(scene, "difficulty_" + str(challenge_difficulty if challenge_difficulty >= 0 else 0))
	elif scene.filename.ends_with("/shop.tscn"):
		shop(scene)
	elif scene is TitleScreen:
		if not policy.brawler and challenge_difficulty < 0 and ProgressData.saved_run_state.has_run_state and ProgressData.check_dlc_valid_for_saved_run_state():
			decision = "Continue saved run"
			scene._main_menu._on_ContinueButton_pressed()
		else:
			decision = "Start new run"
			scene._main_menu._on_StartButton_pressed()
	elif scene.has_method("_on_StartButton_pressed"):
		decision = "Start new run"
		scene._on_StartButton_pressed()
	else:
		# Wave-end upgrades do not necessarily pause SceneTree.
		if scene.has_node("EntitySpawner"):
			var retry = scene.get("_retry_wave")
			if is_instance_valid(retry) and retry.is_visible_in_tree():
				decision = "Defeated - end run without retry"
				record("defeat", {"wave":RunData.current_wave})
				save_image("defeat.png")
				retry._on_CancelButton_pressed()
				return
			for key in ["_upgrades_ui", "_coop_upgrades_ui"]:
				var upgrades = scene.get(key)
				if is_instance_valid(upgrades) and upgrades.is_visible_in_tree():
					choose_upgrade(upgrades)
					return
			return
		choose_upgrade(scene)

func select_element(scene, preferred):
	var selected = null
	for e in nodes(scene):
		if not e is InventoryElement:
			continue
		if e.is_locked or e.is_random or e.is_special or e.item == null:
			continue
		if selected == null:
			selected = e
		if e.item.my_id == preferred or e.item.my_id.begins_with(preferred + "_") or (scene is DifficultySelection and e.item.value == (challenge_difficulty if challenge_difficulty >= 0 else 0)):
			selected = e
			break
	if scene is CharacterSelection or scene is WeaponSelection or scene is DifficultySelection:
		if selected == null or not (selected.item.my_id == preferred or selected.item.my_id.begins_with(preferred + "_")):
			enabled = false
			decision = "Requested character/weapon/difficulty unavailable"
			record("selection_unavailable", {"id":preferred})
			return
	if selected != null:
		decision = "Select " + selected.item.my_id
		record("select", {"id":selected.item.my_id})
		scene._on_element_pressed(selected, 0)

func stat_snapshot():
	var stats = {}
	stats["stat_elemental_damage"] = Utils.get_stat(Keys.generate_hash("stat_elemental_damage"), 0)
	for key in ["stat_max_hp","stat_armor","stat_melee_damage","stat_ranged_damage","stat_percent_damage","stat_attack_speed","stat_lifesteal","stat_hp_regeneration","stat_speed","stat_dodge","stat_crit_chance","stat_range","stat_harvesting","stat_luck"]:
		stats[key] = Utils.get_capped_stat(Keys.generate_hash(key), 0) if key == "stat_max_hp" else Utils.get_stat(Keys.generate_hash(key), 0)
	stats["trees"] = RunData.get_player_effect(Keys.generate_hash("trees"),0)
	stats["items_price"] = RunData.get_player_effect(Keys.items_price_hash,0)
	stats["harvesting_growth"] = RunData.get_player_effect(Keys.generate_hash("harvesting_growth"),0)
	stats["stat_gains"] = {}
	for key in stats.keys():
		if str(key).begins_with("stat_") and key != "stat_gains":
			stats.stat_gains[key] = RunData.get_stat_gain(Keys.generate_hash(key),0)
	return stats

func observe_healing(source, requested, actual):
	if not healing_totals.has(source):
		healing_totals[source] = {"requested":0,"effective":0,"events":0}
	healing_totals[source].requested += requested
	healing_totals[source].effective += actual
	healing_totals[source].events += 1

func value_item(item, price = 0):
	if policy.forced_low_health_start(item.effects) or policy.unsupported_extra_spawn(item.effects):
		return -1000.0
	var stats = stat_snapshot()
	if item.my_id == "item_handcuffs":
		return -1000.0
	for effect in item.effects:
		if effect.key == "hp_cap":
			return -1000.0
		if effect.value < 0 and policy.breaks_floor(effect.key, effect.value*stats.stat_gains.get(effect.key,1.0), stats, RunData.current_wave):
			return -1000.0
		if effect.key == "stat_armor" and effect.value < 0 and stats.get("stat_armor",0) < max(2, RunData.current_wave * 0.6):
			return -1000.0
	var score = policy.score_effects(item.effects, stats, RunData.current_wave)
	var damage_key = damage_stat()
	var ranged_delta = 0.0
	for effect in item.effects:
		if effect.key == damage_key and effect.custom_key != "temp_stats_while_not_moving":
			ranged_delta += effect.value*stats.stat_gains.get(damage_key,1.0)
	if ranged_delta != 0.0:
		var old_weight = policy.weights(stats,RunData.current_wave)[damage_key]
		if ranged_delta < 0.0:
			old_weight = max(old_weight,4.0 if policy.brawler else 6.0)
		score -= ranged_delta * old_weight
		score += ranged_damage_score(RunData.get_player_weapons(0),stats,ranged_delta)
	var owned_ids = []
	for owned in RunData.get_player_items(0):
		owned_ids.append(owned.my_id)
	score += synergy_bonus(item.my_id, owned_ids)
	score += policy.special_item_score(item.my_id,RunData.current_wave,price,owned_ids.count(item.my_id),max(150.0,shop_opening_gold*0.7),max(0.1,1.0+stats.items_price/100.0))
	# Autonomous survival cannot currently model ongoing self-damage safely.
	if item.my_id in ["item_blood_donation", "item_bloody_hand"]:
		score -= 1000.0
	return score

func synergy_bonus(item_id, owned_ids = []):
	if policy.character == "character_mage":
		if item_id == "item_scared_sausage":
			return 12.0 / (1.0 + owned_ids.count(item_id))
		if item_id == "item_snake":
			return 8.0 / (1.0 + owned_ids.count(item_id))
		return 0.0
	if policy.brawler:
		return 0.0
	# Additional pierces have diminishing benefit; do not pay the same bonus again.
	if item_id == "item_bandana":
		if "item_bandana" in owned_ids:
			return -1000.0
		return 10.0 if "item_sharp_bullet" in owned_ids else 45.0
	if item_id == "item_sharp_bullet":
		return 25.0 if "item_bandana" in owned_ids else 45.0
	if item_id == "item_baby_with_a_beard":
		return 15.0 if item_id in owned_ids else 45.0
	if item_id == "item_ricochet":
		return -1000.0 if gun_profile == "smg_shotgun" else 45.0
	if item_id == "item_pumpkin" and gun_profile == "smg_shotgun":
		return 18.0 / (1 + owned_ids.count(item_id))
	return 0.0

func weapon_value(item, weapons):
	if policy.character in ["character_chunky", "character_old"]:
		return 175.0 + item.tier * 35.0 if item.weapon_id == "weapon_double_barrel_shotgun" else -1.0
	if policy.character == "character_mage":
		return 150.0 + item.tier * 35.0 if item.weapon_id == "weapon_taser" else -1.0
	if policy.brawler:
		var melee_weapon = "weapon_knife" if selected_character == "character_crazy" else "weapon_fist"
		return 150.0 + item.tier * 35.0 if item.weapon_id == melee_weapon else -1.0
	# Ranger starts with a pistol in addition to the selected gun. Permit native
	# pair upgrades of that existing pistol rather than unrelated pistol tiers.
	if policy.character == "character_ranger" and item.weapon_id == "weapon_pistol":
		for owned in weapons:
			if owned.my_id == item.my_id and owned.upgrades_into != null:
				return 150.0 + item.tier * 35.0
		return -1.0
	if policy.character == "character_ranger" and item.weapon_id == "weapon_shredder":
		var support_count = 0
		var support_match = false
		for owned in weapons:
			if owned.weapon_id == "weapon_shredder":
				support_count += 1
				if owned.my_id == item.my_id and item.upgrades_into != null:
					support_match = true
		return 175.0 + item.tier * 35.0 if support_count == 0 or (support_count == 1 and weapons.size() >= 6 and support_match) else -1.0
	if gun_profile == "smg_shotgun":
		var caps = {"weapon_smg":4,"weapon_double_barrel_shotgun":2}
		if not caps.has(item.weapon_id):
			return -1.0
		var count = 0
		var matching = false
		var has_starter_pistol = false
		for owned in weapons:
			if policy.character == "character_ranger" and owned.weapon_id == "weapon_pistol":
				has_starter_pistol = true
			if owned.weapon_id == item.weapon_id:
				count += 1
				if owned.my_id == item.my_id and item.upgrades_into != null:
					matching = true
				# Native combine can upgrade a pair first, then buy another tier.
				# Do not reject the offer before the marginal planner can evaluate it.
				if owned.upgrades_into != null:
					var copies = 0
					for other in weapons:
						if other.my_id == owned.my_id:
							copies += 1
					if copies >= 2:
						matching = true
		# 4+2 is a target composition, not permission to fight with empty slots.
		# Temporary SMGs can be combined normally when a shotgun later appears.
		var temporary_smg = item.weapon_id == "weapon_smg" and (weapons.size() < 6 or has_starter_pistol)
		if count >= caps[item.weapon_id] and not temporary_smg and not (weapons.size() >= 6 and matching):
			return -1.0
		return (175.0 if item.weapon_id == "weapon_double_barrel_shotgun" else 150.0) + item.tier * 35.0

	if item.weapon_id == "weapon_smg":
		return 150.0 + item.tier * 35.0
	if item.weapon_id == "weapon_shredder":
		var count = 0
		for weapon in weapons:
			if weapon.weapon_id == "weapon_shredder":
				count += 1
		if count < 1:
			return 170.0 + item.tier * 30.0
		# A duplicate bought at full capacity upgrades the existing support gun.
		if count == 1 and weapons.size() >= 6:
			for owned in weapons:
				if owned.my_id == item.my_id and item.upgrades_into != null:
					return 150.0 + item.tier * 30.0
		return -1.0
	return -1.0

# Approximate unarmored direct DPS, only for comparing native shop investments.
# Ignores spread, piercing, crit and shared attack speed; not a combat simulator.
func damage_stat():
	if policy.character == "character_mage":
		return "stat_elemental_damage"
	return "stat_melee_damage" if policy.brawler else "stat_ranged_damage"

func base_gun_dps(weapon, ranged_damage):
	var stats = weapon.stats
	var hit = float(stats.damage)
	var damage_key = damage_stat()
	for scaling in stats.scaling_stats:
		if scaling[0] == damage_key or scaling[0] == Keys.generate_hash(damage_key):
			hit += ranged_damage * scaling[1]
	var duration = stats.get_base_cooldown_value(stats,1.0)
	var hits = 1 if policy.brawler else stats.nb_projectiles
	return max(1.0,hit) * hits / max(0.05,duration)

# Normalize direct attack gains to the existing percent-damage utility.
# This is a shop model, not a survival or hit-rate simulation.
func loadout_dps(weapons, ranged):
	var total = 0.0
	for owned in weapons:
		total += base_gun_dps(owned,ranged)
	return total

func ranger_replacement(item, weapons, stats):
	if policy.character != "character_ranger" or weapons.size() != 6 or not item.weapon_id in ["weapon_smg","weapon_double_barrel_shotgun","weapon_shredder"]:
		return null
	var ranged = float(stats.get("stat_ranged_damage",0))
	for owned in weapons:
		# Require a real direct-DPS improvement, not only a fixed support bonus.
		if owned.weapon_id == "weapon_pistol" and base_gun_dps(item,ranged) > base_gun_dps(owned,ranged)*1.25:
			return owned
	return null

func direct_gain_score(gain, baseline, stats):
	return gain / max(0.1,baseline) * max(1.0,100.0+stats.get("stat_percent_damage",0)) * policy.weights(stats,RunData.current_wave).get("stat_percent_damage",0.9)

func ranged_damage_score(weapons, stats, delta):
	var ranged = float(stats.get(damage_stat(),0))
	var baseline = loadout_dps(weapons,ranged)
	if baseline <= 0.0:
		return delta * policy.weights(stats,RunData.current_wave)[damage_stat()]
	return direct_gain_score(loadout_dps(weapons,ranged+delta)-baseline,baseline,stats)

func marginal_weapon_score(item, weapons, stats, wave):
	if weapons.size() < 6:
		return weapon_value(item,weapons)
	var ranged = float(stats.get(damage_stat(),0))
	var direct_merge_gain = -1.0
	for owned in weapons:
		if owned.my_id == item.my_id and owned.upgrades_into != null:
			direct_merge_gain = max(direct_merge_gain,base_gun_dps(owned.upgrades_into,ranged)-base_gun_dps(owned,ranged))
	# A directly buyable duplicate uses native auto-combine; score that action.
	if direct_merge_gain > 0.0:
		return direct_gain_score(direct_merge_gain,loadout_dps(weapons,ranged),stats)
	var gain = -1.0
	var replacement = ranger_replacement(item,weapons,stats)
	if replacement != null:
		gain = base_gun_dps(item,ranged)-base_gun_dps(replacement,ranged)
	for owned in weapons:
		var copies = 0
		for other in weapons:
			if other.my_id == owned.my_id:
				copies += 1
		if copies >= 2 and owned.upgrades_into != null:
			gain = max(gain,base_gun_dps(item,ranged)+base_gun_dps(owned.upgrades_into,ranged)-2*base_gun_dps(owned,ranged))
	if gain <= 0.0:
		return -1.0
	return direct_gain_score(gain,loadout_dps(weapons,ranged),stats)

func choose_upgrade(scene):
	var candidates = []
	var best = null
	var score = -100000.0
	var upgrade_stats = stat_snapshot()
	if upgrade_roll_wave != RunData.current_wave:
		upgrade_roll_wave = RunData.current_wave
		upgrade_rolls = 0
		upgrade_roll_spent = 0
	for n in nodes(scene):
		if n is UpgradeUI and n.is_visible_in_tree() and not n.button.disabled:
			var s = policy.upgrade_score(n.upgrade_data.effects,upgrade_stats,RunData.current_wave,value_item(n.upgrade_data))
			candidates.append({"id":n.upgrade_data.my_id,"score":s})
			if s > score:
				score = s
				best = n
	if best != null:
		if scene.has_method("_get_player_container"):
			var container = scene._get_player_container(0)
			if is_instance_valid(container) and not container._button_pressed and container._reroll_button.is_visible_in_tree() and not container._reroll_button.disabled and policy.reroll_upgrade(best.upgrade_data.effects,upgrade_stats,RunData.current_wave,score,RunData.get_player_currency(0),container._reroll_price,upgrade_rolls,upgrade_roll_spent):
				upgrade_rolls += 1
				upgrade_roll_spent += container._reroll_price
				record("upgrade_reroll",{"wave":RunData.current_wave,"offers":candidates,"rejected_best":best.upgrade_data.my_id,"best_score":score,"cost":container._reroll_price,"rolls":upgrade_rolls})
				decision = "Reroll weak upgrades"
				container._on_RerollButton_pressed()
				return
		record("upgrade_candidates", {"wave":RunData.current_wave,"stats":stat_snapshot(),"offers":candidates,"selected":best.upgrade_data.my_id})
		decision = "Upgrade " + best.upgrade_data.my_id
		record("upgrade", {"id":best.upgrade_data.my_id,"score":score})
		best._on_ChooseButton_pressed()
		return
	for n in nodes(scene):
		if n is UpgradesUIPlayerContainer and n._take_button.is_visible_in_tree() and not n._take_button.disabled:
			if value_item(n._item_data) < 0 and not n._discard_button.disabled:
				decision = "Recycle crate " + n._item_data.my_id
				record("recycle_crate", {"id":n._item_data.my_id})
				n._discard_button.emit_signal("pressed")
			else:
				decision = "Take crate " + n._item_data.my_id
				n._take_button.emit_signal("pressed")
			return

func shop(scene):
	if get_tree().paused:
		decision = "Paused - waiting"
		return
	var best = null
	var best_score = 0.0
	var weapons = RunData.get_player_weapons(0)
	var gold = RunData.get_player_currency(0)
	if shop_opening_gold < 0:
		shop_opening_gold = gold
	var shop_items = scene._get_shop_items_container(0)
	if is_instance_valid(pending_shop_buy):
		var pending = pending_shop_buy
		pending_shop_buy = null
		if pending.active and pending.value <= gold and shop_items._can_weapon_be_bought(pending):
			record("buy", {"id":pending.item_data.my_id,"cost":pending.value,"gold":gold,"reason":"committed_merge_purchase"})
			pending._on_BuyButton_pressed()
			return
		record("merge_commit_cancelled", {"gold":gold})
	var shop_stats = stat_snapshot()
	var offers = []
	for n in shop_items._shop_items:
		if not is_instance_valid(n) or not n.active:
			continue
		var item = n.item_data
		if n._button.disabled or n.value > gold:
			record("shop_rejected", {"wave":RunData.current_wave,"id":item.my_id,"cost":n.value,"gold":gold,"reason":"disabled" if n._button.disabled else "unaffordable"})
			continue
		var score = value_item(item,n.value)
		if item is WeaponData:
			score = weapon_value(item, weapons)
			if score <= 0:
				record("shop_rejected", {"wave":RunData.current_wave,"id":item.my_id,"cost":n.value,"gold":gold,"score":score,"reason":"profile"})
				continue
			score = marginal_weapon_score(item,weapons,shop_stats,RunData.current_wave)
			if not policy.weapon_purchase_worthwhile(score,n.value,RunData.current_wave):
				record("shop_rejected", {"wave":RunData.current_wave,"id":item.my_id,"cost":n.value,"gold":gold,"score":score,"reason":"weapon_value_threshold"})
				continue
			if not shop_items._can_weapon_be_bought(n):
				var can_make_slot = ranger_replacement(item,weapons,shop_stats) != null and not RunData.get_player_effect_bool(Keys.lock_current_weapons_hash,0)
				if weapons.size() >= 6 and not RunData.has_weapon_slot_available(item,0):
					for owned in weapons:
						if RunData.can_combine(owned,0):
							can_make_slot = true
				if not can_make_slot:
					continue
		else:
			if not policy.purchase_worthwhile(score,n.value):
				record("shop_rejected", {"wave":RunData.current_wave,"id":item.my_id,"cost":n.value,"gold":gold,"score":score,"reason":"item_value_threshold"})
				continue
			if weapons.size() < 4 and score < 20.0:
				continue
		offers.append({"id":item.my_id,"cost":n.value,"score":score})
		# Prefer value per material rather than any tiny positive raw score.
		score /= float(n.value + 15)
		if score > best_score:
			best_score = score
			best = n
	record("shop_candidates", {"wave":RunData.current_wave,"gold":gold,"offers":offers,"stats":shop_stats})
	if best != null:
		if best.item_data is WeaponData and not shop_items._can_weapon_be_bought(best):
			var merge_weapon = null
			var merge_gain = -INF
			for owned in weapons:
				if RunData.can_combine(owned,0):
					var gain = base_gun_dps(owned.upgrades_into,shop_stats.get(damage_stat(),0))-2*base_gun_dps(owned,shop_stats.get(damage_stat(),0))
					if gain > merge_gain:
						merge_gain = gain
						merge_weapon = owned
			var replacement = ranger_replacement(best.item_data,weapons,shop_stats)
			if replacement != null and -base_gun_dps(replacement,shop_stats.get("stat_ranged_damage",0)) >= merge_gain and not RunData.get_player_effect_bool(Keys.lock_current_weapons_hash,0):
				var planned_id = best.item_data.my_id
				record("replace_weapon",{"sold":replacement.my_id,"planned_buy":planned_id,"cost":best.value,"gold":gold})
				scene._on_item_discard_button_pressed(replacement,0)
				# Native recycling refreshes the shop controls. Reacquire the offer.
				for offer in scene._get_shop_items_container(0)._shop_items:
					if is_instance_valid(offer) and offer.active and offer.item_data.my_id == planned_id and offer.value <= RunData.get_player_currency(0) and scene._get_shop_items_container(0)._can_weapon_be_bought(offer):
						record("buy",{"id":planned_id,"cost":offer.value,"reason":"committed_pistol_replacement"})
						offer._on_BuyButton_pressed()
						return
				record("replacement_offer_unavailable",{"id":planned_id})
				return
			if merge_weapon != null:
				pending_shop_buy = best
				record("combine", {"id":merge_weapon.my_id,"planned_buy":best.item_data.my_id,"ranked_before_merge":true,"merge_dps_delta":merge_gain})
				scene._on_item_combine_button_pressed(merge_weapon,0)
				return
			return
		decision = "Buy " + best.item_data.my_id
		record("buy", {"id":best.item_data.my_id,"cost":best.value,"gold":gold,"value_per_cost":best_score})
		best._on_BuyButton_pressed()
		return
	var reroll_cost = scene._reroll_price[0]
	var reserve = policy.shop_reserve(RunData.current_wave)
	if not scene._get_reroll_button(0).disabled and policy.can_reroll(gold, reroll_cost, shop_rolls, weapons.size(), RunData.current_wave, shop_opening_gold, shop_reroll_spent):
		shop_rolls += 1
		shop_reroll_spent += reroll_cost
		decision = "Reroll shop"
		record("reroll", {"cost":reroll_cost,"reserve":reserve,"gold":gold})
		scene._on_RerollButton_pressed(0)
		return
	record("shop_exit", {"wave":RunData.current_wave,"gold":gold,"opening_gold":shop_opening_gold,"rerolls":shop_rolls,"reroll_spent":shop_reroll_spent,"stats":stat_snapshot()})
	decision = "Next wave"
	scene._on_GoButton_pressed(0)

# One representative per 96px cell; preserve the closest threat and occupancy.
# At most 100 cells per kind inside the 420px local window.
func add_threat(cells, point, pos, radius, bullet = false, velocity = Vector2.ZERO):
	if pos.distance_squared_to(point) > 420.0 * 420.0:
		return
	var cell = ((point - pos) / 96.0).floor()
	var key = Vector3(cell.x, cell.y, 1 if bullet else 0)
	if not cells.has(key):
		cells[key] = [point, radius, 1, velocity, 0.0, 0.65 if bullet else policy.body_horizon]
	else:
		var entry = cells[key]
		entry[2] += 1
		entry[1] = max(entry[1], radius)
		if pos.distance_squared_to(point) < pos.distance_squared_to(entry[0]):
			entry[0] = point
			entry[3] = velocity

func danger_at(point, threats):
	var risk = 0.0
	for t in threats:
		var d2 = point.distance_squared_to(t[0])
		var radius = t[1]
		if d2 < 230.0 * 230.0:
			# Local risk, capped density: distant hordes cannot swamp loot reward.
			risk += 150000.0 / max(400.0, d2) * (1.0 + min(t[2] - 1, 3) * 0.12)
			if d2 < radius * radius:
				risk += 1800.0 * (1.0 - d2 / (radius * radius))
	return risk

# Closest relative approach over the entire travel segment, including fast bullets.
# Exact time spent inside a constant-velocity threat circle during its active window.
func contact_fraction(offset, relative_velocity, radius, active_from, active_to):
	var a = relative_velocity.length_squared()
	var c = offset.length_squared() - radius * radius
	if a < 0.000001:
		return 1.0 if c <= 0.0 else 0.0
	var projection = offset.dot(relative_velocity)
	var discriminant = projection * projection - a * c
	if discriminant < 0.0:
		return 0.0
	var root = sqrt(discriminant)
	var enter = max(active_from,(-projection-root)/a)
	var leave = min(active_to,(-projection+root)/a)
	return max(0.0,leave-enter) / max(0.01,active_to-active_from)

func danger_path(pos, velocity, threats):
	var risk = 0.0
	for threat in threats:
		var offset = threat[0] - pos
		var relative_velocity = threat[3] - velocity
		var active_from = threat[4] if threat.size() > 4 else 0.0
		var active_to = min(0.65, threat[5]) if threat.size() > 5 else 0.65
		if active_to < active_from:
			continue
		var t = clamp(-offset.dot(relative_velocity) / max(1.0, relative_velocity.length_squared()), active_from, active_to)
		var distance_squared = (offset + relative_velocity * t).length_squared()
		var radius = threat[1]
		if distance_squared < 230.0 * 230.0:
			risk += 450000.0 / max(400.0, distance_squared)
			# Closest-distance-only assigns identical impact severity when already
			# overlapping, even if one direction escapes and another stays inside.
			var fraction = contact_fraction(offset,relative_velocity,radius,active_from,active_to)
			risk += 10000.0 * fraction
			risk += policy.new_contact_penalty(offset,relative_velocity,radius,active_from,active_to,fraction)
	return risk

# Native slash animations sweep x=-152..163 around Hitbox local y=18.
# The second variant offsets the Hitbox itself by +165, so use its transform.
# Keep telegraphed segments separate: grid merging would erase the long shape.
func slash_footprint(hitbox_transform, elapsed = 0.0):
	var result = []
	for x in [-152.0,-104.0,-56.0,-8.0,40.0,88.0,136.0,164.0]:
		result.append([hitbox_transform.xform(Vector2(x,18)),42.0 * max(hitbox_transform.x.length(),hitbox_transform.y.length()),1,Vector2.ZERO,max(0.0,0.48-elapsed),max(0.0,0.60-elapsed)])
	return result

func refresh_loot(scene, pos, threats, bounds, health_ratio = 1.0):
	var cells = {}
	# Active gold excludes pooled/hidden materials. Already attracted loot needs no chase.
	var golds = scene.get("_active_golds")
	if golds is Array:
		for m in golds:
			if not is_instance_valid(m) or not m.visible or m.already_picked_up or is_instance_valid(m.attracted_by):
				continue
			var point = m.global_position
			if not bounds.has_point(point):
				continue
			var key = (point / 120.0).floor()
			if not cells.has(key):
				cells[key] = [point, 0.0, pos.distance_squared_to(point)]
			var entry = cells[key]
			entry[1] += float(m.value)
			var d2 = pos.distance_squared_to(point)
			if d2 < entry[2]:
				entry[0] = point
				entry[2] = d2
	loot_cells = cells.size()
	has_loot_target = false
	has_healing_target = false
	var best = 0.0
	for entry in cells.values():
		var distance = sqrt(entry[2])
		var approach = pos.move_toward(entry[0], min(distance, 160.0))
		var utility = 160.0 * min(entry[1], 12.0) / (distance + 100.0)
		utility -= danger_at(approach, threats) * 0.03
		if utility > best:
			best = utility
			loot_target = entry[0]
			has_loot_target = true
	# Recovery targets are only scanned alongside loot, not for every direction.
	var consumables = scene.get("_consumables")
	if health_ratio < 0.8 and consumables is Array:
		for item in consumables:
			if not is_instance_valid(item) or not item.visible or item.already_picked_up or not item.has_healing_effect():
				continue
			var point = item.global_position
			if not bounds.has_point(point):
				continue
			var approach = pos.move_toward(point, min(pos.distance_to(point), 160.0))
			var utility = 4000.0 * (1.0 - health_ratio) / (pos.distance_to(point) + 100.0) - danger_at(approach, threats) * 0.03
			if utility > best:
				best = utility
				loot_target = point
				has_loot_target = true
				has_healing_target = true

# Boundary is a movement feasibility constraint, not a price a crowded AI can pay.
func boundary_allows(pos, destination, bounds):
	if bounds.has_point(destination):
		return true
	var from_error = Vector2(abs(pos.x-clamp(pos.x,bounds.position.x,bounds.end.x)),abs(pos.y-clamp(pos.y,bounds.position.y,bounds.end.y)))
	var to_error = Vector2(abs(destination.x-clamp(destination.x,bounds.position.x,bounds.end.x)),abs(destination.y-clamp(destination.y,bounds.position.y,bounds.end.y)))
	return to_error.x <= from_error.x + 0.01 and to_error.y <= from_error.y + 0.01 and to_error.length_squared() < from_error.length_squared()

func on_native_player_hit(player, value, _knockback, _crit, dodged, protected, _burning, args, _hit_type, _pierced):
	var details = {"wave":RunData.current_wave,"damage":value,"dodged":dodged,"protected":protected,"hp":player.current_stats.health,"position":[player.global_position.x,player.global_position.y],"direction":[direction.x,direction.y],"slash_zones":slash_zones,"nearby_bosses":nearby_bosses}
	if is_instance_valid(args.from):
		if body_forecasts.has(args.from.get_instance_id()) and args.from is Node2D:
			var forecast = body_forecasts[args.from.get_instance_id()]
			var dt = (OS.get_ticks_msec()-forecast_msec)/1000.0
			var predicted = forecast[0] + forecast[1] * dt
			details["forecast_age"] = dt
			details["forecast_source_position"] = [forecast[0].x,forecast[0].y]
			details["forecast_source_velocity"] = [forecast[1].x,forecast[1].y]
			details["forecast_error"] = predicted.distance_to(args.from.global_position)
			details["forecast_player_position"] = [forecast_player_position.x,forecast_player_position.y]
		else:
			details["source_not_in_body_forecast"] = true
		details["source_scene"] = args.from.filename
		details["source_path"] = str(args.from.get_path())
		if args.from is Node2D:
			details["source_position"] = [args.from.global_position.x,args.from.global_position.y]
	if is_instance_valid(args.hitbox):
		details["hitbox_path"] = str(args.hitbox.get_path())
		details["hitbox_position"] = [args.hitbox.global_position.x,args.hitbox.global_position.y]
	record("native_player_hit",details)

func add_body_threat(cells, bosses, point, pos, velocity, is_boss):
	# Preserve individual collision geometry in the immediate body-contact region.
	if is_boss or pos.distance_squared_to(point) <= 180.0 * 180.0:
		if pos.distance_squared_to(point) <= 420.0 * 420.0:
			bosses.append([point,72.0,1,velocity,0.0,0.65 if is_boss else policy.body_horizon])
	else:
		add_threat(cells,point,pos,72.0,false,velocity)

func threat_units(spawner):
	# Native enemies excludes the separate bosses list (elites are bosses too).
	return spawner.get_all_enemies(false)

# Rank only living hostile enemies. The same order drives weapon aim and approach.
func enemy_priority(enemy):
	if not is_instance_valid(enemy) or not enemy is Unit or enemy.dead:
		return -1
	if enemy is Neutral:
		var tree = enemy.filename.ends_with("/tree.tscn") or enemy.filename.ends_with("/tree_jungle.tscn")
		return policy.target_priority(false,false,false,false,true) if tree else -1
	if not enemy is Enemy or enemy.get_charmed_by_player_index() >= 0:
		return -1
	var spawning = enemy._current_attack_behavior is SpawningAttackBehavior
	var shooting = enemy._current_attack_behavior is ShootingAttackBehavior
	return policy.target_priority(enemy is Boss, enemy is Healer or enemy is Buffer, spawning, shooting)

func is_emergency_target(enemy, player_position, player_velocity):
	return is_instance_valid(enemy) and enemy is Enemy and not enemy is Boss and not enemy.dead and enemy.get_charmed_by_player_index() < 0 and policy.imminent_contact(enemy.global_position-player_position,enemy._integrate_forces_velocity-player_velocity)

func priority_target(targets, origin, min_range, max_range, player_position = null, player_velocity = Vector2.ZERO):
	var best = [null,INF]
	var best_priority = -1
	var best_cost = INF
	for enemy in targets:
		var priority = enemy_priority(enemy)
		if priority < 0:
			continue
		var distance = origin.distance_to(enemy.global_position)
		if distance <= min_range or distance > max_range:
			continue
		if player_position != null and is_emergency_target(enemy,player_position,player_velocity):
			priority = 6 # Only weapon aim: clear imminent body contact, then resume boss.
		var cost = distance
		if enemy is Boss:
			var warning = charge_warning(enemy)
			cost = boss_model.focus_cost(distance,float(enemy.current_stats.health)/max(1.0,enemy.max_stats.health),not warning.empty(),enemy.get_instance_id()==focused_boss_id)
		if priority > best_priority or (priority == best_priority and cost < best_cost):
			best = [enemy,distance]
			best_priority = priority
			best_cost = cost
	return best

func charge_warning(enemy):
	var behavior = enemy._current_attack_behavior
	if not behavior is ChargingAttackBehavior:
		return {}
	var animation = enemy._animation_player
	var preparing = animation.is_playing() and animation.current_animation == enemy.shoot_animation_name and not enemy._can_move and not enemy._move_locked
	var charging = enemy._move_locked
	var in_range = enemy.current_target != null and Utils.is_between(enemy.global_position.distance_to(enemy.current_target.global_position),behavior.min_range,behavior.max_range)
	if not preparing and not charging and (behavior._current_cd/60.0 > 0.35 or not in_range):
		return {}
	var delay = 0.0
	if preparing:
		delay = max(0.0,animation.get_animation(animation.current_animation).length-animation.current_animation_position)/max(0.01,animation.playback_speed)
	elif not charging:
		delay = behavior._current_cd/60.0 + animation.get_animation(enemy.shoot_animation_name).length/max(0.01,animation.playback_speed)
	var axis = behavior._charge_direction
	if not preparing and not charging or behavior.target_calculation_timing != 0:
		axis = enemy.current_target.global_position-enemy.global_position if enemy.current_target != null else Vector2.ZERO
	return {"id":enemy.enemy_id,"delay":delay,"direction":axis,"speed":behavior.charge_speed*RunData.current_run_accessibility_settings.speed,"duration":behavior._unlock_move_timer.time_left if charging else behavior.charge_duration,"phase":"charge" if charging else ("windup" if preparing else "cooldown")}

func observe_weapon_target(target, weapon_id, emergency = false):
	if target[0] == null or clock < next_aim_report:
		return
	next_aim_report = clock + 1.0
	var enemy = target[0]
	var id = enemy.filename if enemy is Neutral else enemy.enemy_id
	record("weapon_target", {"id":id,"priority":6 if emergency else enemy_priority(enemy),"emergency_contact":emergency,"distance":target[1],"weapon":weapon_id})

func steer(player):
	if is_instance_valid(player) and not player.is_connected("took_damage",self,"on_native_player_hit"):
		player.connect("took_damage",self,"on_native_player_hit")
	if finished or not is_instance_valid(player) or player.dead:
		return Vector2.ZERO
	var frame = Engine.get_physics_frames()
	if cached_frame >= 0 and frame - cached_frame < 4:
		return direction
	cached_frame = frame
	var current_hp = player.current_stats.health
	var sampled_damage = observed_hp >= 0 and current_hp < observed_hp
	var hp_before = observed_hp
	observed_hp = current_hp
	var previous_position = observed_position
	observed_position = player.global_position
	var started = OS.get_ticks_usec()
	var scene = get_tree().current_scene
	if scene == null or not scene.has_node("EntitySpawner"):
		return Vector2.ZERO
	var spawner = scene.get_node("EntitySpawner")
	var pos = player.global_position
	var bounds = ZoneService.get_current_zone_rect().grow(-45)
	var cells = {}
	var movement_targets = threat_units(spawner).duplicate()
	for neutral in spawner.neutrals:
		if is_instance_valid(neutral) and policy.movement_target_allowed(true,pos.distance_to(neutral.global_position)):
			movement_targets.append(neutral)
	var attack_target = priority_target(movement_targets,pos,0.0,INF)[0]
	var new_focus = attack_target.get_instance_id() if attack_target is Boss else 0
	if new_focus != focused_boss_id:
		focused_boss_id = new_focus
		if focused_boss_id != 0:
			record("boss_focus",{"id":attack_target.enemy_id,"instance_id":focused_boss_id,"health":attack_target.current_stats.health,"reason":"distance_health_charge_with_hysteresis"})
	combat_target_id = ""
	if is_instance_valid(attack_target):
		combat_target_id = attack_target.filename if attack_target is Neutral else attack_target.enemy_id
	var attack_reach = 0.0
	for weapon in player.current_weapons:
		var reach = max(0.0,weapon.get_max_range()-weapon.global_position.distance_to(pos))
		attack_reach = reach if attack_reach == 0.0 else min(attack_reach,reach)
	var boss_threats = []
	boss_warnings = []
	orbit_segments_count = 0
	nearby_bosses = 0
	body_forecasts = {}
	forecast_msec = OS.get_ticks_msec()
	forecast_player_position = pos
	for enemy in threat_units(spawner):
		if is_instance_valid(enemy) and not enemy.dead:
			# Ordinary chargers share the native behavior with charging bosses.
			var warning = charge_warning(enemy)
			if not warning.empty():
				var segment = boss_model.charge_segment(enemy.global_position,warning.direction,warning.speed,warning.delay,warning.duration)
				if not segment.empty():
					boss_threats.append(segment)
				if enemy is Boss or pos.distance_squared_to(enemy.global_position) <= 600.0*600.0:
					boss_warnings.append({"id":warning.id,"phase":warning.phase,"delay":warning.delay,"direction":[warning.direction.x,warning.direction.y]})
			if enemy is Boss:
				for attached in enemy._all_additional_projectiles:
					if not is_instance_valid(attached) or not attached is EnemyProjectileRotating or not attached.is_visible_in_tree() or attached._enable_stop_delay:
						continue
					var pivot = attached.get_parent()
					if not pivot is Pivot:
						continue
					var center_velocity = enemy._integrate_forces_velocity
					if not warning.empty() and warning.phase == "charge":
						center_velocity = warning.direction.normalized()*warning.speed
					var factor = RunData.current_run_accessibility_settings.speed
					for arc in boss_model.orbit_segments(pivot.global_position,center_velocity,attached.global_position-pivot.global_position,pivot.direction*pivot.rotation_speed*factor,attached.speed*factor,attached.actual_target_distance):
						var at_start = arc[0]+arc[3]*arc[4]
						var at_end = arc[0]+arc[3]*arc[5]
						if Geometry.get_closest_point_to_segment_2d(pos,at_start,at_end).distance_to(pos) < 600.0:
							boss_threats.append(arc)
							orbit_segments_count += 1
			if pos.distance_squared_to(enemy.global_position) <= 420.0 * 420.0:
				body_forecasts[enemy.get_instance_id()] = [enemy.global_position,enemy._integrate_forces_velocity]
			if enemy is Boss and pos.distance_squared_to(enemy.global_position) <= 420.0 * 420.0:
				nearby_bosses += 1
			add_body_threat(cells, boss_threats, enemy.global_position, pos, enemy._integrate_forces_velocity, enemy is Boss)
	var slash_threats = []
	slash_zones = 0
	var projectiles = scene.get("_enemy_projectiles")
	if is_instance_valid(projectiles):
		for p in projectiles.get_children():
			if p is Projectile and p.visible and not p._enable_stop_delay:
				if p.filename.begins_with("res://projectiles/slash/"):
					# Warning lasts until .48s; damaging sweep .48-.60s.
					if p._animation_player.current_animation_position <= 0.6:
						for segment in slash_footprint(p._hitbox.global_transform, p._animation_player.current_animation_position):
							if pos.distance_squared_to(segment[0]) < 480.0 * 480.0:
								slash_threats.append(segment)
								slash_zones += 1
					continue
				# Keep ordinary bullets separate from enemy cells.
				add_threat(cells, p.global_position, pos, 58.0, true, p.velocity)
	var threats = cells.values() + boss_threats + slash_threats
	if clock >= next_boss_report and (not boss_warnings.empty() or orbit_segments_count > 0):
		next_boss_report = clock+1.0
		record("boss_forecast",{"warnings":boss_warnings,"orbit_segments":orbit_segments_count,"focus":focused_boss_id})
	threat_cells = threats.size()
	if clock >= next_loot_scan:
		next_loot_scan = clock + 0.25
		refresh_loot(scene, pos, threats, bounds, float(player.current_stats.health) / max(1.0, player.max_stats.health))
	var center = bounds.position + bounds.size / 2
	var radial = (pos - center).normalized()
	if radial == Vector2.ZERO:
		radial = Vector2.RIGHT
	var patrol = center + radial.rotated(0.65) * min(bounds.size.x, bounds.size.y) * 0.3
	var health_ratio = float(player.current_stats.health) / max(1.0,player.max_stats.health)
	var pursue_loot = has_loot_target and not (is_instance_valid(attack_target) and enemy_priority(attack_target) >= 4 and health_ratio > 0.55 and not has_healing_target) and (has_healing_target or health_ratio > 0.45 or threats.size() < 8)
	var target = loot_target if pursue_loot else patrol
	var best = -1e20
	var previous_direction = direction
	var best_direction = Vector2.ZERO
	var speed = max(1.0, float(player.max_stats.speed))
	var initial_distance = pos.distance_to(target)
	var candidate_details = []
	for v in directions:
		if not boundary_allows(pos,pos + v * speed * policy.body_horizon,bounds):
			continue
		var score = v.dot(previous_direction) * 6.0
		# Reward actual progress toward a material cluster, in world-space units.
		var end = pos + v * speed * 0.6
		score += (initial_distance - end.distance_to(target)) * (1.4 if pursue_loot else 0.25)
		score -= danger_path(pos, v * speed, threats)
		if is_instance_valid(attack_target) and not has_healing_target and (not attack_target is Boss or charge_warning(attack_target).empty()):
			var target_velocity = Vector2.ZERO if attack_target is Neutral else attack_target._integrate_forces_velocity
			var enemy_future = attack_target.global_position + target_velocity * 0.35
			var attack_distance = (pos + v * speed * 0.35).distance_to(enemy_future)
			if policy.brawler:
				score += policy.engagement_score(attack_distance,attack_reach,health_ratio)
				score += policy.approach_score(pos.distance_to(enemy_future),attack_distance,attack_reach,health_ratio)
			elif health_ratio > 0.4 and attack_reach > 180.0:
				var preferred_range = min(320.0,attack_reach*0.7)
				score += policy.approach_score(pos.distance_to(enemy_future),attack_distance,preferred_range,health_ratio)
				score += max(0.0,1.0-abs(attack_distance-preferred_range)/max(100.0,preferred_range)) * 160.0
		if sampled_damage:
			candidate_details.append({"v":[v.x,v.y],"score":score})
		if score > best:
			best = score
			best_direction = v
	direction = best_direction
	if sampled_damage:
		var threat_details = []
		for threat in threats:
			threat_details.append({"point":[threat[0].x,threat[0].y],"radius":threat[1],"count":threat[2],"velocity":[threat[3].x,threat[3].y],"active_from":threat[4] if threat.size()>4 else 0.0,"active_to":threat[5] if threat.size()>5 else 0.65})
		record("damage_context", {"wave":RunData.current_wave,"hp_before":hp_before,"hp":current_hp,"position":[pos.x,pos.y],"previous_position":[previous_position.x,previous_position.y],"previous_direction":[previous_direction.x,previous_direction.y],"chosen_direction":[direction.x,direction.y],"speed":speed,"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"candidates":candidate_details,"threats":threat_details,"nearby_bosses":nearby_bosses,"slash_zones":slash_zones})
	steer_us = OS.get_ticks_usec() - started
	steer_peak_us = max(steer_peak_us, steer_us)
	decision = "%s | HP %s/%s | cells %s | AI %.2f ms" % [("Heal" if has_healing_target else "Collect XP") if pursue_loot else "Kite", player.current_stats.health, player.max_stats.health, threat_cells, steer_us / 1000.0]
	return direction

func report(scene):
	var state = {"scene":scene.filename,"wave":RunData.current_wave,"difficulty":RunData.current_difficulty,"won":RunData.run_won,"finished":finished,"enabled":enabled,"decision":decision}
	if scene.has_node("EntitySpawner"):
		var s = scene.get_node("EntitySpawner")
		state["enemies"] = s.enemies.size()
		if not s._players.empty() and is_instance_valid(s._players[0]):
			var p = s._players[0]
			state["hp"] = p.current_stats.health
			state["max_hp"] = p.max_stats.health
			state["position"] = [p.global_position.x,p.global_position.y]
	state["strategy_version"] = "0.6.17-dev"
	state["profile"] = gun_profile
	state["character"] = selected_character
	state["run_id"] = recording_id
	state["recording_enabled"] = recording_enabled
	state["trees_killed_total"] = ProgressData.data.get("trees_killed",0)
	state["development_speed"] = development_speed
	state["time_scale"] = Engine.time_scale
	state["physics_hz"] = Engine.iterations_per_second
	state["physics_delta"] = get_physics_process_delta_time()
	state["native_tick_delta"] = Utils.physics_one(get_physics_process_delta_time())
	state["simulation_seconds"] = clock
	state["combat_target"] = combat_target_id
	state["boss_warnings"] = boss_warnings
	state["orbit_segments"] = orbit_segments_count
	state["healing_totals"] = healing_totals.duplicate(true)
	state["build_stats"] = stat_snapshot()
	state["raw_max_hp"] = Utils.get_stat(Keys.stat_max_hp_hash, 0)
	state["weapons"] = []
	for weapon in RunData.get_player_weapons(0):
		state["weapons"].append(weapon.my_id)
	state["paused"] = get_tree().paused
	state["focused"] = OS.is_window_focused()
	state["steer_ms"] = steer_us / 1000.0
	state["steer_peak_ms"] = steer_peak_us / 1000.0
	state["fps"] = Engine.get_frames_per_second()
	state["nearby_bosses"] = nearby_bosses
	state["slash_zones"] = slash_zones
	state["healing_target"] = has_healing_target
	state["threat_cells"] = threat_cells
	state["loot_cells"] = loot_cells
	state["loot_target"] = [loot_target.x, loot_target.y] if has_loot_target else null
	steer_peak_us = 0
	if scene.has_node("EntitySpawner") and state.has("hp"):
		recent_combat.append(state.duplicate(true))
		if recent_combat.size() > 120:
			recent_combat.pop_front()
	var f = File.new()
	f.open(evidence + "/state.json", File.WRITE)
	f.store_string(JSON.print(state))
	f.close()
	record("state", state)

func save_image(filename):
	var image = get_viewport().get_texture().get_data()
	image.flip_y()
	image.save_png(evidence + "/" + filename)


func begin_recording():
	if recording_id != "":
		end_recording()
	log_file.close()
	log_file.open(evidence + "/events.jsonl", File.WRITE)
	var dt = OS.get_datetime()
	recording_id = "run-%04d%02d%02d-%02d%02d%02d-%s" % [dt.year,dt.month,dt.day,dt.hour,dt.minute,dt.second,OS.get_ticks_msec()]
	recording_ended = false
	recording_end_at = -1.0
	healing_totals = {}
	focused_boss_id = 0
	boss_warnings = []
	if not recording_enabled:
		recording_ended = true
		record("run_start",{"run_id":recording_id,"character":selected_character,"recording":false})
		return
	var pid = OS.execute("C:/Users/75315/miniconda3/python.exe", PoolStringArray(["F:/codex-project/tudou/record_run.py",recording_id,str(OS.get_process_id())]), false)
	record("recording_start", {"run_id":recording_id,"worker_pid":pid})

func end_recording():
	if recording_id == "" or recording_ended:
		return
	var f = File.new()
	f.open("F:/codex-project/tudou/recordings/" + recording_id + ".stop", File.WRITE)
	f.store_string("run ended")
	f.close()
	recording_ended = true
	record("recording_stop", {"run_id":recording_id})

func update_recording(scene):
	# A finished run must never be rearmed just by visiting character selection.
	if finished:
		if recording_end_at >= 0 and clock >= recording_end_at:
			end_recording()
		return
	var changed = scene.filename != last_scene
	var new_selection = changed and scene is CharacterSelection
	var new_game = scene.filename == "res://main.tscn" and recording_id == ""
	if new_selection or new_game:
		finished = false
		settlement_at = -1.0
		observed_hp = -1
		recent_combat = []
		begin_recording()
	previous_wave = RunData.current_wave
	if not recording_enabled:
		recording_label.text = "REC OFF"
		return
	if recording_id == "":
		recording_label.text = "REC waiting for next run"
		return
	if scene is BaseEndRun and not recording_ended and recording_end_at < 0:
		recording_end_at = clock + 3.0
	if changed and scene is TitleScreen and not recording_ended:
		recording_end_at = clock + 1.0
	if recording_end_at >= 0 and clock >= recording_end_at:
		end_recording()
	if clock < recording_status_at:
		return
	recording_status_at = clock + 0.5
	var f = File.new()
	var status_path = "F:/codex-project/tudou/recordings/" + recording_id + ".json"
	if f.open(status_path, File.READ) == OK:
		var status = parse_json(f.get_as_text())
		f.close()
		if status is Dictionary:
			recording_label.text = "REC " + str(status.get("state", "starting")) + " | " + recording_id
	else:
		recording_label.text = "REC starting | " + recording_id

func _exit_tree():
	Engine.time_scale = 1.0
	Engine.iterations_per_second = normal_physics_hz
	end_recording()


func analyze_run():
	var analysis = policy.analyze(recent_combat, RunData.current_wave)
	analysis["strategy_version"] = "0.6.17-dev"
	analysis["run_id"] = recording_id
	analysis["gun_profile"] = gun_profile
	analysis["character"] = selected_character
	analysis["development_speed"] = development_speed
	analysis["healing_totals"] = healing_totals.duplicate(true)
	analysis["won"] = RunData.run_won
	analysis["recording"] = "F:/codex-project/tudou/recordings/" + recording_id + ".mp4" if recording_enabled else ""
	var results_dir = Directory.new()
	results_dir.make_dir_recursive(evidence + "/results")
	var result_file = File.new()
	if result_file.open(evidence + "/results/" + recording_id + ".json", File.WRITE) == OK:
		result_file.store_string(JSON.print(analysis))
		result_file.close()
	log_file.flush()
	results_dir.copy(evidence + "/events.jsonl", evidence + "/results/" + recording_id + "-events.jsonl")
	results_dir.copy(evidence + "/settlement.png", evidence + "/results/" + recording_id + ".png")
	record("analysis", analysis)


func load_base_item(folder, resource_name):
	var path = "res://items/all/" + folder + "/" + resource_name + ".tres"
	if not ResourceLoader.exists(path):
		path = "res://items/all/00_base_game/" + folder + "/" + resource_name + ".tres"
	return load(path)

func verify_recovery():
	var selected_brawler = policy.brawler
	var saved_character_policy = policy.character
	policy.character = "character_well_rounded"
	var selected_profile = gun_profile
	policy.brawler = false
	var passed = policy.should_restart(false,true,true,8.0) and not policy.should_restart(true,true,true,10.0) and not policy.should_restart(false,true,false,10.0) and not policy.should_restart(false,false,true,10.0) and not policy.should_restart(false,true,true,7.9)
	var imported = File.new()
	if imported.open(evidence + "/previous-combat.json", File.READ) == OK:
		var states = parse_json(imported.get_as_text())
		imported.close()
		if states is Array and not states.empty():
			var analysis = policy.analyze(states, states.back().get("wave",0))
			var results = Directory.new()
			results.make_dir_recursive(evidence + "/results")
			if imported.open(evidence + "/results/imported-wave17-analysis.json", File.WRITE) == OK:
				imported.store_string(JSON.print(analysis))
				imported.close()
			passed = passed and analysis.largest_sampled_hp_drop >= 26 and not analysis.changes.empty()
	passed = passed and policy.breaks_floor("stat_speed",-10,{"stat_speed":9},17)
	passed = passed and policy.breaks_floor("stat_attack_speed",-10,{"stat_attack_speed":3},17)
	passed = passed and policy.breaks_floor("stat_range",-50,{"stat_range":-15},12)
	gun_profile = "legacy"
	var support = {"weapon_id":"weapon_shredder","my_id":"weapon_shredder_1","tier":0,"upgrades_into":true}
	var smg = {"weapon_id":"weapon_smg","my_id":"weapon_smg_1"}
	passed = passed and weapon_value(support,[support,smg,smg,smg,smg,smg]) > 0
	passed = passed and weapon_value(support,[support,smg]) < 0
	var incoming = [[Vector2(200,0),58.0,1,Vector2(-500,0)]]
	var leaving = [[Vector2(200,0),58.0,1,Vector2(500,0)]]
	passed = passed and danger_path(Vector2.ZERO,Vector2.ZERO,incoming) > danger_path(Vector2.ZERO,Vector2.ZERO,leaving) * 10
	passed = passed and policy.can_reroll(2165,36,3,6,16,2237,72)
	passed = passed and not policy.can_reroll(250,36,3,6,16,2237,72)
	passed = passed and not policy.can_reroll(2000,36,16,6,16,2237,72)
	passed = passed and not policy.can_reroll(2000,36,3,6,16,2237,780)
	passed = passed and not policy.can_reroll(300,10,3,6,5,300,20)
	gun_profile = "smg_shotgun"
	var shotgun = load("res://weapons/ranged/double_barrel_shotgun/1/double_barrel_shotgun_data.tres")
	var actual_smg = load("res://weapons/ranged/smg/1/smg_data.tres")
	var early_guns = [actual_smg,actual_smg,actual_smg,actual_smg,actual_smg,actual_smg.upgrades_into]
	var early_stats = {"stat_ranged_damage":0,"stat_percent_damage":5}
	var ranged_offer_score = ranged_damage_score(early_guns,early_stats,2)
	var early_upgrade_score = marginal_weapon_score(actual_smg,early_guns,early_stats,5)
	passed = passed and ranged_offer_score > 28.8
	passed = passed and policy.purchase_worthwhile(early_upgrade_score,35)
	passed = passed and ranged_damage_score(early_guns,{"stat_ranged_damage":20,"stat_percent_damage":5},2) < ranged_offer_score
	passed = passed and ranged_damage_score(early_guns,early_stats,-1) < 0
	record("dps_regression", {"ranged2_score":ranged_offer_score,"smg_upgrade_score":early_upgrade_score,"hp9_score":28.8})
	passed = passed and weapon_value(shotgun,[actual_smg,actual_smg,actual_smg,actual_smg]) > 0
	passed = passed and weapon_value(actual_smg,[actual_smg,actual_smg,actual_smg,actual_smg]) > 0
	passed = passed and weapon_value(shotgun,[actual_smg,actual_smg,actual_smg,actual_smg,shotgun,shotgun]) > 0
	passed = passed and weapon_value(shotgun,[actual_smg,shotgun,shotgun]) < 0
	passed = passed and weapon_value(support,[actual_smg]) < 0
	passed = passed and synergy_bonus("item_sharp_bullet") > 0
	passed = passed and synergy_bonus("item_ricochet") < 0
	var slash_native = load("res://projectiles/slash/slash_projectile.tscn")
	var slash_native_2 = load("res://projectiles/slash/slash_projectile_2.tscn")
	passed = passed and slash_native != null and slash_native_2 != null
	var long_slash = slash_footprint(Transform2D(0.0,Vector2.ZERO))
	passed = passed and long_slash.size() == 8
	passed = passed and danger_path(Vector2(140,18),Vector2.ZERO,long_slash) > 4000.0
	passed = passed and danger_path(Vector2(140,200),Vector2.ZERO,long_slash) < 500.0
	var rotated_slash = slash_footprint(Transform2D(PI/2,Vector2(165,0)))
	passed = passed and danger_path(Vector2(147,140),Vector2.ZERO,rotated_slash) > 4000.0
	passed = passed and synergy_bonus("item_bandana",[]) > 40.0
	passed = passed and synergy_bonus("item_bandana",["item_sharp_bullet"]) < 15.0
	passed = passed and synergy_bonus("item_bandana",["item_sharp_bullet","item_bandana"]) < -900.0
	passed = passed and synergy_bonus("item_baby_with_a_beard",["item_baby_with_a_beard"]) < synergy_bonus("item_baby_with_a_beard",[])
	var timed_warning = [[Vector2.ZERO,42.0,1,Vector2.ZERO,0.48,0.60]]
	passed = passed and danger_path(Vector2.ZERO,Vector2(0,300),timed_warning) < danger_path(Vector2.ZERO,Vector2.ZERO,timed_warning) * 0.1
	var active_warning = [[Vector2.ZERO,42.0,1,Vector2.ZERO,0.0,0.12]]
	passed = passed and danger_path(Vector2.ZERO,Vector2(0,300),active_warning) > 5000.0
	var arena = Rect2(45,45,1950,1150)
	passed = passed and not boundary_allows(Vector2(70,70),Vector2(-200,70),arena)
	passed = passed and not boundary_allows(Vector2(70,70),Vector2(70,-200),arena)
	passed = passed and boundary_allows(Vector2(24,36),Vector2(200,200),arena)
	passed = passed and not boundary_allows(Vector2(24,36),Vector2(10,200),arena)
	passed = passed and boundary_allows(Vector2(24,36),Vector2(35,40),arena)
	var bait = load_base_item("bait","bait_data")
	var bait_unit = load("res://zones/common/bait/unit_bait.tres")
	passed = passed and policy.unsupported_extra_spawn(bait.effects)
	passed = passed and not policy.unsupported_extra_spawn([])
	passed = passed and bait_unit.min_number == 7 and bait_unit.max_number == 8
	var ghost = load_base_item("weird_ghost","weird_ghost_data")
	passed = passed and policy.forced_low_health_start(ghost.effects)
	passed = passed and not policy.forced_low_health_start([])
	var barricade = load_base_item("barricade","barricade_data")
	var moving_stats = {"stat_armor":5,"stat_speed":20}
	passed = passed and policy.score_effects(barricade.effects,moving_stats,16) < 0.0
	var stationary_armor = load_base_item("barricade","barricade_effect_1")
	passed = passed and policy.score_effects([stationary_armor],moving_stats,16) == 0.0
	var always_speed_loss = load_base_item("barricade","barricade_effect_2")
	passed = passed and policy.score_effects([always_speed_loss],moving_stats,16) < 0.0
	passed = passed and weapon_value(actual_smg,[actual_smg,actual_smg,actual_smg,actual_smg,actual_smg]) > 0
	passed = passed and weapon_value(shotgun,[actual_smg,actual_smg,actual_smg,actual_smg,actual_smg,actual_smg]) > 0
	var smg3 = load("res://weapons/ranged/smg/3/smg_3_data.tres")
	var pistol = load("res://weapons/ranged/pistol/1/pistol_data.tres")
	policy.character = "character_ranger"
	passed = passed and ranger_replacement(smg3,[pistol,actual_smg,actual_smg,actual_smg,shotgun,shotgun],{"stat_ranged_damage":9}) == pistol
	passed = passed and ranger_replacement(actual_smg,[pistol,actual_smg],{"stat_ranged_damage":9}) == null
	passed = passed and ranger_replacement(smg3,[actual_smg,actual_smg,actual_smg,actual_smg,shotgun,shotgun],{"stat_ranged_damage":9}) == null
	policy.character = "character_well_rounded"
	passed = passed and ranger_replacement(smg3,[pistol,actual_smg,actual_smg,actual_smg,shotgun,shotgun],{"stat_ranged_damage":9}) == null
	var weak_body = {"stat_ranged_damage":6,"stat_armor":1}
	var advanced_guns = [smg3,actual_smg,actual_smg,actual_smg,shotgun,shotgun]
	var upgrade_points = marginal_weapon_score(smg3,advanced_guns,weak_body,11)
	passed = passed and upgrade_points > 0 and upgrade_points < weapon_value(smg3,advanced_guns)
	passed = passed and marginal_weapon_score(actual_smg,[actual_smg],weak_body,1) == weapon_value(actual_smg,[actual_smg])
	passed = passed and base_gun_dps(smg3,7) > base_gun_dps(smg3,6)
	passed = passed and policy.purchase_worthwhile(6.6,57)
	passed = passed and policy.purchase_worthwhile(25.5,197)
	passed = passed and not policy.purchase_worthwhile(4.45,122)
	passed = passed and not policy.purchase_worthwhile(-1000.0,40)
	passed = passed and not policy.purchase_worthwhile(3.0,17)
	var exit_fast = contact_fraction(Vector2(-30,0),Vector2(-300,0),72.0,0.0,0.65)
	var cross_deeper = contact_fraction(Vector2(-30,0),Vector2(300,0),72.0,0.0,0.65)
	passed = passed and exit_fast < cross_deeper and exit_fast > 0
	passed = passed and contact_fraction(Vector2.ZERO,Vector2.ZERO,72.0,0.0,0.65) == 1.0
	passed = passed and contact_fraction(Vector2.ZERO,Vector2(-300,0),42.0,0.48,0.60) == 0.0
	var smg2 = load("res://weapons/ranged/smg/2/smg_2_data.tres")
	var six_lower_tier = [smg2,smg2,smg2,smg2,smg2,smg2]
	passed = passed and weapon_value(smg3,six_lower_tier) > 0
	passed = passed and marginal_weapon_score(smg3,six_lower_tier,{"stat_ranged_damage":22},19) > 0
	var shotgun2 = load("res://weapons/ranged/double_barrel_shotgun/2/double_barrel_shotgun_2_data.tres")
	var shotgun3 = load("res://weapons/ranged/double_barrel_shotgun/3/double_barrel_shotgun_3_data.tres")
	passed = passed and weapon_value(shotgun3,[smg2,smg2,smg2,smg2,shotgun2,shotgun2]) > 0
	var native_spawner = load("res://global/entity_spawner.gd").new()
	var boss_marker = Node.new()
	var charmed_marker = Node.new()
	native_spawner.enemies = [charmed_marker]
	native_spawner.bosses = [boss_marker]
	native_spawner.charmed_enemies = [charmed_marker]
	var test_body_cells = {}
	var crowded_corner = Vector2(263.717957,1231.81189)
	var crowded_bounds = Rect2(45,45,1958,1446)
	passed = passed and boundary_allows(crowded_corner,crowded_corner+Vector2.DOWN*558*policy.body_horizon,crowded_bounds)
	passed = passed and not boundary_allows(crowded_corner,crowded_corner+Vector2.DOWN*558*0.65,crowded_bounds)
	var test_boss_bodies = []
	add_body_threat(test_body_cells,test_boss_bodies,Vector2(240,240),Vector2.ZERO,Vector2(-500,0),true)
	add_body_threat(test_body_cells,test_boss_bodies,Vector2(200,200),Vector2.ZERO,Vector2.ZERO,false)
	passed = passed and test_body_cells.size() == 1 and test_boss_bodies.size() == 1
	passed = passed and test_boss_bodies[0][0] == Vector2(240,240) and test_boss_bodies[0][3] == Vector2(-500,0)
	var near_cells = {}
	var near_bodies = []
	add_body_threat(near_cells,near_bodies,Vector2(10,10),Vector2.ZERO,Vector2.ZERO,false)
	add_body_threat(near_cells,near_bodies,Vector2(80,80),Vector2.ZERO,Vector2(-500,0),false)
	passed = passed and near_cells.empty() and near_bodies.size() == 2
	passed = passed and near_bodies[1][3] == Vector2(-500,0)
	var native_hostiles = threat_units(native_spawner)
	passed = passed and boss_marker in native_hostiles and not (charmed_marker in native_hostiles)
	passed = passed and native_spawner.enemies.size() == 1
	native_spawner.free()
	boss_marker.free()
	charmed_marker.free()
	policy.character = "character_chunky"
	policy.brawler = false
	passed = passed and weapon_value(shotgun,[]) > 0 and weapon_value(actual_smg,[]) < 0
	var checks = File.new()
	policy.character = "character_mage"
	policy.brawler = false
	var mage_taser = load("res://weapons/ranged/taser/1/taser_data.tres")
	passed = passed and damage_stat() == "stat_elemental_damage"
	passed = passed and weapon_value(mage_taser,[]) > 0 and weapon_value(actual_smg,[]) < 0
	passed = passed and base_gun_dps(mage_taser,10) > base_gun_dps(mage_taser,5)
	passed = passed and ranged_damage_score([mage_taser],{"stat_elemental_damage":5},2) > 0
	checks.open(evidence + "/revision-check.json",File.WRITE)
	checks.store_string(JSON.print({"version":"0.5.25","passed":passed,"checks":["native early six SMG ranged2 vs HP9 and affordable tier1 upgrade DPS normalization","recovery gates","real defeat evidence","speed/attack/range floors","support upgrade at full slots","no extra support at open slots","incoming projectile collision","real wave16 shop budget regression","reroll purchase reserve / budget / iteration limits","early economy preserved","native shotgun/SMG slot caps and merge","sharp bullet synergy","avoid bounce damage loss for piercing trial","native slash resources","full warning sweep footprint / safe lane","rotated and offset slash transform","real sharp bullet plus triple bandana regression","duplicate synergy diminishing returns","warning escape before native active interval","already active slash stays dangerous","wall infeasible moves rejected","real lethal corner24/36 escape allowed","native barricade stationary armor excluded while moving","unconditional speed penalty retained","real four SMG empty-slot deadlock regression","temporary sixth SMG and later shotgun accepted","native full-loadout marginal upgrade valuation","early slot filling retains priority","real armor offer accepted / weaker marginal weapon rejected","unified item and weapon admission threshold","inside-threat fast escape vs deeper crossing duration","stationary and delayed activation contact fractions","real higher-tier offer admitted after lower-tier merge","shotgun pair-to-higher-tier purchase admitted","native bait extra7-8 enemies risk detected","native weird ghost forced-low-health risk detected","same-cell nearfield normal bodies retained independently","same-cell boss body and velocity retained independently","native separate boss list included","native charmed-enemy exclusion retained"]}))
	checks.close()
	policy.brawler = selected_brawler
	policy.character = saved_character_policy
	gun_profile = selected_profile
	record("recovery_selfcheck", {"passed":passed})
	if not passed:
		enabled = false
		decision = "Recovery check failed - stopped"
