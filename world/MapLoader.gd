extends Node
class_name MapLoader
## world/MapLoader.gd — Carga mapas .oamap.json (tools/convert_aoe2.py) y
## .json propios (data/maps/arabia.json) a un formato común y los spawnea.
##
## Formato común:
##   { "name": String, "size": Vector2i, "terrain_grid": Array[int],
##     "resources": Array[{def_id:String, tile:Vector2i, amount:int}],
##     "spawns": Array[Vector2i], "seed": int, "source": String }
##   - terrain_grid: w*h enteros (0=hierba, 1=tierra). Vacío = no detallado.
##   - resources: def_id debe existir en ResourceNode.def_ids().
##   - spawns[i] = tile inicial del jugador i (1..8, dentro del mapa).
##
## Determinismo: toda colocación procedural usa SimRNG local (nunca randf).
## Fallback: si el archivo falta, el JSON es inválido o la validación falla,
##   se carga res://data/maps/arabia.json; si hasta eso falla, mapa mínimo
##   hardcoded (144x144, 2 spawns). Nunca devuelve un dict vacío.
##
## Spawneo:
##   spawn_all(mapa, padre) crea ResourceNodes (setup+register+add_child,
##   posicionados en tile_to_world) y registra 1 TC por spawn vía
##   GameManager.register_building(pid, "centro_urbano"). No crea escenas
##   de edificios/unidades: devuelve las posiciones para que el caller las
##   instancie. Uso:
##     var ml := MapLoader.new()
##     add_child(ml)
##     var r := ml.load_and_spawn("res://assets/imported/acropolis.oamap.json", self, 1234, 2)
##     # r = {map, spawned, fallback_used, errors, source_path}

const FALLBACK_MAP := "res://data/maps/arabia.json"
const TILE := 2.0 # igual que Terrain.TILE (mundo = tile * 2.0)
const MIN_SIZE := 32
const MAX_SIZE := 256
const MAX_PLAYERS := 8
const SPAWN_MARGIN := 10 # tiles libres al borde para TCs

# Cuántos nodos genera cada contador de arabia.json (reparto por spawn).
const TREES_PER_PATCH := 9
const GOLD_PER_PILE := 1
const STONE_PER_PILE := 1

var last_errors: Array = []
var last_fallback_used := false


# ---------------------------------------------------------------- carga --
## Lee un JSON cualquiera a Dictionary. {} si falta o es inválido.
static func load_file(path: String) -> Dictionary:
	var fpath := path.strip_edges()
	if fpath.is_empty() or not FileAccess.file_exists(fpath):
		return {}
	var f := FileAccess.open(fpath, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Punto de entrada principal: carga, normaliza, valida; fallback a arabia.
## player_count <= 0 = respetar el que pida cada formato (defecto 2).
## Devuelve {map, fallback_used: bool, errors: Array, source_path: String}.
func load_map(path: String, seed: int = 1234, player_count: int = -1) -> Dictionary:
	last_errors.clear()
	last_fallback_used = false
	var raw := load_file(path)
	var count := player_count if player_count > 0 else _wanted_players(raw)
	count = clampi(count, 1, MAX_PLAYERS)
	var common := to_common(raw, path, seed, count)
	var chk := validate(common)
	if raw.is_empty():
		last_errors.append("no se pudo leer '%s', usando fallback" % path)
	elif not bool(chk.get("ok", false)):
		for e in chk.get("errors", []):
			last_errors.append(str(e))
	if raw.is_empty() or not bool(chk.get("ok", false)):
		return _use_fallback(path, seed, count)
	return {"map": common, "fallback_used": false,
		"errors": [], "source_path": path}


## Convierte cualquier dict crudo (oamap / propio / común) al formato común.
## raw vacío = mapa mínimo hardcoded (lo usa el fallback en última instancia).
func to_common(raw: Dictionary, source_path: String, seed: int, player_count: int) -> Dictionary:
	var count := clampi(player_count, 1, MAX_PLAYERS)
	if _is_common(raw):
		var c := _normalize_common(raw, source_path, seed)
		# Si el común no trae spawns suficientes, se generan sin tocar recursos.
		if (c["spawns"] as Array).size() < count:
			var rng := SimRNG.new()
			rng.set_seed(seed)
			c["spawns"] = _make_spawns(c["size"], count, rng)
			rng.free()
		return c
	var size := _parse_size(raw)
	var rng := SimRNG.new()
	rng.set_seed(seed)
	var spawns := _make_spawns(size, count, rng)
	var resources: Array = []
	var terrain: Array = []
	var name := str(raw.get("name", source_path.get_file()))
	if _is_oamap(raw, source_path):
		var hint := int(raw.get("hint_resources", 6))
		resources = _resources_from_hint(size, spawns, hint, rng)
		terrain = _make_terrain_grid(size, rng)
	else:
		# Mapa propio estilo arabia.json (start_resources) o dict desconocido.
		var srv = raw.get("start_resources", {})
		var sr: Dictionary = srv if srv is Dictionary else {}
		if sr.is_empty() and not raw.is_empty():
			# Desconocido pero con size:_counts por defecto de arabia.
			sr = {"wood_patches": 8, "gold_piles": 6, "stone_piles": 4,
				"forage": 4, "boars": 2}
		elif sr.is_empty():
			sr = {}
		resources = _resources_from_counts(size, spawns, sr, rng)
		terrain = _make_terrain_grid(size, rng)
		if raw.is_empty():
			name = "fallback_minimo"
	rng.free()
	return {"name": name, "size": size, "terrain_grid": terrain,
		"resources": resources, "spawns": spawns,
		"seed": seed, "source": source_path}


## Valida el formato común. Devuelve {ok: bool, errors: Array[String]}.
func validate(map: Dictionary) -> Dictionary:
	var errors: Array = []
	for k in ["name", "size", "terrain_grid", "resources", "spawns"]:
		if not map.has(k):
			errors.append("falta clave '%s'" % k)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var size := Vector2i(144, 144)
	var size_ok := false
	if map.has("size"):
		var sv = map["size"]
		if sv is Vector2i or sv is Vector2 or (sv is Array and sv.size() >= 2):
			size = _as_vec2i(sv)
			size_ok = true
	if not size_ok:
		errors.append("size ausente o con tipo inválido (esperado Vector2i/Array [w,h])")
	elif size.x < MIN_SIZE or size.y < MIN_SIZE or size.x > MAX_SIZE or size.y > MAX_SIZE:
		errors.append("size fuera de rango [%d..%d]: %s" % [MIN_SIZE, MAX_SIZE, str(size)])
	var total := size.x * size.y
	var tg: Array = map["terrain_grid"] if map.get("terrain_grid") is Array else []
	if not tg.is_empty() and tg.size() != total:
		errors.append("terrain_grid=%d, esperado %d (w*h) o vacío" % [tg.size(), total])
	var valid_defs := ResourceNode.def_ids()
	var spawns: Array = map["spawns"] if map.get("spawns") is Array else []
	if spawns.size() < 1 or spawns.size() > MAX_PLAYERS:
		errors.append("spawns debe ser 1..%d, hay %d" % [MAX_PLAYERS, spawns.size()])
	for i in spawns.size():
		if not _in_bounds(spawns[i], size):
			errors.append("spawn %d fuera del mapa: %s" % [i, str(spawns[i])])
	_check_min_spawn_distance(spawns, size, errors)
	var res: Array = map["resources"] if map.get("resources") is Array else []
	for i in res.size():
		var r = res[i]
		if typeof(r) != TYPE_DICTIONARY:
			errors.append("resources[%d] no es dict" % i)
			continue
		if not valid_defs.has(str(r.get("def_id", ""))):
			errors.append("resources[%d] def_id desconocido: '%s'" % [i, str(r.get("def_id", ""))])
		if not _in_bounds(r.get("tile", Vector2i(-1, -1)), size):
			errors.append("resources[%d] tile fuera del mapa: %s" % [i, str(r.get("tile"))])
		if int(r.get("amount", 0)) < -1:
			errors.append("resources[%d] amount inválido: %s" % [i, str(r.get("amount"))])
	return {"ok": errors.is_empty(), "errors": errors}


## Crea ResourceNodes + registra TCs en GameManager.
## Devuelve {resources_spawned, tcs_registered, first_node_id, spawn_world: Array[Vector3]}.
func spawn_all(map: Dictionary, parent: Node, game_manager: Node = null,
		start_node_id: int = 0) -> Dictionary:
	var chk := validate(map)
	if not bool(chk.get("ok", false)):
		push_error("MapLoader.spawn_all: mapa inválido: %s" % str(chk.get("errors", [])))
		return {"resources_spawned": 0, "tcs_registered": 0,
			"first_node_id": start_node_id, "spawn_world": []}
	var gm := game_manager if game_manager != null else get_node_or_null("/root/GameManager")
	var gm_slots := MAX_PLAYERS
	if gm != null and gm.get("players") is Array:
		gm_slots = (gm.get("players") as Array).size()
	var res: Array = map["resources"] if map.get("resources") is Array else []
	var nid := start_node_id
	for r in res:
		var node := ResourceNode.new()
		node.name = "Res_%d_%s" % [nid, str(r["def_id"])]
		if not node.setup(nid, str(r["def_id"]), int(r.get("amount", ResourceNode.USE_DEF_AMOUNT))):
			node.free()
			continue
		if not node.register():
			node.free()
			continue
		node.position = tile_to_world(_as_vec2i(r["tile"]))
		parent.add_child(node)
		nid += 1
	var spawns: Array = map["spawns"] if map.get("spawns") is Array else []
	var worlds: Array = []
	var tcs := 0
	for i in spawns.size():
		worlds.append(tile_to_world(_as_vec2i(spawns[i])))
		if gm != null and i < gm_slots and gm.has_method("register_building"):
			gm.register_building(i, "centro_urbano")
			tcs += 1
	return {"resources_spawned": nid - start_node_id, "tcs_registered": tcs,
		"first_node_id": start_node_id, "spawn_world": worlds}


## Atajo: load_map + spawn_all en una llamada.
func load_and_spawn(path: String, parent: Node, seed: int = 1234,
		player_count: int = 2, game_manager: Node = null,
		start_node_id: int = 0) -> Dictionary:
	var loaded := load_map(path, seed, player_count)
	var stats := spawn_all(loaded["map"], parent, game_manager, start_node_id)
	loaded["spawned"] = stats
	return loaded


func tile_to_world(t: Vector2i) -> Vector3:
	return Vector3(float(t.x) * TILE, 0.0, float(t.y) * TILE)


func world_to_tile(w: Vector3) -> Vector2i:
	return Vector2i(int(w.x / TILE), int(w.z / TILE))


# ------------------------------------------------------------- formatos --
static func _is_oamap(raw: Dictionary, path: String) -> bool:
	return path.ends_with(".oamap.json") or raw.has("imported_from")


static func _is_common(raw: Dictionary) -> bool:
	return raw.has("size") and raw.has("resources") and raw.has("spawns")


static func _parse_size(raw: Dictionary) -> Vector2i:
	# Acepta size_tiles (oamap/propio) o size (común/Vector2i/string).
	for k in ["size_tiles", "size"]:
		if raw.has(k):
			var v = raw[k]
			if v is Vector2i:
				return Vector2i(clampi(v.x, MIN_SIZE, MAX_SIZE), clampi(v.y, MIN_SIZE, MAX_SIZE))
			if v is Vector2:
				return Vector2i(clampi(int(v.x), MIN_SIZE, MAX_SIZE), clampi(int(v.y), MIN_SIZE, MAX_SIZE))
			if v is Array and v.size() >= 2:
				return Vector2i(clampi(int(v[0]), MIN_SIZE, MAX_SIZE), clampi(int(v[1]), MIN_SIZE, MAX_SIZE))
	return Vector2i(144, 144)


static func _wanted_players(raw: Dictionary) -> int:
	if raw.has("players"):
		return clampi(int(raw["players"]), 1, MAX_PLAYERS)
	if raw.has("spawns") and raw["spawns"] is Array:
		return clampi((raw["spawns"] as Array).size(), 1, MAX_PLAYERS)
	return 2


func _normalize_common(raw: Dictionary, source_path: String, seed: int) -> Dictionary:
	var size := _parse_size(raw)
	var tg: Array = []
	if raw.get("terrain_grid", []) is Array:
		tg = (raw["terrain_grid"] as Array).duplicate(true)
	var res: Array = []
	for r in (raw.get("resources", []) as Array):
		if typeof(r) == TYPE_DICTIONARY:
			res.append({"def_id": str(r.get("def_id", "")),
				"tile": _as_vec2i(r.get("tile", Vector2i(-1, -1))),
				"amount": int(r.get("amount", ResourceNode.USE_DEF_AMOUNT))})
	var spawns: Array = []
	for s in (raw.get("spawns", []) as Array):
		spawns.append(_as_vec2i(s))
	return {"name": str(raw.get("name", source_path.get_file())), "size": size,
		"terrain_grid": tg, "resources": res, "spawns": spawns,
		"seed": int(raw.get("seed", seed)), "source": source_path}


# ---------------------------------------------------------- generación --
## Spawns en círculo alrededor del centro (determinista). 1P = centro.
func _make_spawns(size: Vector2i, count: int, rng: SimRNG) -> Array:
	var out: Array = []
	var cx := float(size.x) * 0.5
	var cy := float(size.y) * 0.5
	if count == 1:
		out.append(Vector2i(int(cx), int(cy)))
		return out
	var radius := minf(float(size.x), float(size.y)) * 0.38
	var offset := rng.next_float() * TAU
	for i in count:
		var a := offset + float(i) * TAU / float(count)
		var px := clampi(int(cx + cos(a) * radius), SPAWN_MARGIN, size.x - SPAWN_MARGIN)
		var py := clampi(int(cy + sin(a) * radius), SPAWN_MARGIN, size.y - SPAWN_MARGIN)
		out.append(Vector2i(px, py))
	return out


## Recursos desde contadores estilo arabia.json, repartidos por spawn
## (cercanos a cada TC, estilo AoE2) + resto neutrales dispersos.
func _resources_from_counts(size: Vector2i, spawns: Array, sr: Dictionary, rng: SimRNG) -> Array:
	var out: Array = []
	var n := maxi(1, spawns.size())
	_scatter_near(out, size, spawns, rng, "tree", TREES_PER_PATCH * maxi(1, int(sr.get("wood_patches", 8)) / n), 6.0, 12)
	_scatter_near(out, size, spawns, rng, "gold_mine", GOLD_PER_PILE * maxi(1, int(sr.get("gold_piles", 6)) / n), 5.0, 4)
	_scatter_near(out, size, spawns, rng, "stone_mine", STONE_PER_PILE * maxi(1, int(sr.get("stone_piles", 4)) / n), 6.0, 4)
	_scatter_near(out, size, spawns, rng, "berry_bush", maxi(1, int(sr.get("forage", 4)) / n) * 2, 4.0, 2)
	_scatter_near(out, size, spawns, rng, "boar", maxi(1, int(sr.get("boars", 2)) / n), 7.0, 2)
	_scatter_neutral(out, size, rng, "deer", 4, 2)
	if bool(sr.get("water", false)):
		_scatter_neutral(out, size, rng, "shore_fish", 3, 0)
	return out


## .oamap.json solo trae hint_resources (nº menciones gold+wood en el .rms):
## se traduce a densidad de minas/bosques; el resto, valores de arabia.
func _resources_from_hint(size: Vector2i, spawns: Array, hint: int, rng: SimRNG) -> Array:
	var density := clampi(hint, 2, 20)
	return _resources_from_counts(size, spawns, {
		"wood_patches": clampi(density, 4, 12),
		"gold_piles": clampi(density / 2, 3, 8),
		"stone_piles": 4, "forage": 4, "boars": 2,
	}, rng)


## Rejilla w*h: 0=hierba, 1=tierra (manchas deterministas ~35%).
func _make_terrain_grid(size: Vector2i, rng: SimRNG) -> Array:
	var out: Array = []
	out.resize(size.x * size.y)
	for i in out.size():
		out[i] = 1 if rng.next_float() < 0.35 else 0
	return out


func _scatter_near(out: Array, size: Vector2i, spawns: Array, rng: SimRNG,
		def_id: String, per_spawn: int, dist: float, jitter: int) -> void:
	for s in spawns:
		var base := _as_vec2i(s)
		for i in per_spawn:
			var a := rng.next_float() * TAU
			var d := dist + float(rng.next_int(0, jitter))
			out.append({"def_id": def_id, "tile": _clamp_tile(
				base + Vector2i(int(cos(a) * d), int(sin(a) * d)), size),
				"amount": ResourceNode.USE_DEF_AMOUNT})


func _scatter_neutral(out: Array, size: Vector2i, rng: SimRNG,
		def_id: String, total: int, _unused: int) -> void:
	for i in total:
		out.append({"def_id": def_id, "tile": Vector2i(
			rng.next_int(SPAWN_MARGIN, size.x - SPAWN_MARGIN),
			rng.next_int(SPAWN_MARGIN, size.y - SPAWN_MARGIN)),
			"amount": ResourceNode.USE_DEF_AMOUNT})


# --------------------------------------------------------------- fallback --
func _use_fallback(failed_path: String, seed: int, count: int) -> Dictionary:
	last_fallback_used = true
	var raw := load_file(FALLBACK_MAP)
	if raw.is_empty():
		last_errors.append("fallback '%s' también falló: mapa mínimo hardcoded" % FALLBACK_MAP)
		var size := Vector2i(144, 144)
		var rng := SimRNG.new()
		rng.set_seed(seed)
		var spawns := _make_spawns(size, count, rng)
		var res := _resources_from_counts(size, spawns,
			{"wood_patches": 8, "gold_piles": 6, "stone_piles": 4, "forage": 4, "boars": 2}, rng)
		rng.free()
		return {"map": {"name": "fallback_minimo", "size": size,
			"terrain_grid": [], "resources": res, "spawns": spawns,
			"seed": seed, "source": "hardcoded"},
			"fallback_used": true, "errors": last_errors.duplicate(true),
			"source_path": failed_path}
	var common := to_common(raw, FALLBACK_MAP, seed, count)
	return {"map": common, "fallback_used": true,
		"errors": last_errors.duplicate(true), "source_path": FALLBACK_MAP}


# ----------------------------------------------------------------- ayuda --
static func _as_vec2i(v) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(int(v.x), int(v.y))
	if v is Array and v.size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)


static func _in_bounds(v, size: Vector2i) -> bool:
	var t := _as_vec2i(v)
	return t.x >= 0 and t.y >= 0 and t.x < size.x and t.y < size.y


static func _clamp_tile(t: Vector2i, size: Vector2i) -> Vector2i:
	return Vector2i(clampi(t.x, 1, size.x - 2), clampi(t.y, 1, size.y - 2))


static func _check_min_spawn_distance(spawns: Array, size: Vector2i, errors: Array) -> void:
	var min_d := float(mini(size.x, size.y)) * 0.15
	for i in spawns.size():
		for j in range(i + 1, spawns.size()):
			var a := _as_vec2i(spawns[i])
			var b := _as_vec2i(spawns[j])
			if Vector2(a - b).length() < min_d:
				errors.append("spawns %d y %d demasiado juntos (%s vs %s)" % [i, j, str(a), str(b)])
