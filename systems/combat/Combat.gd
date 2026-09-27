extends Node
# Combat - combate AoE2 determinista por tick (lockstep 10Hz).
#
# Reglas implementadas (ver data/units/*.json + data/actions.json):
#   - Dano: max(1, atk - armadura) + bonus_vs. (calc_damage)
#   - Armaduras separadas: atacante melee -> armor_melee; atacante ranged/pierce -> armor_pierce.
#   - Melee: rango 1.2 (default, override por unidad), cooldown 1.5s = 15 ticks. Dano instantaneo.
#   - Ranged: proyectil vel 12.0 tiles/s (arquero.json), cooldown 2.0s = 20 ticks.
#     Error 0 si el objetivo esta parado; si se movio el tick anterior, dispersion
#     determinista en disco via SimRNG (consume 2 pasos: angulo + radio, orden por id).
#     El proyectil vuela a un punto fijo (aim); al llegar solo hace dano si el
#     objetivo sigue a <= MISS_CAPTURE del punto (si esquivo, falla sin dano).
#   - Patrol / attack-move: escanean enemigos en radio de vision (sight) cada 5 ticks.
#   - Guard/guardia: sigue a su objetivo (follow) y ataca enemigos en su propia vision.
#
# Determinismo: sin randf/randi/Time/fisica; iteracion ordenada por id;
#   movimiento lineal con velocidad fija (tiles/s); cooldowns en ticks enteros;
#   RNG solo via SimAPI.SimRNGNode (fallback hash determinista si no hay autoload).
#   Tick 10Hz: avanzar con tick(t) o via EventBus.tick_finished. Comandos via
#   EventBus.command_issued (tipos: move, attack, attack_move, patrol, stop, guard/guardia).
#
# IDs: unidades y edificios comparten el espacio de targeting; el llamante debe
#   usar ids unicos entre ambos (recomendado: edificios con id >= 100000).

const TICK_RATE := 10 # debe coincidir con SimAPI.TICK_RATE
const DT := 0.1 # 1.0 / TICK_RATE, sin Time ni delta flotante en logica
const MELEE_RANGE_DEFAULT := 1.2 # milicia.json range
const MELEE_COOLDOWN_SEC := 1.5 # -> 15 ticks
const RANGED_COOLDOWN_SEC := 2.0 # arquero.json fire_cooldown_sec -> 20 ticks
const PROJECTILE_SPEED_DEFAULT := 12.0 # arquero.json projectile_speed
const SCAN_PERIOD := 5 # patrol/attack-move escanean cada 5 ticks
const ARRIVE_EPS := 0.05 # tolerancia de llegada en tiles
const MELEE_EPS := 0.001
const GUARD_FOLLOW_DIST := 1.5 # guardia se queda a esta distancia de su protegido
const MISS_SPREAD_RADIUS := 1.0 # radio del disco de dispersion vs objetivo movil
const MISS_CAPTURE_RADIUS := 0.5 # si el objetivo esta mas lejos del aim, el tiro falla
const PROJECTILE_EXTRA_TICKS := 10 # margen sobre el vuelo teorico antes de expirar

# Estados canonicos.
const ST_IDLE := "idle"
const ST_MOVE := "move"
const ST_ATTACK := "attack" # objetivo forzado, persigue sin importar vision
const ST_ATTACK_MOVE := "attack_move" # avanza a dest, engancha lo que ve cada 5 ticks
const ST_PATROL := "patrol" # ping-pong A<->B, engancha lo que ve cada 5 ticks
const ST_GUARD := "guard" # sigue a guard_id, ataca lo que ve en su vision

# unit_db: kind(lower) -> stats base cargados de data/units/*.json en _ready.
var _unit_db := {}
# id -> {id, player_id, kind, cls, pos:Vector2, hp, max_hp, attack, armor_melee,
#   armor_pierce, range, sight, speed, ranged:bool, projectile_speed,
#   cooldown_ticks, cooldown_left, state, target_id, dest:Vector2,
#   patrol_a:Vector2, patrol_b:Vector2, patrol_dest:Vector2, guard_id, alive, moved:bool}
var _units := {}
# id -> {id, player_id, kind, cls, pos:Vector2, hp, max_hp, armor_melee, armor_pierce, alive}
var _buildings := {}
# id -> {id, owner_id, player_id, target_id, pos:Vector2, aim:Vector2, speed,
#   atk, bonus, age_ticks, max_age_ticks, alive}
var _projectiles := {}
var _next_projectile_id := 1
# Snapshot de "se movio el tick anterior" para la regla error-0-si-parado.
var _prev_moved := {}


func _ready() -> void:
	_load_unit_db()
	EventBus.command_issued.connect(_on_cmd)
	EventBus.tick_finished.connect(_on_tick)


# ------------------------------------------------------- base de datos ---
func _load_unit_db() -> void:
	_unit_db.clear()
	for kind in ["milicia", "arquero", "aldeano", "monje"]:
		var path := "res://data/units/%s.json" % kind
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_unit_db[kind] = parsed


func _ensure_db() -> void:
	if not _unit_db.is_empty():
		return
	_load_unit_db()
	# Fallback por si los JSON no existen (tests sin filesystem): replica los valores
	# de milicia.json / arquero.json / aldeano.json para no romper determinismo.
	if not _unit_db.has("milicia"):
		_unit_db["milicia"] = {"hp": 45, "attack": 4, "armor_melee": 0, "armor_pierce": 1,
			"range": 1.2, "sight": 4.0, "speed": 0.9, "bonus_vs": {"edificio": 2}}
	if not _unit_db.has("arquero"):
		_unit_db["arquero"] = {"hp": 30, "attack": 4, "armor_melee": 0, "armor_pierce": 0,
			"range": 5.0, "sight": 6.0, "speed": 0.96,
			"projectile_speed": 12.0, "fire_cooldown_sec": 2.0}
	if not _unit_db.has("aldeano"):
		_unit_db["aldeano"] = {"hp": 25, "attack": 3, "armor_melee": 0, "armor_pierce": 0,
			"range": 1.0, "sight": 4.0, "speed": 0.8}


func _base_for(kind: String) -> Dictionary:
	_ensure_db()
	return _unit_db.get(kind.to_lower().strip_edges(), {})


# ------------------------------------------------------------- dano ---
## Formula AoE2: max(1, atk - armor) + bonus. Se mantiene por compatibilidad.
func calc_damage(atk: float, armor: float, bonus: float = 0.0) -> float:
	return maxf(1.0, atk - armor) + bonus


## Bonus vs tipo: {"edificio": 2} suma 2 si el objetivo es de esa clase/kind (case-insensitive).
func bonus_vs_target(attacker: Dictionary, target: Dictionary) -> float:
	var b = attacker.get("bonus_vs", {})
	if typeof(b) != TYPE_DICTIONARY or b.is_empty():
		return 0.0
	var cls := str(target.get("cls", target.get("kind", ""))).to_lower().strip_edges()
	var kind := str(target.get("kind", "")).to_lower().strip_edges()
	for k in b.keys():
		var key := str(k).to_lower().strip_edges()
		if key == cls or key == kind:
			return float(b[k])
	return 0.0


## Dano melee (usa armor_melee del objetivo) + bonus_vs.
func calc_melee_damage(attacker: Dictionary, target: Dictionary) -> float:
	return calc_damage(float(attacker.get("attack", 0.0)),
		float(target.get("armor_melee", 0.0)), bonus_vs_target(attacker, target))


## Dano pierce/ranged (usa armor_pierce del objetivo) + bonus_vs.
func calc_pierce_damage(atk: float, target: Dictionary, bonus: float) -> float:
	return calc_damage(atk, float(target.get("armor_pierce", 0.0)), bonus)


## Dano que haria attacker_id a target_id con la armadura correcta (solo lectura).
func damage_for(attacker_id: int, target_id: int) -> float:
	var a := _get_target(attacker_id)
	var t := _get_target(target_id)
	if a.is_empty() or t.is_empty():
		return 0.0
	if bool(a.get("ranged", false)):
		return calc_pierce_damage(float(a.get("attack", 0.0)), t, bonus_vs_target(a, t))
	return calc_melee_damage(a, t)


# ---------------------------------------------------------- registro ---
func register_unit(unit_id: int, player_id: int, kind: String, pos, overrides: Dictionary = {}) -> bool:
	var base := _base_for(kind)
	var k := kind.to_lower().strip_edges()
	var max_hp := float(overrides.get("hp", overrides.get("max_hp", base.get("hp", 30))))
	var atk := float(overrides.get("attack", base.get("attack", 3)))
	var a_melee := float(overrides.get("armor_melee", base.get("armor_melee", 0)))
	var a_pierce := float(overrides.get("armor_pierce", base.get("armor_pierce", 0)))
	var rng := float(overrides.get("range", base.get("range", MELEE_RANGE_DEFAULT)))
	var sight := float(overrides.get("sight", base.get("sight", 4.0)))
	var speed := float(overrides.get("speed", base.get("speed", 0.9)))
	var proj_speed := float(overrides.get("projectile_speed", base.get("projectile_speed", 0.0)))
	var ranged := bool(overrides.get("ranged", proj_speed > 0.0 or rng > MELEE_RANGE_DEFAULT + 0.01))
	if ranged and proj_speed <= 0.0:
		proj_speed = PROJECTILE_SPEED_DEFAULT
	var cd_sec := float(overrides.get("cooldown_sec",
		overrides.get("fire_cooldown_sec",
			base.get("fire_cooldown_sec",
				RANGED_COOLDOWN_SEC if ranged else MELEE_COOLDOWN_SEC))))
	var bonus = overrides.get("bonus_vs", base.get("bonus_vs", {}))
	_units[unit_id] = {
		"id": unit_id, "player_id": player_id, "kind": k,
		"cls": str(overrides.get("cls", overrides.get("armor_class", k))),
		"pos": _as_vec2(pos), "hp": max_hp, "max_hp": max_hp,
		"attack": atk, "armor_melee": a_melee, "armor_pierce": a_pierce,
		"range": rng, "sight": sight, "speed": speed,
		"ranged": ranged, "projectile_speed": proj_speed,
		"cooldown_ticks": maxi(1, int(round(cd_sec * float(TICK_RATE)))),
		"cooldown_left": 0, "state": ST_IDLE, "target_id": -1,
		"dest": _as_vec2(pos), "patrol_a": _as_vec2(pos),
		"patrol_b": _as_vec2(pos), "patrol_dest": _as_vec2(pos),
		"guard_id": -1, "alive": true, "moved": false,
		"bonus_vs": (bonus as Dictionary).duplicate(true) if typeof(bonus) == TYPE_DICTIONARY else {},
	}
	_prev_moved[unit_id] = false
	return true


func register_building(building_id: int, player_id: int, pos, hp: float = 500.0,
		armor_melee: float = 0.0, armor_pierce: float = 0.0, kind: String = "edificio") -> bool:
	var k := kind.to_lower().strip_edges()
	_buildings[building_id] = {
		"id": building_id, "player_id": player_id, "kind": k, "cls": "edificio",
		"pos": _as_vec2(pos), "hp": hp, "max_hp": hp,
		"armor_melee": armor_melee, "armor_pierce": armor_pierce, "alive": true,
	}
	return true


func remove_unit(unit_id: int) -> void:
	_units.erase(unit_id)
	_prev_moved.erase(unit_id)


func remove_building(building_id: int) -> void:
	_buildings.erase(building_id)


func clear() -> void:
	_units.clear()
	_buildings.clear()
	_projectiles.clear()
	_prev_moved.clear()
	_next_projectile_id = 1


func has_unit(unit_id: int) -> bool:
	return _units.has(unit_id)


func get_unit(unit_id: int) -> Dictionary:
	return _units.get(unit_id, {})


func get_building(building_id: int) -> Dictionary:
	return _buildings.get(building_id, {})


func is_alive(entity_id: int) -> bool:
	return bool(_get_target(entity_id).get("alive", false))


func get_hp(entity_id: int) -> float:
	return float(_get_target(entity_id).get("hp", 0.0))


func get_pos(entity_id: int) -> Vector2:
	var t := _get_target(entity_id)
	if t.is_empty():
		return Vector2.ZERO
	return t["pos"]


func get_projectiles() -> Array:
	var out: Array = []
	for pid in _projectiles.keys():
		out.append((_projectiles[pid] as Dictionary).duplicate(true))
	return out


func _get_target(entity_id: int) -> Dictionary:
	if _units.has(entity_id):
		return _units[entity_id]
	if _buildings.has(entity_id):
		return _buildings[entity_id]
	return {}


# ---------------------------------------------------------- comandos ---
func _on_cmd(cmd: Dictionary) -> void:
	var t := str(cmd.get("type", ""))
	if t not in ["move", "attack", "attack_move", "patrol", "stop", "guard", "guardia"]:
		return
	var payload: Dictionary = cmd.get("payload", {})
	var ids := _parse_unit_ids(payload)
	if ids.is_empty():
		return
	match t:
		"move":
			var d: Vector2 = _parse_pos(payload, "dest")
			for uid in ids:
				order_move(int(uid), d)
		"attack":
			var tgt := _parse_target_id(payload)
			for uid in ids:
				order_attack(int(uid), tgt)
		"attack_move":
			var d2: Vector2 = _parse_pos(payload, "dest")
			for uid in ids:
				order_attack_move(int(uid), d2)
		"patrol":
			var d3: Vector2 = _parse_pos(payload, "dest")
			for uid in ids:
				order_patrol(int(uid), d3)
		"stop":
			for uid in ids:
				order_stop(int(uid))
		"guard", "guardia":
			var g := _parse_target_id(payload)
			if g < 0:
				g = int(payload.get("guard_id", payload.get("guard_target", payload.get("follow_id", -1))))
			for uid in ids:
				order_guard(int(uid), g)


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


func _parse_target_id(payload: Dictionary) -> int:
	for key in ["target_id", "target", "entity", "entity_id", "enemy_id", "victim_id"]:
		if payload.has(key):
			var v = payload[key]
			if typeof(v) == TYPE_DICTIONARY:
				if (v as Dictionary).has("id"):
					return int((v as Dictionary)["id"])
				continue
			if typeof(v) == TYPE_ARRAY:
				continue # es posicion, no entidad
			return int(v)
	return -1


func _parse_pos(payload: Dictionary, default_key: String = "dest"):
	for key in [default_key, "pos", "dest", "position", "to", "point", "target_pos"]:
		if payload.has(key):
			var v = payload[key]
			if typeof(v) == TYPE_ARRAY or v is Vector2 or v is Vector3 or typeof(v) == TYPE_DICTIONARY:
				# "target" puede ser id de entidad: solo tratar como pos si es Array/Vector/dict con x,y.
				if key == "target" and not (typeof(v) == TYPE_ARRAY or v is Vector2 or v is Vector3 or (typeof(v) == TYPE_DICTIONARY and (v.has("x") or v.has("pos")))):
					continue
				return _as_vec2(v)
	if payload.has("x") and payload.has("y"):
		return Vector2(float(payload["x"]), float(payload["y"]))
	return Vector2.ZERO


## Ordenes publicas (las usa Military AI / tests). Devuelven false si la unidad no existe o esta muerta.
func order_move(unit_id: int, dest) -> bool:
	if not _alive_unit(unit_id):
		return false
	var u: Dictionary = _units[unit_id]
	u["state"] = ST_MOVE
	u["dest"] = _as_vec2(dest)
	u["target_id"] = -1
	u["guard_id"] = -1
	return true


func order_attack(unit_id: int, target_id: int) -> bool:
	if not _alive_unit(unit_id):
		return false
	if not is_alive(target_id):
		return false
	if unit_id == target_id:
		return false
	var u: Dictionary = _units[unit_id]
	u["state"] = ST_ATTACK
	u["target_id"] = target_id
	u["guard_id"] = -1
	return true


func order_attack_move(unit_id: int, dest) -> bool:
	if not _alive_unit(unit_id):
		return false
	var u: Dictionary = _units[unit_id]
	u["state"] = ST_ATTACK_MOVE
	u["dest"] = _as_vec2(dest)
	u["guard_id"] = -1
	# Escaneo inmediato (ademas del periodico cada 5 ticks) para respuesta rapida.
	var e := nearest_enemy(u["pos"], float(u["sight"]), int(u["player_id"]), unit_id)
	u["target_id"] = e
	return true


func order_patrol(unit_id: int, dest) -> bool:
	if not _alive_unit(unit_id):
		return false
	var u: Dictionary = _units[unit_id]
	u["state"] = ST_PATROL
	u["patrol_a"] = (u["pos"] as Vector2)
	u["patrol_b"] = _as_vec2(dest)
	u["patrol_dest"] = _as_vec2(dest)
	u["guard_id"] = -1
	var e := nearest_enemy(u["pos"], float(u["sight"]), int(u["player_id"]), unit_id)
	u["target_id"] = e
	return true


## Guardia: sigue a guard_id (aliado/recurso a proteger) y ataca enemigos en su vision.
func order_guard(unit_id: int, guard_id: int) -> bool:
	if not _alive_unit(unit_id):
		return false
	if guard_id == unit_id:
		return false
	var u: Dictionary = _units[unit_id]
	u["state"] = ST_GUARD
	u["guard_id"] = guard_id
	u["target_id"] = -1
	return true


func order_stop(unit_id: int) -> bool:
	if not _units.has(unit_id):
		return false
	var u: Dictionary = _units[unit_id]
	u["state"] = ST_IDLE
	u["target_id"] = -1
	u["guard_id"] = -1
	return true


func _alive_unit(unit_id: int) -> bool:
	return _units.has(unit_id) and bool(_units[unit_id].get("alive", false))


# -------------------------------------------------------------- tick ---
func _on_tick(t: int) -> void:
	tick(t)


## Avanza 1 tick de simulacion (0.1s). Orden determinista por id.
func tick(t: int) -> void:
	# Snapshot de movimiento del tick anterior (regla error-0-si-parado).
	for uid in _units.keys():
		_prev_moved[uid] = bool((_units[uid] as Dictionary).get("moved", false))
		(_units[uid] as Dictionary)["moved"] = false
	var do_scan := (t % SCAN_PERIOD == 0)
	var ids: Array = _units.keys()
	ids.sort()
	for uid in ids:
		_step_unit(_units[uid], t, do_scan)
	var pids: Array = _projectiles.keys()
	pids.sort()
	for pid in pids:
		_step_projectile(_projectiles[pid])


func _step_unit(u: Dictionary, t: int, do_scan: bool) -> void:
	if not bool(u.get("alive", false)):
		return
	if int(u.get("cooldown_left", 0)) > 0:
		u["cooldown_left"] = int(u["cooldown_left"]) - 1
	match str(u.get("state", ST_IDLE)):
		ST_IDLE:
			pass
		ST_MOVE:
			_move_unit_towards(u, u["dest"])
		ST_ATTACK:
			_step_combat(u, int(u.get("target_id", -1)), false, t)
		ST_ATTACK_MOVE:
			_step_attack_move(u, do_scan)
		ST_PATROL:
			_step_patrol(u, do_scan)
		ST_GUARD:
			_step_guard(u, do_scan)
		_:
			u["state"] = ST_IDLE


## Logica comun de persecucion + golpe/disparo. follow_only=false en attack forzado.
func _step_combat(u: Dictionary, target_id: int, _unused: bool, _t: int) -> void:
	if target_id < 0 or not is_alive(target_id):
		u["target_id"] = -1
		if str(u.get("state")) == ST_ATTACK:
			u["state"] = ST_IDLE
		return
	var tgt := _get_target(target_id)
	if _is_friendly(int(u["player_id"]), int(tgt.get("player_id", -1))):
		u["target_id"] = -1
		if str(u.get("state")) == ST_ATTACK:
			u["state"] = ST_IDLE
		return
	var dist := (u["pos"] as Vector2).distance_to(tgt["pos"] as Vector2)
	if dist <= float(u.get("range", MELEE_RANGE_DEFAULT)) + MELEE_EPS:
		_try_hit(u, target_id)
	else:
		_move_unit_towards(u, tgt["pos"])


func _step_attack_move(u: Dictionary, do_scan: bool) -> void:
	if do_scan or int(u.get("target_id", -1)) < 0 or not is_alive(int(u.get("target_id", -1))):
		if do_scan or not is_alive(int(u.get("target_id", -1))):
			var e := nearest_enemy(u["pos"], float(u["sight"]), int(u["player_id"]), int(u["id"]))
			u["target_id"] = e
	var tgt_id := int(u.get("target_id", -1))
	if tgt_id >= 0 and is_alive(tgt_id):
		_step_combat(u, tgt_id, false, 0)
		return
	u["target_id"] = -1
	_move_unit_towards(u, u["dest"])
	# Al llegar se queda en attack_move haciendo hold-and-scan (no pasa a idle).


func _step_patrol(u: Dictionary, do_scan: bool) -> void:
	if do_scan or int(u.get("target_id", -1)) < 0 or not is_alive(int(u.get("target_id", -1))):
		if do_scan or not is_alive(int(u.get("target_id", -1))):
			var e := nearest_enemy(u["pos"], float(u["sight"]), int(u["player_id"]), int(u["id"]))
			u["target_id"] = e
	var tgt_id := int(u.get("target_id", -1))
	if tgt_id >= 0 and is_alive(tgt_id):
		_step_combat(u, tgt_id, false, 0)
		return
	u["target_id"] = -1
	_move_unit_towards(u, u["patrol_dest"])
	if (u["pos"] as Vector2).distance_to(u["patrol_dest"] as Vector2) <= ARRIVE_EPS:
		# Ping-pong A <-> B.
		if (u["patrol_dest"] as Vector2).distance_to(u["patrol_a"] as Vector2) <= ARRIVE_EPS:
			u["patrol_dest"] = u["patrol_b"]
		else:
			u["patrol_dest"] = u["patrol_a"]


func _step_guard(u: Dictionary, do_scan: bool) -> void:
	var gid := int(u.get("guard_id", -1))
	var g := _get_target(gid)
	if gid < 0 or g.is_empty() or not bool(g.get("alive", false)):
		u["guard_id"] = -1
		u["state"] = ST_IDLE
		u["target_id"] = -1
		return
	# La guardia ataca con su propia vision (escaneo periodico + revalidacion).
	if do_scan or int(u.get("target_id", -1)) < 0 or not is_alive(int(u.get("target_id", -1))):
		if do_scan or not is_alive(int(u.get("target_id", -1))):
			var e := nearest_enemy(u["pos"], float(u["sight"]), int(u["player_id"]), int(u["id"]))
			u["target_id"] = e
	var tgt_id := int(u.get("target_id", -1))
	if tgt_id >= 0 and is_alive(tgt_id):
		_step_combat(u, tgt_id, false, 0)
		return
	u["target_id"] = -1
	# Seguir al protegido: acercarse si esta mas lejos de GUARD_FOLLOW_DIST.
	var gp: Vector2 = g["pos"]
	if (u["pos"] as Vector2).distance_to(gp) > GUARD_FOLLOW_DIST:
		_move_unit_towards(u, gp)


## Intenta golpear/disparar si el cooldown lo permite.
func _try_hit(u: Dictionary, target_id: int) -> void:
	if int(u.get("cooldown_left", 0)) > 0:
		return
	var tgt := _get_target(target_id)
	if tgt.is_empty() or not bool(tgt.get("alive", false)):
		u["target_id"] = -1
		if str(u.get("state")) == ST_ATTACK:
			u["state"] = ST_IDLE
		return
	if bool(u.get("ranged", false)):
		_fire_projectile(u, target_id, tgt)
	else:
		var dmg := calc_melee_damage(u, tgt)
		u["cooldown_left"] = int(u.get("cooldown_ticks", int(round(MELEE_COOLDOWN_SEC * TICK_RATE))))
		_apply_damage(target_id, dmg, int(u.get("id", -1)))


func _fire_projectile(u: Dictionary, target_id: int, tgt: Dictionary) -> void:
	u["cooldown_left"] = int(u.get("cooldown_ticks", int(round(RANGED_COOLDOWN_SEC * TICK_RATE))))
	var from: Vector2 = u["pos"]
	var aim: Vector2 = tgt["pos"]
	# Error 0 si el objetivo esta parado; si se movio el tick anterior,
	# dispersion determinista en disco via SimRNG.
	if bool(_prev_moved.get(target_id, false)):
		var ang := _rng_next_float() * TAU
		var rr := sqrt(_rng_next_float()) * MISS_SPREAD_RADIUS
		aim += Vector2(cos(ang), sin(ang)) * rr
	var speed := float(u.get("projectile_speed", PROJECTILE_SPEED_DEFAULT))
	if speed <= 0.0:
		speed = PROJECTILE_SPEED_DEFAULT
	var dist := from.distance_to(aim)
	var flight_ticks := int(ceil(dist / maxf(0.01, speed * DT))) + 1
	var pid := _next_projectile_id
	_next_projectile_id += 1
	_projectiles[pid] = {
		"id": pid, "owner_id": int(u.get("id", -1)), "player_id": int(u.get("player_id", -1)),
		"target_id": target_id, "pos": from, "aim": aim, "speed": speed,
		"atk": float(u.get("attack", 0.0)), "bonus": bonus_vs_target(u, tgt),
		"age_ticks": 0, "max_age_ticks": flight_ticks + PROJECTILE_EXTRA_TICKS, "alive": true,
	}


func _step_projectile(p: Dictionary) -> void:
	if not bool(p.get("alive", false)):
		return
	p["age_ticks"] = int(p["age_ticks"]) + 1
	if int(p["age_ticks"]) > int(p["max_age_ticks"]):
		p["alive"] = false
		return
	var step := float(p.get("speed", PROJECTILE_SPEED_DEFAULT)) * DT
	p["pos"] = _move_towards(p["pos"], p["aim"], step)
	if (p["pos"] as Vector2).distance_to(p["aim"] as Vector2) <= ARRIVE_EPS:
		p["alive"] = false # se consume llegue o falle
		var tgt := _get_target(int(p.get("target_id", -1)))
		if tgt.is_empty() or not bool(tgt.get("alive", false)):
			return # objetivo muerto en vuelo: tiro perdido
		# Solo impacta si el objetivo sigue cerca del punto apuntado.
		if (tgt["pos"] as Vector2).distance_to(p["aim"] as Vector2) <= MISS_CAPTURE_RADIUS:
			var dmg := calc_pierce_damage(float(p.get("atk", 0.0)), tgt, float(p.get("bonus", 0.0)))
			_apply_damage(int(p.get("target_id", -1)), dmg, int(p.get("owner_id", -1)))


func _apply_damage(target_id: int, dmg: float, killer_id: int) -> void:
	var tgt := _get_target(target_id)
	if tgt.is_empty() or not bool(tgt.get("alive", false)):
		return
	tgt["hp"] = float(tgt.get("hp", 0.0)) - maxf(0.0, dmg)
	if float(tgt["hp"]) <= 0.0:
		tgt["hp"] = 0.0
		tgt["alive"] = false
		if _units.has(target_id):
			(_units[target_id] as Dictionary)["state"] = "dead"
		if EventBus.has_signal("unit_died"):
			EventBus.emit_signal("unit_died", target_id, killer_id)


# ------------------------------------------------------------ vision ---
## Enemigo vivo mas cercano en radio de vision (sight). -1 si no hay.
## Orden determinista: menor distancia, desempate por menor id.
func nearest_enemy(from_pos, sight: float, seeker_player_id: int, seeker_id: int = -1) -> int:
	var fp := _as_vec2(from_pos)
	var best := -1
	var best_d := 1e18
	var ids: Array = _units.keys()
	ids.sort()
	for uid in ids:
		uid = int(uid)
		if uid == seeker_id:
			continue
		var u: Dictionary = _units[uid]
		if not bool(u.get("alive", false)):
			continue
		if _is_friendly(seeker_player_id, int(u.get("player_id", -1))):
			continue
		var d := fp.distance_to(u["pos"] as Vector2)
		if d <= sight and (d < best_d - 0.000001 or (absf(d - best_d) <= 0.000001 and (best < 0 or uid < best))):
			best_d = d
			best = uid
	var bids: Array = _buildings.keys()
	bids.sort()
	for bid in bids:
		bid = int(bid)
		var b: Dictionary = _buildings[bid]
		if not bool(b.get("alive", false)):
			continue
		if _is_friendly(seeker_player_id, int(b.get("player_id", -1))):
			continue
		var d2 := fp.distance_to(b["pos"] as Vector2)
		if d2 <= sight and (d2 < best_d - 0.000001 or (absf(d2 - best_d) <= 0.000001 and (best < 0 or bid < best))):
			best_d = d2
			best = bid
	return best


func _is_friendly(a_pid: int, b_pid: int) -> bool:
	if a_pid == b_pid:
		return true
	# Mismo equipo = no enemigo (si GameManager esta disponible).
	if typeof(GameManager) != TYPE_NIL and GameManager != null:
		var ps = GameManager.get("players")
		if typeof(ps) == TYPE_ARRAY and a_pid >= 0 and b_pid >= 0:
			var arr: Array = ps
			if a_pid < arr.size() and b_pid < arr.size():
				var pa = arr[a_pid]
				var pb = arr[b_pid]
				if typeof(pa) == TYPE_DICTIONARY and typeof(pb) == TYPE_DICTIONARY:
					if int(pa.get("team", a_pid)) == int(pb.get("team", b_pid)):
						return true
	return false


# ------------------------------------------------------------ helpers ---
func _rng_next_float() -> float:
	# Via SimRNG (lockstep). Fallback determinista hash(tick+id) si no hay autoload (tests).
	if typeof(SimAPI) != TYPE_NIL and SimAPI != null and SimAPI.get("SimRNGNode") != null:
		return float(SimAPI.SimRNGNode.next_float())
	var s := int(_next_projectile_id * 2654435761 + 40503) & 0x7FFFFFFF
	return float(s % 1000000) / 1000000.0


func _move_unit_towards(u: Dictionary, target) -> void:
	var old: Vector2 = u["pos"]
	var step := float(u.get("speed", 0.9)) * DT
	var np := _move_towards(old, _as_vec2(target), step)
	u["pos"] = np
	if np.distance_to(old) > 0.000001:
		u["moved"] = true


func _move_towards(pos: Vector2, target: Vector2, max_step: float) -> Vector2:
	var d := pos.distance_to(target)
	if d <= max_step or d <= 0.000001:
		return target
	var t := max_step / d
	return Vector2(lerpf(pos.x, target.x, t), lerpf(pos.y, target.y, t))


## Acepta Vector2 / Vector3 / Array [x,y(,z)] / dict {x,y} y normaliza a Vector2.
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


# --------------------------------------------------------------- hash ---
## Cadena canonica del estado (para hash anti-desync en NetManager).
func sim_state_string() -> String:
	var parts: Array = []
	var ids: Array = _units.keys()
	ids.sort()
	for uid in ids:
		var u: Dictionary = _units[uid]
		var p: Vector2 = u["pos"]
		parts.append("u%d:p%d:%s:%.3f,%.3f:%.1f:%s:%d:%d" % [
			int(uid), int(u["player_id"]), str(u.get("state", ST_IDLE)),
			p.x, p.y, float(u.get("hp", 0.0)),
			str(u.get("target_id", -1)), int(u.get("cooldown_left", 0)),
			int(u.get("guard_id", -1))])
	var bids: Array = _buildings.keys()
	bids.sort()
	for bid in bids:
		var b: Dictionary = _buildings[bid]
		parts.append("b%d:%.1f" % [int(bid), float(b.get("hp", 0.0))])
	var pids: Array = _projectiles.keys()
	pids.sort()
	for pid in pids:
		var pr: Dictionary = _projectiles[pid]
		if bool(pr.get("alive", false)):
			var pp: Vector2 = pr["pos"]
			parts.append("p%d:%.2f,%.2f>%d" % [int(pid), pp.x, pp.y, int(pr.get("target_id", -1))])
	return "|".join(parts)


func sim_hash() -> int:
	if typeof(SimAPI) != TYPE_NIL and SimAPI != null and SimAPI.has_method("sim_hash"):
		return int(SimAPI.sim_hash(sim_state_string()))
	return int(hash(sim_state_string()))
