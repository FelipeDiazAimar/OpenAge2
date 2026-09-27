extends Node2D
## Sincroniza una EntityView por entidad de Sim.world (solo lectura),
## interpola posiciones entre ticks y resuelve picking/selección.

const Iso := preload("res://engine/render2d/Iso.gd")
const EntityView := preload("res://engine/render2d/EntityView.gd")
## Segundos que un cadáver queda en el suelo (el último segundo se funde).
const CORPSE_TIME := 5.0

var sim
var locator
var colors: Dictionary = {}
var views: Dictionary = {}
## Cadáveres (solo render): {view, t}. No se seleccionan.
var corpses: Array = []
var _prev: Dictionary = {}
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
		elif str(ev.get("type", "")) == "carcass":
			_dying[int(ev["id"])] = 0.0
	for c in corpses.duplicate():
		c["t"] += delta
		c["view"].update_view(false, Vector2.ZERO, delta, "death")
		if c["t"] > CORPSE_TIME - 1.0:
			c["view"].modulate.a = clampf(CORPSE_TIME - c["t"], 0.0, 1.0)
		if c["t"] >= CORPSE_TIME:
			c["view"].queue_free()
			corpses.erase(c)
	for id in views.keys():
		if not w.entities.has(id):
			views[id].queue_free()
			views.erase(id)
			_dying.erase(id)
	var ids: Array = w.entities.keys()
	ids.sort()
	var a := clampf(alpha, 0.0, 1.0)
	for id in ids:
		var e: Dictionary = w.entities[id]
		var v = views.get(id)
		if v == null:
			v = EntityView.new()
			v.setup(id, sim.def_for(id), colors.get(e["owner"], Color(0.6, 0.6, 0.6)), locator)
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
		var col: Color = colors.get(e["owner"], Color(0.6, 0.6, 0.6))
		v.set_color(col)
		v.owned = str(e["type"]) == "resource" and int(e["owner"]) >= 0
		var action := ""
		var att: Dictionary = w.comp(id, "Attack")
		var g: Dictionary = w.comp(id, "Gather")
		if not att.is_empty() and bool(att["attacking"]):
			action = "attack"
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
		v.update_view(moving, facing, delta, action)


## Cadáver: animación de muerte una vez (si hay pack) y fundido.
func _spawn_corpse(ev: Dictionary) -> void:
	var def: Dictionary = sim.registry.get_def(str(ev["def_id"]))
	# Sin animación de muerte no hay cadáver: si no, la unidad quedaría "de pie"
	# (fantasma) varios segundos.
	if def.is_empty() or not (def.get("graphics", {}) as Dictionary).has("death"):
		return
	var v := EntityView.new()
	v.setup(int(ev["id"]), def, colors.get(ev["owner"], Color(0.6, 0.6, 0.6)), locator)
	v.one_shot = true
	v.z_index = -1 # bajo las unidades vivas
	v.position = Iso.milli_to_screen(ev["pos"])
	add_child(v)
	v.update_view(false, Iso.to_screen(Vector2(ev["facing"])), 0.0, "death")
	corpses.append({"view": v, "t": 0.0})


## Entidad bajo el punto (coordenadas de mundo del canvas). Prioriza unidades.
func pick(world_pos: Vector2) -> int:
	var best := -1
	var best_score := INF
	for id in views:
		var v = views[id]
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
		if e.is_empty() or int(e["owner"]) != owner or not sim.world.has_ability(id, "Move"):
			continue
		if box.has_point(views[id].position):
			out.append(id)
	out.sort()
	return out


func set_selected(ids: Array) -> void:
	for id in views:
		views[id].selected = ids.has(id)
