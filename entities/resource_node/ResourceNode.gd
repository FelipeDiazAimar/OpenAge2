extends Node
class_name ResourceNode
## ResourceNode — nodo de recurso agotable, determinista (Godot 4.4, GDScript).
##
## Cubre data/maps/resource_defs.json:
##   tree (100 madera), berry_bush (125 alimento), boar (340), sheep (100),
##   deer (140), gold_mine (800 oro), stone_mine (800 piedra),
##   shore_fish (infinito, costero).
## Sin regen (regen_per_sec = 0). Agotable salvo pesca infinita.
##
## API pedida:
##   register() -> bool        | registra en el índice global (id único).
##   harvest(amount: int) -> int (taken: lo realmente extraído).
##   is_depleted() -> bool
##
## Determinismo (lockstep 10 Hz, core/API.md):
##   - Solo aritmética entera. NADA de randf/Time/floats acumulados en lógica.
##   - amount == INFINITE (-1) = nunca se agota (banco de peces).
##   - Orden canónico (ids ordenados) en serialización y save_all.
## Guardado:
##   - get_state() / load_state(d) por nodo.
##   - save_all(path) / load_all(path) estáticos para partida guardada.

const DEFS_PATH := "res://data/maps/resource_defs.json"
const INFINITE := -1
const USE_DEF_AMOUNT := -2 # centinela de setup(): usar amount del def

# Fallback si el JSON no es legible. Debe coincidir con resource_defs.json.
const FALLBACK_AMOUNTS := {
	"tree": 100,
	"berry_bush": 125,
	"boar": 340,
	"sheep": 100,
	"deer": 140,
	"gold_mine": 800,
	"stone_mine": 800,
	"shore_fish": INFINITE,
}
const FALLBACK_RESOURCE := {
	"tree": "wood",
	"berry_bush": "food",
	"boar": "food",
	"sheep": "food",
	"deer": "food",
	"gold_mine": "gold",
	"stone_mine": "stone",
	"shore_fish": "food",
}

static var _registry: Dictionary = {} # int node_id -> ResourceNode
static var _defs_cache: Dictionary = {} # String def_id -> Dictionary (cargado del JSON)
static var _defs_loaded := false

var node_id: int = -1
var def_id: String = ""
var resource: String = "" # "wood" | "food" | "gold" | "stone"
var amount_left: int = 0 # INFINITE (-1) = pesca infinita
var amount_max: int = 0
var depletable: bool = true
var regen_per_sec: float = 0.0 # siempre 0: sin regen (documentado, no aplicado)
var coastal: bool = false
var _registered := false


# --- Definiciones -------------------------------------------------------

static func _fallback_def(p_def_id: String) -> Dictionary:
	var amt: int = int(FALLBACK_AMOUNTS.get(p_def_id, 0))
	return {
		"id": p_def_id,
		"resource": str(FALLBACK_RESOURCE.get(p_def_id, "")),
		"amount": amt,
		"infinite": amt == INFINITE,
		"depletable": amt != INFINITE,
		"regen_per_sec": 0.0,
		"coastal": p_def_id == "shore_fish",
	}

## Carga resource_defs.json a caché estática. Idempotente. Devuelve nº de defs.
static func load_defs(path: String = DEFS_PATH) -> int:
	_defs_cache.clear()
	_defs_loaded = false
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("resources"):
				for r in parsed["resources"]:
					if typeof(r) == TYPE_DICTIONARY and r.has("id"):
						var did := str(r["id"])
						_defs_cache[did] = {
							"id": did,
							"resource": str(r.get("resource", "")),
							"amount": int(r.get("amount", 0)),
							"infinite": bool(r.get("infinite", int(r.get("amount", 0)) == INFINITE)),
							"depletable": bool(r.get("depletable", int(r.get("amount", 0)) != INFINITE)),
							"regen_per_sec": 0.0, # forzado: sin regen por diseño
							"coastal": bool(r.get("coastal", false)),
						}
				_defs_loaded = true
				return _defs_cache.size()
	# Fallback: 8 defs compiladas (partida sigue siendo jugable/determinista).
	for did in FALLBACK_AMOUNTS.keys():
		_defs_cache[str(did)] = _fallback_def(str(did))
	_defs_loaded = true
	return _defs_cache.size()

static func get_def(p_def_id: String) -> Dictionary:
	if not _defs_loaded:
		load_defs()
	if _defs_cache.has(p_def_id):
		return (_defs_cache[p_def_id] as Dictionary).duplicate(true)
	return _fallback_def(p_def_id)

static func def_ids() -> Array:
	if not _defs_loaded:
		load_defs()
	var out: Array = _defs_cache.keys()
	out.sort()
	return out


# --- Ciclo de vida ------------------------------------------------------

## Configura el nodo ANTES de register(). p_amount_override == USE_DEF_AMOUNT
## usa la cantidad del def; cualquier otro valor la sustituye (INFINITE = infinito).
func setup(p_node_id: int, p_def_id: String, p_amount_override: int = USE_DEF_AMOUNT) -> bool:
	if _registered:
		push_error("ResourceNode.setup: nodo %d ya registrado, no reconfigurable" % node_id)
		return false
	if p_node_id < 0 or p_def_id.is_empty():
		push_error("ResourceNode.setup: id/def inválidos (%d, '%s')" % [p_node_id, p_def_id])
		return false
	var d := ResourceNode.get_def(p_def_id)
	node_id = p_node_id
	def_id = p_def_id
	resource = str(d.get("resource", ""))
	var base_amt: int = int(d.get("amount", 0))
	var amt: int = base_amt if p_amount_override == USE_DEF_AMOUNT else p_amount_override
	if amt == INFINITE or (p_amount_override == USE_DEF_AMOUNT and bool(d.get("infinite", false))):
		amount_left = INFINITE
		amount_max = INFINITE
		depletable = false
	else:
		amount_left = maxi(0, amt)
		amount_max = maxi(0, amt)
		depletable = bool(d.get("depletable", true))
	regen_per_sec = 0.0
	coastal = bool(d.get("coastal", false))
	return true

## Registra en el índice global. false si id duplicado o nodo sin setup.
func register() -> bool:
	if node_id < 0 or def_id.is_empty():
		push_error("ResourceNode.register: llamar a setup() primero")
		return false
	if _registry.has(node_id):
		push_error("ResourceNode.register: node_id duplicado: %d" % node_id)
		return false
	_registry[node_id] = self
	_registered = true
	return true

func unregister() -> bool:
	return ResourceNode.unregister_id(node_id) if _registered else false

func _exit_tree() -> void:
	if _registered and _registry.get(node_id) == self:
		_registry.erase(node_id)
		_registered = false

static func unregister_id(p_node_id: int) -> bool:
	if _registry.has(p_node_id):
		var n = _registry[p_node_id] as ResourceNode
		_registry.erase(p_node_id)
		if n != null:
			n._registered = false
		return true
	return false

static func clear_all() -> void:
	for k in _registry.keys():
		var n = _registry[k] as ResourceNode
		if n != null:
			n._registered = false
	_registry.clear()

static func is_registered(p_node_id: int) -> bool:
	return _registry.has(p_node_id)

static func get_by_id(p_node_id: int) -> ResourceNode:
	return _registry.get(p_node_id) as ResourceNode

static func ids_sorted() -> Array:
	var out: Array = _registry.keys()
	out.sort()
	return out

static func count() -> int:
	return _registry.size()


# --- Cosecha (núcleo determinista) --------------------------------------

## Extrae hasta `requested` unidades. Devuelve lo realmente extraído (taken).
## Infinito: devuelve `requested` sin mermar. Agotado o requested<=0: 0.
func harvest(requested: int) -> int:
	if requested <= 0:
		return 0
	if amount_left == INFINITE:
		return requested
	if amount_left <= 0:
		return 0
	var taken: int = mini(requested, amount_left)
	amount_left -= taken
	return taken

func is_depleted() -> bool:
	if amount_left == INFINITE:
		return false
	return amount_left <= 0

## Restante (-1 = infinito). Solo lectura, para HUD/IA.
func remaining() -> int:
	return amount_left


# --- Guardado + estado canónico -----------------------------------------

func get_state() -> Dictionary:
	return {
		"node_id": node_id,
		"def_id": def_id,
		"resource": resource,
		"amount_left": amount_left,
		"amount_max": amount_max,
		"depletable": depletable,
		"regen_per_sec": 0.0,
		"coastal": coastal,
	}

## Restaura estado guardado. Devuelve false si el dict es inválido.
func load_state(s: Dictionary) -> bool:
	if not s.has("node_id") or not s.has("def_id"):
		push_error("ResourceNode.load_state: dict inválido (falta node_id/def_id)")
		return false
	node_id = int(s.get("node_id", -1))
	def_id = str(s.get("def_id", ""))
	resource = str(s.get("resource", ""))
	amount_left = int(s.get("amount_left", 0))
	amount_max = int(s.get("amount_max", 0))
	depletable = bool(s.get("depletable", amount_left != INFINITE))
	regen_per_sec = 0.0
	coastal = bool(s.get("coastal", false))
	if node_id < 0 or def_id.is_empty():
		return false
	return true

## Cadena canónica ordenada por node_id (para hash anti-desync vía SimAPI).
static func canonical_string() -> String:
	var parts: PackedStringArray = []
	for k in ids_sorted():
		var n := _registry[k] as ResourceNode
		parts.append("%d:%s:%s:%d" % [n.node_id, n.def_id, n.resource, n.amount_left])
	return ";".join(parts)

## Guarda todos los registrados en JSON {node_id: state}. Ordenado por id.
static func save_all(path: String) -> bool:
	var all: Dictionary = {}
	for k in ids_sorted():
		var n := _registry[k] as ResourceNode
		all[str(int(k))] = n.get_state()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ResourceNode.save_all: no se pudo escribir %s" % path)
		return false
	f.store_string(JSON.stringify(all, "\t"))
	return true

## Carga un save_all(): limpia el registro y recrea los nodos. Devuelve nº.
static func load_all(path: String) -> int:
	if not FileAccess.file_exists(path):
		push_error("ResourceNode.load_all: no existe %s" % path)
		return -1
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ResourceNode.load_all: no se pudo leer %s" % path)
		return -1
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ResourceNode.load_all: JSON inválido en %s" % path)
		return -1
	clear_all()
	var n := 0
	var keys: Array = (parsed as Dictionary).keys()
	keys.sort()
	for k in keys:
		var s = (parsed as Dictionary)[k]
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var node := ResourceNode.new()
		if node.load_state(s):
			if _registry.has(node.node_id):
				push_error("ResourceNode.load_all: node_id duplicado en save: %d" % node.node_id)
				node.free()
				continue
			# Inserción directa: el save ya trae ids validados.
			_registry[node.node_id] = node
			node._registered = true
			n += 1
		else:
			node.free()
	return n
