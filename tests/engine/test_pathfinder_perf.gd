extends "res://tests/engine/TestCase.gd"
## Presupuesto de rendimiento del A* en el mapa real (144x144). Límites
## holgados para no ser frágiles, pero muy por debajo de la versión con
## diccionarios (81 ms esquina a esquina, 391 ms a zona encerrada).

const Grid := preload("res://engine/sim/Grid.gd")
const Pathfinder := preload("res://engine/sim/Pathfinder.gd")


func _ms(g, a: Vector2i, b: Vector2i) -> float:
	g.region_of(Vector2i.ZERO) # etiquetado de regiones: costo aparte (una vez por cambio)
	var t0 := Time.get_ticks_usec()
	var p := Pathfinder.find_path(g, a, b)
	assert_false(p.is_empty())
	return (Time.get_ticks_usec() - t0) / 1000.0


func test_corner_to_corner_under_budget() -> void:
	var g := Grid.new(144, 144)
	g.block_rect(Vector2i(60, 10), Vector2i(4, 120))
	var ms := _ms(g, Vector2i(2, 2), Vector2i(140, 140))
	assert_true(ms < 30.0, "esquina a esquina: %.1f ms" % ms)


func test_unreachable_under_budget() -> void:
	var g := Grid.new(144, 144)
	for i in range(90, 111):
		g.set_blocked(Vector2i(i, 90), true)
		g.set_blocked(Vector2i(i, 110), true)
		g.set_blocked(Vector2i(90, i), true)
		g.set_blocked(Vector2i(110, i), true)
	var ms := _ms(g, Vector2i(2, 2), Vector2i(100, 100))
	assert_true(ms < 60.0, "zona encerrada: %.1f ms" % ms)


func test_region_labeling_under_budget() -> void:
	var g := Grid.new(144, 144)
	g.block_rect(Vector2i(60, 10), Vector2i(4, 120))
	var t0 := Time.get_ticks_usec()
	g.region_of(Vector2i.ZERO)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_true(ms < 40.0, "etiquetado 144x144: %.1f ms" % ms)
