extends "res://tests/engine/TestCase.gd"

const MATCH := "res://game/scenes/Match.tscn"


func test_match_spawns_and_moves() -> void:
	var m = load(MATCH).instantiate()
	Engine.get_main_loop().root.add_child(m)
	assert_eq(m.sim.players.size(), 2)
	var villagers: Array = []
	var tcs := 0
	for id in m.sim.world.entities:
		var d: String = m.sim.world.entities[id]["def_id"]
		if d == "aldeano" and m.sim.world.entities[id]["owner"] == m.local_pid:
			villagers.append(id)
		elif d == "centro_urbano":
			tcs += 1
	assert_eq(tcs, 2)
	assert_eq(villagers.size(), 3)
	villagers.sort()
	m.select([villagers[0]])
	assert_true(m.layer.views[villagers[0]].selected)
	var start: Vector2i = m.sim.world.entities[villagers[0]]["pos"]
	var goal := Vector2(start) / 1000.0 + Vector2(6, 0)
	m.issue_move(goal)
	for i in 120:
		m.tick_once()
	var end: Vector2i = m.sim.world.entities[villagers[0]]["pos"]
	assert_true(Vector2(end).distance_to(goal * 1000.0) < 2.0, "llegó: %s" % end)
	m.queue_free()
