extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const EntityLayer := preload("res://engine/render2d/EntityLayer.gd")
const SelectionOverlay := preload("res://engine/render2d/SelectionOverlay.gd")
const AssetLocator := preload("res://engine/assets/AssetLocator.gd")


func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	return s


func _layer(s: Sim) -> EntityLayer:
	var layer := EntityLayer.new()
	layer.bind(s, AssetLocator.new(), {0: Color.BLUE, 1: Color.RED})
	layer.snapshot()
	layer.sync(1.0, 0.0)
	return layer


func test_foundation_shows_progress() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(11, 12))
	var h := s.place_foundation(0, "casa", Vector2i(12, 12))
	var layer := _layer(s)
	assert_true(layer.views[h].is_under_construction())
	s.queue_command(0, "build", {"ids": [v], "target": h})
	for i in 60:
		s.step()
	layer.sync(1.0, 0.1)
	var p: float = layer.views[h].progress
	assert_true(p > 0.2 and p < 0.4, "avance visible: %f" % p)
	if layer.views[v].has_sprite(): # los PNG del DE los extrae cada jugador
		assert_eq(layer.views[v].current_anim(), "build", "el aldeano usa la animación de construir")
	for i in 200:
		s.step()
	layer.sync(1.0, 0.1)
	assert_false(layer.views[h].is_under_construction())
	layer.free()


func test_ghost_green_and_red() -> void:
	var s := _sim()
	s.spawn("tree", -1, Vector2i(12, 12))
	var layer := _layer(s)
	var def: Dictionary = s.players[0]["defs"].get_def("casa")
	layer.show_ghost(def, Vector2i(12, 12), s.can_place(0, "casa", Vector2i(12, 12)) == "")
	assert_true(layer.ghost.modulate.r > layer.ghost.modulate.g, "rojo sobre un árbol")
	layer.show_ghost(def, Vector2i(20, 20), s.can_place(0, "casa", Vector2i(20, 20)) == "")
	assert_true(layer.ghost.modulate.g > layer.ghost.modulate.r, "verde en casilla libre")
	layer.hide_ghost()
	assert_true(layer.ghost == null)
	layer.free()


func test_rally_flag() -> void:
	var o := SelectionOverlay.new()
	o.set_rally(Vector2(100, 50), Vector2.ZERO)
	assert_eq(o.rally, Vector2(100, 50))
	o.set_rally(null)
	assert_true(o.rally == null)
	o.free()
