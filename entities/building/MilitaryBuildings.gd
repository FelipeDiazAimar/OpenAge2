extends Node
# MilitaryBuildings - requisitos por edad de edificios militares AoE2.
# Fuente de verdad de datos: data/buildings/*.json (campo "requires_age").
# Esta clase es solo helper determinista (sin estado) para HUD/IA/tests:
# valida si un edificio militar es construible segun la edad actual.
# Orden de edades (GameManager.AGE_ORDER): alta_edad_media < feudal < castillos < imperial.

class_name MilitaryBuildings

const AGE_ORDER := ["alta_edad_media", "feudal", "castillos", "imperial"]

# Requisito minimo por edificio militar. Debe coincidir con los JSON.
const AGE_REQUIREMENTS := {
	"cuartel": "alta_edad_media",
	"arqueria": "feudal",
	"establo": "feudal",
	"torre_vigia": "feudal",
	"muro": "feudal",
	"puerta": "feudal",
	"taller_asedio": "castillos",
	"castillo": "castillos",
}

const MILITARY_IDS := [
	"cuartel", "arqueria", "establo", "taller_asedio",
	"castillo", "torre_vigia", "muro", "puerta",
]


static func get_required_age(building_id: String) -> String:
	return str(AGE_REQUIREMENTS.get(building_id.to_lower().strip_edges(), ""))


static func is_military_building(building_id: String) -> bool:
	return building_id.to_lower().strip_edges() in MILITARY_IDS


static func age_index(age_id: String) -> int:
	return AGE_ORDER.find(age_id.to_lower().strip_edges())


## True si `current_age` cumple el requisito del edificio. Edad desconocida -> false.
static func can_build(building_id: String, current_age: String) -> bool:
	var req := get_required_age(building_id)
	if req.is_empty():
		return false
	var req_i := age_index(req)
	var cur_i := age_index(current_age)
	if req_i < 0 or cur_i < 0:
		return false
	return cur_i >= req_i


## Lista de ids militares disponibles en `current_age` (ordenada, determinista).
static func available_for_age(current_age: String) -> Array:
	var out: Array = []
	for bid in MILITARY_IDS:
		if can_build(str(bid), current_age):
			out.append(bid)
	return out
