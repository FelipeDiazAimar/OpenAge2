extends Node
# RangedSiege - tiro a distancia y asedio determinista por tick (lockstep 10Hz).
#
# Cubre las unidades de data/units/*.json de rango/asedio:
#   tiro recto (proyectil via Combat): guerrillero, ballestero, arquero_tiro_largo.
#   asedio: ariete (melee anti-edificio), catapulta (dano en area via
#     SiegeProjectiles, radio 2.0), trebuchet/trabuquete (alcance 16, solo
#     dispara desempaquetado, con zona muerta min_range 3.0).
# PACK_UNPACK: el trebuchet alterna entre movil (empaquetado, no dispara) y
#   fijo (desempaquetado, dispara). Transiciones de 3.0s = 30 ticks.
#
# Determinismo: sin randf/randi/Time/fisica; iteracion ordenada por id;
#   contadores en ticks enteros; solo se mueve/dispara segun estado pack.
#   Tick 10Hz: avanzar con tick(t) o via EventBus.tick_finished. Comandos
#   pack/unpack via EventBus.command_issued (tipos: pack, unpack, pack_toggle
#   y alias ES: empacar, desempacar). Fuente de verdad de stats: los JSON.

class_name RangedSiege

signal pack_state_changed(unit_id: int, packed: bool)

const TICK_RATE := 10 # debe coincidir con SimAPI.TICK_RATE
const DT := 0.1 # 1.0 / TICK_RATE, sin Time ni delta flotante en logica

const KIND_GUERRILLERO := "guerrillero"
const KIND_BALLESTERO := "ballestero"
const KIND_TIRO_LARGO := "arquero_tiro_largo"
const KIND_ARIETE := "ariete"
const KIND_CATAPULTA := "catapulta"
const KIND_TREBUCHET := "trebuchet"
const KIND_TRABUQUETE := "trabuquete" # alias ES (data/buildings/castillo.json)

const ARCHER_LINE := [KIND_GUERRILLERO, KIND_BALLESTERO, KIND_TIRO_LARGO]
const SIEGE_KINDS := [KIND_ARIETE, KIND_CATAPULTA, KIND_TREBUCHET, KIND_TRABUQUETE]
const PACKABLE_KINDS := [KIND_TREBUCHET, KIND_TRABUQUETE]

# PACK_UNPACK: nombres canonicos de la accion empacar/desempacar del trebuchet.
const ACTION_PACK := "pack"
const ACTION_UNPACK := "unpack"
const ACTION_PACK_TOGGLE := "pack_toggle"
const PACK_UNPACK := {
	"pack": ACTION_PACK,
	"unpack": ACTION_UNPACK,
	"toggle": ACTION_PACK_TOGGLE,
}
# Alias aceptados en command_issued (ES + EN).
const CMD_PACK := ["pack", "empacar"]
const CMD_UNPACK := ["unpack", "desempacar"]
const CMD_TOGGLE := ["pack_toggle", "pack_unpack", "empacar_desempacar"]

const PACK_TIME_SEC := 3.0 # -> PACK_TICKS
const UNPACK_TIME_SEC := 3.0 # -> UNPACK_TICKS
const PACK_TICKS := 30
const UNPACK_TICKS := 30

const TREB_RANGE := 16.0 # trebuchet.json range
const TREB_MIN_RANGE := 3.0 # zona muerta: muy cerca no puede disparar
const CATAPULT_MIN_RANGE := 3.0 # catapulta.json min_range
const CATAPULT_SPLASH := 2.0 # = SiegeProjectiles.SPLASH_RADIUS
const TREB_SPLASH := 1.0 # trebuchet: tiro de precision, area menor

const TR_NONE := ""
const TR_PACKING := "packing"
const TR_UNPACKING := "unpacking"

# id -> {id, kind, packed:bool, transitioning:String, progress:int, progress_total:int}
var _units := {}


func _ready() -> void:
	EventBus.tick_finished.connect(_on_tick)
	EventBus.command_issued.connect(_on_cmd)


# ------------------------------------------------------------ clasificar ---
static func _norm_kind(kind: String) -> String:
	return kind.to_lower().strip_edges()


static func is_packable(kind: String) -> bool:
	return _norm_kind(kind) in PACKABLE_KINDS


static func is_siege(kind: String) -> bool:
	return _norm_kind(kind) in SIEGE_KINDS


static func is_archer_line(kind: String) -> bool:
	return _norm_kind(kind) in ARCHER_LINE


## True si la unidad usa parabola de catapulta (SiegeProjectiles) en vez de flecha.
static func uses_catapult_projectile(kind: String) -> bool:
	var k := _norm_kind(kind)
	return k == KIND_CATAPULTA or k in PACKABLE_KINDS


## Radio de area documentado (catapulta 2.0, trebuchet 1.0, resto 0.0).
static func splash_radius_for(kind: String) -> float:
	var k := _norm_kind(kind)
	if k == KIND_CATAPULTA:
		return CATAPULT_SPLASH
	if k in PACKABLE_KINDS:
		return TREB_SPLASH
	return 0.0


## Zona muerta minima (los JSON la traen; fallback por si falta el dato).
static func min_range_for(kind: String) -> float:
	var k := _norm_kind(kind)
	if k in PACKABLE_KINDS:
		return TREB_MIN_RANGE
	if k == KIND_CATAPULTA:
		return CATAPULT_MIN_RANGE
	return 0.0


## True si `to` esta a distancia disparable desde `from` (respeta min_range).
static func in_range(from, to, max_range: float, kind: String = "") -> bool:
	var a := _as_vec2(from)
	var b := _as_vec2(to)
	var d := a.distance_to(b)
	if d > max_range + 0.001:
		return false
	if kind != "" and d < min_range_for(kind) - 0.001:
		return false
	return true


# ------------------------------------------------------------ registro ---
func register_unit(unit_id: int, kind: String, start_packed: bool = true) -> bool:
	var k := _norm_kind(kind)
	_units[unit_id] = {
		"id": unit_id, "kind": k,
		"packed": start_packed if k in PACKABLE_KINDS else false,
		"transitioning": TR_NONE, "progress": 0, "progress_total": 0,
	}
	return true


func unregister_unit(unit_id: int) -> void:
	_units.erase(unit_id)


func clear() -> void:
	_units.clear()


func has_unit(unit_id: int) -> bool:
	return _units.has(unit_id)


func get_unit(unit_id: int) -> Dictionary:
	return _units.get(unit_id, {})


func is_packed(unit_id: int) -> bool:
	return bool(_units.get(unit_id, {}).get("packed", false))


func is_transitioning(unit_id: int) -> bool:
	return str(_units.get(unit_id, {}).get("transitioning", TR_NONE)) != TR_NONE


## Solo dispara desempaquetado y quieto (sin transicion). El resto siempre puede.
func can_fire(unit_id: int) -> bool:
	if not _units.has(unit_id):
		return false
	var u: Dictionary = _units[unit_id]
	if str(u["kind"]) not in PACKABLE_KINDS:
		return true
	return not bool(u["packed"]) and str(u["transitioning"]) == TR_NONE


## El trebuchet solo se mueve empaquetado y quieto (sin transicion). El resto siempre.
func can_move(unit_id: int) -> bool:
	if not _units.has(unit_id):
		return false
	var u: Dictionary = _units[unit_id]
	if str(u["kind"]) not in PACKABLE_KINDS:
		return true
	return bool(u["packed"]) and str(u["transitioning"]) == TR_NONE


# ----------------------------------------------------- pack / unpack ---
## Empaquetar: solo si esta desempaquetado y quieto. 3.0s = 30 ticks.
func order_pack(unit_id: int) -> bool:
	if not _units.has(unit_id):
		return false
	var u: Dictionary = _units[unit_id]
	if str(u["kind"]) not in PACKABLE_KINDS:
		return false
	if bool(u["packed"]) or str(u["transitioning"]) != TR_NONE:
		return false
	u["transitioning"] = TR_PACKING
	u["progress"] = 0
	u["progress_total"] = PACK_TICKS
	return true


## Desempaquetar: solo si esta empaquetado y quieto. 3.0s = 30 ticks.
func order_unpack(unit_id: int) -> bool:
	if not _units.has(unit_id):
		return false
	var u: Dictionary = _units[unit_id]
	if str(u["kind"]) not in PACKABLE_KINDS:
		return false
	if not bool(u["packed"]) or str(u["transitioning"]) != TR_NONE:
		return false
	u["transitioning"] = TR_UNPACKING
	u["progress"] = 0
	u["progress_total"] = UNPACK_TICKS
	return true


## Alterna segun estado actual. False si no es packable o esta en transicion.
func order_pack_toggle(unit_id: int) -> bool:
	if not _units.has(unit_id):
		return false
	if is_transitioning(unit_id):
		return false
	if is_packed(unit_id):
		return order_unpack(unit_id)
	return order_pack(unit_id)


func _on_cmd(cmd: Dictionary) -> void:
	var t := str(cmd.get("type", "")).to_lower().strip_edges()
	if t not in CMD_PACK and t not in CMD_UNPACK and t not in CMD_TOGGLE:
		return
	var payload: Dictionary = cmd.get("payload", {})
	for uid in _parse_unit_ids(payload):
		if t in CMD_PACK:
			order_pack(int(uid))
		elif t in CMD_UNPACK:
			order_unpack(int(uid))
		else:
			order_pack_toggle(int(uid))


func _parse_unit_ids(payload: Dictionary) -> Array:
	var out: Array = []
	for key in ["unit_ids", "units", "ids"]:
		if payload.has(key) and typeof(payload[key]) == TYPE_ARRAY:
			for v in payload[key]:
				out.append(int(v))
	for key in ["unit_id", "unit", "id", "entity_id"]:
		if payload.has(key):
			out.append(int(payload[key]))
	var seen := {}
	var dedup: Array = []
	for v in out:
		if not seen.has(v):
			seen[v] = true
			dedup.append(v)
	return dedup


# ---------------------------------------------------------------- tick ---
func _on_tick(t: int) -> void:
	tick(t)


## Avanza 1 tick: progresa empacados/desempacados en curso. Orden por id.
func tick(_t: int = -1) -> void:
	var ids: Array = _units.keys()
	ids.sort()
	for uid in ids:
		var u: Dictionary = _units[uid]
		var tr := str(u.get("transitioning", TR_NONE))
		if tr == TR_NONE:
			continue
		u["progress"] = int(u["progress"]) + 1
		if int(u["progress"]) >= int(u["progress_total"]):
			u["transitioning"] = TR_NONE
			u["progress"] = 0
			u["progress_total"] = 0
			if tr == TR_PACKING:
				u["packed"] = true
			elif tr == TR_UNPACKING:
				u["packed"] = false
			pack_state_changed.emit(int(uid), bool(u["packed"]))


# -------------------------------------------------------------- helpers ---
static func _as_vec2(pos) -> Vector2:
	if pos is Vector2:
		return pos
	if pos is Vector3:
		return Vector2(pos.x, pos.z)
	if typeof(pos) == TYPE_DICTIONARY:
		var d: Dictionary = pos
		if d.has("pos"):
			return _as_vec2(d["pos"])
		if d.has("x") and d.has("y"):
			return Vector2(float(d["x"]), float(d["y"]))
		return Vector2.ZERO
	if typeof(pos) == TYPE_ARRAY:
		var a: Array = pos
		if a.size() >= 3:
			return Vector2(float(a[0]), float(a[2]))
		if a.size() == 2:
			return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


# ----------------------------------------------------------------- hash ---
## Cadena canonica del estado (para hash anti-desync en NetManager).
func sim_state_string() -> String:
	var parts: Array = []
	var ids: Array = _units.keys()
	ids.sort()
	for uid in ids:
		var u: Dictionary = _units[uid]
		parts.append("rs%d:%s:%s:%d" % [
			int(uid), str(u.get("kind", "")),
			str(u.get("transitioning", TR_NONE)) if str(u.get("transitioning", TR_NONE)) != TR_NONE else ("packed" if bool(u.get("packed", false)) else "unpacked"),
			int(u.get("progress", 0))])
	return "|".join(parts)
