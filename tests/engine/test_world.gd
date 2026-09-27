extends "res://tests/engine/TestCase.gd"

const World := preload("res://engine/sim/World.gd")
const SpatialHash := preload("res://engine/sim/SpatialHash.gd")

const SOLDADO := {"id": "soldado", "type": "unit",
	"abilities": {"Hitpoints": {"max": 45.0}, "Move": {"speed": 0.9}}}
const ARBOL := {"id": "arbol", "type": "resource",
	"abilities": {"ResourceSource": {"resource": "wood", "amount": 100.0, "rate_key": "wood"}}}


func test_spawn_creates_components() -> void:
	var w := World.new()
	var a := w.spawn(SOLDADO, 0, Vector2i(1000, 2000))
	var t := w.spawn(ARBOL, -1, Vector2i(5000, 5000))
	assert_eq([a, t], [1, 2])
	assert_eq(w.entities[a]["def_id"], "soldado")
	assert_eq(w.entities[a]["pos"], Vector2i(1000, 2000))
	var hp := w.comp(a, "Hitpoints")
	assert_eq(typeof(hp["hp"]), TYPE_INT)
	assert_eq(hp["hp"], 45)
	assert_eq(hp["max"], 45)
	assert_eq(w.comp(a, "Move")["params"]["speed"], 0.9)
	assert_eq(w.comp(t, "ResourceSource")["amount"], 100000)
	assert_true(w.has_ability(a, "Move"))
	assert_false(w.has_ability(t, "Move"))


func test_ids_with_sorted_after_despawn() -> void:
	var w := World.new()
	for i in 3:
		w.spawn(SOLDADO, 0, Vector2i(0, 0))
	w.despawn(2)
	var d := w.spawn(SOLDADO, 1, Vector2i(0, 0))
	assert_eq(d, 4, "los ids no se reciclan")
	assert_eq(w.ids_with("Move"), [1, 3, 4])
	assert_false(w.entities.has(2))
	assert_eq(w.comp(2, "Move"), {})


func test_spatial_query_radius_including_negative() -> void:
	var s := SpatialHash.new()
	s.insert(1, Vector2i(0, 0))
	s.insert(2, Vector2i(3000, 4000))
	s.insert(3, Vector2i(10000, 0))
	s.insert(4, Vector2i(-1500, -1500))
	assert_eq(s.query_radius(Vector2i(0, 0), 5000), [1, 2, 4])
	s.move(3, Vector2i(1000, 0))
	assert_eq(s.query_radius(Vector2i(0, 0), 1000), [1, 3])
	s.remove(1)
	assert_eq(s.query_radius(Vector2i(0, 0), 1000), [3])
	assert_eq(s.count(), 3)


func test_set_pos_updates_spatial() -> void:
	var w := World.new()
	var a := w.spawn(SOLDADO, 0, Vector2i(0, 0))
	w.set_pos(a, Vector2i(20000, 20000))
	assert_eq(w.spatial.query_radius(Vector2i(0, 0), 1000), [])
	assert_eq(w.spatial.query_radius(Vector2i(20000, 20000), 0), [a])


func test_state_hash_deterministic() -> void:
	var a := World.new()
	var b := World.new()
	for w in [a, b]:
		w.spawn(SOLDADO, 0, Vector2i(1000, 1000))
		w.spawn(ARBOL, -1, Vector2i(3000, 3000))
	assert_eq(a.state_hash(), b.state_hash())
	assert_eq(a.state_hash().length(), 64)
	b.set_pos(1, Vector2i(1001, 1000))
	assert_true(a.state_hash() != b.state_hash())
