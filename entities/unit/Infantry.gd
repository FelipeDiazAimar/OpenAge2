extends RefCounted
class_name Infantry
# Infanteria - linea de espadachines + lancero/huscarle (data-driven).
#
# Linea evolutiva (cuartel, investigada una vez, aplica a todas las unidades vivas
# del tipo anterior, estilo AoE2):
#   milicia -> hombre_armas (feudal, 100F 40G) -> espadachin_mandoble
#   (castillos, 200F 65G) -> campeon (imperial, 300F 200G)
# Lancero (bonus vs caballeria 3) y huscarle (anti-arquero, armor_pierce 6)
# son ramas aparte sin evolucion.
#
# Los stats base viven en data/units/*.json; este script solo centraliza la
# progresion para UI/Tech/Ages. Sin randf/Time; puro diccionario + consulta.
# Uso: Infantry.upgrade_cost("milicia") -> {"food": 100, "gold": 40}

const SWORD_LINE: Array[String] = ["milicia", "hombre_armas", "espadachin_mandoble", "campeon"]

const INFANTRY_UNITS: Array[String] = [
	"milicia", "hombre_armas", "espadachin_mandoble", "campeon",
	"lancero", "huscarle",
]

# unit_id (origen) -> {next, cost, requires_age, research_time_sec}.
# Clave siempre en minusculas sin espacios. {} si es fin de linea / rama lateral.
const UPGRADE_LINE := {
	"milicia": {
		"next": "hombre_armas",
		"cost": {"food": 100, "gold": 40},
		"requires_age": "feudal",
		"research_time_sec": 40,
	},
	"hombre_armas": {
		"next": "espadachin_mandoble",
		"cost": {"food": 200, "gold": 65},
		"requires_age": "castillos",
		"research_time_sec": 45,
	},
	"espadachin_mandoble": {
		"next": "campeon",
		"cost": {"food": 300, "gold": 200},
		"requires_age": "imperial",
		"research_time_sec": 100,
	},
	"campeon": {},
	"lancero": {},
	"huscarle": {},
}


## Coste de mejora para pasar de unit_id a su siguiente evolucion.
## Retorna {} si no hay mejora (campeon, lancero, huscarle o id desconocido).
## El diccionario retornado es una copia (seguro para modificar/sumar).
static func upgrade_cost(unit_id: String) -> Dictionary:
	var key := unit_id.to_lower().strip_edges()
	if not UPGRADE_LINE.has(key):
		return {}
	var entry: Dictionary = UPGRADE_LINE[key]
	return (entry.get("cost", {}) as Dictionary).duplicate(true)


## Siguiente unidad en la linea, o "" si es fin de linea / desconocida.
static func upgrade_next(unit_id: String) -> String:
	var key := unit_id.to_lower().strip_edges()
	if not UPGRADE_LINE.has(key):
		return ""
	return str((UPGRADE_LINE[key] as Dictionary).get("next", ""))


## Edad requerida para la mejora, o "" si no hay mejora.
static func upgrade_age(unit_id: String) -> String:
	var key := unit_id.to_lower().strip_edges()
	if not UPGRADE_LINE.has(key):
		return ""
	return str((UPGRADE_LINE[key] as Dictionary).get("requires_age", ""))


## true si la unidad pertenece a la infanteria de cuartel.
static func is_infantry(unit_id: String) -> bool:
	return unit_id.to_lower().strip_edges() in INFANTRY_UNITS
