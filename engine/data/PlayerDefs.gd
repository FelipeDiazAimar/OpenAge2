extends RefCounted
## Vista de definiciones de UN jugador: copia del Registry con los efectos de
## su civilización y de sus tecnologías investigadas. Se recalcula al investigar,
## nunca por tick. Las mejoras afectan a las unidades vivas (leen de aquí).

const Patch := preload("res://engine/data/Patch.gd")

var civ_id := ""
var defs: Dictionary = {}
var disabled: Dictionary = {}
var upgrades: Dictionary = {}
var researched: Array[String] = []


func _init(registry_defs: Dictionary, civ: String) -> void:
	civ_id = civ
	defs = registry_defs.duplicate(true)
	var civ_def: Dictionary = defs.get(civ, {})
	for id in civ_def.get("disabled", []):
		disabled[str(id)] = true
	apply_effects(civ_def.get("effects", []))


func apply_effects(effects: Array) -> Array[String]:
	var errs: Array[String] = []
	for e in effects:
		var op := str(e["op"])
		if op == "enable" or op == "disable":
			for id in Patch.select(defs, str(e["target"])):
				if op == "disable":
					disabled[id] = true
				else:
					disabled.erase(id)
		elif op == "replace_entity":
			upgrades[str(e["from"])] = str(e["to"])
		else:
			errs.append_array(Patch.apply(defs, e))
	return errs


func research(tech_id: String) -> Array[String]:
	if researched.has(tech_id):
		return ["%s ya investigada" % tech_id]
	var tech: Dictionary = defs.get(tech_id, {})
	if str(tech.get("type", "")) != "tech":
		return ["%s no es una tecnología" % tech_id]
	researched.append(tech_id)
	return apply_effects(tech.get("effects", []))


func is_available(id: String) -> bool:
	return defs.has(id) and not disabled.has(id)


## Sigue la cadena de mejoras (milicia -> hombre_armas -> ...).
func resolve_unit(id: String) -> String:
	var cur := id
	var guard := 0
	while upgrades.has(cur) and guard < 16:
		cur = upgrades[cur]
		guard += 1
	return cur


func get_def(id: String) -> Dictionary:
	return defs.get(id, {})
