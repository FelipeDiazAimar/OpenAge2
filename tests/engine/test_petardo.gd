extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const Combat := preload("res://engine/sim/systems/CombatSystem.gd")


func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	return s


func _hit(s: Sim) -> Array:
	var p := s.spawn("petardo", 0, Vector2i(10, 10))
	var b := s.spawn("castillo", 1, Vector2i(20, 20))
	var dmg: Dictionary = s.world.comp(p, "Attack")["params"]["damage"]
	var hp0: int = s.world.comp(b, "Hitpoints")["hp"]
	Combat.apply_damage(s, dmg, b, p)
	return [p, b, hp0]


func test_petardo_dies_on_hit() -> void:
	var s := _sim()
	var res: Array = _hit(s)
	assert_false(s.world.entities.has(res[0]), "el petardo muere tras impactar")


func test_petardo_heavy_building_damage() -> void:
	var s := _sim()
	var res: Array = _hit(s)
	var hp1: int = s.world.comp(res[1], "Hitpoints")["hp"]
	assert_true(int(res[2]) - hp1 >= 500, "edificio recibe daño gordo: %d" % (int(res[2]) - hp1))
