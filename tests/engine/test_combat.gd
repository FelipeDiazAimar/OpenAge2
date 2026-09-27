extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const CombatSystem := preload("res://engine/sim/systems/CombatSystem.gd")


func _sim(team1: int = 1) -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", team1)
	return s


func _steps(s: Sim, n: int) -> void:
	for i in n:
		s.step()


func _hp(s: Sim, id: int) -> int:
	return int(s.world.comp(id, "Hitpoints").get("hp", -1))


func test_damage_formula() -> void:
	var r := Registry.new()
	r.load_mods("res://mods")
	var militia: Dictionary = r.get_def("milicia")
	var archer: Dictionary = r.get_def("arquero")
	var house: Dictionary = r.get_def("casa")
	var atk_m: Dictionary = militia["abilities"]["Attack"]["damage"]
	var atk_a: Dictionary = archer["abilities"]["Attack"]["damage"]
	assert_eq(CombatSystem.damage(atk_m, archer, archer["abilities"]["Armor"]["classes"]), 4)
	assert_eq(CombatSystem.damage(atk_m, house, {"melee": 1, "pierce": 0}), 5, "bonus contra edificio")
	assert_eq(CombatSystem.damage(atk_a, militia, militia["abilities"]["Armor"]["classes"]), 3, "4 perforante - 1")
	assert_eq(CombatSystem.damage({"melee": 4}, militia, {"melee": 10}), 1, "mínimo 1")
	var scout: Dictionary = r.get_def("scout")
	assert_eq(CombatSystem.damage(scout["abilities"]["Attack"]["damage"], archer, {}), 5, "bonus 'arquero' vale contra tag 'arqueros'")


func test_melee_kills_villager() -> void:
	var s := _sim()
	var m := s.spawn("milicia", 0, Vector2i(10, 10))
	var v := s.spawn("aldeano", 1, Vector2i(11, 10))
	s.queue_command(0, "attack", {"ids": [m], "target": v})
	_steps(s, 20)
	assert_eq(_hp(s, v), 21, "primer golpe: 4 (se acerca a 0.7 casillas y golpea)")
	_steps(s, 130)
	assert_false(s.world.entities.has(v), "7 golpes de 4 matan 25 HP")
	var ev := s.drain_events()
	assert_eq(ev.size(), 1)
	assert_eq(ev[0]["type"], "death")
	assert_eq(ev[0]["def_id"], "aldeano")
	assert_eq(s.world.comp(m, "Attack")["target"], -1)


func test_chases_target() -> void:
	var s := _sim()
	var m := s.spawn("milicia", 0, Vector2i(5, 5))
	var v := s.spawn("aldeano", 1, Vector2i(12, 5))
	s.queue_command(0, "attack", {"ids": [m], "target": v})
	_steps(s, 120)
	assert_true(_hp(s, v) < 25, "caminó hasta el objetivo y lo golpeó")


func test_archer_projectile_hits() -> void:
	var s := _sim()
	var a := s.spawn("arquero", 0, Vector2i(10, 10))
	var v := s.spawn("aldeano", 1, Vector2i(14, 10))
	s.queue_command(0, "attack", {"ids": [a], "target": v})
	var seen := false
	for i in 12:
		s.step()
		seen = seen or not s.projectiles.is_empty()
	assert_true(seen, "disparó un proyectil")
	assert_eq(_hp(s, v), 21)
	assert_true(s.world.entities[a]["pos"] == Vector2i(10500, 10500), "a distancia no se acerca")


func test_target_dies_midswing_and_projectile_lands_empty() -> void:
	var s := _sim()
	var a := s.spawn("arquero", 0, Vector2i(10, 10))
	var v := s.spawn("aldeano", 1, Vector2i(14, 10))
	s.queue_command(0, "attack", {"ids": [a], "target": v})
	while s.projectiles.is_empty() and s.world.tick < 40:
		s.step()
	assert_false(s.projectiles.is_empty())
	s.world.set_pos(v, Vector2i(30500, 30500))
	_steps(s, 10)
	assert_eq(_hp(s, v), 25, "el proyectil cayó donde estaba: falló")
	s.remove(v)
	_steps(s, 30)
	assert_eq(s.world.comp(a, "Attack")["target"], -1)


func test_villagers_dont_auto_attack() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	var m := s.spawn("milicia", 1, Vector2i(11, 10))
	_steps(s, 60)
	assert_true(_hp(s, v) < 25, "la milicia enemiga ataca sola")
	assert_eq(_hp(s, m), 45, "el aldeano no contraataca solo")


func test_allies_not_attacked() -> void:
	var s := _sim(0)
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	s.spawn("milicia", 1, Vector2i(11, 10))
	_steps(s, 60)
	assert_eq(_hp(s, v), 25)


func test_tower_shoots_enemy_in_range() -> void:
	var s := _sim()
	s.spawn("torre_vigia", 0, Vector2i(10, 10))
	var v := s.spawn("aldeano", 1, Vector2i(16, 10))
	_steps(s, 40)
	assert_true(_hp(s, v) < 25, "la torre dispara sola")
	var far := s.spawn("aldeano", 1, Vector2i(30, 30))
	_steps(s, 40)
	assert_eq(_hp(s, far), 25, "fuera de alcance no")


func test_building_destroyed_unblocks() -> void:
	var s := _sim()
	var m := s.spawn("milicia", 0, Vector2i(10, 12))
	var house := s.spawn("casa", 1, Vector2i(11, 12))
	s.world.comp(house, "Hitpoints")["hp"] = 5
	s.queue_command(0, "attack", {"ids": [m], "target": house})
	_steps(s, 40)
	assert_false(s.world.entities.has(house))
	assert_true(s.grid.is_walkable(Vector2i(11, 12)))
	var ev := s.drain_events()
	assert_eq(ev[ev.size() - 1]["kind"], "building")


func test_attack_command_validation() -> void:
	var s := _sim()
	var m := s.spawn("milicia", 0, Vector2i(10, 10))
	var own := s.spawn("aldeano", 0, Vector2i(11, 10))
	var tree := s.spawn("tree", -1, Vector2i(10, 11))
	var enemy := s.spawn("aldeano", 1, Vector2i(9, 10))
	for t in [own, tree, "x", NAN, 9999]:
		s.queue_command(0, "attack", {"ids": [m], "target": t})
	s.queue_command(1, "attack", {"ids": [m], "target": enemy})
	_steps(s, 3)
	assert_true(s.world.comp(m, "Attack")["target"] == -1 or s.world.comp(m, "Attack")["target"] == enemy, "solo el enemigo (automático) es válido")
	s.queue_command(0, "attack", {"ids": [float(m)], "target": float(enemy)})
	_steps(s, 3)
	assert_eq(s.world.comp(m, "Attack")["target"], enemy)
	assert_true(s.world.comp(m, "Attack")["explicit"])


func test_orders_cancel_each_other() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	var tree := s.spawn("tree", -1, Vector2i(11, 10))
	var enemy := s.spawn("aldeano", 1, Vector2i(10, 11))
	s.queue_command(0, "gather", {"ids": [v], "target": tree})
	_steps(s, 3)
	s.queue_command(0, "attack", {"ids": [v], "target": enemy})
	_steps(s, 3)
	assert_eq(s.world.comp(v, "Gather")["state"], "idle", "atacar cancela recolectar")
	assert_eq(s.world.comp(v, "Attack")["target"], enemy)
	s.queue_command(0, "move", {"ids": [v], "pos": [20500, 20500]})
	_steps(s, 3)
	assert_eq(s.world.comp(v, "Attack")["target"], -1, "mover cancela atacar")
	s.queue_command(0, "stop", {"ids": [v]})
	_steps(s, 3)
	assert_false(s.world.comp(v, "Move")["moving"], "stop detiene")


func test_debug_spawn_only_when_enabled() -> void:
	var s := _sim()
	s.queue_command(0, "debug_spawn", {"def": "milicia", "n": 3, "pos": [20500, 20500], "owner": 0})
	_steps(s, 3)
	assert_eq(s.world.entities.size(), 0)
	s.debug_enabled = true
	s.queue_command(0, "debug_spawn", {"def": "milicia", "n": 3, "pos": [20500, 20500], "owner": 1})
	_steps(s, 3)
	assert_eq(s.world.entities.size(), 3)
	for id in s.world.entities:
		assert_eq(s.world.entities[id]["owner"], 1)


func test_combat_deterministic() -> void:
	var hashes := []
	for run in 2:
		var s := _sim()
		for i in 3:
			s.spawn("arquero", 0, Vector2i(8, 8 + i))
			s.spawn("milicia", 1, Vector2i(14, 8 + i))
		_steps(s, 300)
		hashes.append(s.state_hash())
	assert_eq(hashes[0], hashes[1])
