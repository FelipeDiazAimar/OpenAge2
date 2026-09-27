extends "res://tests/engine/TestCase.gd"

const Patch := preload("res://engine/data/Patch.gd")


func _defs() -> Dictionary:
	return {
		"milicia": {"id": "milicia", "type": "unit", "tags": ["infanteria"], "cost": {"food": 60, "gold": 20},
			"abilities": {"Attack": {"damage": {"melee": 4}}, "Hitpoints": {"max": 45}}},
		"arquero": {"id": "arquero", "type": "unit", "tags": ["arqueros"], "cost": {"wood": 25, "gold": 45},
			"abilities": {"Attack": {"damage": {"pierce": 4}}, "Hitpoints": {"max": 30}}},
		"aldeano": {"id": "aldeano", "type": "unit", "tags": ["aldeano"], "cost": {"food": 50},
			"abilities": {"Hitpoints": {"max": 25}}},
		"casa": {"id": "casa", "type": "building", "tags": ["edificio"], "abilities": {"Hitpoints": {"max": 550}}},
	}


func test_selectors() -> void:
	var d := _defs()
	assert_eq(Patch.select(d, "tag:infanteria|tag:arqueros"), ["arquero", "milicia"])
	assert_eq(Patch.select(d, "type:unit&tag:aldeano"), ["aldeano"])
	assert_eq(Patch.select(d, "id:casa"), ["casa"])
	assert_eq(Patch.select(d, "type:unit"), ["aldeano", "arquero", "milicia"])
	assert_eq(Patch.select(d, "tag:nada"), [])


func test_add_creates_leaf_and_skips_missing_ability() -> void:
	var d := _defs()
	var errs := Patch.apply(d, {"target": "type:unit", "op": "add", "path": "abilities.Attack.damage.melee", "value": 1})
	assert_eq(errs, [])
	assert_eq(d["milicia"]["abilities"]["Attack"]["damage"], {"melee": 5})
	assert_eq(d["arquero"]["abilities"]["Attack"]["damage"], {"pierce": 4, "melee": 1})
	assert_false(d["aldeano"]["abilities"].has("Attack"), "sin Attack no se toca")


func test_mul_skips_missing_leaf() -> void:
	var d := _defs()
	Patch.apply(d, {"target": "type:unit", "op": "mul", "path": "cost.wood", "value": 0.9})
	assert_eq(d["arquero"]["cost"]["wood"], 22.5)
	assert_false(d["milicia"]["cost"].has("wood"))


func test_set_append_remove() -> void:
	var d := _defs()
	Patch.apply(d, {"target": "id:casa", "op": "set", "path": "abilities.Hitpoints.max", "value": 600})
	assert_eq(d["casa"]["abilities"]["Hitpoints"]["max"], 600)
	Patch.apply(d, {"target": "id:casa", "op": "append", "path": "tags", "value": "civil"})
	Patch.apply(d, {"target": "id:casa", "op": "append", "path": "tags", "value": "civil"})
	assert_eq(d["casa"]["tags"], ["edificio", "civil"])
	Patch.apply(d, {"target": "id:casa", "op": "remove", "path": "tags", "value": "edificio"})
	assert_eq(d["casa"]["tags"], ["civil"])
	Patch.apply(d, {"target": "id:milicia", "op": "remove", "path": "cost.gold"})
	assert_eq(d["milicia"]["cost"], {"food": 60})


func test_type_mismatch_reports_error() -> void:
	var d := _defs()
	var errs := Patch.apply(d, {"target": "id:milicia", "op": "add", "path": "tags", "value": 1})
	assert_has_error(errs, "milicia.tags: add sobre un valor no numérico")
