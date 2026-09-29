extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const MapGen := preload("res://engine/sim/MapGen.gd")
const AIPlayer := preload("res://engine/ai/AIPlayer.gd")

const STARTS: Array[Vector2i] = [Vector2i(39, 39), Vector2i(105, 105)]


## Partida estándar 144×144 (como Match): TC, 3 aldeanos y explorador.
func _match(r: Registry) -> Sim:
	var s := Sim.new(r, 144, 144)
	for i in 2:
		s.add_player(i, ["britones", "francos"][i], i)
		s.spawn("centro_urbano", i, STARTS[i] - Vector2i(2, 2))
		for off in [Vector2i(3, -1), Vector2i(-1, 3), Vector2i(3, 3)]:
			s.spawn("aldeano", i, STARTS[i] + off)
		s.spawn("scout", i, STARTS[i] + Vector2i(-4, -1))
	MapGen.generate(s, 1234, STARTS)
	return s


func _run(s: Sim, ais: Array, n: int) -> void:
	for t in n:
		s.step()
		for ai in ais:
			ai.tick()


func _count(s: Sim, pid: int, def_id: String, built_only := true) -> int:
	var n := 0
	for id in s.world.ids_with("Hitpoints"):
		var e: Dictionary = s.world.entities[id]
		if int(e["owner"]) == pid and e["def_id"] == def_id and (not built_only or s.is_built(id)):
			n += 1
	return n


func test_ai_economy() -> void:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := _match(r)
	var ai := AIPlayer.new(s, 0)
	var housed := 0
	for t in 4500:
		s.step()
		ai.tick()
		var p: Vector2i = s.population(0)
		if p.x >= p.y:
			housed += 1
	assert_true(_count(s, 0, "aldeano") >= 14, "aldeanos: %d" % _count(s, 0, "aldeano"))
	assert_true(_count(s, 0, "casa") >= 2, "casas: %d" % _count(s, 0, "casa"))
	assert_true(_count(s, 0, "campamento_maderero") >= 1)
	assert_true(housed < 900, "casi nunca sin casas (%d ticks)" % housed)


func test_ai_does_not_mutate_shared_defs() -> void:
	var r := Registry.new()
	r.load_mods("res://mods")
	var before: Dictionary = r.get_def("feudal")["cost"].duplicate(true)
	var s := _match(r)
	_run(s, [AIPlayer.new(s, 0)], 2000)
	assert_eq(r.get_def("feudal")["cost"], before, "la IA no toca las definiciones")


func test_ai_ages_up_and_attacks() -> void:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 80, 80)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	s.spawn("centro_urbano", 0, Vector2i(10, 10))
	s.spawn("molino", 0, Vector2i(18, 10))
	s.spawn("campamento_maderero", 0, Vector2i(10, 18))
	s.spawn("cuartel", 0, Vector2i(20, 18))
	for i in 4:
		s.spawn("casa", 0, Vector2i(4, 4 + 3 * i))
	for i in 20:
		s.spawn("aldeano", 0, Vector2i(24 + i % 5, 24 + i / 5))
	for k in ["food", "wood", "gold", "stone"]:
		s.players[0]["res"][k] = 3000 * 1000
	var enemy_tc := s.spawn("centro_urbano", 1, Vector2i(60, 60))
	var ai := AIPlayer.new(s, 0)
	_run(s, [ai], 1600)
	assert_eq(s.age_of(0), 1, "avanza a Feudal")
	for i in 10:
		s.spawn("milicia", 0, Vector2i(30 + i % 5, 30 + i / 5))
	_run(s, [ai], 1500)
	var hp := int(s.world.comp(enemy_tc, "Hitpoints")["hp"]) if s.world.entities.has(enemy_tc) else 0
	assert_true(hp < 2400, "ataca al enemigo: HP del TC %d" % hp)


func test_ai_deterministic() -> void:
	var r := Registry.new()
	r.load_mods("res://mods")
	var hashes := []
	for run in 2:
		var s := _match(r)
		_run(s, [AIPlayer.new(s, 0), AIPlayer.new(s, 1)], 1500)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])


func test_match_has_ai_opponent() -> void:
	var m = load("res://game/scenes/Match.tscn").instantiate()
	Engine.get_main_loop().root.add_child(m)
	assert_eq(m.ais.size(), 1, "el jugador 2 es la IA")
	var tc := -1
	for id in m.sim.world.entities:
		var e: Dictionary = m.sim.world.entities[id]
		if e["def_id"] == "centro_urbano" and int(e["owner"]) == 1:
			tc = id
	for i in 30:
		m.tick_once()
	assert_true((m.sim.world.comp(tc, "Queue")["items"] as Array).size() > 0, "la IA ya entrena aldeanos")
	m.queue_free()
