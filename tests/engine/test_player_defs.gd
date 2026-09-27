extends "res://tests/engine/TestCase.gd"

const PlayerDefs := preload("res://engine/data/PlayerDefs.gd")


func _defs() -> Dictionary:
	return {
		"milicia": {"id": "milicia", "type": "unit", "tags": ["infanteria"], "cost": {"food": 60, "gold": 20},
			"abilities": {"Attack": {"damage": {"melee": 4}}, "Hitpoints": {"max": 45}}},
		"hombre_armas": {"id": "hombre_armas", "type": "unit", "tags": ["infanteria"], "cost": {"food": 60, "gold": 20},
			"abilities": {"Attack": {"damage": {"melee": 6}}, "Hitpoints": {"max": 55}}},
		"huscarle": {"id": "huscarle", "type": "unit", "tags": ["infanteria"], "abilities": {"Hitpoints": {"max": 60}}},
		"forja": {"id": "forja", "type": "tech", "effects": [
			{"target": "tag:infanteria", "op": "add", "path": "abilities.Attack.damage.melee", "value": 1}]},
		"hombre_armas_up": {"id": "hombre_armas_up", "type": "tech", "effects": [
			{"op": "replace_entity", "from": "milicia", "to": "hombre_armas"}]},
		"godos": {"id": "godos", "type": "civ", "disabled": [], "effects": [
			{"target": "tag:infanteria", "op": "mul", "path": "cost.food", "value": 0.8}]},
		"britones": {"id": "britones", "type": "civ", "disabled": ["huscarle"], "effects": []},
	}


func test_civ_effects_and_disabled() -> void:
	var g := PlayerDefs.new(_defs(), "godos")
	assert_eq(g.get_def("milicia")["cost"]["food"], 48.0)
	assert_true(g.is_available("huscarle"))
	var b := PlayerDefs.new(_defs(), "britones")
	assert_eq(b.get_def("milicia")["cost"]["food"], 60)
	assert_false(b.is_available("huscarle"))
	assert_false(b.is_available("no_existe"))


func test_research_is_per_player() -> void:
	var src := _defs()
	var p0 := PlayerDefs.new(src, "britones")
	var p1 := PlayerDefs.new(src, "britones")
	assert_eq(p0.research("forja"), [])
	assert_eq(p0.get_def("milicia")["abilities"]["Attack"]["damage"]["melee"], 5)
	assert_eq(p1.get_def("milicia")["abilities"]["Attack"]["damage"]["melee"], 4)
	assert_eq(src["milicia"]["abilities"]["Attack"]["damage"]["melee"], 4, "registry intacto")
	assert_has_error(p0.research("forja"), "forja ya investigada")
	assert_has_error(p0.research("milicia"), "milicia no es una tecnología")


func test_replace_entity_upgrade() -> void:
	var p := PlayerDefs.new(_defs(), "britones")
	assert_eq(p.resolve_unit("milicia"), "milicia")
	p.research("hombre_armas_up")
	assert_eq(p.resolve_unit("milicia"), "hombre_armas")


func test_enable_disable_effects() -> void:
	var p := PlayerDefs.new(_defs(), "britones")
	p.apply_effects([{"target": "id:huscarle", "op": "enable"}])
	assert_true(p.is_available("huscarle"))
	p.apply_effects([{"target": "tag:infanteria", "op": "disable"}])
	assert_false(p.is_available("milicia"))
