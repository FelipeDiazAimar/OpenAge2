class_name BuildingDefs
extends Node

const DATA_DIR := "res://data/buildings"

const BUILDING_IDS: Array[String] = [
	"casa",
	"centro_urbano",
	"cuartel",
	"campamento_maderero",
	"molino",
	"campamento_minero",
	"granja",
	"mercado",
	"monasterio",
	"herreria",
	"universidad",
	"muelle",
]

var _defs: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	_defs.clear()
	for id: String in BUILDING_IDS:
		var path := "%s/%s.json" % [DATA_DIR, id]
		if not FileAccess.file_exists(path):
			push_warning("BuildingDefs: falta %s" % path)
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_warning("BuildingDefs: no se pudo abrir %s" % path)
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary and (parsed as Dictionary).has("id"):
			_defs[str((parsed as Dictionary)["id"])] = parsed
		else:
			push_warning("BuildingDefs: JSON inválido en %s" % path)


func get_def(id: String) -> Dictionary:
	return _defs.get(id, {})


func has_id(id: String) -> bool:
	return _defs.has(id)


func all_ids() -> Array:
	var out: Array = _defs.keys()
	out.sort()
	return out


func cost_of(id: String) -> Dictionary:
	var d: Dictionary = get_def(id)
	return d.get("cost", {})


func hp_of(id: String) -> int:
	var d: Dictionary = get_def(id)
	return int(d.get("hp", 0))
