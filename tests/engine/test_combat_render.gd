extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const EntityLayer := preload("res://engine/render2d/EntityLayer.gd")
const ProjectileLayer := preload("res://engine/render2d/ProjectileLayer.gd")
const AssetLocator := preload("res://engine/assets/AssetLocator.gd")


func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	return s


func test_corpse_from_death_event_then_expires() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 1, Vector2i(10, 10))
	var layer := EntityLayer.new()
	layer.bind(s, AssetLocator.new(["user://nada"], ["user://nada"]), {0: Color.BLUE, 1: Color.RED})
	layer.snapshot()
	layer.sync(1.0, 0.0)
	s.kill(v)
	layer.sync(1.0, 0.1)
	assert_false(layer.views.has(v))
	assert_eq(layer.corpses.size(), 1, "cadáver creado")
	for i in 60:
		layer.sync(1.0, 0.1)
	assert_eq(layer.corpses.size(), 0, "desaparece tras CORPSE_TIME")
	layer.free()


func test_projectiles_are_drawn() -> void:
	var s := _sim()
	var a := s.spawn("arquero", 0, Vector2i(10, 10))
	var v := s.spawn("aldeano", 1, Vector2i(14, 10))
	s.queue_command(0, "attack", {"ids": [a], "target": v})
	var pl := ProjectileLayer.new()
	pl.bind(s)
	var max_drawn := 0
	for i in 12:
		s.step()
		pl.sync(0.5)
		max_drawn = maxi(max_drawn, pl.drawn)
	assert_eq(max_drawn, 1)
	pl.free()


func test_damaged_units_show_hp_ratio() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 1, Vector2i(10, 10))
	var layer := EntityLayer.new()
	layer.bind(s, AssetLocator.new(["user://nada"], ["user://nada"]), {0: Color.BLUE, 1: Color.RED})
	layer.snapshot()
	s.world.comp(v, "Hitpoints")["hp"] = 10
	layer.sync(1.0, 0.0)
	assert_true(absf(layer.views[v].hp_ratio - 0.4) < 0.001)
	layer.free()


func test_no_ghost_corpse_without_death_anim() -> void:
	var s := _sim()
	var m := s.spawn("milicia", 1, Vector2i(10, 10))
	var layer := EntityLayer.new()
	layer.bind(s, AssetLocator.new(["user://nada"], ["user://nada"]), {0: Color.BLUE, 1: Color.RED})
	layer.snapshot()
	layer.sync(1.0, 0.0)
	s.kill(m)
	layer.sync(1.0, 0.1)
	assert_eq(layer.corpses.size(), 0, "sin animación de muerte no queda una unidad 'fantasma' de pie")
	layer.free()
