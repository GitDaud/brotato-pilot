extends SceneTree

var failures = 0

func check(condition, label):
	if not condition:
		failures += 1
		printerr("FAIL brawler: " + label)

func _init():
	var policy = load("res://mods-unpacked/Codex-Pilot/strategy.gd").new()
	var ranged_weights = policy.weights({},3)
	check(ranged_weights["stat_ranged_damage"] == 12.0, "case 12")
	policy.brawler = true
	var stats = {"stat_range":-50,"stat_ranged_damage":-50,"stat_melee_damage":4,"stat_dodge":15}
	check(policy.weights(stats,3)["stat_melee_damage"] > policy.weights(stats,3)["stat_attack_speed"], "case 15")
	check(policy.score_effects([{"key":"stat_ranged_damage","value":-10,"custom_key":""}],stats,3) == 0.0, "case 16")
	check(policy.score_effects([{"key":"stat_melee_damage","value":-4,"custom_key":""}],stats,3) < 0.0, "case 17")
	check(not policy.breaks_floor("stat_ranged_damage",-10,stats,3), "case 18")
	check(policy.breaks_floor("stat_melee_damage",-6,stats,3), "case 19")
	check(policy.breaks_floor("stat_range",-1,stats,3), "case 20")
	check(policy.weights({"stat_dodge":60},20)["stat_dodge"] == 0.0, "case 21")
	var dodge_gain = {"key":"stat_dodge","value":9,"custom_key":""}
	check(policy.score_effects([dodge_gain],{"stat_dodge":55},16) == 10.0, "55 to 64 counts only five usable dodge")
	check(policy.score_effects([dodge_gain],{"stat_dodge":60},16) == 0.0, "capped dodge has no gain")
	check(policy.score_effects([{"key":"stat_dodge","value":-10,"custom_key":""}],{"stat_dodge":64},16) == -12.0, "dodge loss below cap still costs value")
	check(policy.movement_target_allowed(true,420.0), "nearby tree pursued")
	check(not policy.movement_target_allowed(true,421.0), "distant tree does not suppress XP")
	check(policy.movement_target_allowed(false,2000.0), "distant boss still eligible")
	var in_range = policy.engagement_score(130,160,1.0)
	check(in_range > policy.engagement_score(300,160,1.0), "case 23")
	check(policy.engagement_score(60,160,1.0) == 0.0, "case 24")
	check(policy.engagement_score(130,160,0.4) == 0.0, "case 25")
	check(policy.engagement_score(100,80,1.0) == 0.0, "case 26")
	var result = policy.analyze([{"wave":3,"build_stats":stats}],3)
	check(not "stat_ranged_damage" in JSON.print(result.findings), "case 28")
	check(policy.target_priority(true,false,false,false) > policy.target_priority(false,true,true,true), "boss above support")
	check(policy.target_priority(false,true,false,false) > policy.target_priority(false,false,false,true), "support above shooter")
	check(policy.target_priority(false,false,true,false) > policy.target_priority(false,false,false,false), "spawner above ordinary")
	check(policy.target_priority(false,false,false,true) > policy.target_priority(false,false,false,false), "shooter above ordinary")
	check(policy.approach_score(900,850,160,1.0) > 0.0, "approach distant target")
	check(policy.approach_score(900,950,160,1.0) < 0.0, "reject retreat from distant target")
	check(policy.approach_score(900,850,160,0.4) == 0.0, "low health disables pursuit")
	check(policy.approach_score(130,110,160,1.0) == 0.0, "no reward for closing inside reach")
	check(policy.target_priority(true,false,false,false) > policy.target_priority(false,false,false,false,true), "boss above tree")
	check(policy.target_priority(false,false,false,false,true) > policy.target_priority(false,true,true,true), "tree above other enemies")
	check(policy.special_item_score("item_coupon",2,20,0) > 4.0, "early coupon pays back")
	check(policy.special_item_score("item_coupon",19,60,0) == 0.0, "late coupon rejected")
	check(policy.special_item_score("item_tree",2,20,0) > 4.0, "early tree investment")
	check(policy.special_item_score("item_tree",19,62,0) == 0.0, "late tree rejected")
	check(policy.special_item_score("item_cute_monkey",5,42,0) > 4.0, "monkey recovery no longer zero")
	check(policy.harvesting_return(0,8,2) > policy.harvesting_return(0,8,15), "harvesting remaining horizon")
	check(policy.harvesting_return(0,8,19) == 0.0, "no spending after final payout")
	check(policy.harvesting_return(8,-10,5) < 0.0, "harvesting loss charged")
	check(policy.weights({"stat_luck":-28},10)["stat_luck"] > policy.weights({"stat_luck":20},10)["stat_luck"], "repair negative luck")
	var boss = load("res://mods-unpacked/Codex-Pilot/boss_model.gd").new()
	var arc = boss.orbit_segments(Vector2.ZERO,Vector2(10,0),Vector2(250,0),1.2,0,250)
	for i in range(arc.size()):
		var segment = arc[i]
		var t = segment[5]
		var expected = Vector2(10,0)*t+Vector2(250,0).rotated(1.2*t)
		check((segment[0]+segment[3]*t).distance_to(expected) < 0.01, "orbit endpoint and moving parent")
	check(boss.charge_segment(Vector2.ZERO,Vector2.RIGHT,750,0.8,0.5).empty(), "charge outside horizon")
	var charge = boss.charge_segment(Vector2(10,0),Vector2.RIGHT,750,0.2,0.5)
	check((charge[0]+charge[3]*0.2).distance_to(Vector2(10,0)) < 0.01, "delayed charge origin")
	check(boss.focus_cost(200,0.2,false,false) < boss.focus_cost(200,0.9,false,false), "finish wounded boss")
	check(boss.focus_cost(200,0.2,true,false) > boss.focus_cost(200,0.2,false,false), "avoid charging boss")
	var hp_effect = {"key":"stat_max_hp","value":4,"custom_key":""}
	check(abs(policy.score_effects([hp_effect],{"stat_max_hp":10,"stat_gains":{"stat_max_hp":0.75}},3)-9.6) < 0.001, "native ranger HP gain multiplier")
	policy.character = "character_chunky"
	check(policy.score_effects([{"key":"stat_speed","value":3,"custom_key":""}],{"stat_speed":0,"stat_gains":{"stat_speed":0}},3) == 0.0, "chunky cannot buy speed gains")
	check(policy.score_effects([{"key":"stat_lifesteal","value":5,"custom_key":""}],{"stat_lifesteal":-100},3) == 0.0, "chunky unusable lifesteal not valued")
	policy.character = "character_apprentice"
	check(policy.weights({},3)["stat_max_hp"] > 3.2, "apprentice offsets HP loss per level")
	if failures > 0:
		quit(1)
		return
	print("PASS brawler: melee scoring, ranged penalty, floors, dodge cap, attack band, contact exclusion, retreat, melee review")
	quit()
