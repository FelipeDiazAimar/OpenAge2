extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const OK_ROOT := "res://tests/engine/fixtures/mods_ok"
const BAD_ROOT := "res://tests/engine/fixtures/mods_bad"


func _ok() -> Registry:
	var r := Registry.new()
	r.load_mods(OK_ROOT)
	return r


func test_loads_ok_fixture() -> void:
	var r := _ok()
	assert_eq(r.errors, [])
	assert_eq(r.defs.keys().size(), 4, str(r.defs.keys()))
	assert_true(r.has("soldado") and r.has("cuartel") and r.has("edad1") and r.has("torre"))
	assert_false(r.has("unidad_base"), "abstractos fuera de defs")
	assert_true(r.abstract_defs.has("unidad_base"))


func test_mod_order_respects_depends() -> void:
	var r := _ok()
	assert_eq(r.mods.map(func(m): return m["id"]), ["core", "addon"])


func test_extends_merges_and_unions_tags() -> void:
	var s := _ok().get_def("soldado")
	assert_eq(s["abilities"]["Move"], {"speed": 1.0})
	assert_eq(s["tags"], ["unidad", "infanteria"])
	assert_eq(s["pop_cost"], 1)
	assert_false(s.has("extends"))
	assert_false(s.has("abstract"))


func test_patch_from_dependent_mod() -> void:
	var s := _ok().get_def("soldado")
	assert_eq(s["abilities"]["Hitpoints"], {"max": 50})
	assert_eq(s["abilities"]["Attack"]["damage"], {"melee": 4})
	assert_false(s.has("patch"))


func test_ids_of_type_sorted() -> void:
	assert_eq(_ok().ids_of_type("building"), ["cuartel", "torre"])


func test_hash_stable() -> void:
	var a := _ok()
	var b := _ok()
	assert_eq(a.content_hash.length(), 64)
	assert_eq(a.content_hash, b.content_hash)
	var only_core := Registry.new()
	assert_true(only_core.load_mods(OK_ROOT, ["core"]), str(only_core.errors))
	assert_true(only_core.content_hash != a.content_hash)


func test_enabled_without_dependency_fails() -> void:
	var r := Registry.new()
	assert_false(r.load_mods(OK_ROOT, ["addon"]))
	assert_has_error(r.errors, "mod addon: depende de 'core'")


func test_bad_fixture_reports_everything() -> void:
	var r := Registry.new()
	assert_false(r.load_mods(BAD_ROOT))
	assert_has_error(r.errors, "herencia circular")
	assert_has_error(r.errors, "soldado.hp: campo desconocido")
	assert_has_error(r.errors, "cuartel.abilities.Train.units: 'fantasma' no existe")
	assert_has_error(r.errors, "cuartel.abilities.Train.units: 'cuartel' no es de tipo unit")
	assert_has_error(r.errors, "parche sobre 'nadie', que no existe")
	assert_eq(r.content_hash, "")


func test_missing_and_empty_roots() -> void:
	var r := Registry.new()
	assert_false(r.load_mods("res://tests/engine/fixtures/no_existe"))
	assert_has_error(r.errors, "carpeta de mods no encontrada")
	var e := Registry.new()
	assert_false(e.load_mods("res://tests/engine/fixtures/mods_empty"))
	assert_has_error(e.errors, "no hay mods")


func test_parse_json_text_bom_and_errors() -> void:
	var ok := Registry.parse_json_text("﻿{\"id\": \"x\"}")
	assert_true(ok["ok"])
	assert_eq(ok["data"], {"id": "x"})
	var bad := Registry.parse_json_text("{\n\"id\": ")
	assert_false(bad["ok"])
	assert_true("línea" in str(bad["error"]), str(bad["error"]))


func test_malformed_manifest_fields_are_errors() -> void:
	var r := Registry.new()
	assert_false(r.load_mods("res://tests/engine/fixtures/mods_bad_manifest"))
	assert_has_error(r.errors, "mod.json: depends debe ser lista de textos")
	assert_has_error(r.errors, "mod.json: priority debe ser número")


func test_effect_and_unique_references_are_checked() -> void:
	var r := Registry.new()
	assert_false(r.load_mods(BAD_ROOT))
	assert_has_error(r.errors, "mala.effects[0].target: término desconocido 'tags:infanteria'")
	assert_has_error(r.errors, "mala.effects[1].target: 'fantasma' no existe")
	assert_has_error(r.errors, "mala.effects[2].to: 'no_existe' no existe")
	assert_has_error(r.errors, "mala.effects[3].target: tipo desconocido 'dragon'")
	assert_has_error(r.errors, "unico.abilities.Unique.civ: 'atlantes' no existe")


func test_tag_selector_without_matches_is_warning() -> void:
	var r := Registry.new()
	assert_true(r.load_mods("res://tests/engine/fixtures/mods_warn"), str(r.errors))
	assert_has_error(r.warnings, "t.effects[0].target: tag 'nadie' no coincide con ninguna entidad")
