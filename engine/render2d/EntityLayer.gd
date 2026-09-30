extends Node2D
## Sincroniza una EntityView por entidad de Sim.world (solo lectura),
## interpola posiciones entre ticks y resuelve picking/selección.

const Iso := preload("res://engine/render2d/Iso.gd")
const EntityView := preload("res://engine/render2d/EntityView.gd")
const FP := preload("res://engine/sim/FixedPoint.gd")
## Segundos que un cadáver queda en el suelo (el último segundo se funde).
const CORPSE_TIME := 5.0
const SINK_TIME := 3.0 # hundimiento: escora + hundido + fundido

var sim
var locator
var colors: Dictionary = {}
var views: Dictionary = {}
## Cadáveres (solo render): {view, t}. No se seleccionan.
var corpses: Array = []
## Escombros de edificios (destruction una vez + rubble quieto, permanente).
var rubbles: Array = []
var _prev: Dictionary = {}
## Comida inicial por mina (id -> amount) para la fracción visual.
var _mine_max: Dictionary = {}
## Edad cacheada por jugador para refrescar looks {age} al avanzar.
var _ages: Dictionary = {}
## Carcasas recientes: id -> segundos desde la muerte (animación death y luego decay).
var _dying: Dictionary = {}
const DEATH_TIME := 1.2


func _init() -> void:
	y_sort_enabled = true


func bind(p_sim, p_locator, p_colors: Dictionary) -> void:
	sim = p_sim
	locator = p_locator
	colors = p_colors


func snapshot() -> void:
	_prev.clear()
	for id in sim.world.entities:
		_prev[id] = sim.world.entities[id]["pos"]


func sync(alpha: float, delta: float) -> void:
	var w = sim.world
	for ev in sim.drain_events():
		if str(ev.get("type", "")) == "death":
			_spawn_corpse(ev)
			_spawn_rubble(ev)
		elif str(ev.get("type", "")) == "carcass":
			_dying[int(ev["id"])] = 0.0
	for p in range(sim.players.size()):
		var na := int(sim.age_of(p))
		if not _ages.has(p):
			_ages[p] = na
		elif int(_ages[p]) != na:
			_ages[p] = na
			for vid in views:
				var vv = views[vid]
				var e2: Dictionary = w.entities.get(vid, {})
				if e2.is_empty():
					continue
				if str(vv.kind) == "building" and int(e2.get("owner", -1)) == p:
					vv.refresh_age(na)
	for c in corpses.duplicate():
		c["t"] += delta
		if bool(c.get("sink", false)):
			var p := clampf(float(c["t"]) / SINK_TIME, 0.0, 1.0)
			c["view"].update_view(false, c.get("face", Vector2.ZERO), delta, "")
			c["view"].tick_sink(p, float(c["y0"]), 20.0)
			if float(c["t"]) >= SINK_TIME:
				c["view"].queue_free()
				corpses.erase(c)
			continue
		c["view"].update_view(false, Vector2.ZERO, delta, "death")
		if c["t"] > CORPSE_TIME - 1.0:
			c["view"].modulate.a = clampf(CORPSE_TIME - c["t"], 0.0, 1.0)
		if c["t"] >= CORPSE_TIME:
			c["view"].queue_free()
			corpses.erase(c)
	for rb in rubbles:
		rb["t"] = float(rb["t"]) + delta
		if float(rb["t"]) > 2.0 and str(rb.get("rubble", "")) != "" and not bool(rb.get("settled", false)):
			rb["settled"] = true
			var rv = rb["view"]
			rv.one_shot = false
			rv.update_view(false, Vector2.ZERO, 0.0, "rubble")
	for id in views.keys():
		if not w.entities.has(id):
			views[id].queue_free()
			views.erase(id)
			_dying.erase(id)
			_mine_max.erase(id)
	var ids: Array = w.entities.keys()
	ids.sort()
	var a := clampf(alpha, 0.0, 1.0)
	for id in ids:
		var e: Dictionary = w.entities[id]
		var v = views.get(id)
		var gar: Dictionary = w.comp(id, "Garrisoned")
		if (not gar.is_empty() and bool(gar["inside"])) or w.has_ability(id, "Held"):
			# (guarecida, o reliquia que lleva un monje o está en el monasterio)
			# Guarecida: no se dibuja ni se puede elegir.
			if v != null:
				v.visible = false
				v.selected = false
			continue
		if v != null and not v.visible:
			v.visible = true
		if v == null:
			var ociv := ""
			var pl: Array = sim.players
			if int(e["owner"]) >= 0 and int(e["owner"]) < pl.size():
				ociv = str((pl[int(e["owner"])] as Dictionary).get("civ", ""))
			var oage: int = int(sim.age_of(int(e["owner"]))) if int(e["owner"]) >= 0 and int(e["owner"]) < pl.size() else 1
			v = EntityView.new()
			v.setup(id, sim.def_for(id), colors.get(e["owner"], Color(0.6, 0.6, 0.6)), locator, ociv, oage)
			if w.has_ability(id, "Farm"):
				v.z_index = -1 # suelo: los granjeros se dibujan encima
			add_child(v)
			views[id] = v
		var cur: Vector2i = e["pos"]
		var prev: Vector2i = _prev.get(id, cur)
		v.position = Iso.to_screen(Vector2(prev).lerp(Vector2(cur), a) / 1000.0)
		var m: Dictionary = w.comp(id, "Move")
		var moving := false
		var facing := Vector2.ZERO
		if not m.is_empty():
			moving = m["moving"] or prev != cur
			facing = Iso.to_screen(Vector2(m["facing"]))
		var hp: Dictionary = w.comp(id, "Hitpoints")
		if not hp.is_empty() and int(hp["max"]) > 0:
			v.hp_ratio = float(hp["hp"]) / float(hp["max"])
		var f: Dictionary = w.comp(id, "Foundation")
		v.progress = 1.0 if f.is_empty() else float(f["progress"]) / float(maxi(1, int(f["total"])))
		var col: Color = colors.get(e["owner"], Color(0.6, 0.6, 0.6))
		v.set_color(col)
		v.owned = str(e["type"]) == "resource" and int(e["owner"]) >= 0 and w.has_ability(id, "Hitpoints")
		var action := ""
		var att: Dictionary = w.comp(id, "Attack")
		var g: Dictionary = w.comp(id, "Gather")
		var bld: Dictionary = w.comp(id, "Build")
		if not att.is_empty() and bool(att["attacking"]):
			action = "attack"
		elif not bld.is_empty() and (str(bld["state"]) == "building" or str(bld["state"]) == "repairing"):
			action = "build"
		elif not g.is_empty() and str(g["state"]) == "gathering":
			action = "task_" + str(g["kind"])
		var src: Dictionary = w.comp(id, "ResourceSource")
		if not src.is_empty() and bool(src["killed"]):
			# Carcasa: la animación de muerte una vez y luego el cuerpo en el suelo.
			var t: float = _dying.get(id, DEATH_TIME) + delta
			_dying[id] = t
			v.one_shot = t < DEATH_TIME
			action = "death" if t < DEATH_TIME else "decay"
			moving = false
		var fcomp: Dictionary = w.comp(id, "Farm")
		if not fcomp.is_empty() and not src.is_empty():
			var maxfood := float((fcomp.get("params", {}) as Dictionary).get("food", 0))
			if maxfood > 0.0:
				v.farm_frac = clampf(float(src.get("amount", 0)) / (maxfood * FP.SCALE), 0.0, 1.0)
		if (str(v.def_id) == "gold_mine" or str(v.def_id) == "stone_mine") and not src.is_empty():
			if not _mine_max.has(id):
				_mine_max[id] = float(src.get("amount", 1))
			v.mine_frac = clampf(float(src.get("amount", 0)) / maxf(float(_mine_max[id]), 1.0), 0.0, 1.0)
		v.update_view(moving, facing, delta, action)


## Vista previa de colocación: el edificio en la casilla, verde si se puede
## y rojo si no. def vacío la oculta.
var ghost
var _ghost_def := ""


func show_ghost(def: Dictionary, tile: Vector2i, ok: bool) -> void:
	if def.is_empty():
		hide_ghost()
		return
	if ghost == null or _ghost_def != str(def["id"]):
		hide_ghost()
		ghost = EntityView.new()
		ghost.setup(-1, def, Color(1, 1, 1), locator)
		ghost.z_index = 50
		add_child(ghost)
		_ghost_def = str(def["id"])
	var size := Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
	ghost.position = Iso.to_screen(Vector2(tile) + Vector2(size) * 0.5)
	ghost.modulate = Color(0.55, 1.0, 0.55, 0.75) if ok else Color(1.0, 0.35, 0.35, 0.75)
	ghost.update_view(false, Vector2.ZERO, 0.0, "")


func hide_ghost() -> void:
	if ghost != null:
		ghost.queue_free()
		ghost = null
		_ghost_def = ""


## Cadáver: death + fundido. Barco = graphics con "sail"; sin death se hunde
## ~3s con su idle/walk (escora + y+ + fundido) en vez de quedar de pie.
func _spawn_corpse(ev: Dictionary) -> void:
	var def: Dictionary = sim.registry.get_def(str(ev["def_id"]))
	if def.is_empty():
		return
	var gfx: Dictionary = def.get("graphics", {})
	if gfx.has("sail") and not gfx.has("death"):
		var sv := EntityView.new()
		sv.setup(int(ev["id"]), def, colors.get(ev["owner"], Color(0.6, 0.6, 0.6)), locator)
		sv.z_index = -1
		sv.position = Iso.milli_to_screen(ev["pos"])
		add_child(sv)
		var face := Iso.to_screen(Vector2(ev["facing"]))
		sv.update_view(false, face, 0.0, "")
		corpses.append({"view": sv, "t": 0.0, "sink": true, "y0": sv.position.y, "face": face})
		return
	# Sin animación de muerte no hay cadáver: si no, la unidad quedaría "de pie"
	# (fantasma) varios segundos.
	if not gfx.has("death"):
		return
	var v := EntityView.new()
	v.setup(int(ev["id"]), def, colors.get(ev["owner"], Color(0.6, 0.6, 0.6)), locator)
	v.one_shot = true
	v.z_index = -1 # bajo las unidades vivas
	v.position = Iso.milli_to_screen(ev["pos"])
	add_child(v)
	v.update_view(false, Iso.to_screen(Vector2(ev["facing"])), 0.0, "death")
	corpses.append({"view": v, "t": 0.0})


## Escombro de edificio: animación de destrucción una vez (si hay pack) y
## luego la pila de rubble quieta. Sin packs no hay escombro.
func _spawn_rubble(ev: Dictionary) -> void:
	var def: Dictionary = sim.registry.get_def(str(ev["def_id"]))
	var gfx: Dictionary = def.get("graphics", {})
	if def.is_empty() or str(def.get("type", "")) != "building" or not gfx.has("destruction"):
		return
	var v := EntityView.new()
	v.setup(int(ev["id"]), def, colors.get(ev["owner"], Color(0.6, 0.6, 0.6)), locator)
	v.one_shot = true
	v.z_index = -1 # bajo las unidades vivas
	v.position = Iso.milli_to_screen(ev["pos"])
	add_child(v)
	v.update_view(false, Vector2.ZERO, 0.0, "destruction")
	rubbles.append({"view": v, "t": 0.0, "rubble": str(gfx.get("rubble", ""))})
	while rubbles.size() > 40:
		var old_rb: Dictionary = rubbles[0]
		rubbles.erase(old_rb)
		(old_rb["view"] as Node).queue_free()


## Entidad bajo el punto (coordenadas de mundo del canvas). Prioriza unidades.
func pick(world_pos: Vector2) -> int:
	var best := -1
	var best_score := INF
	for id in views:
		var v = views[id]
		if not v.visible:
			continue
		var local: Vector2 = world_pos - v.position
		var d: float
		if v.kind == "building":
			d = Vector2(local.x, local.y * 2.0).length()
		elif v.kind == "resource":
			d = Vector2(local.x, local.y + 30.0).length() * 0.5
		else:
			d = Vector2(local.x, local.y + 28.0).length() * 0.5
		if d <= v.pick_radius() * (1.0 if v.kind == "building" else 1.5) and d < best_score:
			best_score = d
			best = id
	return best


func ids_in_rect(r: Rect2, owner: int) -> Array[int]:
	var out: Array[int] = []
	var box := r.abs()
	for id in views:
		var e: Dictionary = sim.world.entities.get(id, {})
		if e.is_empty() or int(e["owner"]) != owner or not sim.world.has_ability(id, "Move") or not views[id].visible:
			continue
		if box.has_point(views[id].position):
			out.append(id)
	out.sort()
	return out


func set_selected(ids: Array) -> void:
	for id in views:
		views[id].selected = ids.has(id)
