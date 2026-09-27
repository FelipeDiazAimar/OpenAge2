extends "res://tests/engine/TestCase.gd"

const MATCH := "res://game/scenes/Match.tscn"


func _spawn() -> Node:
	var m = load(MATCH).instantiate()
	Engine.get_main_loop().root.add_child(m)
	return m


func _despawn(m: Node) -> void:
	if m.get_parent() != null:
		m.get_parent().remove_child(m)
	m.queue_free()


func test_esc_without_sim_no_crash() -> void:
	var m = load(MATCH).instantiate()
	assert_true(m.sim == null, "sin entrar en arbol sim es null")
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_ESCAPE
	m._unhandled_input(ev)
	m._process(0.016)
	assert_true(m.sim == null, "sigue sin sim y sin crash")
	m.free()


func test_issue_move_without_selection_noop() -> void:
	var m = _spawn()
	m.select([])
	var pending_before: int = m.sim._pending.size()
	m.issue_move(Vector2(70, 70))
	assert_eq(m.sim._pending.size(), pending_before, "sin seleccion no encola")
	assert_true(m.selected.is_empty(), "seleccion sigue vacia")
	_despawn(m)


func test_select_unknown_ids_no_crash() -> void:
	var m = _spawn()
	m.select([999999, -42])
	assert_eq(m.selected.size(), 2, "conserva ids aunque no existan")
	for id in m.layer.views:
		assert_false(m.layer.views[id].selected, "ninguna vista queda seleccionada")
	m.issue_move(Vector2(70, 70))
	for i in 5:
		m.tick_once()
	assert_true(m.sim.world.entities.size() > 0, "entidades intactas")
	_despawn(m)


func test_tick_once_advances_sim() -> void:
	var m = _spawn()
	var t: int = m.sim.world.tick
	var n: int = m.sim.world.entities.size()
	m.tick_once()
	assert_eq(m.sim.world.tick, t + 1, "tick avanza en 1")
	assert_eq(m.sim.world.entities.size(), n, "sin spawns laterales")
	_despawn(m)
