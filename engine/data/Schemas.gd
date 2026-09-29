extends RefCounted
## Esquemas de entidades, habilidades y efectos. validate_entity() devuelve
## errores "archivo: id.ruta: problema". Números de JSON llegan como float.
## Tipos de campo: number, int, string, bool, dict, array, string_list,
## class_map {texto: número}, res_map {recurso: número}, int_pair, requires, effects.

const RESOURCES: Array[String] = ["wood", "food", "gold", "stone"]
const ENTITY_TYPES: Array[String] = ["unit", "building", "resource", "tech", "age", "civ", "terrain"]
const EFFECT_OPS: Array[String] = ["set", "add", "mul", "append", "remove", "enable", "disable", "replace_entity"]

const COMMON := {
	"id": {"type": "string", "required": true},
	"type": {"type": "string", "required": true},
	"extends": {"type": "string"},
	"abstract": {"type": "bool"},
	"patch": {"type": "bool"},
	"name": {"type": "string"},
	"description": {"type": "string"},
	"hotkey": {"type": "string"},
	"tags": {"type": "string_list"},
	"requires": {"type": "requires"},
	"cost": {"type": "res_map"},
	"graphics": {"type": "dict"},
	"abilities": {"type": "dict"},
}

const BY_TYPE := {
	"unit": {
		"train_time": {"type": "number", "required": true},
		"pop_cost": {"type": "int", "required": true},
		"upgrades_to": {"type": "string"},
	},
	"building": {
		"build_time": {"type": "number", "required": true},
		"footprint": {"type": "int_pair", "required": true},
		"build_menu": {"type": "string"},
	},
	"resource": {},
	"terrain": {
		"texture": {"type": "string", "required": true},
		"color": {"type": "string", "required": true},
	},
	"tech": {
		"research_time": {"type": "number", "required": true},
		"at": {"type": "string", "required": true},
		"effects": {"type": "effects", "required": true},
		"legacy_effects": {"type": "dict"},
	},
	"age": {
		"index": {"type": "int", "required": true},
		"research_time": {"type": "number", "required": true},
		"prerequisite_buildings": {"type": "dict"},
	},
	"civ": {
		"color": {"type": "string", "required": true},
		"effects": {"type": "effects"},
		"disabled": {"type": "string_list"},
		"unique_units": {"type": "string_list"},
		"unique_techs": {"type": "string_list"},
		"legacy_effects": {"type": "array"},
	},
}

const ABILITIES := {
	"Hitpoints": {"max": {"type": "number", "required": true}, "regen": {"type": "number"}},
	"Armor": {"classes": {"type": "class_map", "required": true}},
	"Move": {"speed": {"type": "number", "required": true}},
	"Vision": {"sight": {"type": "number", "required": true}},
	"Selectable": {"radius": {"type": "number"}},
	"Attack": {
		"damage": {"type": "class_map", "required": true},
		"range": {"type": "number", "required": true},
		"reload": {"type": "number", "required": true},
		"min_range": {"type": "number"},
		"attack_delay": {"type": "number"},
		"accuracy": {"type": "number"},
		"projectile_speed": {"type": "number"},
		"area_radius": {"type": "number"},
	},
	"Gather": {"rates": {"type": "class_map", "required": true}, "capacity": {"type": "number", "required": true}},
	"Build": {"rate": {"type": "number", "required": true}},
	"Repair": {"rate": {"type": "number", "required": true}, "cost_factor": {"type": "number"}},
	"DropSite": {"accepts": {"type": "string_list", "required": true}},
	"ResourceSource": {
		"resource": {"type": "string", "required": true},
		"amount": {"type": "number", "required": true},
		"rate_key": {"type": "string", "required": true},
		"infinite": {"type": "bool"},
		"requires_kill": {"type": "bool"},
		"hostile": {"type": "bool"},
		"tame": {"type": "bool"},
		"flees": {"type": "bool"},
		"water": {"type": "bool"},
	},
	"Farm": {"food": {"type": "number", "required": true}, "rate_key": {"type": "string", "required": true}},
	"Train": {"units": {"type": "string_list", "required": true}, "queue": {"type": "int", "required": true}},
	"Research": {"techs": {"type": "string_list", "required": true}},
	"AgeAdvance": {},
	"Bell": {},
	"RallyPoint": {},
	"Garrison": {
		"capacity": {"type": "int", "required": true},
		"arrows_per_unit": {"type": "number"},
		"heal_rate": {"type": "number"},
	},
	"Garrisonable": {},
	"ProvidesPop": {"amount": {"type": "int", "required": true}},
	"Convert": {
		"range": {"type": "number", "required": true},
		"cooldown": {"type": "number", "required": true},
		"chance": {"type": "number", "required": true},
	},
	"Heal": {"range": {"type": "number", "required": true}, "rate": {"type": "number", "required": true}},
	"Trade": {"gold_base": {"type": "number", "required": true}, "gold_per_tile": {"type": "number", "required": true}},
	"Packable": {"pack_time": {"type": "number", "required": true}, "unpack_time": {"type": "number", "required": true}},
	"Wonder": {"victory_time": {"type": "number", "required": true}},
	"Unique": {"civ": {"type": "string", "required": true}},
	"Relic": {"gold_per_sec": {"type": "number", "required": true}},
	"RelicHolder": {},
	"Market": {},
	"Dock": {},
	"Gate": {},
	"Demolish": {},
}


static func validate_entity(e: Dictionary, src: String) -> Array[String]:
	var errs: Array[String] = []
	var id := str(e.get("id", "?"))
	var t := str(e.get("type", ""))
	if not ENTITY_TYPES.has(t):
		errs.append("%s: %s.type: tipo desconocido '%s'" % [src, id, t])
		return errs
	var abstract := bool(e.get("abstract", false))
	var fields: Dictionary = COMMON.duplicate()
	fields.merge(BY_TYPE[t])
	_check_fields(e, fields, id, src, abstract, errs)
	if t == "terrain":
		if e.get("texture") is String and not str(e["texture"]).begins_with("terrain:"):
			errs.append("%s: %s.texture: debe empezar con 'terrain:'" % [src, id])
		if e.get("color") is String and not Color.html_is_valid(str(e["color"])):
			errs.append("%s: %s.color: color inválido '%s'" % [src, id, e["color"]])
	var abil: Variant = e.get("abilities", {})
	if not (abil is Dictionary):
		return errs
	var names: Array = (abil as Dictionary).keys()
	names.sort()
	for a in names:
		var prefix := "%s.abilities.%s" % [id, a]
		if not ABILITIES.has(a):
			errs.append("%s: %s: habilidad desconocida" % [src, prefix])
			continue
		if not (abil[a] is Dictionary):
			errs.append("%s: %s: debe ser objeto" % [src, prefix])
			continue
		_check_fields(abil[a], ABILITIES[a], prefix, src, abstract, errs)
	return errs


## "" si el efecto es válido; si no, el motivo.
static func validate_effect(e: Variant) -> String:
	if not (e is Dictionary):
		return "debe ser objeto"
	var op := str(e.get("op", ""))
	if not EFFECT_OPS.has(op):
		return "op desconocida '%s'" % op
	if op == "replace_entity":
		return "" if e.get("from") is String and e.get("to") is String else "replace_entity requiere from y to"
	if not (e.get("target") is String):
		return "falta target"
	if op == "enable" or op == "disable":
		return ""
	if not (e.get("path") is String):
		return "falta path"
	if not e.has("value") and op != "remove":
		return "falta value"
	if (op == "add" or op == "mul") and not is_num(e["value"]):
		return "value debe ser número"
	return ""


static func is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## "" si v cumple el tipo; si no, el motivo.
static func type_error(v: Variant, type: String) -> String:
	match type:
		"number":
			return "" if is_num(v) else "debe ser número"
		"int":
			return "" if is_num(v) and float(v) == floorf(float(v)) else "debe ser entero"
		"string":
			return "" if v is String else "debe ser texto"
		"bool":
			return "" if v is bool else "debe ser true/false"
		"dict":
			return "" if v is Dictionary else "debe ser objeto"
		"array":
			return "" if v is Array else "debe ser lista"
		"string_list":
			if not (v is Array):
				return "debe ser lista de textos"
			for x in v:
				if not (x is String):
					return "debe ser lista de textos"
			return ""
		"class_map":
			if not (v is Dictionary):
				return "debe ser objeto {clase: número}"
			for k in v:
				if not is_num(v[k]):
					return "valor de '%s' debe ser número" % k
			return ""
		"res_map":
			if not (v is Dictionary):
				return "debe ser objeto {recurso: número}"
			for k in v:
				if not RESOURCES.has(str(k)):
					return "recurso desconocido '%s'" % k
				if not is_num(v[k]):
					return "valor de '%s' debe ser número" % k
			return ""
		"int_pair":
			if v is Array and v.size() == 2 and type_error(v[0], "int") == "" and type_error(v[1], "int") == "":
				return ""
			return "debe ser [entero, entero]"
		"requires":
			if not (v is Dictionary):
				return "debe ser objeto {age, techs}"
			for k in v:
				if k != "age" and k != "techs":
					return "clave desconocida '%s' (usa age/techs)" % k
			if v.has("age") and not (v["age"] is String):
				return "age debe ser texto"
			if v.has("techs") and type_error(v["techs"], "string_list") != "":
				return "techs debe ser lista de textos"
			return ""
		"effects":
			if not (v is Array):
				return "debe ser lista de efectos"
			for i in v.size():
				var why := validate_effect(v[i])
				if why != "":
					return "efecto %d: %s" % [i, why]
			return ""
	return "tipo de esquema desconocido '%s'" % type


static func _check_fields(obj: Dictionary, fields: Dictionary, prefix: String, src: String, skip_required: bool, errs: Array[String]) -> void:
	var keys: Array = obj.keys()
	keys.sort()
	for k in keys:
		var key := str(k)
		if key.begins_with("_"):
			continue
		if not fields.has(key):
			errs.append("%s: %s.%s: campo desconocido" % [src, prefix, key])
			continue
		var why := type_error(obj[k], str(fields[key]["type"]))
		if why != "":
			errs.append("%s: %s.%s: %s" % [src, prefix, key, why])
	if skip_required:
		return
	var req: Array = fields.keys()
	req.sort()
	for key in req:
		if bool(fields[key].get("required", false)) and not obj.has(key):
			errs.append("%s: %s.%s: falta campo obligatorio" % [src, prefix, key])
