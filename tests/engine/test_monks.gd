extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const MonkSystem := preload("res://engine/sim/systems/MonkSystem.gd")


func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	return s


func _steps(s: Sim, n: int) -> void:
	for i in n:
		s.step()


func test_convert_takes_between_4_and_10_seconds() -> void:
	var s := _sim()
	var monk := s.spawn("monje", 0, Vector2i(10, 10))
	var u := s.spawn("arquero", 1, Vector2i(14, 10))
	s.queue_command(0, "convert", {"ids": [monk], "target": u})
	_steps(s, 40)
	assert_eq(int(s.world.entities[u]["owner"]), 1, "antes de 4 s no convierte")
	_steps(s, 70)
	assert_eq(int(s.world.entities[u]["owner"]), 0, "a los 10 s como máximo, convertida")
	assert_eq(s.world.comp(u, "Attack")["params"], s.players[0]["defs"].get_def("arquero")["abilities"]["Attack"], "stats del nuevo dueño")
	assert_true(int(s.world.comp(monk, "Convert")["faith"]) > 0, "recarga la fe")
	assert_true(s.drain_events().any(func(e): return e["type"] == "converted" and e["id"] == u))


func test_convert_rules() -> void:
	var s := _sim()
	var monk := s.spawn("monje", 0, Vector2i(10, 10))
	var other_monk := s.spawn("monje", 1, Vector2i(12, 10))
	var ram := s.spawn("ariete", 1, Vector2i(12, 12))
	var house := s.spawn("casa", 1, Vector2i(14, 14))
	var mine := s.spawn("milicia", 0, Vector2i(9, 9))
	assert_eq(MonkSystem.convert_error(s, monk, other_monk), "no convierte monjes")
	assert_eq(MonkSystem.convert_error(s, monk, ram), "requiere Redención")
	assert_eq(MonkSystem.convert_error(s, monk, house), "solo unidades")
	assert_eq(MonkSystem.convert_error(s, monk, mine), "no es enemiga")
	s.players[0]["defs"].researched.append("redencion")
	assert_eq(MonkSystem.convert_error(s, monk, ram), "")


func test_converted_unit_drops_its_orders() -> void:
	var s := _sim()
	var monk := s.spawn("monje", 0, Vector2i(10, 10))
	var u := s.spawn("milicia", 1, Vector2i(13, 10))
	var victim := s.spawn("aldeano", 0, Vector2i(20, 20))
	s.queue_command(1, "attack", {"ids": [u], "target": victim})
	s.queue_command(0, "convert", {"ids": [monk], "target": u})
	_steps(s, 120)
	assert_eq(int(s.world.entities[u]["owner"]), 0, "convertida (en alcance: 10 s como máximo)")
	assert_eq(s.world.comp(u, "Attack")["target"], -1, "ya no ataca al que ahora es aliado")
	assert_eq(int(s.world.comp(victim, "Hitpoints")["hp"]), 25)


func test_heal_injured_ally() -> void:
	var s := _sim()
	var monk := s.spawn("monje", 0, Vector2i(10, 10))
	var u := s.spawn("milicia", 0, Vector2i(13, 10))
	s.world.comp(u, "Hitpoints")["hp"] = 10
	s.queue_command(0, "heal", {"ids": [monk], "target": u})
	_steps(s, 100)
	var hp := int(s.world.comp(u, "Hitpoints")["hp"])
	assert_true(hp > 20, "cura: %d" % hp)
	_steps(s, 300)
	assert_eq(int(s.world.comp(u, "Hitpoints")["hp"]), 45)
	assert_eq(s.world.comp(monk, "Heal")["target"], -1, "al terminar, suelta")


func test_idle_monk_auto_heals() -> void:
	var s := _sim()
	var monk := s.spawn("monje", 0, Vector2i(10, 10))
	var u := s.spawn("milicia", 0, Vector2i(12, 10))
	s.world.comp(u, "Hitpoints")["hp"] = 20
	var enemy := s.spawn("aldeano", 1, Vector2i(7, 15)) # fuera de la vista de la milicia
	s.world.comp(enemy, "Hitpoints")["hp"] = 20
	_steps(s, 200)
	assert_true(int(s.world.comp(u, "Hitpoints")["hp"]) > 20, "cura sola a la propia")
	assert_true(int(s.world.comp(enemy, "Hitpoints")["hp"]) <= 20, "no al enemigo")


func test_monks_deterministic() -> void:
	var hashes := []
	for run in 2:
		var s := _sim()
		var monk := s.spawn("monje", 0, Vector2i(10, 10))
		var u := s.spawn("arquero", 1, Vector2i(14, 10))
		s.queue_command(0, "convert", {"ids": [monk], "target": u})
		_steps(s, 150)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])
