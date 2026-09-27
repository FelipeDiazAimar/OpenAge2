extends RefCounted
## Selectores y operaciones de parche (tecnologías, civilizaciones, mods).
## Selector: "tag:a|tag:b&type:unit" = OR de grupos AND. Términos id:, tag:, type:.

const Merge := preload("res://engine/data/Merge.gd")
const Schemas := preload("res://engine/data/Schemas.gd")


static func matches(def: Dictionary, selector: String) -> bool:
	for alt in selector.split("|"):
		var ok := true
		for term in alt.split("&"):
			if not _term(def, term.strip_edges()):
				ok = false
				break
		if ok:
			return true
	return false


static func select(defs: Dictionary, selector: String) -> Array[String]:
	var out: Array[String] = []
	for id in defs:
		if matches(defs[id], selector):
			out.append(str(id))
	out.sort()
	return out


## Aplica set/add/mul/append/remove sobre defs (in place). Devuelve errores.
static func apply(defs: Dictionary, effect: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var op := str(effect["op"])
	var path := str(effect["path"])
	var value: Variant = effect.get("value")
	var parts := path.split(".")
	for id in select(defs, str(effect["target"])):
		var def: Dictionary = defs[id]
		if parts[0] == "abilities" and parts.size() >= 2 and not (def.get("abilities", {}) as Dictionary).has(parts[1]):
			continue
		var cur: Variant = Merge.path_get(def, path)
		if op == "set":
			Merge.path_set(def, path, value.duplicate(true) if (value is Dictionary or value is Array) else value)
		elif op == "add":
			if cur == null:
				Merge.path_set(def, path, value)
			elif Schemas.is_num(cur):
				Merge.path_set(def, path, cur + value)
			else:
				errs.append("%s.%s: add sobre un valor no numérico" % [id, path])
		elif op == "mul":
			if cur == null:
				continue
			if Schemas.is_num(cur):
				Merge.path_set(def, path, cur * value)
			else:
				errs.append("%s.%s: mul sobre un valor no numérico" % [id, path])
		elif op == "append":
			if cur == null:
				Merge.path_set(def, path, [value])
			elif cur is Array:
				if not (cur as Array).has(value):
					(cur as Array).append(value)
			else:
				errs.append("%s.%s: append sobre algo que no es lista" % [id, path])
		elif op == "remove":
			if cur is Array and value != null:
				(cur as Array).erase(value)
			elif cur != null:
				Merge.path_erase(def, path)
		else:
			errs.append("%s: op '%s' no se aplica sobre datos" % [id, op])
	return errs


static func _term(def: Dictionary, term: String) -> bool:
	var kind := term.get_slice(":", 0)
	var val := term.get_slice(":", 1)
	match kind:
		"id":
			return str(def.get("id", "")) == val
		"tag":
			return (def.get("tags", []) as Array).has(val)
		"type":
			return str(def.get("type", "")) == val
	return false
