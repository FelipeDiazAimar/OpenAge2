extends Node
# Techs - investigacion de Herreria / Universidad / Monasterio + techs unicas.
#
# Modelo "como edades" (GameManager._process_age_research): cada jugador tiene
# UNA investigacion a la vez con timer en ticks (10 Hz). Coste al iniciar
# (GameManager.try_spend), reembolso 50% al cancelar (refund_cancel).
# Determinismo: sin randf/Time/SceneTreeTimer; iteracion ordenada por pid;
# carga de JSON solo en _ready (fuera del tick).
#
# Comandos (via SimAPI.queue_command, lockstep):
#   SimAPI.queue_command(pid, "research_tech", {"tech_id": "forja"})
#   SimAPI.queue_command(pid, "cancel_research_tech", {})
# NOTA: el tipo "research" esta reservado para edades en GameManager
# (avance de edad). Usar SIEMPRE "research_tech" para no disparar un age_up
# accidental (GameManager interpreta "research" sin age/target como "edad
# siguiente" y cobraria 500 de comida).
#
# DB: data/techs/herreria.json, universidad.json, monasterio.json +
#     data/factions/*.json (disponibilidad por civ + techs unicas de castillo).
# Efectos cuantificados: {"categoria": "infanteria|arqueros|caballeria",
#   "attack": int, "armor_melee": int, "armor_pierce": int, "range": int, ...}
# Getters para Combat/Production/MonkAI:
#   get_bonus_ataque(pid, categoria), get_bonus_armadura_melee(pid, categoria),
#   get_bonus_armadura_pierce(pid, categoria), get_bonus_alcance(pid, categoria),
#   is_completed(pid, tech_id), has_balistica(pid), get_velocidad_produccion(pid, edificio)

const TICK_RATE := 10 # debe coincidir con SimAPI.TICK_RATE y GameManager.TICK_RATE
const TECHS_DIR := "res://data/techs"
const FACTIONS_DIR := "res://data/factions"
const AGE_ORDER := ["alta_edad_media", "feudal", "castillos", "imperial"]

# Fallback si los JSON no son legibles (tests sin filesystem).
# Replica data/techs/*.json: +1 atk/def por nivel, brasa +1 alcance, etc.
const FALLBACK_TECHS := [
	{"id": "forja", "building": "herreria", "edad": "feudal", "coste": {"food": 150}, "tiempo_sec": 30, "requiere": [], "efectos": {"categoria": "infanteria", "attack": 1}},
	{"id": "hierro_fundido", "building": "herreria", "edad": "castillos", "coste": {"food": 220, "gold": 160}, "tiempo_sec": 40, "requiere": ["forja"], "efectos": {"categoria": "infanteria", "attack": 1}},
	{"id": "alto_horno", "building": "herreria", "edad": "imperial", "coste": {"food": 350, "gold": 250}, "tiempo_sec": 60, "requiere": ["hierro_fundido"], "efectos": {"categoria": "infanteria", "attack": 2}},
	{"id": "armadura_inf_1", "building": "herreria", "edad": "feudal", "coste": {"food": 100}, "tiempo_sec": 30, "requiere": [], "efectos": {"categoria": "infanteria", "armor_melee": 1}},
	{"id": "armadura_inf_2", "building": "herreria", "edad": "castillos", "coste": {"food": 200, "gold": 100}, "tiempo_sec": 40, "requiere": ["armadura_inf_1"], "efectos": {"categoria": "infanteria", "armor_melee": 1, "armor_pierce": 1}},
	{"id": "armadura_inf_3", "building": "herreria", "edad": "imperial", "coste": {"food": 300, "gold": 150}, "tiempo_sec": 60, "requiere": ["armadura_inf_2"], "efectos": {"categoria": "infanteria", "armor_melee": 1, "armor_pierce": 1}},
	{"id": "ataque_arq_1", "building": "herreria", "edad": "feudal", "coste": {"food": 100, "gold": 50}, "tiempo_sec": 30, "requiere": [], "efectos": {"categoria": "arqueros", "attack": 1}},
	{"id": "ataque_arq_2", "building": "herreria", "edad": "castillos", "coste": {"food": 200, "gold": 100}, "tiempo_sec": 40, "requiere": ["ataque_arq_1"], "efectos": {"categoria": "arqueros", "attack": 1}},
	{"id": "ataque_arq_3", "building": "herreria", "edad": "imperial", "coste": {"food": 300, "gold": 200}, "tiempo_sec": 60, "requiere": ["ataque_arq_2"], "efectos": {"categoria": "arqueros", "attack": 1, "range": 1}},
	{"id": "armadura_arq_1", "building": "herreria", "edad": "feudal", "coste": {"food": 150}, "tiempo_sec": 30, "requiere": [], "efectos": {"categoria": "arqueros", "armor_melee": 1, "armor_pierce": 1}},
	{"id": "armadura_arq_2", "building": "herreria", "edad": "castillos", "coste": {"food": 200, "gold": 100}, "tiempo_sec": 40, "requiere": ["armadura_arq_1"], "efectos": {"categoria": "arqueros", "armor_melee": 1, "armor_pierce": 1}},
	{"id": "armadura_arq_3", "building": "herreria", "edad": "imperial", "coste": {"food": 250, "gold": 150}, "tiempo_sec": 60, "requiere": ["armadura_arq_2"], "efectos": {"categoria": "arqueros", "armor_melee": 1, "armor_pierce": 2}},
	{"id": "ataque_cab_1", "building": "herreria", "edad": "feudal", "coste": {"food": 150}, "tiempo_sec": 30, "requiere": [], "efectos": {"categoria": "caballeria", "attack": 1}},
	{"id": "ataque_cab_2", "building": "herreria", "edad": "castillos", "coste": {"food": 220, "gold": 160}, "tiempo_sec": 40, "requiere": ["ataque_cab_1"], "efectos": {"categoria": "caballeria", "attack": 1}},
	{"id": "ataque_cab_3", "building": "herreria", "edad": "imperial", "coste": {"food": 350, "gold": 250}, "tiempo_sec": 60, "requiere": ["ataque_cab_2"], "efectos": {"categoria": "caballeria", "attack": 2}},
	{"id": "armadura_cab_1", "building": "herreria", "edad": "feudal", "coste": {"food": 150}, "tiempo_sec": 30, "requiere": [], "efectos": {"categoria": "caballeria", "armor_melee": 1, "armor_pierce": 1}},
	{"id": "armadura_cab_2", "building": "herreria", "edad": "castillos", "coste": {"food": 200, "gold": 100}, "tiempo_sec": 40, "requiere": ["armadura_cab_1"], "efectos": {"categoria": "caballeria", "armor_melee": 1, "armor_pierce": 1}},
	{"id": "armadura_cab_3", "building": "herreria", "edad": "imperial", "coste": {"food": 300, "gold": 150}, "tiempo_sec": 60, "requiere": ["armadura_cab_2"], "efectos": {"categoria": "caballeria", "armor_melee": 1, "armor_pierce": 2}},
	{"id": "balistica", "building": "universidad", "edad": "castillos", "coste": {"wood": 300, "gold": 175}, "tiempo_sec": 60, "requiere": [], "efectos": {"categoria": "arqueros", "balistica": true}},
	{"id": "quimica", "building": "universidad", "edad": "imperial", "coste": {"food": 300, "gold": 200}, "tiempo_sec": 60, "requiere": [], "efectos": {"categoria": "arqueros", "attack": 1, "bonus_vs_edificio": 2}},
	{"id": "redencion", "building": "monasterio", "edad": "castillos", "coste": {"gold": 475}, "tiempo_sec": 60, "requiere": [], "efectos": {"convierte_edificios": true}},
	{"id": "fervor", "building": "monasterio", "edad": "castillos", "coste": {"gold": 140}, "tiempo_sec": 40, "requiere": [], "efectos": {"velocidad_monje_bonus": 0.5}},
	{"id": "santidad", "building": "monasterio", "edad": "castillos", "coste": {"gold": 120}, "tiempo_sec": 40, "requiere": [], "efectos": {"hp_monje": 45}},
	{"id": "iluminacion", "building": "monasterio", "edad": "imperial", "coste": {"gold": 120}, "tiempo_sec": 40, "requiere": [], "efectos": {"recuperacion_fe_bonus": 0.5}},
	{"id": "teocracia", "building": "monasterio", "edad": "imperial", "coste": {"gold": 200}, "tiempo_sec": 40, "requiere": [], "efectos": {"teocracia": true}},
]

# tech_id -> {id, nombre, building, edad, coste:Dictionary, ticks:int, requiere:Array, efectos:Dictionary}
var techs_db := {}
# civ_id -> {tech_tree:Dictionary, unique_techs:Array, team_bonus:Dictionary}
var factions_db := {}
# pid int -> Array[String] techs completadas
var _completed := {}
# pid int -> {} o {tech_id, ticks_left, ticks_total, cost:Dictionary, building:String}
var _researching := {}


func _ready() -> void:
	_load_techs_db()
	_load_factions_db()
	if typeof(EventBus) != TYPE_NIL and EventBus != null:
		if not EventBus.command_issued.is_connected(_on_cmd):
			EventBus.command_issued.connect(_on_cmd)
		if not EventBus.tick_finished.is_connected(_on_tick):
			EventBus.tick_finished.connect(_on_tick)


# ------------------------------------------------------------------ datos ---

func _load_techs_db() -> void:
	techs_db.clear()
	for fname in ["herreria.json", "universidad.json", "monasterio.json"]:
		var path: String = TECHS_DIR + "/" + fname
		var building: String = fname.get_basename() # herreria / universidad / monasterio
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		building = str(parsed.get("building", building)).to_lower().strip_edges()
		for t in (parsed.get("techs", []) as Array):
			if typeof(t) != TYPE_DICTIONARY or not (t as Dictionary).has("id"):
				continue
			_register_tech(t, building)
	if techs_db.is_empty():
		for t in FALLBACK_TECHS:
			_register_tech(t, str(t.get("building", "herreria")))
	# Techs unicas de castillo (data/factions/*.json -> unique_techs).
	# Se registran DESPUES para no ser sobrescritas por el fallback.
	_register_unique_techs_fallback()


func _register_tech(t: Dictionary, default_building: String) -> void:
	var tid := str(t.get("id", "")).to_lower().strip_edges()
	if tid.is_empty() or techs_db.has(tid):
		return
	var req: Array = []
	for r in (t.get("requiere", t.get("requires", [])) as Array):
		req.append(str(r).to_lower().strip_edges())
	techs_db[tid] = {
		"id": tid,
		"nombre": str(t.get("nombre", t.get("name", tid))),
		"building": str(t.get("edificio", t.get("building", default_building))).to_lower().strip_edges(),
		"edad": str(t.get("edad", t.get("age", "feudal"))).to_lower().strip_edges(),
		"coste": (t.get("coste", t.get("cost", {})) as Dictionary).duplicate(true),
		"ticks": maxi(1, int(t.get("tiempo_sec", t.get("research_time_sec", 30))) * TICK_RATE),
		"requiere": req,
		"efectos": (t.get("efectos", t.get("effects", {})) as Dictionary).duplicate(true),
	}


func _register_unique_techs_fallback() -> void:
	# Respaldo por si data/factions no es legible: las 8 unicas con sus costes.
	var uniq := [
		{"id": "punteria", "building": "castillo", "edad": "castillos", "coste": {"wood": 750, "gold": 450}, "tiempo_sec": 60, "efectos": {"categoria": "arqueros", "alcance_arqueros": 2, "ataque_arqueros": 1, "ataque_torres": 2}},
		{"id": "maquina_guerra", "building": "castillo", "edad": "imperial", "coste": {"wood": 850, "gold": 750}, "tiempo_sec": 75, "efectos": {"ataque_trabuquete_bonus": 0.5}},
		{"id": "hachas_barbas", "building": "castillo", "edad": "castillos", "coste": {"food": 300, "gold": 300}, "tiempo_sec": 50, "efectos": {"alcance_hachero": 1, "ataque_hachero": 2}},
		{"id": "caballerosidad", "building": "castillo", "edad": "imperial", "coste": {"food": 400, "gold": 400}, "tiempo_sec": 60, "efectos": {"velocidad_establo": 0.4}},
		{"id": "anarquia", "building": "castillo", "edad": "castillos", "coste": {"food": 450, "gold": 250}, "tiempo_sec": 50, "efectos": {"huscarle_en_cuartel": true}},
		{"id": "perfusion", "building": "castillo", "edad": "imperial", "coste": {"food": 600, "gold": 400}, "tiempo_sec": 60, "efectos": {"velocidad_cuartel": 0.5}},
		{"id": "fuego_griego", "building": "castillo", "edad": "castillos", "coste": {"food": 400, "gold": 300}, "tiempo_sec": 50, "efectos": {"alcance_barcos_fuego": 1, "ataque_barcos_fuego": 2}},
		{"id": "logistica", "building": "castillo", "edad": "imperial", "coste": {"food": 1000, "gold": 600}, "tiempo_sec": 70, "efectos": {"pisoteo_catafracta": 5}},
	]
	for t in uniq:
		_register_tech(t, "castillo")


func _load_factions_db() -> void:
	factions_db.clear()
	var dir := DirAccess.open(FACTIONS_DIR)
	if dir == null:
		return
	var files: Array = []
	for _f in dir.get_files():
		files.append(_f)
	files.sort()
	for fname in files:
		if not str(fname).ends_with(".json"):
			continue
		var f := FileAccess.open(FACTIONS_DIR + "/" + str(fname), FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("id"):
			continue
		var civ := str(parsed["id"]).to_lower().strip_edges()
		factions_db[civ] = {
			"tech_tree": (parsed.get("tech_tree", {}) as Dictionary).duplicate(true),
			"unique_techs": (parsed.get("unique_techs", []) as Array).duplicate(true),
			"team_bonus": (parsed.get("team_bonus", {}) as Dictionary).duplicate(true),
		}
		# Registrar las unicas de ESTA civ (sobrescriben el fallback si difieren).
		for t in (parsed.get("unique_techs", []) as Array):
			if typeof(t) == TYPE_DICTIONARY and (t as Dictionary).has("id"):
				var tid := str((t as Dictionary)["id"]).to_lower().strip_edges()
				if not techs_db.has(tid):
					var cost: Dictionary = ((t as Dictionary).get("coste", (t as Dictionary).get("cost", {})) as Dictionary).duplicate(true)
					techs_db[tid] = {
						"id": tid,
						"nombre": str((t as Dictionary).get("nombre", tid)),
						"building": str((t as Dictionary).get("edificio", "castillo")).to_lower().strip_edges(),
						"edad": str((t as Dictionary).get("edad", "castillos")).to_lower().strip_edges(),
						"coste": cost,
						"ticks": maxi(1, int((t as Dictionary).get("tiempo_sec", 60)) * TICK_RATE),
						"requiere": [],
						"efectos": ((t as Dictionary).get("efectos", {}) as Dictionary).duplicate(true),
						"civ": civ, # marca de origen: solo esta civ puede investigarla
					}


func get_tech_data(tech_id: String) -> Dictionary:
	return (techs_db.get(tech_id.to_lower().strip_edges(), {}) as Dictionary).duplicate(true)


func get_time_ticks(tech_id: String) -> int:
	var d: Dictionary = techs_db.get(tech_id.to_lower().strip_edges(), {})
	return maxi(1, int(d.get("ticks", 30 * TICK_RATE)))


# --------------------------------------------------------------- consulta ---

func is_completed(pid: int, tech_id: String) -> bool:
	var arr: Array = _completed.get(pid, [])
	return arr.has(tech_id.to_lower().strip_edges())


func get_completed(pid: int) -> Array:
	return (_completed.get(pid, []) as Array).duplicate()


func is_researching(pid: int) -> bool:
	return _researching.has(pid) and not (_researching[pid] as Dictionary).is_empty()


func get_progress(pid: int) -> Dictionary:
	if not is_researching(pid):
		return {}
	return (_researching[pid] as Dictionary).duplicate(true)


func clear() -> void:
	_completed.clear()
	_researching.clear()


func _civ_of(pid: int) -> String:
	if typeof(GameManager) != TYPE_NIL and GameManager != null and GameManager.has_method("get_player"):
		var p: Dictionary = GameManager.get_player(pid)
		return str(p.get("civ", "")).to_lower().strip_edges()
	return ""


func _age_of(pid: int) -> String:
	if typeof(GameManager) != TYPE_NIL and GameManager != null and GameManager.has_method("get_player"):
		var p: Dictionary = GameManager.get_player(pid)
		return str(p.get("age", "alta_edad_media")).to_lower().strip_edges()
	return "alta_edad_media"


func _age_reached(current: String, required: String) -> bool:
	var ci := AGE_ORDER.find(current.to_lower().strip_edges())
	var ri := AGE_ORDER.find(required.to_lower().strip_edges())
	if ri < 0:
		return true # edad desconocida -> permisivo
	if ci < 0:
		return false
	return ci >= ri


func _is_available_for_civ(tech_id: String, civ: String) -> bool:
	var tid := tech_id.to_lower().strip_edges()
	if civ.is_empty() or not factions_db.has(civ):
		return true # civ desconocida o sin DB -> permisivo (modding/tests)
	var tree: Dictionary = factions_db[civ].get("tech_tree", {})
	# Tech unica con marca "civ": solo su civ.
	var d: Dictionary = techs_db.get(tid, {})
	if d.has("civ") and str(d["civ"]) != civ:
		return false
	# Buscar el id en cualquier seccion del tech_tree: false explicito = vetado.
	for section in tree.keys():
		var sec = tree[section]
		if typeof(sec) == TYPE_DICTIONARY and (sec as Dictionary).has(tid):
			return bool((sec as Dictionary)[tid])
	# Resumen de vetadas (compatibilidad con edicion manual).
	var deny: Array = tree.get("no_disponible_resumen", [])
	if deny.has(tid):
		return false
	return true


func can_research(pid: int, tech_id: String) -> Dictionary:
	var tid := tech_id.to_lower().strip_edges()
	if not techs_db.has(tid):
		return {"ok": false, "reason": "unknown_tech"}
	if is_completed(pid, tid):
		return {"ok": false, "reason": "already_completed"}
	if is_researching(pid):
		return {"ok": false, "reason": "already_researching"}
	var d: Dictionary = techs_db[tid]
	var civ := _civ_of(pid)
	if not _is_available_for_civ(tid, civ):
		return {"ok": false, "reason": "civ_disabled"}
	if not _age_reached(_age_of(pid), str(d.get("edad", "feudal"))):
		return {"ok": false, "reason": "need_age:" + str(d.get("edad", ""))}
	for r in (d.get("requiere", []) as Array):
		if not is_completed(pid, str(r)):
			return {"ok": false, "reason": "missing_prereq:" + str(r)}
	# Edificio requerido: solo se exige si GameManager lleva registro de
	# edificios (partida real). Con lista vacia (tests unitarios) se omite.
	var need_building := str(d.get("building", ""))
	if not need_building.is_empty() and typeof(GameManager) != TYPE_NIL and GameManager != null:
		if GameManager.has_method("get_player"):
			var p: Dictionary = GameManager.get_player(pid)
			var owned: Array = p.get("buildings", [])
			if not owned.is_empty() and not owned.has(need_building):
				return {"ok": false, "reason": "missing_building:" + need_building}
	if typeof(GameManager) != TYPE_NIL and GameManager != null and GameManager.has_method("has_resources"):
		if not GameManager.has_resources(pid, (d.get("coste", {}) as Dictionary)):
			return {"ok": false, "reason": "no_resources"}
	return {"ok": true, "reason": "ok", "cost": (d.get("coste", {}) as Dictionary).duplicate(true), "ticks": int(d.get("ticks", 0))}


# --------------------------------------------------------------- comandos ---

func _on_cmd(cmd: Dictionary) -> void:
	if typeof(cmd) != TYPE_DICTIONARY:
		return
	var t := str(cmd.get("type", ""))
	if t != "research_tech" and t != "cancel_research_tech":
		return
	var pid := int(cmd.get("player_id", -1))
	var payload: Dictionary = cmd.get("payload", {})
	if t == "research_tech":
		var tid := str(payload.get("tech_id", payload.get("tech", payload.get("id", ""))))
		if not tid.is_empty():
			research(pid, tid)
	else:
		cancel_research(pid)


## Inicia la investigacion (cobra coste, arranca timer por ticks). Como edades.
func research(pid: int, tech_id: String) -> bool:
	var tid := tech_id.to_lower().strip_edges()
	var chk := can_research(pid, tid)
	if not bool(chk.get("ok", false)):
		return false
	var cost: Dictionary = (chk.get("cost", {}) as Dictionary).duplicate(true)
	if typeof(GameManager) != TYPE_NIL and GameManager != null and GameManager.has_method("try_spend"):
		if not GameManager.try_spend(pid, cost):
			return false
	var total := maxi(1, int(chk.get("ticks", 30 * TICK_RATE)))
	_researching[pid] = {
		"tech_id": tid, "ticks_left": total, "ticks_total": total,
		"cost": cost, "building": str((techs_db[tid] as Dictionary).get("building", "")),
	}
	if not _completed.has(pid):
		_completed[pid] = []
	_emit_guarded("tech_progress", [pid, tid, total, total])
	return true


## Cancela la investigacion en curso, reembolso 50%. Como cancel_age_up.
func cancel_research(pid: int) -> bool:
	if not is_researching(pid):
		return false
	var r: Dictionary = _researching[pid]
	_researching[pid] = {}
	if typeof(GameManager) != TYPE_NIL and GameManager != null and GameManager.has_method("refund_cancel"):
		GameManager.refund_cancel(pid, (r.get("cost", {}) as Dictionary))
	_emit_guarded("tech_cancelled", [pid, str(r.get("tech_id", ""))])
	return true


## Trucos/tests: completa inmediatamente sin coste ni tiempo.
func force_complete(pid: int, tech_id: String) -> void:
	var tid := tech_id.to_lower().strip_edges()
	if not techs_db.has(tid):
		return
	if not _completed.has(pid):
		_completed[pid] = []
	if not (_completed[pid] as Array).has(tid):
		(_completed[pid] as Array).append(tid)
	_researching[pid] = {}
	_emit_guarded("tech_researched", [pid, tid])


# ------------------------------------------------------------------ tick ---

func _on_tick(t: int) -> void:
	tick(t)


## Avanza 1 tick: descuenta el frontal de cada jugador. Orden por pid.
func tick(_t: int) -> void:
	var pids: Array = _researching.keys()
	pids.sort()
	for pid in pids:
		var r: Dictionary = _researching[pid]
		if r.is_empty():
			continue
		r["ticks_left"] = int(r["ticks_left"]) - 1
		_emit_guarded("tech_progress", [int(pid), str(r["tech_id"]), int(r["ticks_left"]), int(r["ticks_total"])])
		if int(r["ticks_left"]) <= 0:
			_complete(int(pid), str(r["tech_id"]))


func _complete(pid: int, tech_id: String) -> void:
	_researching[pid] = {}
	if not _completed.has(pid):
		_completed[pid] = []
	if not (_completed[pid] as Array).has(tech_id):
		(_completed[pid] as Array).append(tech_id)
	_emit_guarded("tech_researched", [pid, tech_id])


# -------------------------------------------------- efectos acumulados ---

func _sum_categoria(pid: int, categoria: String, campo: String) -> int:
	var total := 0
	for tid in (_completed.get(pid, []) as Array):
		var d: Dictionary = techs_db.get(str(tid), {})
		var fx: Dictionary = d.get("efectos", {})
		var cat := str(fx.get("categoria", ""))
		if cat == categoria or (campo in ["ataque_torres", "alcance_torres"] and cat == "arqueros"):
			total += int(fx.get(campo, 0))
		# "quimica" y "punteria_universidad" usan categoria arqueros: ya sumadas.
		# Tech unica britona "punteria": campos ataque_arqueros/alcance_arqueros.
		if categoria == "arqueros":
			if campo == "attack":
				total += int(fx.get("ataque_arqueros", 0))
			if campo == "range":
				total += int(fx.get("alcance_arqueros", 0))
	return total


## +N ataque para una categoria (infanteria/arqueros/caballeria). Para Combat.
func get_bonus_ataque(pid: int, categoria: String) -> int:
	return _sum_categoria(pid, categoria.to_lower().strip_edges(), "attack")


## +N armadura cuerpo a cuerpo. Para Combat.
func get_bonus_armadura_melee(pid: int, categoria: String) -> int:
	return _sum_categoria(pid, categoria.to_lower().strip_edges(), "armor_melee")


## +N armadura antiproyectil. Para Combat.
func get_bonus_armadura_pierce(pid: int, categoria: String) -> int:
	return _sum_categoria(pid, categoria.to_lower().strip_edges(), "armor_pierce")


## +N alcance (arqueros; brasa +1, punteria +2). Para Combat ranged.
func get_bonus_alcance(pid: int, categoria: String) -> int:
	return _sum_categoria(pid, categoria.to_lower().strip_edges(), "range")


## Bonus vs edificios de "quimica" (+2). Para Combat.calc_damage.
func get_bonus_vs_edificio(pid: int) -> int:
	var total := 0
	for tid in (_completed.get(pid, []) as Array):
		var fx: Dictionary = (techs_db.get(str(tid), {}) as Dictionary).get("efectos", {})
		total += int(fx.get("bonus_vs_edificio", 0))
	return total


## true si Balistica completada (anula dispersion vs moviles). Para Combat.
func has_balistica(pid: int) -> bool:
	return is_completed(pid, "balistica")


## Bono de velocidad de produccion 0.0-0.9 para cuartel/arqueria/establo/castillo.
## Suma team bonus de la civ + perfusion/caballerosidad + galerias britonas.
func get_velocidad_produccion(pid: int, edificio: String) -> float:
	var b := edificio.to_lower().strip_edges()
	var total := 0.0
	# Team bonus propio + unicas completadas.
	var civ := _civ_of(pid)
	if not civ.is_empty() and factions_db.has(civ):
		var tb: Dictionary = factions_db[civ].get("team_bonus", {})
		var fx: Dictionary = tb.get("efecto", {})
		if b == "cuartel":
			total += float(fx.get("velocidad_cuartel", 0.0))
		if b == "arqueria":
			total += float(fx.get("velocidad_arqueria", 0.0))
		if b == "establo":
			total += float(fx.get("velocidad_establo", 0.0))
	for tid in (_completed.get(pid, []) as Array):
		var efx: Dictionary = (techs_db.get(str(tid), {}) as Dictionary).get("efectos", {})
		if b == "cuartel":
			total += float(efx.get("velocidad_cuartel", 0.0))
		if b == "establo":
			total += float(efx.get("velocidad_establo", 0.0))
	return clampf(total, 0.0, 0.9)


## Bonus de monje agregados (fervor/santidad/iluminacion/teocracia/herejia/
## redencion/curacion + bono civ bizantino). Para MonkAI.
func get_bono_monje(pid: int) -> Dictionary:
	var out := {"velocidad_bonus": 0.0, "hp_extra": 0, "fe_bonus": 0.0,
		"teocracia": false, "herejia": false, "convierte_edificios": false,
		"curacion_extra_hp_s": 0.0}
	for tid in (_completed.get(pid, []) as Array):
		var fx: Dictionary = (techs_db.get(str(tid), {}) as Dictionary).get("efectos", {})
		out["velocidad_bonus"] = float(out["velocidad_bonus"]) + float(fx.get("velocidad_monje_bonus", 0.0))
		out["hp_extra"] = int(out["hp_extra"]) + int(fx.get("hp_monje", 0))
		out["fe_bonus"] = float(out["fe_bonus"]) + float(fx.get("recuperacion_fe_bonus", 0.0))
		if bool(fx.get("teocracia", false)):
			out["teocracia"] = true
		if bool(fx.get("herejia", false)):
			out["herejia"] = true
		if bool(fx.get("convierte_edificios", false)):
			out["convierte_edificios"] = true
		out["curacion_extra_hp_s"] = float(out["curacion_extra_hp_s"]) + float(fx.get("curacion_bonus_hp_s", 0.0))
	return out


func _emit_guarded(sig_name: String, args: Array) -> void:
	if typeof(EventBus) != TYPE_NIL and EventBus != null and EventBus.has_signal(sig_name):
		EventBus.callv("emit_signal", [sig_name] + args)


# ----------------------------------------------------------------- hash ---

## Cadena canonica del estado (para hash anti-desync en NetManager).
func sim_state_string() -> String:
	var parts: Array = []
	var pids: Array = []
	for pid in _completed.keys():
		if not pids.has(pid):
			pids.append(pid)
	for pid in _researching.keys():
		if not pids.has(pid):
			pids.append(pid)
	pids.sort()
	for pid in pids:
		var done: Array = (_completed.get(pid, []) as Array).duplicate()
		done.sort()
		var r: Dictionary = _researching.get(pid, {})
		var cur := "-"
		if not r.is_empty():
			cur = "%s:%d" % [str(r.get("tech_id", "")), int(r.get("ticks_left", 0))]
		parts.append("p%d:[%s]:%s" % [int(pid), ",".join(done), cur])
	return ";".join(parts)


func sim_hash() -> int:
	if typeof(SimAPI) != TYPE_NIL and SimAPI != null and SimAPI.has_method("sim_hash"):
		return int(SimAPI.sim_hash(sim_state_string()))
	return int(hash(sim_state_string()))
