extends Node
# SiegeProjectiles - proyectiles de asedio deterministas por tick (lockstep 10Hz).
#
# Sin fisica de Godot (nada de RigidBody/Area/raycasts): todo manual en tick().
# Dos balisticas:
#   flecha   : recta, velocidad constante ARROW_SPEED, impacto al llegar a `to`
#              (radio de impacto HIT_RADIUS = 0.5). Dano a un solo objetivo.
#   catapulta: parabola de 2.0s fijos (CATAPULT_TICKS = 20 ticks), altura
#              h(t) = 4 * H * t * (1-t). Al impactar: dano en area
#              SPLASH_RADIUS = 2.0 + tala arboles en el area (onagro).
#
# Dano estilo AoE2 (igual que Combat.calc_damage):
#   dmg = max(1, atk - armor_pierce) + bonus_vs_tipo
# Bonus vs tipo: bonus_building si objetivo es edificio, bonus_cavalry si es
#   caballeria. El param `atk` acepta float (usa bonus por defecto) o
#   Dictionary {attack, bonus_building, bonus_cavalry}.
# Ariete: absorbe flechas -> si objetivo es "ram"/"ariete" y el proyectil es
#   flecha, armadura efectiva = max(armor, RAM_PIERCE_ARMOR = 8.0).
#
# Determinismo: sin randf/Time/fisica; iteracion ordenada por id; DT fijo
#   TICK_DT = 0.1; posiciones Vector3 (XZ = tiles, Y = altura visual).
# API pedida: firearrow(from, to, atk), firecatapult(from, to, atk), tick().

signal projectile_impacted(proj_id: int, pos: Vector3)
signal target_damaged(target_id: int, damage: float, hp_left: float)
signal tree_cut(tree_id: int, pos: Vector3)

const TICK_RATE := 10 # debe coincidir con SimAPI.TICK_RATE
const TICK_DT := 0.1 # 1.0 / TICK_RATE, paso fijo, sin delta real
const ARROW_SPEED := 14.0 # tiles/s, recta
const HIT_RADIUS := 0.5 # radio de impacto directo (flecha y centro catapulta)
const CATAPULT_TICKS := 20 # 2.0s * 10Hz, parabola fija
const CATAPULT_HEIGHT := 5.0 # pico del arco en tiles
const SPLASH_RADIUS := 2.0 # dano en area de catapulta
const RAM_PIERCE_ARMOR := 8.0 # ariete absorbe flechas
const ARROW_BONUS_CAVALRY := 2.0
const ARROW_BONUS_BUILDING := 0.0
const CATAPULT_BONUS_BUILDING := 10.0
const CATAPULT_BONUS_CAVALRY := 4.0

const KIND_ARROW := "arrow"
const KIND_CATAPULT := "catapult"

# kinds que cuentan como edificio / caballeria / ariete (ES + EN, minusculas)
const BUILDING_KINDS := ["building", "edificio", "casa", "torre", "castillo", "centro_urbano"]
const CAVALRY_KINDS := ["cavalry", "caballeria", "caballería", "jinete", "caballo"]
const RAM_KINDS := ["ram", "ariete"]

var _next_id := 1
# id -> {id, kind, pos:Vector3, vel:Vector3, from:Vector3, to:Vector3,
#         atk, bonus_building, bonus_cavalry, age, duration, alive}
var _projectiles := {}
# id -> {id, pos:Vector3, kind:String, hp, max_hp, armor_pierce, alive}
var _targets := {}
# id -> {id, pos:Vector3}
var _trees := {}
# Vector2i(celda) -> true : celdas marcadas como bosque (talables por onagro)
var _forest := {}


func _ready() -> void:
	if Engine.has_singleton("EventBus"):
		pass
	EventBus.tick_finished.connect(_on_tick)


func _on_tick(t: int) -> void:
	tick(t)


# ------------------------------------------------------------- registro ---

## Registra un objetivo danable. kind: "infantry","cavalry","building","ram",...
func register_target(id: int, pos, kind: String = "infantry", hp: float = 30.0, armor_pierce: float = 0.0) -> void:
	_targets[id] = {
		"id": id, "pos": _as_vec3(pos), "kind": kind.to_lower().strip_edges(),
		"hp": float(hp), "max_hp": float(hp),
		"armor_pierce": float(armor_pierce), "alive": float(hp) > 0.0,
	}


func unregister_target(id: int) -> void:
	_targets.erase(id)


func get_target(id: int) -> Dictionary:
	return _targets.get(id, {})


func get_target_hp(id: int) -> float:
	return float(_targets.get(id, {}).get("hp", 0.0))


func is_target_alive(id: int) -> bool:
	return bool(_targets.get(id, {}).get("alive", false))


## Registra un arbol talable por el onagro.
func register_tree(id: int, pos) -> void:
	_trees[id] = {"id": id, "pos": _as_vec3(pos)}


func unregister_tree(id: int) -> void:
	_trees.erase(id)


## Marca una celda de grid (enteros de tile) como bosque o no.
func set_forest_cell(x: int, y: int, is_forest: bool) -> void:
	var c := Vector2i(x, y)
	if is_forest:
		_forest[c] = true
	else:
		_forest.erase(c)


func is_forest_at(world_pos) -> bool:
	var w := _as_vec3(world_pos)
	return _forest.has(Vector2i(floori(w.x), floori(w.z)))


func clear() -> void:
	_projectiles.clear()
	_targets.clear()
	_trees.clear()
	_forest.clear()
	_next_id = 1


# --------------------------------------------------------------- disparo ---

## Flecha recta: from -> to a velocidad constante. Devuelve id del proyectil.
## atk: float o {attack, bonus_building, bonus_cavalry}.
func firearrow(from, to, atk) -> int:
	var f := _as_vec3(from)
	var t := _as_vec3(to)
	f.y = 0.0
	t.y = 0.0
	var parsed := _parse_atk(atk, ARROW_BONUS_BUILDING, ARROW_BONUS_CAVALRY)
	var delta := t - f
	delta.y = 0.0
	var dist := Vector2(delta.x, delta.z).length()
	var vel := Vector3.ZERO
	if dist > 0.000001:
		var dir := delta / dist
		vel = dir * ARROW_SPEED
	var pid := _next_id
	_next_id += 1
	# Impacto inmediato si from ~= to (evita proyectil eterno a dist 0).
	if dist <= HIT_RADIUS:
		_projectiles[pid] = _make_proj(pid, KIND_ARROW, t, vel, f, t, parsed, 0, 1)
		_resolve_arrow_impact(pid)
	else:
		_projectiles[pid] = _make_proj(pid, KIND_ARROW, f, vel, f, t, parsed, 0, -1)
	return pid


## Alias snake_case (mismo comportamiento).
func fire_arrow(from, to, atk) -> int:
	return firearrow(from, to, atk)


## Catapulta/onagro: parabola de 2s (20 ticks) de from a to. Devuelve id.
func firecatapult(from, to, atk) -> int:
	var f := _as_vec3(from)
	var t := _as_vec3(to)
	f.y = 0.0
	t.y = 0.0
	var parsed := _parse_atk(atk, CATAPULT_BONUS_BUILDING, CATAPULT_BONUS_CAVALRY)
	var total := float(CATAPULT_TICKS) * TICK_DT # = 2.0s
	var vel := Vector3.ZERO
	if total > 0.000001:
		vel = (t - f) / total
		vel.y = 0.0
	var pid := _next_id
	_next_id += 1
	_projectiles[pid] = _make_proj(pid, KIND_CATAPULT, f, vel, f, t, parsed, 0, CATAPULT_TICKS)
	return pid


## Alias snake_case (mismo comportamiento).
func fire_catapult(from, to, atk) -> int:
	return firecatapult(from, to, atk)


func get_projectile(id: int) -> Dictionary:
	return _projectiles.get(id, {})


func projectile_count() -> int:
	return _projectiles.size()


# ------------------------------------------------------------------ tick ---

## Avanza 1 tick (0.1s). Acepta el nº de tick por compatibilidad lockstep,
## pero no lo usa: el movimiento solo depende de DT fijo. Orden por id.
func tick(_t: int = -1) -> void:
	var ids: Array = _projectiles.keys()
	ids.sort()
	for pid in ids:
		if not _projectiles.has(pid):
			continue # pudo impactar y borrarse en este mismo tick
		var p: Dictionary = _projectiles[pid]
		if p["kind"] == KIND_ARROW:
			_step_arrow(p)
		else:
			_step_catapult(p)


func _step_arrow(p: Dictionary) -> void:
	var step: Vector3 = (p["vel"] as Vector3) * TICK_DT
	var next: Vector3 = (p["pos"] as Vector3) + step
	next.y = 0.0
	p["pos"] = next
	p["age"] = int(p["age"]) + 1
	var to: Vector3 = p["to"]
	# Impacto por cercania (radio 0.5) o por sobrepasar el punto `to`.
	var d := Vector2(next.x - to.x, next.z - to.z).length()
	if d <= HIT_RADIUS or _overshot(p["from"], to, next):
		_resolve_arrow_impact(int(p["id"]))


func _step_catapult(p: Dictionary) -> void:
	p["age"] = int(p["age"]) + 1
	var age := int(p["age"])
	var dur := int(p["duration"])
	var f: Vector3 = p["from"]
	var t: Vector3 = p["to"]
	if age >= dur:
		p["pos"] = t
		_resolve_catapult_impact(int(p["id"]))
		return
	# Parabola determinista: XZ lerp lineal + altura h(t) = 4*H*s*(1-s).
	var s := float(age) / float(dur)
	var flat := f.lerp(t, s)
	flat.y = 0.0
	flat.y = 4.0 * CATAPULT_HEIGHT * s * (1.0 - s)
	p["pos"] = flat


# --------------------------------------------------------------- impacto ---

func _resolve_arrow_impact(pid: int) -> void:
	if not _projectiles.has(pid):
		return
	var p: Dictionary = _projectiles[pid]
	var impact: Vector3 = p["pos"]
	_projectiles.erase(pid)
	projectile_impacted.emit(pid, impact)
	var tid := _nearest_target(impact, HIT_RADIUS)
	if tid < 0:
		return # fallo: sin objetivo en radio 0.5
	_apply_damage(tid, p, impact)


func _resolve_catapult_impact(pid: int) -> void:
	if not _projectiles.has(pid):
		return
	var p: Dictionary = _projectiles[pid]
	var impact: Vector3 = p["pos"]
	impact.y = 0.0
	_projectiles.erase(pid)
	projectile_impacted.emit(pid, impact)
	# Dano en area radio 2.0, orden determinista por id de objetivo.
	var tids := _targets_in_radius(impact, SPLASH_RADIUS)
	for tid in tids:
		_apply_damage(tid, p, impact)
	# Onagro tala: corta arboles registrados en radio 2.0 si el impacto cae
	# en bosque, o si hay arboles en el area aunque no haya celda marcada
	# (las dos vias son deterministas: orden por id).
	var cut := _cut_trees_at(impact, SPLASH_RADIUS)
	if not cut.is_empty():
		tree_cut_batch(cut)


## Emite tree_cut por cada arbol talado (orden por id).
func tree_cut_batch(cut_ids: Array) -> void:
	for tid in cut_ids:
		var pos := Vector3.ZERO
		if _trees.has(int(tid)):
			pos = _trees[int(tid)]["pos"]
		_trees.erase(int(tid))
		tree_cut.emit(int(tid), pos)


# ----------------------------------------------------------------- dano ---

func _apply_damage(tid: int, p: Dictionary, impact: Vector3) -> void:
	if not _targets.has(tid):
		return
	var tgt: Dictionary = _targets[tid]
	if not bool(tgt.get("alive", true)):
		return
	var kind := str(tgt.get("kind", "infantry"))
	var armor := float(tgt.get("armor_pierce", 0.0))
	# Ariete absorbe flechas: armadura efectiva minima 8 vs flecha.
	if p["kind"] == KIND_ARROW and kind in RAM_KINDS:
		armor = maxf(armor, RAM_PIERCE_ARMOR)
	var bonus := 0.0
	if kind in BUILDING_KINDS:
		bonus = float(p["bonus_building"])
	elif kind in CAVALRY_KINDS:
		bonus = float(p["bonus_cavalry"])
	var dmg: float = maxf(1.0, float(p["atk"]) - armor) + bonus
	tgt["hp"] = float(tgt["hp"]) - dmg
	if float(tgt["hp"]) <= 0.0:
		tgt["hp"] = 0.0
		tgt["alive"] = false
	target_damaged.emit(tid, dmg, float(tgt["hp"]))


## Formula AoE2 expuesta (misma que Combat.calc_damage).
func calc_damage(atk: float, armor: float, bonus: float = 0.0) -> float:
	return maxf(1.0, atk - armor) + bonus


# ---------------------------------------------------------------- helpers ---

func _make_proj(pid: int, kind: String, pos: Vector3, vel: Vector3, from: Vector3, to: Vector3, parsed: Dictionary, age: int, duration: int) -> Dictionary:
	return {
		"id": pid, "kind": kind, "pos": pos, "vel": vel,
		"from": from, "to": to,
		"atk": float(parsed["attack"]),
		"bonus_building": float(parsed["bonus_building"]),
		"bonus_cavalry": float(parsed["bonus_cavalry"]),
		"age": age, "duration": duration,
	}


func _parse_atk(atk, def_building: float, def_cavalry: float) -> Dictionary:
	if typeof(atk) == TYPE_DICTIONARY:
		return {
			"attack": float(atk.get("attack", atk.get("atk", 0.0))),
			"bonus_building": float(atk.get("bonus_building", atk.get("bonus_vs_building", def_building))),
			"bonus_cavalry": float(atk.get("bonus_cavalry", atk.get("bonus_vs_cavalry", def_cavalry))),
		}
	return {"attack": float(atk), "bonus_building": def_building, "bonus_cavalry": def_cavalry}


## true si `cur` sobrepaso `to` respecto a `from` (producto punto >= |to-from|^2).
func _overshot(from: Vector3, to: Vector3, cur: Vector3) -> bool:
	var ab := Vector2(to.x - from.x, to.z - from.z)
	var ac := Vector2(cur.x - from.x, cur.z - from.z)
	return (ac.dot(ab)) >= ab.length_squared()


## Objetivo vivo mas cercano dentro del radio; desempate por menor id. -1 si no hay.
func _nearest_target(center: Vector3, radius: float) -> int:
	var best := -1
	var best_d := radius + 0.000001
	var ids: Array = _targets.keys()
	ids.sort()
	for tid in ids:
		var tgt: Dictionary = _targets[tid]
		if not bool(tgt.get("alive", true)):
			continue
		var tp: Vector3 = tgt["pos"]
		var d := Vector2(tp.x - center.x, tp.z - center.z).length()
		if d <= radius + 0.000001:
			if best < 0 or d < best_d - 0.000001:
				best_d = d
				best = int(tid)
	return best


## Todos los objetivos vivos en radio, ordenados por id.
func _targets_in_radius(center: Vector3, radius: float) -> Array:
	var out: Array = []
	var ids: Array = _targets.keys()
	ids.sort()
	for tid in ids:
		var tgt: Dictionary = _targets[tid]
		if not bool(tgt.get("alive", true)):
			continue
		var tp: Vector3 = tgt["pos"]
		if Vector2(tp.x - center.x, tp.z - center.z).length() <= radius + 0.000001:
			out.append(int(tid))
	return out


## Arboles en radio, ordenados por id. Solo tala si cae en bosque o hay
## arboles registrados en el area (regla onagro).
func _cut_trees_at(center: Vector3, radius: float) -> Array:
	var in_radius: Array = []
	var ids: Array = _trees.keys()
	ids.sort()
	for tid in ids:
		var tp: Vector3 = _trees[tid]["pos"]
		if Vector2(tp.x - center.x, tp.z - center.z).length() <= radius + 0.000001:
			in_radius.append(int(tid))
	if in_radius.is_empty():
		return []
	# Si hay celdas de bosque marcadas, exigir bosque cercano; si no hay
	# ninguna celda marcada, talar por arboles registrados (modo simple).
	if _forest.is_empty():
		return in_radius
	if is_forest_at(center):
		return in_radius
	# Sin bosque justo en el centro, aun talar si alguna celda del area es bosque.
	var r := int(ceili(radius))
	var cx := floori(center.x)
	var cz := floori(center.z)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if Vector2(float(dx), float(dz)).length() <= radius + 0.000001:
				if _forest.has(Vector2i(cx + dx, cz + dz)):
					return in_radius
	return []


static func _as_vec3(pos) -> Vector3:
	if pos is Vector3:
		return pos
	if pos is Vector2:
		return Vector3(pos.x, 0.0, pos.y)
	if typeof(pos) == TYPE_ARRAY:
		if pos.size() >= 3:
			return Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		if pos.size() == 2:
			return Vector3(float(pos[0]), 0.0, float(pos[1]))
	return Vector3.ZERO


## Cadena canonica del estado (para hash anti-desync en NetManager).
func sim_state_string() -> String:
	var parts: Array = []
	var pids: Array = _projectiles.keys()
	pids.sort()
	for pid in pids:
		var p: Dictionary = _projectiles[pid]
		var pp: Vector3 = p["pos"]
		parts.append("p%d:%s:%.3f,%.3f:age%d" % [int(pid), str(p["kind"]), pp.x, pp.z, int(p["age"])])
	var tids: Array = _targets.keys()
	tids.sort()
	for tid in tids:
		var t: Dictionary = _targets[tid]
		parts.append("t%d:%s:%.1f" % [int(tid), str(t["kind"]), float(t["hp"])])
	var trees: Array = _trees.keys()
	trees.sort()
	parts.append("trees:%d" % trees.size())
	return "|".join(parts)
