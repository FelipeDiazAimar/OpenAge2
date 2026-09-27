extends "res://tests/engine/TestCase.gd"

const Schemas := preload("res://engine/data/Schemas.gd")


func _milicia() -> Dictionary:
	return {
		"id": "milicia", "type": "unit", "name": "Milicia", "_comment": "ok",
		"tags": ["infanteria"], "cost": {"food": 60, "gold": 20},
		"train_time": 21, "pop_cost": 1, "requires": {"age": "alta_edad_media"},
		"abilities": {
			"Hitpoints": {"max": 45},
			"Armor": {"classes": {"melee": 0, "pierce": 1}},
			"Move": {"speed": 0.9},
			"Attack": {"damage": {"melee": 4, "edificio": 2}, "range": 0, "reload": 2.0},
		},
	}


func test_valid_unit_has_no_errors() -> void:
	assert_eq(Schemas.validate_entity(_milicia(), "m.json"), [])


func test_unknown_type_ability_and_field() -> void:
	var e := _milicia()
	e["hp"] = 45
	e["abilities"]["Volar"] = {}
	e["abilities"]["Move"]["turbo"] = 1
	var errs := Schemas.validate_entity(e, "m.json")
	assert_has_error(errs, "m.json: milicia.hp: campo desconocido")
	assert_has_error(errs, "milicia.abilities.Volar: habilidad desconocida")
	assert_has_error(errs, "milicia.abilities.Move.turbo: campo desconocido")
	var bad := {"id": "x", "type": "dragon"}
	assert_has_error(Schemas.validate_entity(bad, "x.json"), "tipo desconocido 'dragon'")


func test_missing_required() -> void:
	var e := _milicia()
	e["abilities"]["Attack"].erase("reload")
	e.erase("train_time")
	var errs := Schemas.validate_entity(e, "m.json")
	assert_has_error(errs, "milicia.abilities.Attack.reload: falta campo obligatorio")
	assert_has_error(errs, "milicia.train_time: falta campo obligatorio")


func test_abstract_skips_required() -> void:
	var base := {"id": "infanteria_base", "type": "unit", "abstract": true,
		"abilities": {"Garrisonable": {}, "Attack": {"damage": {"melee": 1}}}}
	assert_eq(Schemas.validate_entity(base, "b.json"), [])


func test_int_accepts_whole_float_rejects_fraction() -> void:
	var e := _milicia()
	e["pop_cost"] = 1.0
	assert_eq(Schemas.validate_entity(e, "m.json"), [])
	e["pop_cost"] = 1.5
	assert_has_error(Schemas.validate_entity(e, "m.json"), "milicia.pop_cost: debe ser entero")


func test_res_map_and_requires() -> void:
	var e := _milicia()
	e["cost"] = {"madera": 10}
	e["requires"] = {"edad": "feudal"}
	var errs := Schemas.validate_entity(e, "m.json")
	assert_has_error(errs, "recurso desconocido 'madera'")
	assert_has_error(errs, "clave desconocida 'edad'")


func test_effects() -> void:
	assert_eq(Schemas.validate_effect({"target": "tag:infanteria", "op": "add", "path": "abilities.Attack.damage.melee", "value": 1}), "")
	assert_eq(Schemas.validate_effect({"op": "replace_entity", "from": "milicia", "to": "hombre_armas"}), "")
	assert_eq(Schemas.validate_effect({"target": "id:x", "op": "disable"}), "")
	assert_true("op desconocida" in Schemas.validate_effect({"target": "id:x", "op": "explode"}))
	assert_true("value debe ser número" in Schemas.validate_effect({"target": "id:x", "op": "mul", "path": "cost.wood", "value": "mucho"}))
	var tech := {"id": "forja", "type": "tech", "research_time": 50, "at": "herreria",
		"effects": [{"target": "tag:infanteria", "op": "bad"}]}
	assert_has_error(Schemas.validate_entity(tech, "t.json"), "forja.effects: efecto 0: op desconocida")


func test_terrain_schema() -> void:
	var t := {"id": "grass", "type": "terrain", "name": "Pasto", "texture": "terrain:g_gr2", "color": "#87a244"}
	assert_eq(Schemas.validate_entity(t, "t.json"), [])
	t.erase("texture")
	assert_has_error(Schemas.validate_entity(t, "t.json"), "grass.texture: falta campo obligatorio")


func test_terrain_texture_ref_and_color_are_checked() -> void:
	var t := {"id": "nieve", "type": "terrain", "texture": "g_sno", "color": "blanquito"}
	var errs := Schemas.validate_entity(t, "n.json")
	assert_has_error(errs, "nieve.texture: debe empezar con 'terrain:'")
	assert_has_error(errs, "nieve.color: color inválido 'blanquito'")
