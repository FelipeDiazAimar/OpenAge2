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


func test_bar_refreshes_per_tick_not_per_frame() -> void:
	var m = load(MATCH).instantiate()
	Engine.get_main_loop().root.add_child(m)
	m.sim.add_res(m.local_pid, "wood", 50000)
	m._process(0.001)
	assert_eq(m.bar.text_of("wood"), "Madera 200 (0)", "un frame sin tick no recalcula la barra")
	m._process(0.2)
	assert_eq(m.bar.text_of("wood"), "Madera 250 (0)", "tras un tick sí")
	m.queue_free()


func test_match_has_resources_and_smart_gather() -> void:
	var m = load(MATCH).instantiate()
	Engine.get_main_loop().root.add_child(m)
	var trees := 0
	for id in m.sim.world.entities:
		if m.sim.world.entities[id]["def_id"] == "tree":
			trees += 1
	assert_true(trees > 300, "bosques generados: %d" % trees)
	assert_eq(m.bar.text_of("wood"), "Madera 200 (0)")
	var v := -1
	for id in m.sim.world.entities:
		var e: Dictionary = m.sim.world.entities[id]
		if e["def_id"] == "aldeano" and e["owner"] == m.local_pid and (v < 0 or id < v):
			v = id
	var vpos: Vector2i = m.sim.world.entities[v]["pos"]
	var tree := -1
	var best := 0.0
	for id in m.sim.world.entities:
		var e: Dictionary = m.sim.world.entities[id]
		if e["def_id"] != "tree":
			continue
		var d := Vector2(e["pos"]).distance_to(Vector2(vpos))
		if tree < 0 or d < best:
			tree = id
			best = d
	m.select([v])
	m.smart_command(m.layer.views[tree].position + Vector2(0, -10))
	for i in 3:
		m.tick_once()
	assert_true(m.sim.world.comp(v, "Gather")["state"] != "idle", "clic derecho sobre árbol = recolectar")
	m.queue_free()
