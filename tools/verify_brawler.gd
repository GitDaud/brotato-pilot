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
	if failures > 0:
		quit(1)
		return
	print("PASS brawler: melee scoring, ranged penalty, floors, dodge cap, attack band, contact exclusion, retreat, melee review")
	quit()
