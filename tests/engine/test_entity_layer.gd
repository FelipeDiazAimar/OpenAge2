extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const EntityLayer := preload("res://engine/render2d/EntityLayer.gd")
const AssetLocator := preload("res://engine/assets/AssetLocator.gd")
const Iso := preload("res://engine/render2d/Iso.gd")


func _world() -> Array:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	var v := s.spawn("aldeano", 0, Vector2i(16, 16))
	var e := s.spawn("aldeano", 1, Vector2i(30, 30))
	var layer := EntityLayer.new()
	layer.bind(s, AssetLocator.new(["user://no_hay_sprites"]), {0: Color.BLUE, 1: Color.RED})
	layer.snapshot()
	layer.sync(1.0, 0.0)
	return [s, layer, tc, v, e]


func test_views_follow_sim_with_interpolation() -> void:
	var w := _world()
	var s: Sim = w[0]
	var layer = w[1]
	var v: int = w[3]
	assert_eq(layer.views.size(), 3)
	assert_eq(layer.views[v].position, Iso.milli_to_screen(Vector2i(16500, 16500)))
	s.queue_command(0, "move", {"ids": [v], "pos": [26500, 16500]})
	for i in 3:
		layer.snapshot()
		s.step()
	var prev: Vector2i = Vector2i(16500 + 80, 16500)
	var cur: Vector2i = s.world.entities[v]["pos"]
	layer.sync(0.5, 0.05)
	assert_true(layer.views[v].position.is_equal_approx(Iso.to_screen((Vector2(prev) + Vector2(cur)) / 2000.0)))
	assert_eq(layer.views[v].current_slot(), Iso.dir16(Iso.to_screen(Vector2(1, 0))))
	layer.free()


func test_pick_and_rect_selection() -> void:
	var w := _world()
	var layer = w[1]
	var tc: int = w[2]
	var v: int = w[3]
	var e: int = w[4]
	assert_eq(layer.pick(layer.views[v].position + Vector2(2, -10)), v)
	assert_eq(layer.pick(layer.views[tc].position), tc)
	assert_eq(layer.pick(Vector2(-5000, -5000)), -1)
	var all := Rect2(Vector2(-10000, -10000), Vector2(20000, 20000))
	assert_eq(layer.ids_in_rect(all, 0), [v], "solo unidades propias con Move")
	assert_eq(layer.ids_in_rect(all, 1), [e])
	layer.set_selected([v])
	assert_true(layer.views[v].selected)
	assert_false(layer.views[tc].selected)
	layer.free()


func test_despawned_entities_lose_view() -> void:
	var w := _world()
	var s: Sim = w[0]
	var layer = w[1]
	var e: int = w[4]
	s.world.despawn(e)
	layer.sync(1.0, 0.0)
	assert_false(layer.views.has(e))
	layer.free()
