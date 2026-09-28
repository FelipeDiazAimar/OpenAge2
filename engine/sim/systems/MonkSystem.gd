extends RefCounted
## Monjes estilo AoE2.
## Convertir (Convert {range, cooldown, chance}): acercarse a alcance y
## canalizar; desde los 4 s, una tirada por segundo con `chance` (azar
## determinista de Sim.rng); a los 10 s la conversión es segura. Después, el
## monje recarga su fe `cooldown` segundos. Solo unidades enemigas; el asedio
## solo con la tecnología "redencion"; nunca otros monjes.
## Curar (Heal {range, rate}): HP/s a una unidad propia o aliada herida, por
## orden o, si está ocioso, a la herida más cercana dentro de su vista.

const FP := preload("res://engine/sim/FixedPoint.gd")
const World := preload("res://engine/sim/World.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")
const GatherSystem := preload("res://engine/sim/systems/GatherSystem.gd")
const CombatSystem := preload("res://engine/sim/systems/CombatSystem.gd")
const BuildSystem := preload("res://engine/sim/systems/BuildSystem.gd")
const GarrisonSystem := preload("res://engine/sim/systems/GarrisonSystem.gd")

const MIN_TICKS := 40 # 4 s antes de la primera tirada
const SURE_TICKS := 100 # 10 s: conversión segura
const REPATH := 10
const AUTO_HEAL_EVERY := 10


static func _inside(w, id: int) -> bool:
	return GarrisonSystem.is_inside(w, id)


## "" si el monje id puede convertir a t.
static func convert_error(sim, id: int, t: int) -> String:
	var w = sim.world
	if not w.has_ability(id, "Convert") or not w.entities.has(t) or _inside(w, t):
		return "no se puede convertir"
	var e: Dictionary = w.entities[t]
	if str(e["type"]) != "unit" or not w.has_ability(t, "Hitpoints"):
		return "solo unidades"
	var owner := int(w.entities[id]["owner"])
	if not sim.is_enemy(owner, int(e["owner"])):
		return "no es enemiga"
	var tags: Array = sim.def_for(t).get("tags", [])
	if tags.has("monje"):
		return "no convierte monjes"
	if tags.has("asedio") and not sim.researched(owner).has("redencion"):
		return "requiere Redención"
	return ""


static func heal_error(sim, id: int, t: int) -> String:
	var w = sim.world
	if not w.has_ability(id, "Heal") or id == t or not w.entities.has(t) or _inside(w, t):
		return "no se puede curar"
	var e: Dictionary = w.entities[t]
	if str(e["type"]) != "unit":
		return "solo unidades"
	var owner := int(w.entities[id]["owner"])
	if int(e["owner"]) != owner and sim.team_of(int(e["owner"])) != sim.team_of(owner):
		return "no es aliada"
	var hp: Dictionary = w.comp(t, "Hitpoints")
	if hp.is_empty() or int(hp["hp"]) >= int(hp["max"]):
		return "no está herida"
	return ""


static func stop(sim, id: int) -> void:
	var w = sim.world
	var c: Dictionary = w.comp(id, "Convert")
	if not c.is_empty():
		c["target"] = -1
		c["channel"] = 0
	var h: Dictionary = w.comp(id, "Heal")
	if not h.is_empty():
		h["target"] = -1
		h["explicit"] = false


static func order_convert(sim, id: int, t: int) -> void:
	if convert_error(sim, id, t) != "":
		return
	stop(sim, id)
	var c: Dictionary = sim.world.comp(id, "Convert")
	c["target"] = t
	c["repath"] = 0


static func order_heal(sim, id: int, t: int) -> void:
	if heal_error(sim, id, t) != "":
		return
	stop(sim, id)
	var h: Dictionary = sim.world.comp(id, "Heal")
	h["target"] = t
	h["explicit"] = true
	h["repath"] = 0


static func step(sim) -> void:
	var w = sim.world
	for id in w.ids_with("Convert"):
		if _inside(w, id) or w.has_ability(id, "Carrying"):
			continue
		var c: Dictionary = w.comp(id, "Convert")
		if int(c["faith"]) > 0:
			c["faith"] = int(c["faith"]) - 1
		var t: int = c["target"]
		if t < 0:
			continue
		if convert_error(sim, id, t) != "":
			c["target"] = -1
			c["channel"] = 0
			continue
		if not _approach(sim, id, t, c, FP.from_data(float(c["params"]["range"]))):
			c["channel"] = 0
			continue
		if int(c["faith"]) > 0:
			continue # recargando: espera en alcance
		c["channel"] = int(c["channel"]) + 1
		var ch: int = c["channel"]
		var roll := false
		if ch >= SURE_TICKS:
			roll = true
		elif ch >= MIN_TICKS and (ch - MIN_TICKS) % World.TICK_RATE == 0:
			var p := FP.from_data(float(c["params"]["chance"]))
			roll = int(sim.rng.next_u32() % FP.SCALE) < p
		if roll:
			_convert(sim, id, t, c)
	for id in w.ids_with("Heal"):
		if _inside(w, id) or w.has_ability(id, "Carrying"):
			continue
		_heal_tick(sim, id, w.comp(id, "Heal"))


## Acercarse a t hasta `reach`; true si ya está en alcance (y lo encara).
static func _approach(sim, id: int, t: int, c: Dictionary, reach: int) -> bool:
	var w = sim.world
	var p: Vector2i = w.entities[id]["pos"]
	var tp: Vector2i = w.entities[t]["pos"]
	var m: Dictionary = w.comp(id, "Move")
	if FP.dist(p, tp) <= reach:
		if not m.is_empty() and bool(m["moving"]):
			(m["waypoints"] as Array).clear()
			m["moving"] = false
		if not m.is_empty() and tp != p:
			m["facing"] = tp - p
		return true
	c["repath"] = int(c.get("repath", 0)) - 1
	if not m.is_empty() and (not bool(m["moving"]) or int(c["repath"]) <= 0):
		MoveSystem.order_move(w, sim.grid, id, tp)
		c["repath"] = REPATH
	return false


static func _convert(sim, id: int, t: int, c: Dictionary) -> void:
	var w = sim.world
	var owner := int(w.entities[id]["owner"])
	var old := int(w.entities[t]["owner"])
	GatherSystem.stop(sim, t)
	CombatSystem.stop(sim, t)
	BuildSystem.stop(sim, t)
	GarrisonSystem.cancel(w, t)
	stop(sim, t)
	var m: Dictionary = w.comp(t, "Move")
	if not m.is_empty():
		(m["waypoints"] as Array).clear()
		m["moving"] = false
	w.entities[t]["owner"] = owner
	var def: Dictionary = sim.players[owner]["defs"].get_def(str(w.entities[t]["def_id"]))
	if not def.is_empty():
		w.convert_entity(t, def) # sus stats pasan a ser los del nuevo dueño
	c["target"] = -1
	c["channel"] = 0
	c["faith"] = int(round(float(c["params"]["cooldown"]) * World.TICK_RATE))
	sim.events.append({"type": "converted", "id": t, "from": old, "owner": owner, "by": id})


static func _heal_tick(sim, id: int, h: Dictionary) -> void:
	var w = sim.world
	var t: int = h["target"]
	if t >= 0 and heal_error(sim, id, t) != "":
		h["target"] = -1
		h["explicit"] = false
		t = -1
	if t < 0:
		# Automático: solo si está ocioso (sin moverse ni convertir).
		var c: Dictionary = w.comp(id, "Convert")
		var m: Dictionary = w.comp(id, "Move")
		if (not c.is_empty() and int(c["target"]) >= 0) or (not m.is_empty() and bool(m["moving"])):
			return
		if w.has_ability(id, "RelicTask") or w.has_ability(id, "Garrisoned"):
			return # tiene otra orden (reliquia o guarecerse)
		if (w.tick + id) % AUTO_HEAL_EVERY != 0:
			return
		t = _nearest_injured(sim, id)
		if t < 0:
			return
		h["target"] = t
		h["explicit"] = false
	var reach := FP.from_data(float(h["params"]["range"]))
	if not _approach(sim, id, t, h, reach):
		return
	h["acc"] = int(h.get("acc", 0)) + FP.from_data(float(h["params"]["rate"])) / World.TICK_RATE
	var gain: int = int(h["acc"]) / FP.SCALE
	if gain <= 0:
		return
	h["acc"] = int(h["acc"]) - gain * FP.SCALE
	var hp: Dictionary = w.comp(t, "Hitpoints")
	hp["hp"] = mini(int(hp["max"]), int(hp["hp"]) + gain)


static func _nearest_injured(sim, id: int) -> int:
	var w = sim.world
	var sight := 4000
	if w.has_ability(id, "Vision"):
		sight = FP.from_data(float(w.comp(id, "Vision")["params"]["sight"]))
	var p: Vector2i = w.entities[id]["pos"]
	var best := -1
	var best_d := 0
	for o in w.spatial.query_radius(p, sight):
		if heal_error(sim, id, o) != "":
			continue
		var d := FP.dist(p, w.entities[o]["pos"])
		if best < 0 or d < best_d:
			best = o
			best_d = d
	return best
