extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const ResourceBar := preload("res://engine/ui/ResourceBar.gd")


func test_bar_shows_resources_counts_and_pop() -> void:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.spawn("centro_urbano", 0, Vector2i(10, 10))
	var v := s.spawn("aldeano", 0, Vector2i(19, 12))
	var tree := s.spawn("tree", -1, Vector2i(20, 12))
	var bar := ResourceBar.new()
	bar.setup(s, 0)
	assert_eq(bar.text_of("wood"), "Madera 200 (0)")
	assert_eq(bar.text_of("gold"), "Oro 100 (0)")
	assert_eq(bar.text_of("pop"), "Población 1/5")
	s.queue_command(0, "gather", {"ids": [v], "target": tree})
	for i in 3:
		s.step()
	s.add_res(0, "wood", 5000)
	bar.refresh()
	assert_eq(bar.text_of("wood"), "Madera 205 (1)")
	bar.free()
