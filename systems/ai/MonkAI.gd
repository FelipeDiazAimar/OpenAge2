extends Node
# MonkAI - IA de monjes AoE2, determinista por tick (lockstep 10Hz).
#
# Fuente de datos (solo lectura en _ready, no afecta al tick):
#   data/units/monje.json -> hp 30, speed 0.7, range/sight, actions [move, convert, heal, pick_relic]
#   data/actions.json ->
#     convert {range 8.0, cooldown_sec 12, chance_base 0.35}
#     heal {rate_hp_per_sec 2.5, range 4.0, auto true}
#
# Comportamientos (prioridad por tick y monje, orden determinista por id):
#   1. HUIR: si hay militar enemigo dentro de FLEE_RADIUS, moverse en direccion
#      opuesta (misma velocidad del monje). Interrumpe todo excepto entregar reliquia
#      en curso si ya esta en el monasterio (ese tick se completa primero).
#   2. CURAR AUTO: aliado herido (hp < max_hp) mas cercano en HEAL_RANGE recibe
#      HEAL_RATE hp/s. Sin RNG. No cura enemigos ni a si mismo por encima del max.
#   3. CONVERTIR: enemigo mas cercano en CONVERT_RANGE con cooldown a 0.
#      chance = clamp(0.35 + 0.1 * techs_monasterio_jugador, 0..1).
#      Tirada con SimRNG (reseed_per_tick una vez por tick). Exito: el objetivo
#      cambia player_id al del monje y pierde mejoras (upgrades = {}).
#      Cooldown 12s (120 ticks) se aplica haya exito o fallo.
#   4. RELIQUIA: si esta idle (sin huir/curar/convertir), ir a la reliquia libre
#      mas cercana, recogerla, llevarla al monasterio propio mas cercano.
#      Cada reliquia entregada genera +30 oro/min (0.5/s = 0.05/tick) via
#      GameManager.add_resource, determinista.
#
# Determinismo: sin randf/Time/fisica; iteracion ordenada por id; movimiento
#   lineal con velocidad fija; SimRNG.reseed_per_tick(tick) una vez al inicio
#   del tick y luego next_float() en orden de id de monje (1 consumo por intento).

const TICK_RATE := 10 # debe coincidir con SimAPI.TICK_RATE
const CONVERT_RANGE := 8.0 # monje.json range / actions.json convert.range
const CONVERT_COOLDOWN_TICKS := 120 # convert.cooldown_sec 12 * TICK_RATE
const CONVERT_CHANCE_BASE := 0.35 # actions.json convert.chance_base
const CONVERT_CHANCE_PER_TECH := 0.1 # +0.1 por cada tech de monasterio
const HEAL_RANGE := 4.0 # actions.json heal.range
const HEAL_RATE := 2.5 # actions.json heal.rate_hp_per_sec
const MONK_SPEED := 0.7 # monje.json speed (tiles/s)
const MONK_MAX_HP := 30.0 # monje.json hp
const FLEE_RADIUS := 5.0 # militares enemigos dentro de este radio provocan huida
const RELIC_GOLD_PER_MIN := 30.0 # +30 oro/min por reliquia entregada
const ARRIVE_EPS := 0.05

# Estados canonicos del monje.
const ST_IDLE := "idle"
const ST_FLEE := "flee"
const ST_HEAL := "heal"
const ST_CONVERT := "convert" # tiene objetivo de conversion en rango/cooldown
const ST_FETCH := "fetch_relic" # yendo a por reliquia
const ST_CARRY := "carry_relic" # llevando reliquia al monasterio
const ST_DELIVER := "deliver" # un tick transitorio al entregar (para hash legible)

# id -> {id, player_id, pos:Vector2, hp, max_hp, state, cooldown, target_id, relic_id}
var _monks := {}
# id -> {id, player_id, pos:Vector2, hp, max_hp, is_military:bool, upgrades:Dictionary}
var _units := {}
# id -> {id, pos:Vector2, carrier:int (-1 libre), delivered:bool, monastery_id:int}
var _relics := {}
# id -> {id, player_id, pos:Vector2}
var _monasteries := {}
# player_id -> int nº de techs de monasterio (cada una +0.1 conversion)
var _monastery_techs := {}


func _ready() -> void:
	_load_params_from_json()
	EventBus.command_issued.connect(_on_cmd)
	EventBus.tick_finished.connect(_on_tick)


func _load_params_from_json() -> void:
	# Solo lectura informativa: los const ya coinciden con los JSON.
	# Si difieren, aviso (no se mutan const para no romper determinismo).
	if FileAccess.file_exists("res://data/actions.json"):
		var f := FileAccess.open("res://data/actions.json", FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var acts: Dictionary = parsed.get("actions", {})
				var c: Dictionary = acts.get("convert", {})
				if not c.is_empty():
					if float(c.get("range", CONVERT_RANGE)) != CONVERT_RANGE:
						push_warning("MonkAI: convert.range JSON != const.")
					if float(c.get("chance_base", CONVERT_CHANCE_BASE)) != CONVERT_CHANCE_BASE:
						push_warning("MonkAI: convert.chance_base JSON != const.")
				var h: Dictionary = acts.get("heal", {})
				if not h.is_empty():
					if float(h.get("range", HEAL_RANGE)) != HEAL_RANGE:
						push_warning("MonkAI: heal.range JSON != const.")
					if float(h.get("rate_hp_per_sec", HEAL_RATE)) != HEAL_RATE:
						push_warning("MonkAI: heal.rate JSON != const.")


# --------------------------------------------------------------- registro ---

func register_monk(monk_id: int, player_id: int, pos, hp: float = MONK_MAX_HP) -> void:
	_monks[monk_id] = {
		"id": monk_id, "player_id": player_id, "pos": _as_vec2(pos),
		"hp": minf(hp, MONK_MAX_HP), "max_hp": MONK_MAX_HP,
		"state": ST_IDLE, "cooldown": 0, "target_id": -1, "relic_id": -1,
	}


func register_unit(unit_id: int, player_id: int, pos, hp: float, max_hp: float, is_military: bool = true, upgrades: Dictionary = {}) -> void:
	_units[unit_id] = {
		"id": unit_id, "player_id": player_id, "pos": _as_vec2(pos),
		"hp": hp, "max_hp": max_hp, "is_military": is_military,
		"upgrades": upgrades.duplicate(true),
	}


func register_relic(relic_id: int, pos) -> void:
	_relics[relic_id] = {
		"id": relic_id, "pos": _as_vec2(pos),
		"carrier": -1, "delivered": false, "monastery_id": -1,
	}


func register_monastery(building_id: int, player_id: int, pos) -> void:
	_monasteries[building_id] = {
		"id": building_id, "player_id": player_id, "pos": _as_vec2(pos),
	}


func set_monastery_techs(player_id: int, count: int) -> void:
	_monastery_techs[player_id] = maxi(0, count)


func get_monk(monk_id: int) -> Dictionary:
	return _monks.get(monk_id, {})


func remove_monk(monk_id: int) -> void:
	_drop_relic(monk_id)
	_monks.erase(monk_id)


func clear() -> void:
	_monks.clear()
	_units.clear()
	_relics.clear()
	_monasteries.clear()
	_monastery_techs.clear()


## Si el monje muere con reliquia, esta cae al suelo en su posicion.
func _drop_relic(monk_id: int) -> void:
	if not _monks.has(monk_id):
		return
	var m: Dictionary = _monks[monk_id]
	var rid := int(m.get("relic_id", -1))
	if rid >= 0 and _relics.has(rid):
		_relics[rid]["carrier"] = -1
		_relics[rid]["delivered"] = false
		_relics[rid]["pos"] = m["pos"]
	m["relic_id"] = -1


# ---------------------------------------------------------------- comandos ---

func _on_cmd(cmd: Dictionary) -> void:
	var t := str(cmd.get("type", ""))
	if t not in ["convert", "heal", "pick_relic", "pickup_relic", "move"]:
		return
	var payload: Dictionary = cmd.get("payload", {})
	var mid := int(payload.get("unit_id", payload.get("monk_id", payload.get("unit", -1))))
	if not _monks.has(mid):
		return
	match t:
		"convert":
			order_convert(mid, int(payload.get("target_id", payload.get("target", -1))))
		"heal":
			order_heal(mid, int(payload.get("target_id", payload.get("target", -1))))
		"pick_relic", "pickup_relic":
			order_pick_relic(mid, int(payload.get("relic_id", payload.get("relic", -1))))
		"move":
			# move cancela objetivo manual; la IA automatica sigue en ticks siguientes.
			_monks[mid]["target_id"] = -1
			if _monks[mid].get("state") != ST_CARRY:
				_monks[mid]["state"] = ST_IDLE


func order_convert(monk_id: int, target_id: int) -> bool:
	if not _monks.has(monk_id) or not _units.has(target_id):
		return false
	if _monks[monk_id]["player_id"] == _units[target_id]["player_id"]:
		return false # no convertir aliados
	_monks[monk_id]["target_id"] = target_id
	_monks[monk_id]["state"] = ST_CONVERT
	return true


func order_heal(monk_id: int, target_id: int) -> bool:
	if not _monks.has(monk_id) or not _units.has(target_id):
		return false
	_monks[monk_id]["target_id"] = target_id
	_monks[monk_id]["state"] = ST_HEAL
	return true


func order_pick_relic(monk_id: int, relic_id: int) -> bool:
	if not _monks.has(monk_id) or not _relics.has(relic_id):
		return false
	_monks[monk_id]["relic_id"] = relic_id
	_monks[monk_id]["state"] = ST_FETCH
	return true


# ------------------------------------------------------------------- tick ---

func _on_tick(t: int) -> void:
	tick(t)


## Avanza 1 tick (0.1s). Orden determinista por id de monje.
## Resemilla SimRNG una vez por tick; cada intento de conversion consume
## exactamente 1 next_float() en orden de id.
func tick(t: int) -> void:
	if SimAPI != null and SimAPI.get("SimRNGNode") != null:
		SimAPI.SimRNGNode.reseed_per_tick(t)
	var ids: Array = _monks.keys()
	ids.sort()
	for mid in ids:
		_step_monk(_monks[mid])
	_pay_relic_gold()


func _step_monk(m: Dictionary) -> void:
	# Cooldown siempre decrece (tambien huyendo o cargando).
	if int(m["cooldown"]) > 0:
		m["cooldown"] = int(m["cooldown"]) - 1
	# 0. Si ya lleva reliquia y llego al monasterio, entregar antes de huir.
	if int(m.get("relic_id", -1)) >= 0 and str(m.get("state", "")) == ST_CARRY:
		if _step_carry(m):
			return # entregado este tick
	# 1. Huir de militares enemigos (maxima prioridad de movimiento).
	var threat := _nearest_enemy_military(int(m["id"]), m["pos"])
	if threat >= 0:
		m["state"] = ST_FLEE
		_step_flee(m, threat)
		# Huyendo tambien cura en marcha si hay aliado herido al lado (auto).
		_auto_heal(m)
		return
	# 2. Curar auto radio 4 (aliados, incluido otro monje; no a si mismo).
	if _auto_heal(m):
		# Si habia objetivo manual de conversion fuera de rango, se mantiene;
		# la cura auto no borra target_id manual.
		if str(m.get("state", "")) != ST_CONVERT:
			m["state"] = ST_HEAL
	# 3. Conversion (objetivo manual o automatico mas cercano en rango 8).
	if _step_convert(m):
		return
	# 4. Reliquia (solo si no curo ni convirtio este tick).
	if int(m.get("relic_id", -1)) >= 0 or str(m.get("state", "")) in [ST_FETCH, ST_CARRY]:
		_step_relic(m)
		return
	if str(m.get("state", "")) in [ST_HEAL, ST_CONVERT, ST_FLEE]:
		if str(m.get("state", "")) != ST_CONVERT:
			m["state"] = ST_IDLE
		return
	# Idle: buscar reliquia libre automaticamente.
	var free := _nearest_free_relic(m["pos"])
	if free >= 0:
		m["relic_id"] = free
		m["state"] = ST_FETCH
		_step_relic(m)
	else:
		m["state"] = ST_IDLE


# -------------------------------------------------------------- convertir ---

## Devuelve true si este tick se resolvio un intento de conversion
## (con o sin exito) y no debe hacer reliquia despues.
func _step_convert(m: Dictionary) -> bool:
	var target := int(m.get("target_id", -1))
	# Validar objetivo manual: enemigo vivo y registrado.
	if target >= 0:
		if not _units.has(target) or int(_units[target]["player_id"]) == int(m["player_id"]):
			m["target_id"] = -1
			target = -1
	if target < 0:
		target = _nearest_enemy_in_range(m["pos"], int(m["player_id"]), CONVERT_RANGE)
		if target >= 0:
			m["target_id"] = target
			m["state"] = ST_CONVERT
	if target < 0:
		return false
	var u: Dictionary = _units[target]
	if _dist(m["pos"], u["pos"]) > CONVERT_RANGE:
		# Acercarse (velocidad monje) hasta entrar en rango; sin tirar dados.
		m["state"] = ST_CONVERT
		m["pos"] = _move_towards(m["pos"], u["pos"], MONK_SPEED / float(TICK_RATE))
		return true
	if int(m["cooldown"]) > 0:
		m["state"] = ST_CONVERT
		return true
	# En rango + cooldown listo: tirada determinista.
	var chance := _convert_chance(int(m["player_id"]))
	var roll := 1.0
	if SimAPI != null and SimAPI.get("SimRNGNode") != null:
		roll = SimAPI.SimRNGNode.next_float() # [0,1), 1 consumo por intento
	else:
		roll = 0.0 # sin RNG (tests sin autoload): exito garantizado si chance > 0
	m["cooldown"] = CONVERT_COOLDOWN_TICKS
	if roll < chance:
		_units[target]["player_id"] = int(m["player_id"])
		_units[target]["upgrades"] = {} # el convertido pierde mejoras
		m["target_id"] = -1
		m["state"] = ST_IDLE
		if EventBus.has_signal("unit_converted"):
			EventBus.emit_signal("unit_converted", target, int(m["player_id"]), int(m["id"]))
	else:
		m["state"] = ST_CONVERT # fallo: reintenta tras cooldown
	return true


func _convert_chance(player_id: int) -> float:
	var techs := int(_monastery_techs.get(player_id, 0))
	return clampf(CONVERT_CHANCE_BASE + CONVERT_CHANCE_PER_TECH * float(techs), 0.0, 1.0)


func _nearest_enemy_in_range(from_pos: Vector2, player_id: int, max_range: float) -> int:
	var best := -1
	var best_d := max_range + 0.000001
	var ids: Array = _units.keys()
	ids.sort()
	for uid in ids:
		var u: Dictionary = _units[uid]
		if int(u["player_id"]) == player_id:
			continue
		if float(u.get("hp", 0.0)) <= 0.0:
			continue
		var d := _dist(from_pos, u["pos"])
		if d <= max_range and (d < best_d - 0.000001 or (absf(d - best_d) <= 0.000001 and int(uid) < best)):
			best_d = d
			best = int(uid)
	return best


# ------------------------------------------------------------------ curar ---

## Cura auto: aliado herido mas cercano en HEAL_RANGE. True si curo a alguien.
func _auto_heal(m: Dictionary) -> bool:
	var best := -1
	var best_hp := 1e18
	var ids: Array = _units.keys()
	ids.sort()
	for uid in ids:
		var u: Dictionary = _units[uid]
		if int(u["player_id"]) != int(m["player_id"]):
			continue
		if int(uid) == int(m["id"]):
			continue # usa _units, el monje vive en _monks; guardia por colision de ids
		if float(u.get("hp", 0.0)) <= 0.0 or float(u["hp"]) >= float(u["max_hp"]):
			continue
		var d := _dist(m["pos"], u["pos"])
		if d > HEAL_RANGE:
			continue
		# Prioridad: menor hp actual; desempate por menor id (determinista).
		if float(u["hp"]) < best_hp - 0.000001 or (absf(float(u["hp"]) - best_hp) <= 0.000001 and int(uid) < best):
			best_hp = float(u["hp"])
			best = int(uid)
	# Tambien puede curar a otro monje aliado herido (viven en _monks).
	var mids: Array = _monks.keys()
	mids.sort()
	for oid in mids:
		if int(oid) == int(m["id"]):
			continue
		var o: Dictionary = _monks[oid]
		if int(o["player_id"]) != int(m["player_id"]):
			continue
		if float(o["hp"]) <= 0.0 or float(o["hp"]) >= float(o["max_hp"]):
			continue
		var d := _dist(m["pos"], o["pos"])
		if d > HEAL_RANGE:
			continue
		if float(o["hp"]) < best_hp - 0.000001:
			best_hp = float(o["hp"])
			best = -1000 - int(oid) # marca: objetivo es monje, no _units
	if best == -1:
		return false
	var amount := HEAL_RATE / float(TICK_RATE) # 2.5hp/s -> 0.25/tick
	if best < -1000:
		var oid := -1000 - best
		_monks[oid]["hp"] = minf(float(_monks[oid]["max_hp"]), float(_monks[oid]["hp"]) + amount)
	else:
		_units[best]["hp"] = minf(float(_units[best]["max_hp"]), float(_units[best]["hp"]) + amount)
	return true


# ------------------------------------------------------------------- huir ---

func _nearest_enemy_military(monk_id: int, from_pos: Vector2) -> int:
	var pid := int(_monks[monk_id]["player_id"])
	var best := -1
	var best_d := FLEE_RADIUS + 0.000001
	var ids: Array = _units.keys()
	ids.sort()
	for uid in ids:
		var u: Dictionary = _units[uid]
		if int(u["player_id"]) == pid:
			continue
		if not bool(u.get("is_military", true)):
			continue
		if float(u.get("hp", 0.0)) <= 0.0:
			continue
		var d := _dist(from_pos, u["pos"])
		if d <= FLEE_RADIUS and (d < best_d - 0.000001 or (absf(d - best_d) <= 0.000001 and int(uid) < best)):
			best_d = d
			best = int(uid)
	return best


func _step_flee(m: Dictionary, threat_id: int) -> void:
	var threat_pos: Vector2 = _units[threat_id]["pos"]
	var away: Vector2 = (m["pos"] - threat_pos) as Vector2
	if away.length() <= 0.000001:
		away = Vector2(1, 0) # solapados: direccion fija (determinista)
	else:
		away = away.normalized()
	# Si lleva reliquia, huye hacia su monasterio mas cercano en vez de en linea
	# recta (no la suelta). Si no lleva, huida radial simple.
	if int(m.get("relic_id", -1)) >= 0:
		var mid := _nearest_own_monastery(int(m["player_id"]), m["pos"])
		if mid >= 0:
			var to_safe: Vector2 = (_monasteries[mid]["pos"] - m["pos"]) as Vector2
			if to_safe.length() > 0.000001:
				away = to_safe.normalized()
	var dest: Vector2 = m["pos"] + away * (MONK_SPEED / float(TICK_RATE))
	m["pos"] = dest


# ---------------------------------------------------------------- reliquia ---

func _nearest_free_relic(from_pos: Vector2) -> int:
	var best := -1
	var best_d := 1e18
	var ids: Array = _relics.keys()
	ids.sort()
	for rid in ids:
		var r: Dictionary = _relics[rid]
		if bool(r.get("delivered", false)) or int(r.get("carrier", -1)) >= 0:
			continue
		var d := _dist(from_pos, r["pos"])
		if d < best_d - 0.000001 or (absf(d - best_d) <= 0.000001 and int(rid) < best):
			best_d = d
			best = int(rid)
	return best


func _nearest_own_monastery(player_id: int, from_pos: Vector2) -> int:
	var best := -1
	var best_d := 1e18
	var ids: Array = _monasteries.keys()
	ids.sort()
	for bid in ids:
		var b: Dictionary = _monasteries[bid]
		if int(b["player_id"]) != player_id:
			continue
		var d := _dist(from_pos, b["pos"])
		if d < best_d - 0.000001 or (absf(d - best_d) <= 0.000001 and int(bid) < best):
			best_d = d
			best = int(bid)
	return best


func _step_relic(m: Dictionary) -> void:
	var rid := int(m.get("relic_id", -1))
	if rid < 0:
		m["state"] = ST_IDLE
		return
	if not _relics.has(rid):
		m["relic_id"] = -1
		m["state"] = ST_IDLE
		return
	var r: Dictionary = _relics[rid]
	if bool(r.get("delivered", false)):
		m["relic_id"] = -1
		m["state"] = ST_IDLE
		return
	# Otro monje la cogio primero: buscar otra.
	if int(r.get("carrier", -1)) >= 0 and int(r["carrier"]) != int(m["id"]):
		m["relic_id"] = _nearest_free_relic(m["pos"])
		m["state"] = ST_FETCH if int(m["relic_id"]) >= 0 else ST_IDLE
		return
	if str(m.get("state", "")) == ST_CARRY or int(r.get("carrier", -1)) == int(m["id"]):
		_step_carry(m)
		return
	# ST_FETCH: caminar a la reliquia.
	m["pos"] = _move_towards(m["pos"], r["pos"], MONK_SPEED / float(TICK_RATE))
	if _dist(m["pos"], r["pos"]) <= ARRIVE_EPS:
		r["carrier"] = int(m["id"])
		m["state"] = ST_CARRY


## Lleva la reliquia al monasterio propio mas cercano. True si entrego este tick.
func _step_carry(m: Dictionary) -> bool:
	var rid := int(m.get("relic_id", -1))
	if rid < 0 or not _relics.has(rid):
		m["relic_id"] = -1
		m["state"] = ST_IDLE
		return false
	var r: Dictionary = _relics[rid]
	r["carrier"] = int(m["id"])
	r["pos"] = m["pos"] # la reliquia viaja con el monje (determinista)
	var mid := _nearest_own_monastery(int(m["player_id"]), m["pos"])
	if mid < 0:
		m["state"] = ST_CARRY
		return false # sin monasterio: espera con la reliquia (no la suelta)
	m["pos"] = _move_towards(m["pos"], _monasteries[mid]["pos"], MONK_SPEED / float(TICK_RATE))
	r["pos"] = m["pos"]
	if _dist(m["pos"], _monasteries[mid]["pos"]) <= ARRIVE_EPS:
		r["delivered"] = true
		r["monastery_id"] = mid
		r["carrier"] = -1
		m["relic_id"] = -1
		m["state"] = ST_DELIVER
		if EventBus.has_signal("relic_delivered"):
			EventBus.emit_signal("relic_delivered", rid, int(m["player_id"]), mid)
		return true
	m["state"] = ST_CARRY
	return false


## Oro pasivo: cada reliquia entregada da +30 oro/min a su dueño.
## 30/min = 0.5/s = 0.05/tick. Se acredita por tick via GameManager.
func _pay_relic_gold() -> void:
	var per_tick := RELIC_GOLD_PER_MIN / 60.0 / float(TICK_RATE)
	var owners := {} # player_id -> nº reliquias entregadas
	for rid in _relics.keys():
		var r: Dictionary = _relics[rid]
		if not bool(r.get("delivered", false)):
			continue
		var mid := int(r.get("monastery_id", -1))
		if not _monasteries.has(mid):
			continue
		var pid := int(_monasteries[mid]["player_id"])
		owners[pid] = int(owners.get(pid, 0)) + 1
	var pids: Array = owners.keys()
	pids.sort()
	for pid in pids:
		GameManager.add_resource(int(pid), "gold", per_tick * float(owners[pid]))


# ---------------------------------------------------------------- helpers ---

func _dist(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)


func _move_towards(pos: Vector2, target: Vector2, max_step: float) -> Vector2:
	var d := pos.distance_to(target)
	if d <= max_step or d <= 0.000001:
		return target
	var t := max_step / d
	return Vector2(lerpf(pos.x, target.x, t), lerpf(pos.y, target.y, t))


static func _as_vec2(pos) -> Vector2:
	if pos is Vector2:
		return pos
	if pos is Vector3:
		return Vector2(pos.x, pos.z)
	if typeof(pos) == TYPE_ARRAY:
		if pos.size() >= 3:
			return Vector2(float(pos[0]), float(pos[2]))
		if pos.size() == 2:
			return Vector2(float(pos[0]), float(pos[1]))
	return Vector2.ZERO


## Cadena canonica del estado (para hash anti-desync en NetManager).
func sim_state_string() -> String:
	var parts: Array = []
	var ids: Array = _monks.keys()
	ids.sort()
	for mid in ids:
		var m: Dictionary = _monks[mid]
		var p: Vector2 = m["pos"]
		parts.append("m%d:p%d:%s:%.3f:%d:%d" % [
			int(mid), int(m["player_id"]), str(m["state"]),
			float(m["hp"]), int(m["cooldown"]), int(m.get("relic_id", -1))])
	var uids: Array = _units.keys()
	uids.sort()
	for uid in uids:
		var u: Dictionary = _units[uid]
		parts.append("u%d:p%d:%.2f" % [int(uid), int(u["player_id"]), float(u["hp"])])
	var rids: Array = _relics.keys()
	rids.sort()
	for rid in rids:
		var r: Dictionary = _relics[rid]
		parts.append("r%d:c%d:%d" % [
			int(rid), int(r.get("carrier", -1)), 1 if bool(r.get("delivered", false)) else 0])
	return "|".join(parts)
