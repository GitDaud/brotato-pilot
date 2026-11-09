extends Reference

var armor_bias = 1.0
var brawler = false

# Thresholds are pilot heuristics, not game rules or guide-prescribed breakpoints.
func weights(stats, wave):
	var hp_target = 20.0 + wave * 2.5
	var armor_target = max(2.0, wave * 0.6)
	var result = {
		"stat_max_hp": 3.2 if stats.get("stat_max_hp", 0) < hp_target else 0.9,
		"stat_armor": (9.0 if stats.get("stat_armor", 0) < armor_target else 2.0) * armor_bias,
		"stat_ranged_damage": 12.0 if stats.get("stat_ranged_damage", 0) < 4 + wave else 4.0,
		"stat_percent_damage": 0.9,
		"stat_attack_speed": 2.4 if stats.get("stat_attack_speed", 0) < 30 else 0.8,
		"stat_lifesteal": 4.5 if stats.get("stat_lifesteal", 0) < 8 else 0.5,
		"stat_hp_regeneration": 1.8 if stats.get("stat_hp_regeneration", 0) < 5 else 0.6,
		"stat_speed": 3.0 if stats.get("stat_speed", 0) < 20 else 0.15,
		"stat_dodge": 0.9 if stats.get("stat_dodge", 0) < 60 else 0.0,
		"stat_crit_chance": 0.25,
		"stat_range": 0.06 if stats.get("stat_range", 0) < 30 else 0.0,
		"stat_harvesting": (1.1 if stats.get("stat_harvesting", 0) < 25 else 0.35) if wave <= 6 else (0.25 if wave <= 12 else 0.0),
		"stat_luck": 0.3 if wave < 10 and stats.get("stat_luck", 0) < 15 else 0.05
	}

	if brawler:
		result["stat_ranged_damage"] = 0.0
		result["stat_melee_damage"] = 6.0 if stats.get("stat_melee_damage",0) < 5 + wave else 2.0
		result["stat_attack_speed"] = 1.2 if stats.get("stat_attack_speed",0) < 30 else 0.6
		result["stat_dodge"] = 2.0 if stats.get("stat_dodge",0) < 60 else 0.0
		result["stat_range"] = 0.35 if stats.get("stat_range",0) < 0 else 0.08
	return result

func score_effects(effects, stats, wave):
	var w = weights(stats, wave)
	var score = 0.0
	for e in effects:
		# Pilot continuously moves; a conditional stationary bonus is not active armor.
		if e.custom_key == "temp_stats_while_not_moving":
			continue
		if brawler and e.key == "stat_ranged_damage":
			continue
		if not w.has(e.key):
			continue
		var weight = w[e.key]
		# A capped bonus must not make its corresponding drawback free.
		if e.value < 0:
			weight = max(weight, {"stat_max_hp":2.8,"stat_armor":5.0,"stat_ranged_damage":6.0,"stat_melee_damage":4.0,"stat_speed":1.2,"stat_attack_speed":1.0,"stat_lifesteal":2.0}.get(e.key, 0.0))
		score += float(e.value) * weight
	return score


func analyze(states, wave):
	var result = {"wave":wave,"combat_samples":states.size(),"findings":[],"changes":[],"limitations":"One-second samples cannot identify the lethal enemy or exact hit sequence."}
	if states.empty():
		result.findings.append("No combat samples available; no cause inferred.")
		return result
	var last = states.back()
	var stats = last.get("build_stats", {})
	result["last_combat"] = last
	var largest_drop = 0
	var min_fps = 10000
	for i in states.size():
		min_fps = min(min_fps, states[i].get("fps", 60))
		if i > 0 and states[i].get("wave") == states[i-1].get("wave"):
			largest_drop = max(largest_drop, states[i-1].get("hp",0) - states[i].get("hp",0))
	result["largest_sampled_hp_drop"] = largest_drop
	result["min_sampled_fps"] = min_fps
	if stats.get("stat_armor",0) < max(2, wave * 0.5):
		result.findings.append("Armor below pilot target: " + str(stats.get("stat_armor",0)))
		result.changes.append("Raise armor purchase/upgrade priority; reject armor-negative items while under target.")
	if last.get("max_hp",0) + 5 < last.get("raw_max_hp", stats.get("stat_max_hp",0)):
		result.findings.append("Effective max HP below accumulated HP stat; check cap/conditional effects.")
		result.changes.append("Reject HP-cap items and score HP using capped stat.")
	var damage_key = "stat_melee_damage" if brawler else "stat_ranged_damage"
	for key in ["stat_speed","stat_attack_speed",damage_key]:
		var target = {"stat_speed":15,"stat_attack_speed":20,damage_key:max(4,wave-3)}[key]
		if stats.get(key,0) < target:
			result.findings.append(key + " below revision target: " + str(stats.get(key,0)))
			result.changes.append("Review " + key + " sacrifices and candidate offers before another run.")
	if stats.get("stat_lifesteal",0) < 8:
		result.changes.append("Review recovery for melee contact." if brawler else "Prioritize lifesteal for rapid-fire guns when below 8.")
	return result

func should_restart(won, analyzed, recording_ended, elapsed):
	return not won and analyzed and recording_ended and elapsed >= 8.0


func breaks_floor(key, delta, stats, wave):
	var floors = {"stat_speed": min(15.0, wave * 1.5), "stat_ranged_damage": max(0.0, wave - 3.0), "stat_attack_speed": 0.0, "stat_range": -20.0}
	if brawler:
		floors.erase("stat_ranged_damage")
		floors["stat_melee_damage"] = max(0.0,wave-3.0)
		floors["stat_range"] = -50.0
	if not floors.has(key):
		return false
	return delta < 0 and stats.get(key,0) + delta < floors[key]

# Spend a bounded part of the shop's opening funds searching for useful items.
# Keep enough currency to buy an offer instead of consuming everything in rerolls.
func can_reroll(gold, cost, rolls, weapon_count, wave, opening_gold, spent):
	if wave < 8:
		return rolls < (6 if weapon_count < 6 else 3) and (cost == 0 or gold >= 20 + wave * 3 + cost)
	var reserve = 100 + wave * 8
	var budget = max(60.0, opening_gold * 0.35)
	return rolls < 16 and gold >= reserve + cost and spent + cost <= budget

# Same admission rule for marginal weapons and items, before ranking by cost.
func purchase_worthwhile(score, cost):
	return score >= max(4.0, (cost + 15) * 0.04)

# Unmodeled forced low-health wave starts must not be priced as pure max-HP gains.
func forced_low_health_start(effects):
	for effect in effects:
		if effect.key in ["hp_start_next_wave","hp_start_wave"] and effect.value < 0:
			return true
	return false

func unsupported_extra_spawn(effects):
	for effect in effects:
		if effect.key == "extra_enemies_next_wave" and effect.value > 0:
			return true
	return false

# Reward a reachable attack band, never body overlap. All candidates still pay
# the existing full-path collision and projectile penalties.
func engagement_score(distance, reach, health_ratio):
	if health_ratio <= 0.55 or reach <= 90.0 or distance < 90.0:
		return 0.0
	var preferred = max(90.0,reach * 0.85)
	return max(0.0,1.0-abs(distance-preferred)/max(40.0,reach*0.5)) * 160.0

func target_priority(boss, support, spawning, shooting):
	if boss:
		return 4
	if support or spawning:
		return 3
	if shooting:
		return 2
	return 1

func approach_score(before, after, reach, health_ratio):
	if health_ratio <= 0.55 or reach <= 90.0:
		return 0.0
	return clamp(max(0.0,before-reach)-max(0.0,after-reach),-60.0,60.0)
