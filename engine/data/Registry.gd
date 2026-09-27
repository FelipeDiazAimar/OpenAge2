extends RefCounted
## Registry: carga mods (res://mods/<mod>/mod.json), aplica overrides y
## parches, resuelve herencia "extends", valida contra Schemas y calcula
## content_hash. Única fuente de definiciones para sim, render y UI.
## Las definiciones devueltas no deben mutarse (usar PlayerDefs).

const Merge := preload("res://engine/data/Merge.gd")
const Schemas := preload("res://engine/data/Schemas.gd")
const ENTITY_DIRS: Array[String] = ["base", "units", "buildings", "resources", "techs", "ages", "civs"]

var mods: Array[Dictionary] = []
var defs: Dictionary = {}
var abstract_defs: Dictionary = {}
var errors: Array[String] = []
var warnings: Array[String] = []
var content_hash := ""

var _raw: Dictionary = {}
var _src: Dictionary = {}
var _mod_of: Dictionary = {}


func load_mods(root: String = "res://mods", enabled: Array = []) -> bool:
	mods.clear()
	defs.clear()
	abstract_defs.clear()
	errors.clear()
	warnings.clear()
	content_hash = ""
	_raw.clear()
	_src.clear()
	_mod_of.clear()
	var found := _discover(root, enabled)
	if not errors.is_empty():
		return false
	mods = _order(found)
	if not errors.is_empty():
		return false
	for m in mods:
		_load_mod_entities(m)
	var resolved := {}
	for id in _sorted(_raw):
		_resolve(id, resolved, [])
	for id in _sorted(_raw):
		var d: Dictionary = resolved.get(id, {})
		if d.is_empty():
			continue
		if bool(d.get("abstract", false)):
			abstract_defs[id] = d
		else:
			defs[id] = d
	for id in _sorted(abstract_defs):
		errors.append_array(Schemas.validate_entity(abstract_defs[id], _src[id]))
	for id in _sorted(defs):
		errors.append_array(Schemas.validate_entity(defs[id], _src[id]))
	_check_refs()
	if errors.is_empty():
		content_hash = hash_defs(defs)
	return errors.is_empty()


func get_def(id: String) -> Dictionary:
	return defs.get(id, {})


func has(id: String) -> bool:
	return defs.has(id)


func source_of(id: String) -> String:
	return str(_src.get(id, ""))


func ids_of_type(type: String) -> Array[String]:
	var out: Array[String] = []
	for id in _sorted(defs):
		if str(defs[id].get("type", "")) == type:
			out.append(id)
	return out


## {ok: bool, data: Variant, error: String}. Ignora BOM UTF-8.
static func parse_json_text(text: String) -> Dictionary:
	if text.begins_with(String.chr(0xFEFF)):
		text = text.substr(1)
	var j := JSON.new()
	if j.parse(text) != OK:
		return {"ok": false, "data": null, "error": "línea %d: %s" % [j.get_error_line(), j.get_error_message()]}
	return {"ok": true, "data": j.data, "error": ""}


static func hash_defs(d: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(JSON.stringify(d, "", true, true).to_utf8_buffer())
	return ctx.finish().hex_encode()


# ------------------------------------------------------------------ mods ---

func _discover(root: String, enabled: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(root)
	if dir == null:
		errors.append("%s: carpeta de mods no encontrada" % root)
		return out
	var names: Array = Array(dir.get_directories())
	names.sort()
	for n in names:
		var mpath := "%s/%s/mod.json" % [root, n]
		if not FileAccess.file_exists(mpath):
			continue
		var m: Variant = _read_json(mpath)
		if m == null:
			continue
		if not (m is Dictionary) or not (m.get("id") is String):
			errors.append("%s: mod.json necesita 'id' (texto)" % mpath)
			continue
		var bad := false
		if Schemas.type_error(m.get("depends", []), "string_list") != "":
			errors.append("%s: depends debe ser lista de textos" % mpath)
			bad = true
		if not Schemas.is_num(m.get("priority", 0)):
			errors.append("%s: priority debe ser número" % mpath)
			bad = true
		if bad:
			continue
		if not enabled.is_empty() and not enabled.has(m["id"]):
			continue
		out.append({
			"id": str(m["id"]),
			"version": str(m.get("version", "0")),
			"depends": (m.get("depends", []) as Array).duplicate(),
			"priority": int(m.get("priority", 0)),
			"path": "%s/%s" % [root, n],
		})
	if out.is_empty() and errors.is_empty():
		errors.append("%s: no hay mods (ninguna carpeta con mod.json)" % root)
	return out


## Orden topológico por depends; entre listos, menor priority y luego id.
func _order(found: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := {}
	for m in found:
		ids[m["id"]] = true
	for m in found:
		for dep in m["depends"]:
			if not ids.has(dep):
				errors.append("mod %s: depende de '%s', que no está" % [m["id"], dep])
	if not errors.is_empty():
		return out
	var done := {}
	while out.size() < found.size():
		var ready: Array = []
		for m in found:
			if done.has(m["id"]):
				continue
			var ok := true
			for dep in m["depends"]:
				if not done.has(dep):
					ok = false
			if ok:
				ready.append(m)
		if ready.is_empty():
			errors.append("mods con dependencia circular")
			out.clear()
			return out
		ready.sort_custom(func(a, b): return a["priority"] < b["priority"] or (a["priority"] == b["priority"] and a["id"] < b["id"]))
		out.append(ready[0])
		done[ready[0]["id"]] = true
	return out


func _load_mod_entities(m: Dictionary) -> void:
	for sub in ENTITY_DIRS:
		for f in _json_files("%s/%s" % [m["path"], sub]):
			var e: Variant = _read_json(f)
			if e == null:
				continue
			if not (e is Dictionary) or not (e.get("id") is String):
				errors.append("%s: la entidad necesita 'id' (texto)" % f)
				continue
			var id := str(e["id"])
			if bool(e.get("patch", false)):
				if not _raw.has(id):
					errors.append("%s: parche sobre '%s', que no existe" % [f, id])
					continue
				var p: Dictionary = (e as Dictionary).duplicate(true)
				p.erase("patch")
				_raw[id] = Merge.deep_merge(_raw[id], p)
				_src[id] = "%s (+%s)" % [_src[id], f]
				continue
			if _raw.has(id):
				if _mod_of[id] == m["id"]:
					errors.append("%s: id '%s' repetido en el mod %s (ya en %s)" % [f, id, m["id"], _src[id]])
					continue
				warnings.append("%s: sobrescribe '%s' de %s" % [f, id, _src[id]])
			_raw[id] = e
			_src[id] = f
			_mod_of[id] = m["id"]


func _json_files(dpath: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dpath)
	if dir == null:
		return out
	var files: Array = Array(dir.get_files())
	files.sort()
	for f in files:
		if f.ends_with(".json") and not f.begins_with("_"):
			out.append("%s/%s" % [dpath, f])
	var subs: Array = Array(dir.get_directories())
	subs.sort()
	for s in subs:
		out.append_array(_json_files("%s/%s" % [dpath, s]))
	return out


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("%s: no se pudo abrir" % path)
		return null
	var r := parse_json_text(f.get_as_text())
	if not r["ok"]:
		errors.append("%s: JSON inválido (%s)" % [path, r["error"]])
		return null
	return r["data"]


# ------------------------------------------------------------- herencia ---

func _resolve(id: String, resolved: Dictionary, stack: Array) -> Dictionary:
	if resolved.has(id):
		return resolved[id]
	if stack.has(id):
		errors.append("%s: herencia circular %s" % [_src[id], " -> ".join(PackedStringArray(stack + [id]))])
		return {}
	var own: Dictionary = _raw[id]
	var out: Dictionary
	if own.has("extends"):
		var parent_id := str(own["extends"])
		if not _raw.has(parent_id):
			errors.append("%s: %s extiende '%s', que no existe" % [_src[id], id, parent_id])
			resolved[id] = {}
			return {}
		var parent := _resolve(parent_id, resolved, stack + [id])
		if parent.is_empty():
			resolved[id] = {}
			return {}
		out = Merge.deep_merge(parent, own)
		var tags: Array = (parent.get("tags", []) as Array).duplicate()
		for t in own.get("tags", []):
			if not tags.has(t):
				tags.append(t)
		out["tags"] = tags
		out.erase("extends")
	else:
		out = own.duplicate(true)
	if bool(own.get("abstract", false)):
		out["abstract"] = true
	else:
		out.erase("abstract")
	resolved[id] = out
	return out


# ---------------------------------------------------------- referencias ---

func _check_refs() -> void:
	for id in _sorted(defs):
		var d: Dictionary = defs[id]
		var ab: Dictionary = d.get("abilities", {}) if d.get("abilities") is Dictionary else {}
		if ab.get("Train") is Dictionary:
			for u in ab["Train"].get("units", []):
				_ref(id, "abilities.Train.units", str(u), "unit")
		if ab.get("Research") is Dictionary:
			for t in ab["Research"].get("techs", []):
				_ref(id, "abilities.Research.techs", str(t), "tech")
		if ab.get("DropSite") is Dictionary:
			for r in ab["DropSite"].get("accepts", []):
				if not Schemas.RESOURCES.has(str(r)):
					errors.append("%s: %s.abilities.DropSite.accepts: recurso desconocido '%s'" % [_src[id], id, r])
		var req: Variant = d.get("requires", {})
		if req is Dictionary:
			if req.has("age"):
				_ref(id, "requires.age", str(req["age"]), "age")
			for t in req.get("techs", []):
				_ref(id, "requires.techs", str(t), "tech")
		if d.has("upgrades_to"):
			_ref(id, "upgrades_to", str(d["upgrades_to"]), "unit")
		if ab.get("Unique") is Dictionary:
			_ref(id, "abilities.Unique.civ", str(ab["Unique"].get("civ", "")), "civ")
		if d.get("effects") is Array:
			_check_effects(id, d["effects"])
		match str(d.get("type", "")):
			"tech":
				_ref(id, "at", str(d.get("at", "")), "building")
			"civ":
				for x in d.get("disabled", []):
					if not defs.has(str(x)):
						errors.append("%s: %s.disabled: '%s' no existe" % [_src[id], id, x])
				for u in d.get("unique_units", []):
					_ref(id, "unique_units", str(u), "unit")
				for t in d.get("unique_techs", []):
					_ref(id, "unique_techs", str(t), "tech")


## Selectores de efectos: términos id:/tag:/type: válidos, ids existentes,
## replace_entity entre unidades. Un tag sin coincidencias es solo aviso.
func _check_effects(id: String, effects: Array) -> void:
	var tags := {}
	for d in defs.values():
		for t in d.get("tags", []):
			tags[t] = true
	for i in effects.size():
		var e: Variant = effects[i]
		if not (e is Dictionary):
			continue
		var field := "effects[%d]" % i
		if str(e.get("op", "")) == "replace_entity":
			_ref(id, field + ".from", str(e.get("from", "")), "unit")
			_ref(id, field + ".to", str(e.get("to", "")), "unit")
			continue
		if not (e.get("target") is String):
			continue
		for alt in str(e["target"]).split("|"):
			for raw in alt.split("&"):
				var term := raw.strip_edges()
				var kind := term.get_slice(":", 0)
				var val := term.get_slice(":", 1)
				var where := "%s: %s.%s.target" % [_src[id], id, field]
				if term.find(":") < 0 or not (kind in ["id", "tag", "type"]):
					errors.append("%s: término desconocido '%s' (usa id:, tag: o type:)" % [where, term])
				elif kind == "id" and not defs.has(val):
					errors.append("%s: '%s' no existe" % [where, val])
				elif kind == "type" and not Schemas.ENTITY_TYPES.has(val):
					errors.append("%s: tipo desconocido '%s'" % [where, val])
				elif kind == "tag" and not tags.has(val):
					warnings.append("%s: tag '%s' no coincide con ninguna entidad" % [where, val])


func _ref(id: String, field: String, target: String, type: String) -> void:
	if not defs.has(target):
		errors.append("%s: %s.%s: '%s' no existe" % [_src[id], id, field, target])
	elif str(defs[target].get("type", "")) != type:
		errors.append("%s: %s.%s: '%s' no es de tipo %s" % [_src[id], id, field, target, type])


static func _sorted(d: Dictionary) -> Array:
	var k: Array = d.keys()
	k.sort()
	return k
