extends Node
class_name Ages
# Ages - helper del arbol tecnologico por edades (determinista, solo lectura).
# Lee res://data/ages/tech_tree_full.json (con fallback embebido identico).
# NADA de randf/randi/Time/SceneTreeTimer: comparaciones de indice y listas
# ordenadas alfabeticamente. Pensado para HUD, IA y validacion en ticks.
#
# Uso:
#   Ages.is_unlocked("feudal", "feudal") -> true
#   Ages.is_unlocked("alta_edad_media", "feudal") -> false
#   Ages.available_buildings("britones", "feudal") -> ["arqueria", ...]
#   Ages.available_units("godos", "castillos") -> [...]
#   Ages.available_techs("imperial") -> [...]

const AGE_ORDER := ["alta_edad_media", "feudal", "castillos", "imperial"]
const TECH_TREE_PATH := "res://data/ages/tech_tree_full.json"
const FACTIONS_DIR := "res://data/factions"

# Fallback si tech_tree_full.json no es legible. Debe coincidir con el JSON.
const FALLBACK_BUILDINGS := {
	"casa": {"requires_age": "alta_edad_media"},
	"centro_urbano": {"requires_age": "alta_edad_media"},
	"cuartel": {"requires_age": "alta_edad_media"},
	"granja": {"requires_age": "alta_edad_media"},
	"arqueria": {"requires_age": "feudal"},
	"establo": {"requires_age": "feudal"},
	"herreria": {"requires_age": "feudal"},
	"mercado": {"requires_age": "feudal"},
	"torre_vigilancia": {"requires_age": "feudal"},
	"castillo": {"requires_age": "castillos"},
	"monasterio": {"requires_age": "castillos"},
	"taller_asedio": {"requires_age": "castillos"},
	"universidad": {"requires_age": "castillos"},
	"maravilla": {"requires_age": "imperial"},
}
const FALLBACK_UNITS := {
	"aldeano": {"requires_age": "alta_edad_media", "trained_at": "centro_urbano", "civs": "all", "unique_for": ""},
	"milicia": {"requires_age": "alta_edad_media", "trained_at": "cuartel", "civs": "all", "unique_for": ""},
	"arquero": {"requires_age": "feudal", "trained_at": "arqueria", "civs": "all", "unique_for": ""},
	"carreta_comercio": {"requires_age": "feudal", "trained_at": "mercado", "civs": "all", "unique_for": ""},
	"jinete": {"requires_age": "feudal", "trained_at": "establo", "civs": "all", "unique_for": ""},
	"lancero": {"requires_age": "feudal", "trained_at": "cuartel", "civs": "all", "unique_for": ""},
	"ariete": {"requires_age": "castillos", "trained_at": "taller_asedio", "civs": "all", "unique_for": ""},
	"ballestero": {"requires_age": "castillos", "trained_at": "arqueria", "civs": "all", "unique_for": ""},
	"hombre_de_armas": {"requires_age": "castillos", "trained_at": "cuartel", "civs": "all", "unique_for": ""},
	"monje": {"requires_age": "castillos", "trained_at": "monasterio", "civs": "all", "unique_for": ""},
	"arquero_tiro_largo": {"requires_age": "imperial", "trained_at": "castillo", "civs": ["britones"], "unique_for": "britones"},
	"catafracta": {"requires_age": "imperial", "trained_at": "castillo", "civs": ["bizantinos"], "unique_for": "bizantinos"},
	"huscarle": {"requires_age": "imperial", "trained_at": "castillo", "civs": ["godos"], "unique_for": "godos"},
	"paladin_franco": {"requires_age": "imperial", "trained_at": "castillo", "civs": ["francos"], "unique_for": "francos"},
}
const FALLBACK_TECHS := {
	"telar": {"requires_age": "alta_edad_media"},
	"edad_feudal": {"requires_age": "alta_edad_media"},
	"carretilla": {"requires_age": "feudal"},
	"forja": {"requires_age": "feudal"},
	"edad_castillos": {"requires_age": "feudal"},
	"cota_malla": {"requires_age": "castillos"},
	"fervor": {"requires_age": "castillos"},
	"edad_imperial": {"requires_age": "castillos"},
	"elite_unica": {"requires_age": "imperial"},
	"quimica": {"requires_age": "imperial"},
}
const FALLBACK_CIVS := {
	"bizantinos": {"tech_tree": ["monje", "arquero", "jinete"], "unique_unit": "catafracta"},
	"britones": {"tech_tree": ["arquero", "milicia", "monje"], "unique_unit": "arquero_tiro_largo"},
	"francos": {"tech_tree": ["jinete", "milicia", "monje"], "unique_unit": "paladin_franco"},
	"godos": {"tech_tree": ["milicia", "lancero"], "unique_unit": "huscarle"},
}

static var _db: Dictionary = {}


static func age_index(age_id: String) -> int:
	return AGE_ORDER.find(_norm(age_id))


static func is_unlocked(player_age: String, requires_age: String) -> bool:
	# requires_age vacio = disponible desde el inicio. Edad desconocida = bloqueado.
	var req := _norm(requires_age)
	if req.is_empty():
		return true
	var pi := age_index(player_age)
	var ri := AGE_ORDER.find(req)
	if pi < 0 or ri < 0:
		return false
	return pi >= ri


static func available_buildings(civ: String, age: String) -> Array:
	# Edificios compartidos por todas las civs: acumulados hasta `age`, ordenados.
	# `civ` se normaliza y se reserva para futuras vetas por civ (hoy no hay ninguna).
	_norm(civ)
	var db := _load_db()
	var buildings: Dictionary = db.get("buildings", {})
	var out: Array = []
	for bid in buildings.keys():
		var req := str((buildings[bid] as Dictionary).get("requires_age", ""))
		if is_unlocked(age, req):
			out.append(str(bid))
	out.sort()
	return out


static func available_units(civ: String, age: String) -> Array:
	# Unidades acumuladas hasta `age`, filtradas por civ. Ordenadas.
	# Regla: "civs" == "all" -> todas; si es lista -> solo esas;
	# las unicas (unique_for) solo su civ. Civ desconocida -> solo "all".
	var c := _norm(civ)
	var db := _load_db()
	var units: Dictionary = db.get("units", {})
	var out: Array = []
	for uid in units.keys():
		var u: Dictionary = units[uid]
		if not is_unlocked(age, str(u.get("requires_age", ""))):
			continue
		if _unit_allowed_for(u, c):
			out.append(str(uid))
	out.sort()
	return out


static func available_techs(age: String) -> Array:
	# Tecnologias investigables con `age` actual (acumuladas). Ordenadas.
	var db := _load_db()
	var techs: Dictionary = db.get("techs", {})
	var out: Array = []
	for tid in techs.keys():
		if is_unlocked(age, str((techs[tid] as Dictionary).get("requires_age", ""))):
			out.append(str(tid))
	out.sort()
	return out


static func unlocks_in_age(age: String) -> Dictionary:
	# Lo que se habilita EXACTAMENTE en `age` (no acumulado).
	# {buildings: [...], units: [...], techs: [...]} ordenados. Edad
	# desconocida -> las tres listas vacias.
	var a := _norm(age)
	if AGE_ORDER.find(a) < 0:
		return {"buildings": [], "units": [], "techs": []}
	var db := _load_db()
	var out := {"buildings": [], "units": [], "techs": []}
	for kind in ["buildings", "units", "techs"]:
		var section: Dictionary = db.get(kind, {})
		for key in section.keys():
			if _norm(str((section[key] as Dictionary).get("requires_age", ""))) == a:
				(out[kind] as Array).append(str(key))
		(out[kind] as Array).sort()
	return out


static func get_requires_age(kind: String, entry_id: String) -> String:
	# kind: "building" | "unit" | "tech" (acepta plural). "" si no existe.
	var section_key := _section_for(kind)
	if section_key.is_empty():
		return ""
	var db := _load_db()
	var section: Dictionary = db.get(section_key, {})
	var e: Dictionary = section.get(_norm(entry_id), {})
	return str(e.get("requires_age", ""))


static func _unit_allowed_for(u: Dictionary, civ: String) -> bool:
	var unique_for := _norm(str(u.get("unique_for", "")))
	if not unique_for.is_empty():
		return civ == unique_for
	var civs = u.get("civs", "all")
	if typeof(civs) == TYPE_STRING and _norm(str(civs)) == "all":
		return true
	if typeof(civs) == TYPE_ARRAY:
		if civ.is_empty():
			return false
		return (civs as Array).has(civ)
	return false


static func _section_for(kind: String) -> String:
	match _norm(kind):
		"building", "buildings", "edificio", "edificios":
			return "buildings"
		"unit", "units", "unidad", "unidades":
			return "units"
		"tech", "techs", "tecnologia", "tecnologias":
			return "techs"
	return ""


static func _load_db() -> Dictionary:
	if not _db.is_empty():
		return _db
	if FileAccess.file_exists(TECH_TREE_PATH):
		var f := FileAccess.open(TECH_TREE_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_db = _normalize_tree(parsed)
				return _db
	_db = _normalize_tree({})
	return _db


static func _normalize_tree(parsed: Dictionary) -> Dictionary:
	# Normaliza ids a minusculas y completa con fallbacks (determinista).
	var buildings := {}
	for k in FALLBACK_BUILDINGS.keys():
		buildings[str(k)] = (FALLBACK_BUILDINGS[k] as Dictionary).duplicate(true)
	var units := {}
	for k in FALLBACK_UNITS.keys():
		units[str(k)] = (FALLBACK_UNITS[k] as Dictionary).duplicate(true)
	var techs := {}
	for k in FALLBACK_TECHS.keys():
		techs[str(k)] = (FALLBACK_TECHS[k] as Dictionary).duplicate(true)
	var raw_b: Dictionary = parsed.get("buildings", {})
	for k in raw_b.keys():
		if typeof(raw_b[k]) == TYPE_DICTIONARY:
			buildings[_norm(str(k))] = {"requires_age": _norm(str((raw_b[k] as Dictionary).get("requires_age", "")))}
	var raw_u: Dictionary = parsed.get("units", {})
	for k in raw_u.keys():
		if typeof(raw_u[k]) == TYPE_DICTIONARY:
			var uu: Dictionary = raw_u[k]
			var civs = uu.get("civs", "all")
			var norm_civs = "all"
			if typeof(civs) == TYPE_ARRAY:
				var arr: Array = []
				for c in (civs as Array):
					arr.append(_norm(str(c)))
				arr.sort()
				norm_civs = arr
			units[_norm(str(k))] = {
				"requires_age": _norm(str(uu.get("requires_age", ""))),
				"trained_at": _norm(str(uu.get("trained_at", ""))),
				"civs": norm_civs,
				"unique_for": _norm(str(uu.get("unique_for", ""))),
			}
	var raw_t: Dictionary = parsed.get("techs", {})
	for k in raw_t.keys():
		if typeof(raw_t[k]) == TYPE_DICTIONARY:
			techs[_norm(str(k))] = {"requires_age": _norm(str((raw_t[k] as Dictionary).get("requires_age", "")))}
	return {"buildings": buildings, "units": units, "techs": techs}


static func _norm(s: String) -> String:
	return s.to_lower().strip_edges()
