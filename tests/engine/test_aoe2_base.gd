extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const PlayerDefs := preload("res://engine/data/PlayerDefs.gd")


func _reg() -> Registry:
	var r := Registry.new()
	r.load_mods("res://mods")
	return r


func test_aoe2_base_loads_without_errors() -> void:
	var r := _reg()
	assert_eq(r.errors, [])
	assert_eq(r.ids_of_type("unit").size(), 114)
	assert_eq(r.ids_of_type("building").size(), 20)
	assert_eq(r.ids_of_type("resource").size(), 8)
	assert_eq(r.ids_of_type("age").size(), 4)
	assert_eq(r.ids_of_type("civ").size(), 50)
	assert_eq(r.content_hash.length(), 64)


func test_key_gameplay_data() -> void:
	var r := _reg()
	var aldeano := r.get_def("aldeano")
	assert_eq(aldeano["abilities"]["Gather"]["rates"]["wood"], 0.39)
	assert_eq(aldeano["abilities"]["Gather"]["capacity"], 10)
	assert_true(aldeano["tags"].has("aldeano") and aldeano["tags"].has("unidad"))
	assert_true(aldeano["abilities"].has("Garrisonable"))
	assert_true(r.get_def("cuartel")["abilities"]["Train"]["units"].has("milicia"))
	assert_true(r.get_def("establo")["abilities"]["Train"]["units"].has("scout"))
	assert_eq(r.get_def("centro_urbano")["abilities"]["DropSite"]["accepts"], ["wood", "food", "gold", "stone"])
	assert_eq(r.get_def("casa")["abilities"]["ProvidesPop"]["amount"], 5)
	assert_true(r.get_def("herreria")["abilities"]["Research"]["techs"].has("forja"))


func test_civs_and_techs_apply() -> void:
	var r := _reg()
	var brit := PlayerDefs.new(r.defs, "britones")
	assert_eq(brit.get_def("arquero")["cost"]["wood"], 22.5)
	assert_false(brit.is_available("paladin_franco"))
	assert_true(brit.is_available("arquero_tiro_largo"))
	var fr := PlayerDefs.new(r.defs, "francos")
	assert_true(fr.is_available("paladin_franco"))
	assert_false(fr.is_available("arquero_tiro_largo"))
	var before: float = fr.get_def("milicia")["abilities"]["Attack"]["damage"]["melee"]
	assert_eq(fr.research("forja"), [])
	assert_eq(fr.get_def("milicia")["abilities"]["Attack"]["damage"]["melee"], before + 1)


func test_hash_is_stable_between_loads() -> void:
	assert_eq(_reg().content_hash, _reg().content_hash)


func test_terrains_defined() -> void:
	var r := _reg()
	assert_eq(r.ids_of_type("terrain"), ["dirt", "forest_floor", "grass", "grass_dry"])
	assert_eq(r.get_def("grass")["texture"], "terrain:g_gr2")
