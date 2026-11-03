extends SceneTree
var loot_cells = 0
var has_loot_target = false
var loot_target = Vector2.ZERO
class MockScene:
	extends Node
	var _active_golds = []
	var _consumables = []
class MockGold:
	extends Node2D
	var already_picked_up = false
	var attracted_by = null
	var value = 1
	func has_healing_effect():
		return true
func _init():
	var cells = {}
	for i in 5000:
		var angle = i * 2.399963
		var point = Vector2(cos(angle), sin(angle)) * (30 + i % 390)
		add_threat(cells, point, Vector2.ZERO, 72.0)
	assert(cells.size() <= 100)
	var threats = cells.values()
	var started = OS.get_ticks_usec()
	for iteration in 100:
		for i in 24:
			var v = Vector2.RIGHT.rotated(TAU * i / 24.0)
			for horizon in [0.18, 0.4, 0.65]:
				danger_at(v * 300 * horizon, threats)
	print("DENSE: 5000 threats => ", cells.size(), " cells; scoring mean ms=", (OS.get_ticks_usec()-started)/100000.0)
	var near = {}
	add_threat(near, Vector2(60, 0), Vector2.ZERO, 72.0)
	assert(danger_at(Vector2(55,0), near.values()) > danger_at(Vector2(-100,0), near.values()))
	add_threat(near, Vector2(60,0), Vector2.ZERO,58.0,true)
	assert(near.size() == 2)
	var scene = MockScene.new()
	var right = MockGold.new()
	right.position = Vector2(150,0)
	var left = MockGold.new()
	left.position = Vector2(-150,0)
	scene._active_golds = [right,left]
	refresh_loot(scene,Vector2.ZERO,near.values(),Rect2(-1000,-1000,2000,2000))
	assert(has_loot_target and loot_target.x < 0)
	left.already_picked_up = true
	refresh_loot(scene,Vector2.ZERO,[],Rect2(-1000,-1000,2000,2000))
	assert(loot_target.x > 0)
	right.visible = false
	refresh_loot(scene,Vector2.ZERO,[],Rect2(-1000,-1000,2000,2000))
	assert(not has_loot_target)
	right.visible = true
	right.position = Vector2(100, 0)
	scene._active_golds = []
	scene._consumables = [right]
	refresh_loot(scene,Vector2.ZERO,[],Rect2(-1000,-1000,2000,2000),0.3)
	assert(has_loot_target and loot_target.x == 100)
	refresh_loot(scene,Vector2.ZERO,[],Rect2(-1000,-1000,2000,2000),1.0)
	assert(not has_loot_target)
	right.free()
	left.free()
	scene.free()
	print("PASS: density bound, danger ordering, bullet separation, safe loot, picked/hidden filtering")
	quit()

func add_threat(cells, point, pos, radius, bullet = false):
	if pos.distance_squared_to(point) > 420.0 * 420.0:
		return
	var cell = ((point - pos) / 96.0).floor()
	var key = Vector3(cell.x, cell.y, 1 if bullet else 0)
	if not cells.has(key):
		cells[key] = [point, radius, 1]
	else:
		var entry = cells[key]
		entry[2] += 1
		entry[1] = max(entry[1], radius)
		if pos.distance_squared_to(point) < pos.distance_squared_to(entry[0]):
			entry[0] = point

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

