extends "res://tests/engine/TestCase.gd"

const MatchConfig := preload("res://game/MatchConfig.gd")
const SETUP := "res://game/scenes/Setup.tscn"
const MATCH := "res://game/scenes/Match.tscn"


func test_setup_lists_civs_and_players() -> void:
	MatchConfig.reset()
	var s = load(SETUP).instantiate()
	Engine.get_main_loop().root.add_child(s)
	assert_true(s.civs.size() >= 5, "civilizaciones: %d" % s.civs.size())
	assert_eq(s.rows.size(), 2, "por defecto tú contra la IA")
	assert_eq(s.chosen_slots()[0]["civ"], "britones")
	assert_false(s.chosen_slots()[0]["ai"], "el jugador 1 es humano")
	assert_true(s.chosen_slots()[1]["ai"])
	s._add.pressed.emit()
	s._add.pressed.emit()
	s._add.pressed.emit()
	assert_eq(s.rows.size(), 4, "hasta 4 jugadores")
	s._remove.pressed.emit()
	assert_eq(s.rows.size(), 3)
	s.queue_free()


func test_match_uses_config() -> void:
	MatchConfig.reset()
	MatchConfig.slots = [{"civ": "godos", "team": 0}, {"civ": "vikingos", "team": 1, "ai": true}, {"civ": "francos", "team": 1, "ai": true}]
	MatchConfig.pop_max = 200
	MatchConfig.lake = false
	MatchConfig.map_seed = 777
	var m = load(MATCH).instantiate()
	Engine.get_main_loop().root.add_child(m)
	assert_eq(m.sim.players.size(), 3)
	assert_eq(str(m.sim.players[0]["civ"]), "godos")
	assert_eq(m.ais.size(), 2, "dos rivales IA")
	assert_eq(m.sim.pop_max, 200)
	assert_false(m.sim.grid.is_water(Vector2i(72, 72)), "sin lago")
	assert_eq(m.sim.team_of(1), m.sim.team_of(2), "aliados en el equipo 2")
	m.queue_free()
	MatchConfig.reset()


func test_filter_never_changes_the_chosen_civ() -> void:
	MatchConfig.reset()
	var s = load(SETUP).instantiate()
	Engine.get_main_loop().root.add_child(s)
	if s._filter != null:
		s._filter.text = "fran"
		s._on_civ_filter("fran")
		s._on_civ_filter("zzzzz")
		s._on_civ_filter("")
	assert_eq(s.chosen_slots()[0]["civ"], "britones", "el filtro no cambia la civ")
	assert_eq(s.chosen_slots()[1]["civ"], "francos")
	s._add.pressed.emit()
	assert_true(s.chosen_slots()[2]["ai"], "los jugadores 2 a 4 son IA en local")
	s.queue_free()
