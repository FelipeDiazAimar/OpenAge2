extends RefCounted
## IA de un jugador: lee la simulación (solo lectura) y da órdenes con
## sim.queue_command, igual que una persona. Piensa cada THINK_EVERY ticks.
## Determinista (sin azar ni tiempo real, iteración por id): en LAN corre
## idéntica en todas las PCs y sus órdenes no viajan por la red.
##
## Prioridades de cada turno: defensa, aldeanos, casas, depósitos, granjas,
## reparto de recolectores, edad, investigación, ejército y ataque.

const FP := preload("res://engine/sim/FixedPoint.gd")
const Grid := preload("res://engine/sim/Grid.gd")

const THINK_EVERY := 10
## Aldeanos objetivo por edad.
const VILL_TARGET := [24, 34, 42, 48]
## Reparto de aldeanos por edad (proporciones).
const RATIOS := [
	{"food": 5, "wood": 5, "gold": 0, "stone": 0},
	{"food": 5, "wood": 4, "gold": 2, "stone": 0},
	{"food": 5, "wood": 3, "gold": 3, "stone": 1},
	{"food": 5, "wood": 3, "gold": 3, "stone": 1},
]
## Tamaño de ejército para salir a atacar, por edad.
const ATTACK_ARMY := [7, 10, 16, 22]
## Aldeanos para avanzar a la edad i+1.
const AGE_VILLS := [19, 28, 38]
const SEARCH_R := 26000 # radio de búsqueda de recursos alrededor del TC
const DEFENSE_R := 16000
const RES := ["food", "wood", "gold", "stone"]
const POP_CAP := 200

var sim
var pid := 0
## Enfriamientos: clave -> tick desde el que se puede repetir.
var _cool: Dictionary = {}
var _attacking := false
## Cimientos sin avance tras varios intentos: se dan por perdidos (no bloquean).
var _dead_sites: Dictionary = {}
var _site_tries: Dictionary = {}

# Estado leído en cada turno.
var _tc := -1
var _home := Vector2i.ZERO
var _vills: Array[int] = []
var _army: Array[int] = []
var _bld: Dictionary = {} # def_id -> [ids] (incluye cimientos)
var _res: Dictionary = {}
var _pop := Vector2i.ZERO
var _age := 0


func _init(p_sim, p_pid: int) -> void:
	sim = p_sim
	pid = p_pid


## Llamar una vez después de cada sim.step().
func tick() -> void:
	if (int(sim.world.tick) + pid) % THINK_EVERY != 0:
		return
	_scan()
	if _tc < 0 and _vills.is_empty():
		return # derrotado
	_defend()
	_resume_foundations()
	_train_villagers()
	_houses()
	_dropsites()
	_farms()
	_assign_idle()
	_military_buildings()
	_age_up()
	_research()
	_train_army()
	_attack()


# --- lectura ---------------------------------------------------------------

func _scan() -> void:
	var w = sim.world
	_vills.clear()
	_army.clear()
	_bld.clear()
	_tc = -1
	for id in w.ids_with("Hitpoints"):
		var e: Dictionary = w.entities[id]
		if int(e["owner"]) != pid or _inside(id):
			continue
		var t := str(e["type"])
		if t == "building":
			var d := str(e["def_id"])
			if not _bld.has(d):
				_bld[d] = []
			_bld[d].append(id)
			if d == "centro_urbano" and sim.is_built(id) and _tc < 0:
				_tc = id
		elif t == "unit":
			if w.has_ability(id, "Gather") and w.has_ability(id, "Build"):
				_vills.append(id)
			elif w.has_ability(id, "Attack") and not w.has_ability(id, "Naval") and w.has_ability(id, "Move"):
				_army.append(id)
	if _tc >= 0:
		_home = Grid.tile_of(w.entities[_tc]["pos"])
	elif not _vills.is_empty():
		_home = Grid.tile_of(w.entities[_vills[0]]["pos"])
	_res = sim.res_of(pid)
	_pop = sim.population(pid)
	_age = sim.age_of(pid)


func _inside(id: int) -> bool:
	var g: Dictionary = sim.world.comp(id, "Garrisoned")
	return not g.is_empty() and bool(g["inside"])


func _count(def_id: String) -> int:
	return (_bld.get(def_id, []) as Array).size()


func _built(def_id: String) -> Array:
	return (_bld.get(def_id, []) as Array).filter(func(b): return sim.is_built(b))


func _pending(def_id: String) -> bool:
	for b in _bld.get(def_id, []):
		if not sim.is_built(b) and not _dead_sites.has(b):
			return true
	return false


func _ready(key: String) -> bool:
	return int(sim.world.tick) >= int(_cool.get(key, 0))


func _cooldown(key: String, ticks: int) -> void:
	_cool[key] = int(sim.world.tick) + ticks


func _cmd(type: String, payload: Dictionary) -> void:
	sim.queue_command(pid, type, payload)


func _has(cost: Dictionary, reserve: Dictionary = {}) -> bool:
	for k in cost:
		if int(_res.get(k, 0)) - int(reserve.get(k, 0)) < int(round(float(cost[k]))):
			return false
	return true


func _spend(cost: Dictionary) -> void:
	for k in cost:
		_res[k] = int(_res.get(k, 0)) - int(round(float(cost[k])))


func _def(id: String) -> Dictionary:
	return sim.players[pid]["defs"].get_def(id)


## Lo que se guarda para la próxima edad cuando ya casi toca avanzar.
func _reserve() -> Dictionary:
	if _age < AGE_VILLS.size() and _vills.size() >= AGE_VILLS[_age] - 3:
		var a: Dictionary = sim.next_age(pid)
		if not a.is_empty():
			# Copia: nunca tocar las definiciones compartidas.
			return (a.get("cost", {}) as Dictionary).duplicate()
	return {}


func _dist_tiles(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# --- obras abandonadas -----------------------------------------------------

## Cimientos propios sin nadie construyéndolos: manda al aldeano libre más
## cercano; tras 4 intentos sin avance, se dan por perdidos.
func _resume_foundations() -> void:
	var w = sim.world
	var busy := {}
	for v in _vills:
		var b: Dictionary = w.comp(v, "Build")
		if str(b["state"]) != "idle":
			busy[int(b["target"])] = true
	for d in _bld:
		for f in _bld[d]:
			if sim.is_built(f) or busy.has(f) or _dead_sites.has(f) or not _ready("f%d" % f):
				continue
			var prog: int = w.comp(f, "Foundation")["progress"]
			var tries: Array = _site_tries.get(f, [0, -1])
			if prog == int(tries[1]):
				tries[0] = int(tries[0]) + 1
			tries[1] = prog
			_site_tries[f] = tries
			if int(tries[0]) >= 4:
				_dead_sites[f] = true
				continue
			var bs := _builders(Grid.tile_of(w.entities[f]["pos"]), 1)
			if not bs.is_empty():
				_cmd("build", {"ids": bs, "target": f})
				_cooldown("f%d" % f, 150)


# --- economía --------------------------------------------------------------

func _train_villagers() -> void:
	var target: int = VILL_TARGET[mini(_age, VILL_TARGET.size() - 1)]
	var queued := 0
	for tc in _built("centro_urbano"):
		for it in sim.world.comp(tc, "Queue")["items"]:
			if str(it["kind"]) == "unit":
				queued += 1
	for tc in _built("centro_urbano"):
		var q: Array = sim.world.comp(tc, "Queue")["items"]
		if q.size() >= 2 or _vills.size() + queued >= target:
			continue
		if sim.train_error(pid, tc, "aldeano") != "":
			continue
		_cmd("train", {"id": tc, "def": "aldeano"})
		_spend(_def("aldeano").get("cost", {}))
		queued += 1


func _houses() -> void:
	if _pop.y >= POP_CAP or _pending("casa") or not _ready("casa"):
		return
	var margin := 3 + 3 * _built("centro_urbano").size()
	if _pop.y - _pop.x > margin:
		return
	if _place("casa", _home, 5, 18, 1):
		_cooldown("casa", 60)


## Campamentos junto al recurso más cercano sin depósito cerca, y molino
## junto a las bayas.
func _dropsites() -> void:
	if _vills.size() >= 6:
		_camp_near("campamento_maderero", ["tree"], 5)
	if _vills.size() >= 9:
		_camp_near("molino", ["berry_bush"], 4)
	if _vills.size() >= 16 or _age >= 1:
		_camp_near("campamento_minero", ["gold_mine"], 4)
	if _age >= 2:
		_camp_near("campamento_minero", ["stone_mine"], 4)


func _camp_near(def_id: String, res_defs: Array, near_enough: int) -> void:
	var key := def_id + ":" + str(res_defs)
	if _pending(def_id) or not _ready(key):
		return
	var r := _nearest_resource(res_defs, _home)
	if r < 0:
		return
	var rt := Grid.tile_of(sim.world.entities[r]["pos"])
	# ¿Ya hay un depósito que acepte ese recurso cerca?
	var res := str(sim.world.comp(r, "ResourceSource")["params"]["resource"])
	for d in sim.world.ids_with("DropSite"):
		if int(sim.world.entities[d]["owner"]) != pid:
			continue
		if not (sim.world.comp(d, "DropSite")["params"]["accepts"] as Array).has(res):
			continue
		if _dist_tiles(Grid.tile_of(sim.world.entities[d]["pos"]), rt) <= near_enough:
			return
	if _place(def_id, rt, 2, 6, 1):
		_cooldown(key, 120)


func _farms() -> void:
	if not _ready("granja") or _pending("granja"):
		return
	var food_want := _wanted("food")
	var natural := 0
	for c in sim.world.spatial.query_radius(sim.world.entities[_tc]["pos"] if _tc >= 0 else Grid.center_of(_home), SEARCH_R):
		var src: Dictionary = sim.world.comp(c, "ResourceSource")
		if src.is_empty() or sim.world.has_ability(c, "Farm"):
			continue
		var d := str(sim.world.entities[c]["def_id"])
		if d == "berry_bush" or (d == "sheep" and int(sim.world.entities[c]["owner"]) == pid):
			natural += 1
	var farms := _count("granja")
	var need := food_want - mini(natural, 6)
	if farms >= need:
		return
	var near := _home
	var mills := _built("molino")
	if not mills.is_empty() and farms % 2 == 1:
		near = Grid.tile_of(sim.world.entities[mills[0]]["pos"])
	if _place("granja", near, 2, 9, 1, false):
		_cooldown("granja", 30)


## Aldeanos que se quieren en un recurso ahora.
func _wanted(res: String) -> int:
	var ratio: Dictionary = RATIOS[mini(_age, RATIOS.size() - 1)]
	var total := 0
	for k in ratio:
		total += int(ratio[k])
	return (_vills.size() * int(ratio[res]) + total - 1) / maxi(1, total)


func _assign_idle() -> void:
	var w = sim.world
	var counts: Dictionary = sim.gatherer_counts(pid)
	for v in _vills:
		var g: Dictionary = w.comp(v, "Gather")
		var b: Dictionary = w.comp(v, "Build")
		if str(g["state"]) != "idle" or str(b["state"]) != "idle" or bool(w.comp(v, "Move")["moving"]):
			continue
		if not w.comp(v, "Garrisoned").is_empty() or not _ready("v%d" % v):
			continue
		var order: Array = RES.duplicate()
		order.sort_custom(func(a, c): return _wanted(a) - int(counts[a]) > _wanted(c) - int(counts[c]))
		for res in order:
			var t := _resource_for(res, v)
			if t >= 0:
				_cmd("gather", {"ids": [v], "target": t})
				counts[res] = int(counts[res]) + 1
				_cooldown("v%d" % v, 40)
				break


## Mejor recurso de ese tipo para el aldeano v (comida: ovejas propias,
## carcasas, bayas y granjas libres; nunca caza peligrosa).
func _resource_for(res: String, v: int) -> int:
	var w = sim.world
	var from: Vector2i = w.entities[v]["pos"]
	var best := -1
	var best_score := 0
	for c in w.spatial.query_radius(Grid.center_of(_home), SEARCH_R):
		var src: Dictionary = w.comp(c, "ResourceSource")
		if src.is_empty():
			continue
		var p: Dictionary = src["params"]
		if str(p["resource"]) != res or bool(p.get("water", false)):
			continue
		var d := str(w.entities[c]["def_id"])
		var owner := int(w.entities[c]["owner"])
		var score := FP.dist(from, w.entities[c]["pos"])
		if bool(p.get("requires_kill", false)):
			if bool(p.get("hostile", false)) and not bool(src["killed"]):
				continue # jabalí vivo: no
			if bool(p.get("tame", false)) and owner != pid and owner >= 0:
				continue
			if not bool(src["killed"]) and not bool(p.get("tame", false)):
				continue # ciervos: no los caza
			score -= 20000 # ovejas y carcasas primero (se echan a perder)
		if w.has_ability(c, "Farm"):
			if owner != pid or not sim.is_built(c) or _farm_taken(c, v):
				continue
			score += 5000 # granjas después de lo natural
		if best < 0 or score < best_score:
			best = c
			best_score = score
	return best


func _farm_taken(farm: int, except: int) -> bool:
	for o in sim.world.ids_with("Gather"):
		if o != except and int(sim.world.comp(o, "Gather")["target"]) == farm:
			return true
	return false


func _nearest_resource(defs: Array, near: Vector2i) -> int:
	var w = sim.world
	var best := -1
	var best_d := 0
	for c in w.spatial.query_radius(Grid.center_of(near), SEARCH_R):
		if not defs.has(str(w.entities[c]["def_id"])) or not w.has_ability(c, "ResourceSource"):
			continue
		var d := FP.dist(Grid.center_of(near), w.entities[c]["pos"])
		if best < 0 or d < best_d:
			best = c
			best_d = d
	return best


# --- construcción ----------------------------------------------------------

## Coloca def_id cerca de `near` (anillos rmin..rmax) con `n` constructores.
## margin: deja una casilla libre alrededor (no encerrar a nadie).
func _place(def_id: String, near: Vector2i, rmin: int, rmax: int, n: int, margin: bool = true) -> bool:
	var def := _def(def_id)
	if def.is_empty() or not _has(def.get("cost", {}), _reserve() if def_id != "casa" else {}):
		return false
	var builders := _builders(near, n)
	if builders.is_empty():
		return false
	var tile := _spot(def_id, near, rmin, rmax, margin)
	if tile.x < 0:
		return false
	_cmd("place", {"ids": builders, "def": def_id, "tile": [tile.x, tile.y]})
	_spend(def.get("cost", {}))
	for b in builders:
		_cooldown("v%d" % b, 60)
	return true


func _spot(def_id: String, near: Vector2i, rmin: int, rmax: int, margin: bool) -> Vector2i:
	var size: Vector2i = sim.footprint_of(_def(def_id))
	for r in range(rmin, rmax + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var tile := near + Vector2i(dx, dy) - size / 2
				if sim.can_place(pid, def_id, tile) != "":
					continue
				if margin and not _clear_around(tile, size):
					continue
				return tile
	return Vector2i(-1, -1)


func _clear_around(tile: Vector2i, size: Vector2i) -> bool:
	for y in range(tile.y - 1, tile.y + size.y + 1):
		for x in range(tile.x - 1, tile.x + size.x + 1):
			if not sim.grid.is_walkable(Vector2i(x, y)):
				return false
	return true


## Los n aldeanos más cercanos que no estén construyendo (ociosos primero).
func _builders(near: Vector2i, n: int) -> Array:
	var w = sim.world
	var cands: Array = []
	for v in _vills:
		if str(w.comp(v, "Build")["state"]) != "idle" or not w.comp(v, "Garrisoned").is_empty():
			continue
		var idle: bool = str(w.comp(v, "Gather")["state"]) == "idle"
		var d := FP.dist(w.entities[v]["pos"], Grid.center_of(near))
		cands.append([0 if idle else 1, d, v])
	cands.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	var out: Array = []
	for c in cands.slice(0, n):
		out.append(c[2])
	return out


func _military_buildings() -> void:
	if _tc < 0:
		return
	if _vills.size() >= 14 and _count("cuartel") == 0:
		_place("cuartel", _home, 6, 16, 2)
	if _age >= 1 and _vills.size() >= 20:
		if _count("arqueria") == 0:
			_place("arqueria", _home, 6, 18, 2)
		elif _count("herreria") == 0:
			_place("herreria", _home, 6, 18, 2)
	if _age >= 2 and _count("establo") == 0 and _vills.size() >= 30:
		_place("establo", _home, 6, 18, 2)


# --- edades e investigación ------------------------------------------------

func _age_up() -> void:
	if _tc < 0 or _age >= AGE_VILLS.size() or _vills.size() < AGE_VILLS[_age] or not _ready("age"):
		return
	if sim.age_error(pid, _tc) == "":
		_cmd("age_up", {"id": _tc})
		_spend(sim.next_age(pid).get("cost", {}))
		_cooldown("age", 50)


func _research() -> void:
	if not _ready("research"):
		return
	var reserve := _reserve()
	reserve["food"] = int(reserve.get("food", 0)) + 50 # siempre para un aldeano
	var w = sim.world
	var bids: Array = []
	for d in _bld:
		for b in _bld[d]:
			if w.has_ability(b, "Research") and sim.is_built(b):
				bids.append(b)
	bids.sort()
	for b in bids:
		if not (w.comp(b, "Queue")["items"] as Array).is_empty():
			continue
		for t in w.comp(b, "Research")["params"]["techs"]:
			if sim.research_error(pid, b, str(t)) != "":
				continue
			var cost: Dictionary = _def(str(t)).get("cost", {})
			if not _has(cost, reserve):
				continue
			_cmd("research", {"id": b, "tech": str(t)})
			_spend(cost)
			_cooldown("research", 30)
			return


# --- ejército --------------------------------------------------------------

func _train_army() -> void:
	var w = sim.world
	var reserve := _reserve()
	reserve["food"] = int(reserve.get("food", 0)) + 50
	for d in ["cuartel", "arqueria", "establo"]:
		for b in _built(d):
			if (w.comp(b, "Queue")["items"] as Array).size() >= 2:
				continue
			for u in sim.trainable_units(pid, b):
				var ud := _def(u)
				var ab: Dictionary = ud.get("abilities", {})
				if not ab.has("Attack") or ab.has("Gather") or sim.train_error(pid, b, u) != "":
					continue
				if not _has(ud.get("cost", {}), reserve):
					continue
				_cmd("train", {"id": b, "def": u})
				_spend(ud.get("cost", {}))
				break


## Enemigos con ataque cerca de un centro urbano propio: todo el ejército va;
## sin ejército y con varios enemigos, campana.
func _defend() -> void:
	if _tc < 0:
		return
	var w = sim.world
	var threat := -1
	var threats := 0
	var best_d := 0
	var c: Vector2i = w.entities[_tc]["pos"]
	for e in w.spatial.query_radius(c, DEFENSE_R):
		if not w.has_ability(e, "Attack") or not w.has_ability(e, "Hitpoints"):
			continue
		if not sim.is_enemy(pid, int(w.entities[e]["owner"])) or str(w.entities[e]["type"]) != "unit":
			continue
		threats += 1
		var d := FP.dist(c, w.entities[e]["pos"])
		if threat < 0 or d < best_d:
			threat = e
			best_d = d
	var bell_on := bool(sim.players[pid].get("bell", false))
	if threat >= 0:
		var idle := _army.filter(func(a): return int(w.comp(a, "Attack")["target"]) < 0)
		if not idle.is_empty():
			_cmd("attack", {"ids": idle, "target": threat})
		if threats >= 3 and _army.size() < threats and not bell_on and _ready("bell"):
			_cmd("bell", {"id": _tc})
			_cooldown("bell", 100)
	elif bell_on and _ready("bell"):
		_cmd("bell", {"id": _tc})
		_cooldown("bell", 100)


func _attack() -> void:
	var need: int = ATTACK_ARMY[mini(_age, ATTACK_ARMY.size() - 1)]
	if _army.size() >= need:
		_attacking = true
	elif _army.size() < need / 2:
		_attacking = false
	if not _attacking or _army.is_empty():
		return
	var w = sim.world
	var idle := _army.filter(func(a): return int(w.comp(a, "Attack")["target"]) < 0)
	if idle.is_empty():
		return
	var cx := 0
	var cy := 0
	for a in _army:
		cx += int(w.entities[a]["pos"].x)
		cy += int(w.entities[a]["pos"].y)
	var center := Vector2i(cx / _army.size(), cy / _army.size())
	var t := _nearest_enemy(center)
	if t >= 0:
		_cmd("attack", {"ids": idle, "target": t})


## Enemigo más cercano: primero unidades militares, luego edificios, luego el resto.
func _nearest_enemy(from: Vector2i) -> int:
	var w = sim.world
	var best := -1
	var best_score := 0
	for e in w.ids_with("Hitpoints"):
		var ent: Dictionary = w.entities[e]
		if not sim.is_enemy(pid, int(ent["owner"])) or _enemy_hidden(e):
			continue
		var score := FP.dist(from, ent["pos"])
		if str(ent["type"]) == "building":
			score += 8000
		elif not w.has_ability(e, "Attack"):
			score += 4000
		if best < 0 or score < best_score:
			best = e
			best_score = score
	return best


func _enemy_hidden(e: int) -> bool:
	var g: Dictionary = sim.world.comp(e, "Garrisoned")
	return not g.is_empty() and bool(g["inside"])
