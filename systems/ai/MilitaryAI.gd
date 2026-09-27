extends Node
# MilitaryAI - stances, formaciones, patrol y attack-move (lockstep 10 Hz).
#
# Determinismo: NADA de randf/randi/Time/fisica. Iteracion ordenada por id,
# movimiento lineal con paso fijo, repath con throttle por ticks. Todo tiempo
# se mide en ticks via _on_tick() (TICK_RATE = 10, igual que SimAPI/GameManager).
#
# Navegacion: usa Pathfinding.find_path(from: Vector2i, to: Vector2i) sobre el
# grid 144x144 (celda 1 m = 1 tile). Posiciones internas en tiles (Vector2 x,z,
# igual que Economy): celda = floori(pos), waypoint = centro de celda.
# Si no hay Pathfinding inyectado o no hay ruta, steering directo (recta).
# Separacion: Avoidance.register(id, Vector3, radius) cada tick + update_all(0.1);
# el ajuste (m/s) se suma como desplazamiento push * delta. Sin Avoidance se omite.
#
# Stances (set_stance / comando "stance"):
#   agresivo  - persigue todo enemigo a <= 8 tiles de la unidad; solo suelta
#               la presa si muere o se aleja a > 16 tiles (LOST_AGGR).
#   defensivo - solo engancha enemigos a <= 4 tiles de home (posicion base);
#               si la presa sale de 4.5 tiles de home, rompe y vuelve a home.
#   mantener  - no se mueve a por nadie; ataca solo en rango (attack_range).
#   no_atacar - jamas ataca ni persigue; ignora ordenes de ataque.
# Ordenes de movimiento (move) NO auto-enganchan: se cumplen y punto.
# Idle + patrol + attack-move SI auto-enganchan segun stance.
# Una orden de ataque directa persigue al objetivo (salvo no_atacar).
#
# Formaciones (order_move con formation, offsets deterministas por indice):
#   linea      fila horizontal centrada:      (i - (n-1)/2, 0)
#   escalonada escalera diagonal pura/indice: (i, -i)
#   caja       2 columnas: col=i%2, fil=i/2:  (col-0.5, fil)
#   flanco     alas izq/der alternas:         (+/-(1+k*1.5), 0), k=i/2
# Unidades en tiles, spacing 1. formation_offset() es static y testeable.
#
# Patrol: order_patrol(ids, a, b) ping-pong A<->B; al llegar a un extremo
#   invierte la pierna. Engancha segun stance y retoma la pierna al terminar.
# Attack-move: order_attack_move(ids, destino) avanza por path y engancha
#   enemigos a <= 6 tiles (SIGHT_AM); al perderlos retoma el avance; al llegar
#   se queda hold (home = destino) y sigue enganchando segun stance.
#
# Comandos (EventBus.command_issued, tipos de core/API.md + "stance"):
#   move        {unit_ids, pos|target, formation?}
#   attack      {unit_ids, target|enemy_id}
#   attack_move {unit_ids, pos}
#   patrol      {unit_ids, a, b}  (alias: pos/pos2, from/to)
#   stop        {unit_ids}
#   stance      {unit_ids, stance}
# Posiciones aceptan Vector2 / Vector3 / Array [x,y] / [x,y,z] (x,z en tiles).
#
# Cableado: el bootstrap debe llamar setup(pathfinding_node, avoidance_node).
# Uso en tests sin arbol: load + add_child + llamadas directas a tick(t).

const TICK_RATE := 10 # debe coincidir con SimAPI.TICK_RATE
const TICK_DELTA := 0.1 # 1.0 / TICK_RATE
const ARRIVE_EPS := 0.1 # tolerancia de llegada en tiles
const REPATH_TICKS := 5 # throttle de find_path durante persecuciones
const REPATH_SAME_DES := 0.5 # si el destino apenas se movio, reutiliza path

const CHASE_AGGR := 8.0 # agresivo: radio de persecucion (tiles)
const LOST_AGGR := 16.0 # agresivo: distancia a la que da por perdida la presa
const CHASE_DEF := 4.0 # defensivo: radio de enganche alrededor de home
const LEASH_DEF := 4.5 # defensivo: la presa mas alla de home+esto rompe chase
const SIGHT_AM := 6.0 # attack-move / patrol: radio de adquisicion (tiles)
const ATTACK_PERIOD := 10 # cooldown entre golpes (ticks = 1 s)
const UNIT_RADIUS := 0.4 # radio de separacion por defecto (m = tiles)

const STANCE_AGGRESSIVE := "agresivo"
const STANCE_DEFENSIVE := "defensivo"
const STANCE_HOLD := "mantener"
const STANCE_NO_ATTACK := "no_atacar"
const STANCES := [STANCE_AGGRESSIVE, STANCE_DEFENSIVE, STANCE_HOLD, STANCE_NO_ATTACK]

const FORM_LINE := "linea"
const FORM_ECHELON := "escalonada"
const FORM_BOX := "caja"
const FORM_FLANK := "flanco"
const FORMS := [FORM_LINE, FORM_ECHELON, FORM_BOX, FORM_FLANK]

const ST_IDLE := "idle"
const ST_MOVE := "move"
const ST_CHASE := "chase"
const ST_ATTACK := "attack"
const ST_RETURN := "return"
const ST_PATROL := "patrol"
const ST_ATTACK_MOVE := "attack_move"

const SPEED_DEFAULT := 1.0 # tiles/s (infanteria aprox. AoE2)
const RANGE_DEFAULT := 1.5 # alcance cuerpo a cuerpo + contacto
const ATK_DEFAULT := 4.0
const HP_DEFAULT := 45.0
const ARMOR_DEFAULT := 0.0

var pathfinding: Node # inyectado via setup(); debe exponer find_path/is_walkable
var avoidance: Node # inyectado via setup(); Avoidance con register/update_all

# id -> {id, player_id, pos:Vector2, stance, state, home:Vector2,
#   move_target:Vector2, path:Array[Vector2], path_i:int, path_dest:Vector2, repath:int,
#   target_enemy:int, manual:bool, patrol_a:Vector2, patrol_b:Vector2, patrol_dest:Vector2,
#   am_target:Vector2, cooldown:int, speed, attack_range, atk, hp, armor, radius,
#   formation:String, formation_index:int}
var _units := {}
# id -> {id, player_id, pos:Vector2, hp, armor}
var _enemies := {}


func _ready() -> void:
	EventBus.command_issued.connect(_on_cmd)
	EventBus.tick_finished.connect(_on_tick)


## Inyeccion de dependencias (llamar desde el bootstrap de escena).
func setup(p_pathfinding: Node, p_avoidance: Node = null) -> void:
	pathfinding = p_pathfinding
	avoidance = p_avoidance


# --------------------------------------------------------------- registro ---

func register_unit(unit_id: int, player_id: int, pos, opts: Dictionary = {}) -> void:
	var p := _as_vec2(pos)
	_units[unit_id] = {
		"id": unit_id, "player_id": player_id, "pos": p,
		"stance": str(opts.get("stance", STANCE_AGGRESSIVE)), "state": ST_IDLE,
		"home": p, "move_target": p,
		"path": [], "path_i": 0, "path_dest": Vector2(1e18, 1e18), "repath": 0,
		"target_enemy": -1, "manual": false,
		"patrol_a": p, "patrol_b": p, "patrol_dest": p, "am_target": p,
		"cooldown": 0,
		"speed": float(opts.get("speed", SPEED_DEFAULT)),
		"attack_range": float(opts.get("attack_range", opts.get("range", RANGE_DEFAULT))),
		"atk": float(opts.get("atk", ATK_DEFAULT)),
		"hp": float(opts.get("hp", HP_DEFAULT)),
		"armor": float(opts.get("armor", ARMOR_DEFAULT)),
		"radius": float(opts.get("radius", UNIT_RADIUS)),
		"formation": str(opts.get("formation", "")), "formation_index": int(opts.get("formation_index", 0)),
	}


func register_enemy(enemy_id: int, player_id: int, pos, hp: float = HP_DEFAULT, armor: float = ARMOR_DEFAULT) -> void:
	_enemies[enemy_id] = {
		"id": enemy_id, "player_id": player_id, "pos": _as_vec2(pos),
		"hp": hp, "armor": armor,
	}


func set_enemy_pos(enemy_id: int, pos) -> void:
	if _enemies.has(enemy_id):
		_enemies[enemy_id]["pos"] = _as_vec2(pos)


func get_unit(unit_id: int) -> Dictionary:
	return (_units.get(unit_id, {}) as Dictionary).duplicate(true)


func remove_unit(unit_id: int) -> void:
	_units.erase(unit_id)


func remove_enemy(enemy_id: int) -> void:
	_enemies.erase(enemy_id)


func clear() -> void:
	_units.clear()
	_enemies.clear()
	pathfinding = null
	avoidance = null


## Dano externo (asedio, flechas de otro sistema...). Emite unit_died al morir.
func damage_unit(unit_id: int, amount: float, killer_id: int = -1) -> bool:
	if not _units.has(unit_id):
		return false
	var u: Dictionary = _units[unit_id]
	u["hp"] = float(u["hp"]) - amount
	if float(u["hp"]) <= 0.0:
		_units.erase(unit_id)
		if not _enemies.has(unit_id):
			# Solo limpia presas si ningun enemigo vivo comparte el id
			# (registros de unidades y enemigos son independientes).
			_clear_target_locks(unit_id)
		EventBus.unit_died.emit(unit_id, killer_id)
		return true
	return false


# ---------------------------------------------------------------- ordenes ---

func set_stance(unit_ids: Array, stance: String) -> bool:
	if not STANCES.has(stance):
		return false
	var any := false
	for vid in unit_ids:
		var id := int(vid)
		if not _units.has(id):
			continue
		_units[id]["stance"] = stance
		any = true
		if stance == STANCE_NO_ATTACK:
			# Suelta cualquier presa; si estaba persiguiendo, quieto.
			_units[id]["target_enemy"] = -1
			_units[id]["manual"] = false
			if str(_units[id]["state"]) in [ST_CHASE, ST_ATTACK]:
				_units[id]["state"] = ST_IDLE
				_units[id]["home"] = _units[id]["pos"]
	return any


func order_move(unit_ids: Array, target, formation: String = "") -> bool:
	var dest := _as_vec2(target)
	var ids := _sorted_existing(unit_ids)
	if ids.is_empty():
		return false
	var form := formation if FORMS.has(formation) else ""
	var slots := formation_slots(dest, form, ids) if not form.is_empty() else {}
	for n in ids.size():
		var u: Dictionary = _units[int(ids[n])]
		var slot: Vector2 = slots.get(int(ids[n]), dest)
		u["move_target"] = slot
		u["home"] = slot # el leash defensivo se centra donde termina la orden
		u["target_enemy"] = -1
		u["manual"] = false
		u["state"] = ST_MOVE
		u["formation"] = form
		u["formation_index"] = n
		u["repath"] = 0
		_request_path(u, slot)
	return true


func order_attack(unit_ids: Array, enemy_id: int) -> bool:
	if not _enemies.has(enemy_id):
		return false
	var any := false
	for vid in unit_ids:
		var id := int(vid)
		if not _units.has(id):
			continue
		var u: Dictionary = _units[id]
		if str(u["stance"]) == STANCE_NO_ATTACK:
			continue # no_atacar ignora ordenes de ataque
		u["target_enemy"] = enemy_id
		u["manual"] = true
		if str(u["state"]) in [ST_IDLE, ST_MOVE, ST_RETURN, ST_CHASE, ST_ATTACK]:
			u["state"] = ST_CHASE
		u["repath"] = 0
		any = true
	return any


func order_attack_move(unit_ids: Array, target) -> bool:
	var dest := _as_vec2(target)
	var ids := _sorted_existing(unit_ids)
	if ids.is_empty():
		return false
	for id in ids:
		var u: Dictionary = _units[id]
		u["am_target"] = dest
		u["home"] = dest
		u["target_enemy"] = -1
		u["manual"] = false
		u["state"] = ST_ATTACK_MOVE
		u["repath"] = 0
		_request_path(u, dest)
	return true


func order_patrol(unit_ids: Array, a, b) -> bool:
	var pa := _as_vec2(a)
	var pb := _as_vec2(b)
	var ids := _sorted_existing(unit_ids)
	if ids.is_empty():
		return false
	for id in ids:
		var u: Dictionary = _units[id]
		u["patrol_a"] = pa
		u["patrol_b"] = pb
		# Primera pierna: hacia el extremo mas lejano (ping-pong real).
		u["patrol_dest"] = pa if u["pos"].distance_to(pa) > u["pos"].distance_to(pb) else pb
		u["home"] = u["pos"]
		u["target_enemy"] = -1
		u["manual"] = false
		u["state"] = ST_PATROL
		u["repath"] = 0
		_request_path(u, u["patrol_dest"])
	return true


func order_stop(unit_ids: Array) -> bool:
	var any := false
	for vid in unit_ids:
		var id := int(vid)
		if not _units.has(id):
			continue
		var u: Dictionary = _units[id]
		u["state"] = ST_IDLE
		u["target_enemy"] = -1
		u["manual"] = false
		u["path"] = []
		u["path_i"] = 0
		u["home"] = u["pos"] # S: se planta donde esta
		any = true
	return any


# -------------------------------------------------------------- formacion ---

## Offset en tiles para el miembro `index` (0-based) de un grupo de `total`.
## Determinista puro: mismo (formation, index, total) => mismo offset.
static func formation_offset(formation: String, index: int, total: int = 1) -> Vector2:
	match formation:
		FORM_ECHELON:
			# Escalera diagonal: cada unidad 1 tile a la derecha y 1 atras.
			return Vector2(float(index), -float(index))
		FORM_BOX:
			# Caja de 2 columnas: parejas lado a lado, filas hacia atras.
			var col := index % 2
			var row := index / 2
			return Vector2(float(col) - 0.5, float(row))
		FORM_FLANK:
			# Alas alternas izq/der separandose del ancla.
			var k := index / 2
			var side := 1.0 if index % 2 == 0 else -1.0
			return Vector2(side * (1.0 + float(k) * 1.5), 0.0)
		_: # FORM_LINE y desconocido: fila horizontal centrada en el ancla
			var c := float(maxi(total, 1) - 1) * 0.5
			return Vector2(float(index) - c, 0.0)


## Slots ya resueltos: id unidad -> posicion destino. `ids` debe venir ordenado.
static func formation_slots(anchor: Vector2, formation: String, ids: Array) -> Dictionary:
	var out := {}
	var form := formation if FORMS.has(formation) else FORM_LINE
	for n in ids.size():
		out[int(ids[n])] = anchor + formation_offset(form, n, ids.size())
	return out


# ------------------------------------------------------------------ tick ---

func _on_tick(t: int) -> void:
	tick(t)


## Avanza 1 tick de simulacion (0.1 s). Orden determinista por id de unidad.
func tick(_t: int) -> void:
	var ids: Array = _units.keys()
	ids.sort()
	for vid in ids:
		if _units.has(vid):
			_step_unit(_units[vid])
	_apply_avoidance(ids)


func _step_unit(u: Dictionary) -> void:
	u["cooldown"] = maxi(0, int(u["cooldown"]) - 1)
	u["repath"] = maxi(0, int(u["repath"]) - 1)
	match str(u["state"]):
		ST_IDLE:
			var e := _acquire(u)
			if e >= 0:
				_engage(u, e, false)
		ST_MOVE:
			if _follow_path(u):
				u["state"] = ST_IDLE
		ST_CHASE, ST_ATTACK:
			_step_chase_attack(u)
		ST_RETURN:
			if _follow_path(u):
				u["state"] = ST_IDLE
		ST_PATROL:
			_step_patrol(u)
		ST_ATTACK_MOVE:
			_step_attack_move(u)
		_:
			u["state"] = ST_IDLE


# ---------------------------------------------------------------- combate ---

## Adquisicion automatica segun stance. -1 = nadie a la vista.
func _acquire(u: Dictionary) -> int:
	var stance := str(u["stance"])
	if stance == STANCE_NO_ATTACK:
		return -1
	var pos: Vector2 = u["pos"]
	if stance == STANCE_HOLD:
		return _nearest_enemy(pos, float(u["attack_range"]), pos, -1.0)
	if stance == STANCE_DEFENSIVE:
		# Solo engancha si la presa esta dentro del radio de home.
		return _nearest_enemy(pos, LOST_AGGR, u["home"], CHASE_DEF)
	# agresivo: todo lo que entre en 8 tiles de la unidad.
	return _nearest_enemy(pos, CHASE_AGGR, pos, -1.0)


## Enemigo vivo mas cercano a `pos` dentro de `radius`; si `leash_center` se
## pasa (>= 0 como radio `leash_radius`), la presa debe estar dentro de ese
## radio del centro. Desempate por id (determinista).
func _nearest_enemy(pos: Vector2, radius: float, leash_center: Vector2, leash_radius: float) -> int:
	var best := -1
	var best_d := radius + 0.000001
	var eids: Array = _enemies.keys()
	eids.sort()
	for eid in eids:
		var e: Dictionary = _enemies[eid]
		if leash_radius >= 0.0 and (e["pos"] as Vector2).distance_to(leash_center) > leash_radius + 0.000001:
			continue
		var d: float = (e["pos"] as Vector2).distance_to(pos)
		if d < best_d - 0.000001 or (absf(d - best_d) <= 0.000001 and int(eid) < best):
			best_d = d
			best = int(eid)
	return best


func _engage(u: Dictionary, enemy_id: int, manual: bool) -> void:
	u["target_enemy"] = enemy_id
	u["manual"] = manual
	if str(u["state"]) in [ST_IDLE, ST_MOVE, ST_RETURN, ST_CHASE, ST_ATTACK]:
		u["state"] = ST_CHASE
	# patrol / attack_move conservan su estado y retoman al terminar.


func _check_chase_valid(u: Dictionary) -> Dictionary:
	var eid := int(u["target_enemy"])
	if eid < 0 or not _enemies.has(eid):
		return {}
	return _enemies[eid]


func _step_chase_attack(u: Dictionary) -> void:
	var e := _check_chase_valid(u)
	if e.is_empty():
		_on_target_lost(u)
		return
	var stance := str(u["stance"])
	var epos: Vector2 = e["pos"]
	# Leash por stance (la orden manual solo respeta el radio de perdida).
	if not bool(u["manual"]):
		if stance == STANCE_DEFENSIVE and epos.distance_to(u["home"]) > LEASH_DEF:
			_break_to_home(u)
			return
		if stance == STANCE_HOLD:
			# mantener nunca debio salir: planta y pega solo en rango.
			u["state"] = ST_IDLE
			_on_target_lost(u)
			return
	if (u["pos"] as Vector2).distance_to(epos) > LOST_AGGR:
		_on_target_lost(u)
		return
	var d: float = (u["pos"] as Vector2).distance_to(epos)
	if d <= float(u["attack_range"]) + 0.000001:
		u["state"] = ST_ATTACK
		if int(u["cooldown"]) <= 0:
			_hit(u, e)
	else:
		u["state"] = ST_CHASE
		_request_path(u, epos)
		_follow_path(u)


## Golpe: dmg = max(1, atk - armor) + 0 (igual que Combat.calc_damage).
func _hit(u: Dictionary, e: Dictionary) -> void:
	u["cooldown"] = ATTACK_PERIOD
	var dmg := maxf(1.0, float(u["atk"]) - float(e["armor"]))
	e["hp"] = float(e["hp"]) - dmg
	if float(e["hp"]) <= 0.0:
		var eid := int(e["id"])
		_enemies.erase(eid)
		EventBus.unit_died.emit(eid, int(u["id"]))
		_clear_target_locks(eid)
		_on_target_lost(u)


## Todas las unidades que apuntaban al enemigo muerto sueltan la presa.
func _clear_target_locks(enemy_id: int) -> void:
	var ids: Array = _units.keys()
	ids.sort()
	for vid in ids:
		if _units.has(vid) and int(_units[vid]["target_enemy"]) == enemy_id:
			_on_target_lost(_units[vid])


func _on_target_lost(u: Dictionary) -> void:
	u["target_enemy"] = -1
	u["manual"] = false
	match str(u["state"]):
		ST_CHASE, ST_ATTACK:
			if str(u["stance"]) == STANCE_DEFENSIVE and (u["pos"] as Vector2).distance_to(u["home"]) > ARRIVE_EPS:
				_break_to_home(u)
			else:
				u["state"] = ST_IDLE
				u["home"] = u["pos"]
		ST_PATROL:
			u["repath"] = 0
			_request_path(u, u["patrol_dest"])
		ST_ATTACK_MOVE:
			u["repath"] = 0
			_request_path(u, u["am_target"])


func _break_to_home(u: Dictionary) -> void:
	u["target_enemy"] = -1
	u["manual"] = false
	if (u["pos"] as Vector2).distance_to(u["home"]) <= ARRIVE_EPS:
		u["state"] = ST_IDLE
	else:
		u["state"] = ST_RETURN
		u["repath"] = 0
		_request_path(u, u["home"])


# ------------------------------------------------------------------ ordenes ---

func _step_patrol(u: Dictionary) -> void:
	# 1) Enganchar segun stance (patrulla ve a 8, salvo no_atacar/mantener).
	if int(u["target_enemy"]) < 0:
		var stance := str(u["stance"])
		var e := -1
		if stance == STANCE_AGGRESSIVE:
			e = _nearest_enemy(u["pos"], SIGHT_AM, u["pos"], -1.0)
		elif stance == STANCE_DEFENSIVE:
			e = _nearest_enemy(u["pos"], CHASE_DEF, u["home"], CHASE_DEF)
		elif stance == STANCE_HOLD:
			e = _nearest_enemy(u["pos"], float(u["attack_range"]), u["pos"], -1.0)
		if e >= 0:
			_engage(u, e, false)
	# 2) Si hay presa, pegarse a ella; al morir/perderse se retoma la pierna.
	if int(u["target_enemy"]) >= 0:
		var e2 := _check_chase_valid(u)
		if e2.is_empty() or (u["pos"] as Vector2).distance_to(e2["pos"]) > LOST_AGGR:
			_on_target_lost(u)
		else:
			var d: float = (u["pos"] as Vector2).distance_to(e2["pos"])
			if d <= float(u["attack_range"]) + 0.000001:
				if int(u["cooldown"]) <= 0:
					_hit(u, e2)
			else:
				_request_path(u, e2["pos"])
				_follow_path(u)
			return
	# 3) Sin presa: avanzar la pierna; al llegar, ping-pong al otro extremo.
	if _follow_path(u):
		var dest: Vector2 = u["patrol_dest"]
		var other: Vector2 = u["patrol_a"] if dest.distance_to(u["patrol_a"]) > 0.001 else u["patrol_b"]
		u["patrol_dest"] = other
		u["repath"] = 0
		_request_path(u, other)


func _step_attack_move(u: Dictionary) -> void:
	# 1) Adquisicion en marcha (radio 6, salvo no_atacar/mantener-en-rango).
	if int(u["target_enemy"]) < 0:
		var stance := str(u["stance"])
		var e := -1
		if stance == STANCE_AGGRESSIVE or stance == STANCE_DEFENSIVE:
			e = _nearest_enemy(u["pos"], SIGHT_AM, u["pos"], -1.0)
		elif stance == STANCE_HOLD:
			e = _nearest_enemy(u["pos"], float(u["attack_range"]), u["pos"], -1.0)
		if e >= 0:
			_engage(u, e, false)
	# 2) Presa: enganchar; al terminar se retoma el avance.
	if int(u["target_enemy"]) >= 0:
		var e2 := _check_chase_valid(u)
		if e2.is_empty() or (u["pos"] as Vector2).distance_to(e2["pos"]) > LOST_AGGR:
			_on_target_lost(u)
		else:
			var d: float = (u["pos"] as Vector2).distance_to(e2["pos"])
			if d <= float(u["attack_range"]) + 0.000001:
				if int(u["cooldown"]) <= 0:
					_hit(u, e2)
			else:
				_request_path(u, e2["pos"])
				_follow_path(u)
			return
	# 3) Sin presa: avanzar al destino; al llegar, hold (home = destino).
	if _follow_path(u):
		u["state"] = ST_IDLE
		u["home"] = u["am_target"]


# --------------------------------------------------------------- navegacion ---

## Pide ruta a `dest` (throttle por REPATH_TICKS si el destino apenas cambio).
func _request_path(u: Dictionary, dest: Vector2) -> void:
	if int(u["repath"]) > 0 and (u["path_dest"] as Vector2).distance_to(dest) <= REPATH_SAME_DES and not (u["path"] as Array).is_empty():
		return
	u["path_dest"] = dest
	u["repath"] = REPATH_TICKS
	u["path"] = _compute_waypoints(u["pos"], dest)
	u["path_i"] = 1 if (u["path"] as Array).size() > 1 else 0


## Trail de waypoints (tiles) via Pathfinding.find_path; recta si no hay.
func _compute_waypoints(from: Vector2, dest: Vector2) -> Array:
	var out: Array = []
	if pathfinding != null and pathfinding.has_method("find_path") and pathfinding.has_method("is_walkable"):
		var fc := Vector2i(floori(from.x), floori(from.y))
		var tc := _nearest_walkable(Vector2i(floori(dest.x), floori(dest.y)))
		var raw = pathfinding.find_path(fc, tc)
		for c in raw:
			var cell := Vector2i(int(c.x), int(c.y))
			out.append(Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5))
	if out.is_empty():
		out.append(dest) # fallback determinista: steering directo
	return out


## Celda caminable mas cercana (barrido cuadrado determinista, radio <= 8).
func _nearest_walkable(cell: Vector2i) -> Vector2i:
	if pathfinding == null or not pathfinding.has_method("is_walkable"):
		return cell
	if bool(pathfinding.is_walkable(cell.x, cell.y)):
		return cell
	for r in range(1, 9):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if bool(pathfinding.is_walkable(cell.x + dx, cell.y + dy)):
					return Vector2i(cell.x + dx, cell.y + dy)
	return cell


## Avanza por el path a speed tiles/s. Devuelve true al llegar al final.
func _follow_path(u: Dictionary) -> bool:
	var path: Array = u["path"]
	var i := int(u["path_i"])
	if i >= path.size():
		return true
	var wp: Vector2 = path[i]
	var step: float = float(u["speed"]) * TICK_DELTA
	u["pos"] = _move_towards(u["pos"], wp, step)
	if (u["pos"] as Vector2).distance_to(wp) <= ARRIVE_EPS:
		u["path_i"] = i + 1
	return int(u["path_i"]) >= path.size()


## Separacion Avoidance tras el movimiento (desplazamiento push * delta).
func _apply_avoidance(ids: Array) -> void:
	if avoidance == null or not avoidance.has_method("register") or not avoidance.has_method("update_all"):
		return
	var sorted := ids.duplicate()
	sorted.sort()
	for vid in sorted:
		if not _units.has(vid):
			continue
		var p: Vector2 = _units[vid]["pos"]
		avoidance.register(int(vid), Vector3(p.x, 0.0, p.y), float(_units[vid]["radius"]))
	var push = avoidance.update_all(TICK_DELTA)
	if not (push is Dictionary):
		return
	for vid in sorted:
		if not _units.has(vid) or not push.has(vid):
			continue
		var adj: Vector3 = push[vid]
		var p2: Vector2 = _units[vid]["pos"]
		_units[vid]["pos"] = p2 + Vector2(adj.x, adj.z) * TICK_DELTA


# ---------------------------------------------------------------- comandos ---

func _on_cmd(cmd: Dictionary) -> void:
	var t := str(cmd.get("type", ""))
	var payload: Dictionary = cmd.get("payload", {})
	match t:
		"move":
			var ids := _parse_unit_ids(payload)
			if not ids.is_empty() and _has_pos(payload):
				order_move(ids, _parse_pos(payload), str(payload.get("formation", "")))
		"attack":
			var ids2 := _parse_unit_ids(payload)
			var target := int(payload.get("target", payload.get("enemy_id", payload.get("enemy", -1))))
			if not ids2.is_empty() and target >= 0:
				order_attack(ids2, target)
		"attack_move":
			var ids3 := _parse_unit_ids(payload)
			if not ids3.is_empty() and _has_pos(payload):
				order_attack_move(ids3, _parse_pos(payload))
		"patrol":
			var ids4 := _parse_unit_ids(payload)
			if not ids4.is_empty():
				var a = payload.get("a", payload.get("from", payload.get("pos", null)))
				var b = payload.get("b", payload.get("to", payload.get("pos2", null)))
				if a != null and b != null:
					order_patrol(ids4, a, b)
		"stop":
			var ids5 := _parse_unit_ids(payload)
			if not ids5.is_empty():
				order_stop(ids5)
		"stance":
			var ids6 := _parse_unit_ids(payload)
			if not ids6.is_empty() and payload.has("stance"):
				set_stance(ids6, str(payload["stance"]))


func _parse_unit_ids(payload: Dictionary) -> Array:
	var out: Array = []
	for key in ["unit_ids", "units"]:
		if payload.has(key) and typeof(payload[key]) == TYPE_ARRAY:
			for v in payload[key]:
				out.append(int(v))
	for key in ["unit_id", "unit"]:
		if payload.has(key):
			out.append(int(payload[key]))
	var seen := {}
	var dedup: Array = []
	for v in out:
		if not seen.has(v):
			seen[v] = true
			dedup.append(v)
	return dedup


func _has_pos(payload: Dictionary) -> bool:
	for key in ["pos", "target", "to", "dest"]:
		if payload.has(key):
			return true
	return false


func _parse_pos(payload: Dictionary):
	for key in ["pos", "target", "to", "dest"]:
		if payload.has(key):
			return payload[key]
	return Vector2.ZERO


# ---------------------------------------------------------------- helpers ---

func _sorted_existing(unit_ids: Array) -> Array:
	var out: Array = []
	for vid in unit_ids:
		if _units.has(int(vid)):
			out.append(int(vid))
	out.sort()
	return out


func _move_towards(pos: Vector2, target: Vector2, max_step: float) -> Vector2:
	var d := pos.distance_to(target)
	if d <= max_step or d <= 0.000001:
		return target
	var t := max_step / d
	return Vector2(lerpf(pos.x, target.x, t), lerpf(pos.y, target.y, t))


## Acepta Vector2 / Vector3 / Array [x,y(,z)] y normaliza a Vector2 (x,z) en tiles.
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
	var ids: Array = _units.keys()
	ids.sort()
	for vid in ids:
		var u: Dictionary = _units[vid]
		var p: Vector2 = u["pos"]
		parts.append("%d:%s:%.3f,%.3f:%s:%d:%.1f" % [
			int(vid), str(u["state"]), p.x, p.y,
			str(u["stance"]), int(u["target_enemy"]), float(u["hp"])])
	var eids: Array = _enemies.keys()
	eids.sort()
	for eid in eids:
		var e: Dictionary = _enemies[eid]
		parts.append("e%d:%.1f" % [int(eid), float(e["hp"])])
	return "|".join(parts)
