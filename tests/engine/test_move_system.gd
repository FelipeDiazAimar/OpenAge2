extends "res://tests/engine/TestCase.gd"

const World := preload("res://engine/sim/World.gd")
const Grid := preload("res://engine/sim/Grid.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")

const ALDEANO := {"id": "aldeano", "type": "unit",
	"abilities": {"Hitpoints": {"max": 25}, "Move": {"speed": 0.8}}}


func _setup() -> Array:
	var w := World.new()
	var g := Grid.new(40, 40)
	var id := w.spawn(ALDEANO, 0, Grid.center_of(Vector2i(5, 5)))
	return [w, g, id]


func test_walks_straight_at_speed() -> void:
	var s := _setup()
	var w: World = s[0]
	var id: int = s[2]
	MoveSystem.order_move(w, s[1], id, Grid.center_of(Vector2i(15, 5)))
	assert_true(w.comp(id, "Move")["moving"])
	for i in 124:
		MoveSystem.step(w)
	assert_eq(w.entities[id]["pos"], Vector2i(5500 + 124 * 80, 5500))
	MoveSystem.step(w)
	assert_eq(w.entities[id]["pos"], Vector2i(15500, 5500), "10 casillas a 80 milésimas/tick = 125 ticks")
	assert_false(w.comp(id, "Move")["moving"])
	assert_eq(w.comp(id, "Move")["facing"], Vector2i(80, 0), "último tramo: 80 milésimas hacia +x")


func test_exact_destination_inside_tile() -> void:
	var s := _setup()
	var w: World = s[0]
	var id: int = s[2]
	MoveSystem.order_move(w, s[1], id, Vector2i(8200, 5900))
	for i in 200:
		MoveSystem.step(w)
	assert_eq(w.entities[id]["pos"], Vector2i(8200, 5900))


func test_same_tile_order_moves_inside_tile() -> void:
	var s := _setup()
	var w: World = s[0]
	var id: int = s[2]
	MoveSystem.order_move(w, s[1], id, Vector2i(5900, 5100))
	for i in 20:
		MoveSystem.step(w)
	assert_eq(w.entities[id]["pos"], Vector2i(5900, 5100))


func test_new_order_replaces_old() -> void:
	var s := _setup()
	var w: World = s[0]
	var id: int = s[2]
	MoveSystem.order_move(w, s[1], id, Grid.center_of(Vector2i(30, 5)))
	for i in 10:
		MoveSystem.step(w)
	MoveSystem.order_move(w, s[1], id, Grid.center_of(Vector2i(5, 20)))
	for i in 400:
		MoveSystem.step(w)
	assert_eq(w.entities[id]["pos"], Grid.center_of(Vector2i(5, 20)))
