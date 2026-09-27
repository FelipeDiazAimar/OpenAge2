extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const TerrainLayer := preload("res://engine/render2d/TerrainLayer.gd")
const AssetLocator := preload("res://engine/assets/AssetLocator.gd")


func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.spawn("tree", -1, Vector2i(10, 10))
	s.spawn("tree", -1, Vector2i(0, 0))
	return s


func test_control_map_follows_trees() -> void:
	var s := _sim()
	var c := TerrainLayer.build_control(s, 7)
	assert_eq(c.get_size(), Vector2i(40, 40))
	assert_true(c.get_pixel(10, 10).b > 0.95, "bajo el árbol")
	assert_true(c.get_pixel(11, 10).b > 0.5, "borde del bosque")
	assert_true(c.get_pixel(0, 0).b > 0.95, "árbol en la esquina sin salirse")
	assert_true(c.get_pixel(30, 30).b < 0.01, "lejos de árboles")
	assert_eq(c.get_data(), TerrainLayer.build_control(s, 7).get_data(), "determinista")


func test_setup_without_textures_uses_fallback() -> void:
	var s := _sim()
	var t := TerrainLayer.new()
	t.setup(s, s.registry, AssetLocator.new(["user://nada"], ["user://nada"]), 7)
	var tex: Texture2D = t.material_param("tex_0")
	assert_true(tex != null, "textura de respaldo")
	var px := tex.get_image().get_pixel(0, 0)
	assert_true(px.is_equal_approx(Color("#87a244")), "color del pasto: %s" % px)
	assert_eq(t.material_param("map_size"), Vector2(40, 40))
	t.free()
