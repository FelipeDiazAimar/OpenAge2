extends Node
# Garrison.gd — sistema de guarecer / desguarecer (tecla G / U, campana T).
# AoE2 1:1: TC 15, torre 5, castillo 20, ariete 4 (solo infantería, +velocidad).
# Aldeanos guarecidos disparan flechas desde dentro (TC 5 base +1 por aldeano).
# Al destruir un edificio, evacuación automática (spawn en anillo alrededor).
#
# Comandos (via EventBus.command_issued, formato core/API.md):
#   SimAPI.queue_command(pid, "garrison",   {"unit_ids": [1,2], "building": 10})
#   SimAPI.queue_command(pid, "ungarrison", {"building": 10})                 # U = todos
#   SimAPI.queue_command(pid, "ungarrison", {"building": 10, "unit_ids": [1]}) # parcial
#   SimAPI.queue_command(pid, "bell",       {"on": true})                     # T campana
# La destrucción (evacuación) llega como type "building_destroyed" {"building": id}
# o por llamada directa a on_building_destroyed(id) desde el sistema de combate.
#
# DETERMINISMO lockstep 10Hz: sin randf/Time/OS. Spawn en anillo de ángulos fijos
# (ordenado por unit_id), floats quantizados a 0.001. Estado serializable + hash
# FNV-1a propio (no depende del orden de autoloads) para checks anti-desync.
# Registro autocontenido: los sistemas llaman a register_building/register_unit
# (entities/ está vacío a fecha de este fichero; cuando exista entidad real,
# este módulo sigue siendo la autoridad de quién está dentro de qué).

signal unit_garrisoned(unit_id: int, building_id: int)
signal unit_ungarrisoned(unit_id: int, building_id: int)
signal building_evacuated(building_id: int, unit_ids: Array)

# --- Capacidades AoE2 ---------------------------------------------------------
const CAP_TC := 15
const CAP_TOWER := 5
const CAP_CASTLE := 20
const CAP_RAM := 4
# Edificios no listados aquí no admiten guarnición (capacidad 0: casas, cuartel...).
const CAPACITY_BY_TYPE := {
	"centro_urbano": CAP_TC, "tc": CAP_TC, "town_center": CAP_TC,
	"torre": CAP_TOWER, "torre_vigia": CAP_TOWER, "torre_homenaje": CAP_TOWER,
	"tower": CAP_TOWER, "watch_tower": CAP_TOWER, "keep": CAP_TOWER,
	"castillo": CAP_CASTLE, "castle": CAP_CASTLE,
	"ariete": CAP_RAM, "ariete_capuchado": CAP_RAM, "ram": CAP_RAM,
}
# --- Flechas disparadas desde dentro ------------------------------------------
const TC_BASE_ARROWS := 5      # TC dispara 5 base +1 por aldeano guarecido
const TOWER_BASE_ARROWS := 1   # torre 1 base +1 por unidad (máx +5 = cap 5)
const TOWER_MAX_BONUS := 5
const CASTLE_BASE_ARROWS := 5  # castillo 5 base +1 por unidad guarecida
# --- Ariete --------------------------------------------------------------------
const RAM_SPEED_PER_UNIT := 0.1 # lleno (4) => x1.4 velocidad; vacío => x1.0
# Kinds que el ariete acepta (infantería a pie). Kinds desconocidos (mods) se
# aceptan salvo que estén en la lista de rechazo explícita de abajo.
const INFANTRY_KINDS := [
	"milicia", "militia", "hombre_de_armas", "espadachin_mandoble", "campeon",
	"champion", "lancero", "piquero", "alabardero", "halberdier", "huscarle",
	"infanteria", "infantry",
]
const RAM_REJECT_KINDS := [ # aldeanos, ranged, monjes, asedio, comercio, barcos
	"aldeano", "villager", "arquero", "archer", "guerrillero", "skirmisher",
	"monje", "monk", "ariete", "ram", "onagro", "mangonel", "escorpion",
	"scorpion", "catapulta", "cañon", "bombarda", "carreta_comercio",
	"trade_cart", "pesquero", "fishing_ship", "barco", "galera",
]
const SIEGE_KINDS := [ # no entran en TC/torre/castillo (sí en ariete si infantería)
	"ariete", "ram", "ariete_capuchado", "onagro", "mangonel", "escorpion",
	"scorpion", "catapulta", "cañon", "bombarda",
]
# --- Spawn desguarecer (U) ------------------------------------------------------
const SPAWN_RING_RADIUS := 2.0  # radio base en tiles desde el centro
const SPAWN_RING_GROW := 0.5    # +radio por cada vuelta completa de 8
const SPAWN_PER_RING := 8

# --- Estado --------------------------------------------------------------------
# buildings: int id -> {type:String, pos:Vector2, owner:int, alive:bool}
var buildings: Dictionary = {}
# units: int id -> {kind:String, pos:Vector2, owner:int}
var units: Dictionary = {}
# garrisons: int building_id -> Array[int] unit_ids (siempre ordenado asc)
var garrisons: Dictionary = {}
# garrisoned_in: int unit_id -> int building_id
var garrisoned_in: Dictionary = {}
# bell_on: int player_id -> bool (campana T activa)
var bell_on: Dictionary = {}

# FNV-1a 32-bit (duplicado de SimAPI para no depender del orden de autoloads)
const _FNV_BASIS := 2166136261
const _FNV_PRIME := 16777619
const _FNV_MASK := 0xFFFFFFFF


func _ready() -> void:
	if EventBus != null:
		EventBus.command_issued.connect(_on_command)


func reset() -> void:
	buildings.clear()
	units.clear()
	garrisons.clear()
	garrisoned_in.clear()
	bell_on.clear()

# --- Registro ------------------------------------------------------------------

func register_building(bid: int, btype: String, pos: Vector2, owner: int) -> void:
	buildings[bid] = {
		"type": _norm(btype), "pos": _qpos(pos), "owner": owner, "alive": true,
	}
	if not garrisons.has(bid):
		garrisons[bid] = []

func register_unit(uid: int, kind: String, pos: Vector2, owner: int) -> void:
	units[uid] = {"kind": _norm(kind), "pos": _qpos(pos), "owner": owner}

func unregister_unit(uid: int) -> void:
	if garrisoned_in.has(uid):
		_remove_from_garrison(uid, int(garrisoned_in[uid]), false)
	units.erase(uid)

func remove_building(bid: int) -> void:
	# Borrado limpio (sin evacuación). Para destrucción usar on_building_destroyed.
	buildings.erase(bid)
	garrisons.erase(bid)

func set_building_alive(bid: int, alive: bool) -> void:
	if buildings.has(bid):
		buildings[bid]["alive"] = alive

func _norm(s: String) -> String:
	return s.to_lower().strip_edges().replace(" ", "_")

func _qpos(p: Vector2) -> Vector2:
	return Vector2(snappedf(p.x, 0.001), snappedf(p.y, 0.001))

# --- Consultas -----------------------------------------------------------------

func building_type(bid: int) -> String:
	if not buildings.has(bid):
		return ""
	return str(buildings[bid]["type"])

func get_capacity(bid: int) -> int:
	if not buildings.has(bid):
		return 0
	return int(CAPACITY_BY_TYPE.get(str(buildings[bid]["type"]), 0))

func get_garrisoned(bid: int) -> Array:
	var out: Array = (garrisons.get(bid, []) as Array).duplicate()
	out.sort()
	return out

func get_garrison_count(bid: int) -> int:
	return (garrisons.get(bid, []) as Array).size()

func get_free_slots(bid: int) -> int:
	return maxi(0, get_capacity(bid) - get_garrison_count(bid))

func is_garrisoned(uid: int) -> bool:
	return garrisoned_in.has(uid)

func get_building_of(uid: int) -> int:
	return int(garrisoned_in.get(uid, -1))

func is_garrison_building(bid: int) -> bool:
	return get_capacity(bid) > 0

func can_garrison(uid: int, bid: int, allow_ally: bool = false) -> Dictionary:
	# {ok, reason}. No muta estado. Razones: bad_unit, bad_building, destroyed,
	# no_capacity, already_inside, full, wrong_owner, not_infantry, siege.
	if not units.has(uid):
		return {"ok": false, "reason": "bad_unit"}
	if not buildings.has(bid):
		return {"ok": false, "reason": "bad_building"}
	var b: Dictionary = buildings[bid]
	if not bool(b.get("alive", true)):
		return {"ok": false, "reason": "destroyed"}
	if get_capacity(bid) <= 0:
		return {"ok": false, "reason": "no_capacity"}
	if garrisoned_in.has(uid):
		return {"ok": false, "reason": "already_inside"}
	if get_free_slots(bid) <= 0:
		return {"ok": false, "reason": "full"}
	var u: Dictionary = units[uid]
	if int(u["owner"]) != int(b["owner"]) and not allow_ally:
		return {"ok": false, "reason": "wrong_owner"}
	var kind := str(u["kind"])
	var btype := str(b["type"])
	if _is_ram(btype):
		if not _accepts_ram(kind):
			return {"ok": false, "reason": "not_infantry"}
	elif kind in SIEGE_KINDS:
		return {"ok": false, "reason": "siege"}
	return {"ok": true, "reason": "ok"}

func _is_ram(btype: String) -> bool:
	return int(CAPACITY_BY_TYPE.get(btype, 0)) == CAP_RAM and btype in [
		"ariete", "ariete_capuchado", "ram"]

func _accepts_ram(kind: String) -> bool:
	if kind in INFANTRY_KINDS:
		return true
	return not (kind in RAM_REJECT_KINDS) # abierto a mods: lo desconocido entra

# --- Guarecer / desguarecer ------------------------------------------------------

func garrison_unit(uid: int, bid: int, allow_ally: bool = false) -> bool:
	var chk := can_garrison(uid, bid, allow_ally)
	if not bool(chk.get("ok", false)):
		return false
	(garrisons[bid] as Array).append(uid)
	(garrisons[bid] as Array).sort()
	garrisoned_in[uid] = bid
	unit_garrisoned.emit(uid, bid)
	return true

## Guarece una lista en orden asc de unit_id (determinista). Devuelve nº ok.
func garrison_many(uids: Array, bid: int, allow_ally: bool = false) -> int:
	var ordered: Array = uids.duplicate()
	ordered.sort()
	var n := 0
	for uid in ordered:
		if garrison_unit(int(uid), bid, allow_ally):
			n += 1
	return n

func _remove_from_garrison(uid: int, bid: int, respawn: bool) -> Vector2:
	(garrisons.get(bid, []) as Array).erase(uid)
	garrisoned_in.erase(uid)
	var out := _building_pos(bid)
	if respawn:
		units[uid]["pos"] = out # se recoloca en ungarrison_all/spawn; ver abajo
	unit_ungarrisoned.emit(uid, bid)
	return out

func _building_pos(bid: int) -> Vector2:
	if buildings.has(bid):
		return buildings[bid]["pos"]
	return Vector2.ZERO

## Desguarece (tecla U). unit_ids vacío = todos. Spawn en anillo determinista.
## Devuelve Array[{unit, pos}] en orden asc de unit_id.
func ungarrison(bid: int, unit_ids: Array = []) -> Array:
	if not garrisons.has(bid):
		return []
	var inside: Array = get_garrisoned(bid)
	var wanted: Array
	if unit_ids.is_empty():
		wanted = inside
	else:
		wanted = []
		var want_set: Array = (unit_ids as Array).map(func(x): return int(x))
		for uid in inside:
			if int(uid) in want_set:
				wanted.append(int(uid))
		wanted.sort()
	var spots := get_spawn_positions(bid, wanted)
	var out: Array = []
	for i in wanted.size():
		var uid := int(wanted[i])
		(garrisons[bid] as Array).erase(uid)
		garrisoned_in.erase(uid)
		units[uid]["pos"] = spots[i]
		unit_ungarrisoned.emit(uid, bid)
		out.append({"unit": uid, "pos": spots[i]})
	return out

func ungarrison_all(bid: int) -> Array:
	return ungarrison(bid, [])

## Evacuación al destruir el edificio: saca a todos y marca el edificio muerto.
## Devuelve Array[{unit, pos}] (orden asc unit_id). No falla si ya estaba muerto.
func on_building_destroyed(bid: int) -> Array:
	if not buildings.has(bid):
		return []
	buildings[bid]["alive"] = false
	var out := ungarrison(bid, [])
	building_evacuated.emit(bid, out.map(func(e): return int(e["unit"])))
	return out

## Posiciones de spawn en anillo: ángulo = TAU*k/n, radio crece por vueltas.
## Puro determinista (sin RNG): mismo (pos, ids) => mismos spots.
func get_spawn_positions(bid: int, unit_ids: Array) -> Array:
	var ordered: Array = unit_ids.duplicate()
	ordered.sort()
	var center := _building_pos(bid)
	var out: Array = []
	var n := ordered.size()
	for k in n:
		var ring := k / SPAWN_PER_RING
		var slot := k % SPAWN_PER_RING
		var per := mini(SPAWN_PER_RING, n - ring * SPAWN_PER_RING)
		var ang := TAU * float(slot) / float(maxi(1, per))
		var r := SPAWN_RING_RADIUS + SPAWN_RING_GROW * float(ring)
		out.append(_qpos(center + Vector2(cos(ang), sin(ang)) * r))
	return out

# --- Campana (T) ------------------------------------------------------------------

func set_bell(player_id: int, on: bool) -> int:
	# on=true: aldeanos del jugador entran en sus TCs con hueco (por id).
	# on=false: salen todos los aldeanos guarecidos del jugador.
	# Devuelve nº de unidades movidas.
	bell_on[player_id] = on
	var moved := 0
	if on:
		var tcs: Array = []
		for bid in buildings.keys():
			var b: Dictionary = buildings[bid]
			if int(b["owner"]) == player_id and bool(b.get("alive", true)) \
					and str(b["type"]) in ["centro_urbano", "tc", "town_center"] \
					and get_free_slots(int(bid)) > 0:
				tcs.append(int(bid))
		tcs.sort()
		var vills: Array = []
		for uid in units.keys():
			var u: Dictionary = units[uid]
			if int(u["owner"]) == player_id and str(u["kind"]) in ["aldeano", "villager"] \
					and not garrisoned_in.has(uid):
				vills.append(int(uid))
		vills.sort()
		for uid in vills:
			for bid in tcs:
				if garrison_unit(uid, bid):
					moved += 1
					break
	else:
		var inside: Array = []
		for uid in garrisoned_in.keys():
			var u: Dictionary = units.get(uid, {})
			if u.is_empty():
				continue
			if int(u["owner"]) == player_id and str(u["kind"]) in ["aldeano", "villager"]:
				inside.append(int(uid))
		inside.sort()
		var by_building := {}
		for uid in inside:
			var bid := int(garrisoned_in[uid])
			if not by_building.has(bid):
				by_building[bid] = []
			(by_building[bid] as Array).append(uid)
		for bid in by_building.keys():
			moved += (ungarrison(int(bid), by_building[bid]) as Array).size()
	return moved

func is_bell_on(player_id: int) -> bool:
	return bool(bell_on.get(player_id, false))

# --- Flechas desde dentro ----------------------------------------------------------

func count_villagers_inside(bid: int) -> int:
	var n := 0
	for uid in (garrisons.get(bid, []) as Array):
		if units.has(uid) and str(units[uid]["kind"]) in ["aldeano", "villager"]:
			n += 1
	return n

## Nº de flechas que dispara el edificio: TC 5+aldeanos, torre 1+unidades
## (máx +5), castillo 5+unidades. Ariete y resto: 0 (no disparan).
func get_arrow_count(bid: int) -> int:
	if not buildings.has(bid) or not bool(buildings[bid].get("alive", true)):
		return 0
	var n := get_garrison_count(bid)
	match str(buildings[bid]["type"]):
		"centro_urbano", "tc", "town_center":
			return TC_BASE_ARROWS + count_villagers_inside(bid)
		"torre", "torre_vigia", "torre_homenaje", "tower", "watch_tower", "keep":
			return TOWER_BASE_ARROWS + mini(n, TOWER_MAX_BONUS)
		"castillo", "castle":
			return CASTLE_BASE_ARROWS + n
	return 0

## Unidades que aportan flechas (TC: solo aldeanos; torre/castillo: todos).
func get_arrow_units(bid: int) -> Array:
	var out: Array = []
	if not buildings.has(bid):
		return out
	var btype := str(buildings[bid]["type"])
	var tc := btype in ["centro_urbano", "tc", "town_center"]
	for uid in get_garrisoned(bid):
		if tc and not (units.has(uid) and str(units[uid]["kind"]) in ["aldeano", "villager"]):
			continue
		out.append(int(uid))
	return out

# --- Ariete: bonus de velocidad -----------------------------------------------------

## Factor de velocidad del ariete: 1.0 vacío, +RAM_SPEED_PER_UNIT por infante.
func get_ram_speed_factor(bid: int) -> float:
	if not buildings.has(bid) or not _is_ram(str(buildings[bid]["type"])):
		return 1.0
	return 1.0 + RAM_SPEED_PER_UNIT * float(get_garrison_count(bid))

# --- Comandos via EventBus ------------------------------------------------------------

func _on_command(cmd: Dictionary) -> void:
	apply_command(cmd)

## Punto de entrada determinista (llamado en tick lockstep / tests).
func apply_command(cmd: Dictionary) -> void:
	if typeof(cmd) != TYPE_DICTIONARY:
		return
	var t := str(cmd.get("type", ""))
	var payload: Dictionary = cmd.get("payload", {})
	match t:
		"garrison":
			var bid := int(payload.get("building", payload.get("building_id", payload.get("target", -1))))
			var uids: Array = (payload.get("unit_ids", payload.get("units", [])) as Array).duplicate()
			garrison_many(uids, bid, bool(payload.get("allow_ally", false)))
		"ungarrison":
			var bid2 := int(payload.get("building", payload.get("building_id", -1)))
			var uids2: Array = (payload.get("unit_ids", payload.get("units", [])) as Array).duplicate()
			ungarrison(bid2, uids2)
		"bell":
			set_bell(int(cmd.get("player_id", payload.get("player_id", 0))), bool(payload.get("on", true)))
		"building_destroyed", "demolish":
			on_building_destroyed(int(payload.get("building", payload.get("building_id", -1))))

# --- Guardado + hash anti-desync ----------------------------------------------------------

func save_state() -> Dictionary:
	var b: Dictionary = {}
	for bid in buildings.keys():
		var e: Dictionary = (buildings[bid] as Dictionary).duplicate()
		e["pos"] = [float((e["pos"] as Vector2).x), float((e["pos"] as Vector2).y)]
		b[str(int(bid))] = e
	var u: Dictionary = {}
	for uid in units.keys():
		var e2: Dictionary = (units[uid] as Dictionary).duplicate()
		e2["pos"] = [float((e2["pos"] as Vector2).x), float((e2["pos"] as Vector2).y)]
		u[str(int(uid))] = e2
	var g: Dictionary = {}
	for bid in garrisons.keys():
		g[str(int(bid))] = get_garrisoned(int(bid))
	var bells: Dictionary = {}
	for pid in bell_on.keys():
		bells[str(int(pid))] = bool(bell_on[pid])
	return {"buildings": b, "units": u, "garrisons": g, "bell": bells}

func load_state(d: Dictionary) -> void:
	reset()
	for k in (d.get("buildings", {}) as Dictionary).keys():
		var e: Dictionary = (d["buildings"] as Dictionary)[k]
		var p: Array = e.get("pos", [0, 0])
		buildings[int(k)] = {
			"type": str(e.get("type", "")), "pos": Vector2(float(p[0]), float(p[1])),
			"owner": int(e.get("owner", 0)), "alive": bool(e.get("alive", true)),
		}
	for k in (d.get("units", {}) as Dictionary).keys():
		var e2: Dictionary = (d["units"] as Dictionary)[k]
		var p2: Array = e2.get("pos", [0, 0])
		units[int(k)] = {
			"kind": str(e2.get("kind", "")), "pos": Vector2(float(p2[0]), float(p2[1])),
			"owner": int(e2.get("owner", 0)),
		}
	for k in (d.get("garrisons", {}) as Dictionary).keys():
		var bid := int(k)
		var arr: Array = ((d["garrisons"] as Dictionary)[k] as Array).duplicate()
		arr.sort()
		garrisons[bid] = arr
		for uid in arr:
			garrisoned_in[int(uid)] = bid
	for k in (d.get("bell", {}) as Dictionary).keys():
		bell_on[int(k)] = bool((d["bell"] as Dictionary)[k])

## String canónico (claves e ids ordenados) para hash / depuración.
func serialize_state() -> String:
	var parts: PackedStringArray = []
	var bids: Array = garrisons.keys()
	bids.sort()
	for bid in bids:
		var inner: PackedStringArray = []
		for uid in get_garrisoned(int(bid)):
			inner.append(str(int(uid)))
		parts.append("%d:%s:%s:[%s]" % [
			int(bid), building_type(int(bid)),
			"1" if bool((buildings.get(bid, {}) as Dictionary).get("alive", true)) else "0",
			",".join(inner),
		])
	return ";".join(parts)

func sim_hash_state() -> int:
	var h: int = _FNV_BASIS
	for b in serialize_state().to_utf8_buffer():
		h = ((h ^ int(b)) * _FNV_PRIME) & _FNV_MASK
	return h
