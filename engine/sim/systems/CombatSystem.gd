extends RefCounted
## Combate estilo AoE2. Daño = max(1, Σ clases max(0, ataque - armadura));
## las clases que no son melee/pierce son bonus contra la entidad (id o tag,
## admite plural: "arquero" vale contra "arqueros"). Recarga y retardo del
## golpe en ticks; proyectiles hacia donde estaba el objetivo (pueden fallar);
## militares y edificios con Attack atacan solos a enemigos a la vista.

const FP := preload("res://engine/sim/FixedPoint.gd")
const World := preload("res://engine/sim/World.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")

const CONTACT := 700
const BUILDING_CONTACT := 500
const DEFAULT_DELAY := 3
const ACQUIRE_EVERY := 5
const REPATH_EVERY := 10
const HIT_RADIUS := 500


static func damage(atk: Dictionary, target_def: Dictionary, armor: Dictionary) -> int:
	var tags: Array = target_def.get("tags", [])
	var tid := str(target_def.get("id", ""))
	var keys: Array = atk.keys()
	keys.sort()
	var total := 0
	for c in keys:
		var k := str(c)
		var applies := k == "melee" or k == "pierce" or k == tid or tags.has(k) or tags.has(k + "s") or tags.has(k + "es")
		if applies:
			total += maxi(0, FP.from_data(float(atk[c])) - FP.from_data(float(armor.get(k, 0))))
	return maxi(1, (total + FP.SCALE / 2) / FP.SCALE)


static func order_attack(sim, id: int, target: int) -> void:
	var a: Dictionary = sim.world.comp(id, "Attack")
	if a.is_empty():
		return
	a["target"] = target
	a["explicit"] = true
	a["windup"] = -1
	a["repath"] = 0


static func stop(sim, id: int) -> void:
	var a: Dictionary = sim.world.comp(id, "Attack")
	if a.is_empty():
		return
	a["target"] = -1
	a["explicit"] = false
	a["windup"] = -1
	a["attacking"] = false


static func step(sim) -> void:
	_step_projectiles(sim)
	var w = sim.world
	for id in w.ids_with("Attack"):
		if not w.entities.has(id):
			continue
		var a: Dictionary = w.comp(id, "Attack")
		if int(a["cooldown"]) > 0:
			a["cooldown"] = int(a["cooldown"]) - 1
		var t: int = a["target"]
		if t >= 0 and not _valid_target(sim, id, a, t):
			stop(sim, id)
			t = -1
		if t < 0:
			if _auto(sim, id) and (w.tick + id) % ACQUIRE_EVERY == 0:
				t = _acquire(sim, id)
				a["target"] = t
			if t < 0:
				a["attacking"] = false
				continue
		_engage(sim, id, a, t)


static func _valid_target(sim, id: int, a: Dictionary, t: int) -> bool:
	var w = sim.world
	if not w.entities.has(t) or not w.has_ability(t, "Hitpoints"):
		return false
	if bool(a["explicit"]):
		return true
	return sim.is_enemy(int(w.entities[id]["owner"]), int(w.entities[t]["owner"]))


## Ataque automático: militares (sin Gather) quietos y edificios con Attack.
static func _auto(sim, id: int) -> bool:
	var w = sim.world
	if w.has_ability(id, "Gather"):
		return false
	var m: Dictionary = w.comp(id, "Move")
	return m.is_empty() or not bool(m["moving"])


static func _acquire(sim, id: int) -> int:
	var w = sim.world
	var e: Dictionary = w.entities[id]
	var sight := 0
	if w.has_ability(id, "Vision"):
		sight = FP.from_data(float(w.comp(id, "Vision")["params"]["sight"]))
	sight = maxi(sight, FP.from_data(float(w.comp(id, "Attack")["params"]["range"])) + CONTACT)
	var best := -1
	var best_score := 0
	for c in w.spatial.query_radius(e["pos"], sight):
		if c == id or not w.has_ability(c, "Hitpoints"):
			continue
		if not sim.is_enemy(int(e["owner"]), int(w.entities[c]["owner"])):
			continue
		var score := FP.dist(e["pos"], w.entities[c]["pos"])
		if str(w.entities[c]["type"]) == "building":
			score += 1000000 # AoE2: prefiere unidades
		if best < 0 or score < best_score:
			best = c
			best_score = score
	return best


static func _engage(sim, id: int, a: Dictionary, t: int) -> void:
	var w = sim.world
	var params: Dictionary = a["params"]
	if _in_reach(sim, id, t):
		var m: Dictionary = w.comp(id, "Move")
		var tpos: Vector2i = w.entities[t]["pos"]
		if not m.is_empty():
			if bool(m["moving"]):
				(m["waypoints"] as Array).clear()
				m["moving"] = false
			var d: Vector2i = tpos - w.entities[id]["pos"]
			if d != Vector2i.ZERO:
				m["facing"] = d
		a["attacking"] = true
		if int(a["windup"]) > 0:
			a["windup"] = int(a["windup"]) - 1
		elif int(a["windup"]) < 0 and int(a["cooldown"]) == 0:
			a["cooldown"] = FP.from_data(float(params["reload"])) / (FP.SCALE / World.TICK_RATE)
			a["windup"] = DEFAULT_DELAY
			if params.has("attack_delay"):
				a["windup"] = FP.from_data(float(params["attack_delay"])) / (FP.SCALE / World.TICK_RATE)
		if int(a["windup"]) == 0:
			a["windup"] = -1
			_hit(sim, id, t)
		return
	a["attacking"] = false
	a["windup"] = -1
	if not w.has_ability(id, "Move"):
		a["target"] = -1
		return
	a["repath"] = int(a["repath"]) - 1
	if int(a["repath"]) <= 0:
		a["repath"] = REPATH_EVERY
		MoveSystem.order_move(w, sim.grid, id, _aim_point(sim, id, t))


static func _in_reach(sim, id: int, t: int) -> bool:
	var w = sim.world
	var params: Dictionary = w.comp(id, "Attack")["params"]
	var rng := FP.from_data(float(params["range"]))
	var min_r := FP.from_data(float(params.get("min_range", 0.0)))
	var p: Vector2i = w.entities[id]["pos"]
	var d: int
	var reach: int
	if str(w.entities[t]["type"]) == "building":
		d = _rect_dist(p, _rect(sim, t))
		reach = rng + BUILDING_CONTACT
	else:
		d = FP.dist(p, w.entities[t]["pos"])
		reach = rng + CONTACT
	return d <= reach and d >= min_r


static func _aim_point(sim, id: int, t: int) -> Vector2i:
	var p: Vector2i = sim.world.entities[id]["pos"]
	if str(sim.world.entities[t]["type"]) == "building":
		var r := _rect(sim, t)
		var lo: Vector2i = r[0]
		var hi: Vector2i = r[1]
		return Vector2i(clampi(p.x, lo.x, hi.x - 1), clampi(p.y, lo.y, hi.y - 1))
	return sim.world.entities[t]["pos"]


static func _hit(sim, id: int, t: int) -> void:
	var w = sim.world
	var params: Dictionary = w.comp(id, "Attack")["params"]
	var owner := int(w.entities[id]["owner"])
	if params.has("projectile_speed"):
		var from: Vector2i = w.entities[id]["pos"]
		var to: Vector2i = w.entities[t]["pos"]
		var speed := maxi(1, FP.from_data(float(params["projectile_speed"])) / World.TICK_RATE)
		sim.projectiles.append({
			"id": sim.next_projectile_id(), "owner": owner, "target": t, "from": from, "pos": from,
			"to": to, "speed": speed, "damage": params["damage"],
			"area": FP.from_data(float(params.get("area_radius", 0.0))),
			"age": 0, "total": maxi(1, (FP.dist(from, to) + speed - 1) / speed),
		})
	else:
		apply_damage(sim, params["damage"], t)


static func apply_damage(sim, atk: Dictionary, t: int) -> void:
	var w = sim.world
	if not w.entities.has(t) or not w.has_ability(t, "Hitpoints"):
		return
	var armor: Dictionary = {}
	if w.has_ability(t, "Armor"):
		armor = w.comp(t, "Armor")["params"]["classes"]
	var hp: Dictionary = w.comp(t, "Hitpoints")
	hp["hp"] = int(hp["hp"]) - damage(atk, sim.def_for(t), armor)
	if int(hp["hp"]) <= 0:
		sim.kill(t)


static func _step_projectiles(sim) -> void:
	var w = sim.world
	var keep: Array = []
	for p in sim.projectiles:
		p["age"] = int(p["age"]) + 1
		var pos: Vector2i = p["pos"]
		var to: Vector2i = p["to"]
		var d := to - pos
		var dist := FP.length(d.x, d.y)
		if dist > int(p["speed"]):
			p["pos"] = pos + Vector2i(d.x * int(p["speed"]) / dist, d.y * int(p["speed"]) / dist)
			keep.append(p)
			continue
		p["pos"] = to
		_land(sim, p)
	sim.projectiles = keep


static func _land(sim, p: Dictionary) -> void:
	var w = sim.world
	var to: Vector2i = p["to"]
	var owner := int(p["owner"])
	if int(p["area"]) > 0:
		for c in w.spatial.query_radius(to, int(p["area"])):
			if w.has_ability(c, "Hitpoints") and sim.is_enemy(owner, int(w.entities[c]["owner"])):
				apply_damage(sim, p["damage"], c)
		return
	var t: int = p["target"]
	if w.entities.has(t) and _hits(sim, t, to):
		apply_damage(sim, p["damage"], t)
		return
	for c in w.spatial.query_radius(to, HIT_RADIUS):
		if w.has_ability(c, "Hitpoints") and sim.is_enemy(owner, int(w.entities[c]["owner"])):
			apply_damage(sim, p["damage"], c)
			return


static func _hits(sim, t: int, to: Vector2i) -> bool:
	if str(sim.world.entities[t]["type"]) == "building":
		return _rect_dist(to, _rect(sim, t)) <= HIT_RADIUS
	return FP.dist(sim.world.entities[t]["pos"], to) <= HIT_RADIUS


static func _rect(sim, id: int) -> Array:
	var def: Dictionary = sim.def_for(id)
	var size := Vector2i.ONE
	if def.get("footprint") is Array:
		size = Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
	var half := size * (FP.SCALE / 2)
	var c: Vector2i = sim.world.entities[id]["pos"]
	return [c - half, c + half]


static func _rect_dist(p: Vector2i, r: Array) -> int:
	var lo: Vector2i = r[0]
	var hi: Vector2i = r[1]
	var dx := maxi(maxi(lo.x - p.x, 0), p.x - hi.x)
	var dy := maxi(maxi(lo.y - p.y, 0), p.y - hi.y)
	return FP.length(dx, dy)
