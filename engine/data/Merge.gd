extends RefCounted
## Fusión profunda y acceso por ruta "a.b.c" para definiciones de datos.


## Copia de base con over encima: los diccionarios se fusionan recursivamente;
## cualquier otro valor (listas incluidas) se reemplaza. No muta las entradas.
static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		var v: Variant = over[k]
		if v is Dictionary and out.get(k) is Dictionary:
			out[k] = deep_merge(out[k], v)
		elif v is Dictionary or v is Array:
			out[k] = v.duplicate(true)
		else:
			out[k] = v
	return out


static func path_get(d: Dictionary, path: String, default: Variant = null) -> Variant:
	var cur: Variant = d
	for part in path.split("."):
		if not (cur is Dictionary) or not (cur as Dictionary).has(part):
			return default
		cur = cur[part]
	return cur


static func path_has(d: Dictionary, path: String) -> bool:
	var cur: Variant = d
	for part in path.split("."):
		if not (cur is Dictionary) or not (cur as Dictionary).has(part):
			return false
		cur = cur[part]
	return true


static func path_set(d: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".")
	var cur: Dictionary = d
	for i in parts.size() - 1:
		var p := parts[i]
		if not (cur.get(p) is Dictionary):
			cur[p] = {}
		cur = cur[p]
	cur[parts[parts.size() - 1]] = value


static func path_erase(d: Dictionary, path: String) -> bool:
	var parts := path.split(".")
	var cur: Variant = d
	for i in parts.size() - 1:
		if not (cur is Dictionary) or not (cur as Dictionary).has(parts[i]):
			return false
		cur = cur[parts[i]]
	if not (cur is Dictionary):
		return false
	return (cur as Dictionary).erase(parts[parts.size() - 1])
