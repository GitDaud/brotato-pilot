extends SceneTree

func _init():
	var policy = load("F:/codex-project/tudou/mods-unpacked/Codex-Pilot/strategy.gd").new()
	var low_hp = {"stat_max_hp":24,"stat_armor":2,"stat_speed":33,"stat_harvesting":61,"stat_ranged_damage":4}
	var hp = policy.score_effects([{"key":"stat_max_hp","value":9}],low_hp,10)
	var speed = policy.score_effects([{"key":"stat_speed","value":9}],low_hp,10)
	var harvest = policy.score_effects([{"key":"stat_harvesting","value":8}],low_hp,10)
	assert(hp > speed and hp > harvest)
	assert(policy.score_effects([{"key":"stat_speed","value":-10}],low_hp,10) < -10)
	var early = policy.score_effects([{"key":"stat_harvesting","value":5}],{},2)
	var late = policy.score_effects([{"key":"stat_harvesting","value":5}],{},18)
	assert(early > late)
	assert(policy.score_effects([{"key":"stat_ranged_damage","value":2}],{},3) > policy.score_effects([{"key":"stat_percent_damage","value":5}],{},3))
	assert(policy.score_effects([{"key":"stat_lifesteal","value":2}],{"stat_lifesteal":4},10) > policy.score_effects([{"key":"stat_lifesteal","value":2}],{"stat_lifesteal":30},10))
	print("PASS strategy: W10 defense > excess speed/economy; downside retained; early economy; flat ranged damage; lifesteal saturation")
	quit()
