extends "res://tests/engine/TestCase.gd"

const Merge := preload("res://engine/data/Merge.gd")


func test_deep_merge_merges_dicts_replaces_arrays() -> void:
	var base := {"a": {"x": 1, "y": 2}, "l": [1, 2], "s": "base"}
	var over := {"a": {"y": 3}, "l": [9], "n": true}
	var out := Merge.deep_merge(base, over)
	assert_eq(out, {"a": {"x": 1, "y": 3}, "l": [9], "s": "base", "n": true})
	assert_eq(base, {"a": {"x": 1, "y": 2}, "l": [1, 2], "s": "base"}, "base no se muta")


func test_deep_merge_copies_nested_values() -> void:
	var over := {"a": {"k": [1]}}
	var out := Merge.deep_merge({}, over)
	out["a"]["k"].append(2)
	assert_eq(over, {"a": {"k": [1]}}, "over no se comparte")


func test_path_get_has() -> void:
	var d := {"abilities": {"Attack": {"range": 5.0}}}
	assert_eq(Merge.path_get(d, "abilities.Attack.range"), 5.0)
	assert_eq(Merge.path_get(d, "abilities.Move.speed", -1), -1)
	assert_true(Merge.path_has(d, "abilities.Attack"))
	assert_false(Merge.path_has(d, "abilities.Attack.range.x"))


func test_path_set_creates_intermediates_and_erase() -> void:
	var d := {}
	Merge.path_set(d, "abilities.Attack.damage.edificio", 2)
	assert_eq(d, {"abilities": {"Attack": {"damage": {"edificio": 2}}}})
	assert_true(Merge.path_erase(d, "abilities.Attack.damage.edificio"))
	assert_eq(d, {"abilities": {"Attack": {"damage": {}}}})
	assert_false(Merge.path_erase(d, "no.existe"))
