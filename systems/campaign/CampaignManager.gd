extends Node
# CampaignManager - sistema de campaña OpenAge-LAN (Godot 4.4, determinista).
#
# Responsabilidades:
#   - Cargar data/campaigns/*.json (catálogo ordenado por "order").
#   - Objetivos SECUENCIALES: solo el objetivo actual (obj_index) progresa;
#     al completarse avanza al siguiente; al completar todos -> victoria.
#   - Diálogos intro / victoria / derrota (señal dialogue + EventBus.chat_msg).
#   - Victoria / derrota por triggers evaluados en _on_tick (lockstep 10 Hz).
#   - Oleadas temporizadas (escenario 02) y bot económico simple (trickle por
#     ticks + señal wave_spawned para que producción/combate genere unidades).
#   - Desbloqueo del siguiente escenario por "order" y guardado de progreso
#     en user://campaign_save.json.
#
# Determinismo (lockstep 10 Hz, igual que GameManager/SimAPI):
#   - PROHIBIDO randf/randi/Time/OS en este archivo.
#   - Todo tiempo se mide en ticks (TICK_RATE = 10). NADA de SceneTreeTimer.
#   - Bot y oleadas: iteración ordenada, cantidades fijas por dificultad,
#     periodos fijos en ticks. Mismos ticks -> mismos comandos.
#   - Arranque vía GameManager.setup_lobby(slots) + SimAPI.reset().
#
# Esquema data/campaigns/*.json:
# {
#   "id": "01_sangre_norte", "order": 1, "name": "...", "campaign": "...",
#   "briefing": "texto largo para el menú",
#   "map": "arabia", "map_seed": 1234,
#   "starting_age": "feudal", "starting_res": {"wood": 200, ...},
#   "time_limit_min": 15,           # 0 = sin límite
#   "players": [                     # orden = player_id en GameManager
#     {"civ": "vikingos", "team": 0, "is_player": true, "base": [20, 20]},
#     {"civ": "britones", "team": 1, "is_player": false, "base": [120, 120]}
#   ],
#   "bots": [{"player_id": 1, "difficulty": "facil", "stance": "defensivo"}],
#   "objectives": [                  # SECUENCIALES, en orden de lista
#     {"id": "x", "text": "...", "type": "destroy_building",
#      "building": "cuartel", "owner": 1, "count": 1},
#     {"id": "y", "text": "...", "type": "survive_min", "minutes": 20},
#     {"id": "z", "text": "...", "type": "collect_relic", "count": 3},
#     {"id": "w", "text": "...", "type": "build_building",
#      "building": "maravilla", "owner": 0, "count": 1},
#     {"id": "v", "text": "...", "type": "eliminate_player", "target": 1}
#   ],
#   "defeat": [                      # cualquiera dispara la derrota
#     {"id": "d1", "text": "...", "type": "lose_building",
#      "building": "centro_urbano", "owner": 0}
#   ],
#   "waves": {"interval_min": 4, "count": 5, "first_min": 3,
#             "warning": "¡Se acercan por el fiordo!"},
#   "dialogues": {
#     "intro": [{"speaker": "...", "text": "..."}],
#     "victory": [...], "defeat": [...]
#   },
#   "rewards": {"unlocks": "02_el_fiordo"}
# }
#
# Tipos de trigger de victoria (objectives): destroy_building, survive_min,
# survive_ticks, collect_relic, build_building, eliminate_player.
# Tipos de trigger de derrota (defeat): lose_building, eliminate_player,
# timeout (implícito por time_limit_min, no hace falta declararlo).
#
# Integración con el resto de la sim (los sistemas avisan aquí):
#   report_building_destroyed(owner_pid, building_id)  <- construction/combat
#   report_building_completed(owner_pid, building_id)  <- construction
#   report_relic_secured(player_id, total)              <- MonkAI / monasterio
# Además se escucha EventBus.relic_delivered si existe, y el estado
# vivo/muerto de GameManager (is_alive) como red de seguridad.
# Señal wave_spawned(scenario_id, wave_n, total): producción/combate debe
# generar las unidades de la oleada; CampaignManager solo da el pulso + oro
# al bot para que sea determinista.

signal campaign_started(scenario_id: String)
signal objective_completed(scenario_id: String, objective_id: String, index: int)
signal dialogue(speaker: String, text: String, phase: String)
signal wave_spawned(scenario_id: String, wave_n: int, total: int)
signal campaign_won(scenario_id: String, ticks_used: int)
signal campaign_lost(scenario_id: String, reason: String)
signal progress_saved

const TICK_RATE := 10 # debe coincidir con SimAPI.TICK_RATE / GameManager
const CAMPAIGN_DIR := "res://data/campaigns"
const SAVE_PATH := "user://campaign_save.json"
const SAVE_VERSION := 1

# Bot económico simple: cada BOT_PERIOD ticks el bot recibe recursos fijos
# según dificultad (determinista, sin RNG).
const BOT_PERIOD := 50 # 5 s
const BOT_TRICKLE := {
	"facil": {"wood": 25.0, "food": 25.0, "gold": 0.0, "stone": 0.0},
	"normal": {"wood": 40.0, "food": 40.0, "gold": 20.0, "stone": 10.0},
	"dificil": {"wood": 60.0, "food": 60.0, "gold": 40.0, "stone": 20.0},
}
# Bonus de oleada al bot (para que la presión sea real).
const WAVE_BONUS := {"wood": 100.0, "food": 100.0, "gold": 50.0, "stone": 0.0}

var catalog: Array = [] # Array[Dictionary] metadatos ordenados por order
var progress: Dictionary = {} # sid -> {"completed": bool, "best_ticks": int}
var last_played := ""

# Estado de la partida activa (vacío = sin escenario en curso).
var active: Dictionary = {}
var running := false
var won := false
var lost := false
var lose_reason := ""
var elapsed_ticks := 0
var obj_index := 0
var _obj_state: Array = [] # Array[Dictionary] {completed, progress, needed}
var _relics_secured := 0 # reliquias del jugador (vía report_relic_secured)
var _waves_done := 0
var _bots: Array = [] # Array[Dictionary] {player_id, difficulty, stance}
var _player_pid := 0


func _ready() -> void:
	_load_progress()
	_load_catalog()
	if not EventBus.tick_finished.is_connected(_on_tick):
		EventBus.tick_finished.connect(_on_tick)
	if EventBus.has_signal("relic_delivered"):
		var cb := Callable(self, "_on_relic_delivered")
		if not EventBus.is_connected("relic_delivered", cb):
			EventBus.connect("relic_delivered", cb)


# ------------------------------------------------------------- catálogo ---

func _load_catalog() -> void:
	catalog.clear()
	var dir := DirAccess.open(CAMPAIGN_DIR)
	if dir == null:
		push_warning("CampaignManager: no se pudo abrir " + CAMPAIGN_DIR)
		return
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".json"):
			files.append(f)
	files.sort() # nombre de archivo = orden (01_, 02_, ...) determinista
	for f in files:
		var sc := _load_scenario_file(str(f).get_basename())
		if sc.is_empty():
			continue
		catalog.append({
			"id": str(sc.get("id", str(f).get_basename())),
			"order": int(sc.get("order", 999)),
			"name": str(sc.get("name", sc.get("id", "?"))),
			"campaign": str(sc.get("campaign", "")),
			"briefing": str(sc.get("briefing", "")),
			"file": str(f).get_basename(),
		})
	catalog.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["order"]) != int(b["order"]):
			return int(a["order"]) < int(b["order"])
		return str(a["id"]) < str(b["id"]))


func _load_scenario_file(sid: String) -> Dictionary:
	var path := CAMPAIGN_DIR + "/" + sid + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CampaignManager: no se pudo leer " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CampaignManager: JSON corrupto en " + path)
		return {}
	return parsed


## Lista para el menú: [{id, order, name, campaign, briefing, unlocked,
## completed, best_ticks, best_min}]. Ordenada por order. Determinista.
func list_campaigns() -> Array:
	if catalog.is_empty():
		_load_catalog()
	var out: Array = []
	for entry in catalog:
		var sid := str(entry["id"])
		var p: Dictionary = progress.get(sid, {})
		var best := int(p.get("best_ticks", 0))
		var e: Dictionary = (entry as Dictionary).duplicate(true)
		e["unlocked"] = is_unlocked(sid)
		e["completed"] = bool(p.get("completed", false))
		e["best_ticks"] = best
		e["best_min"] = snappedf(float(best) / float(TICK_RATE * 60), 0.1)
		out.append(e)
	return out


func get_scenario(sid: String) -> Dictionary:
	return _load_scenario_file(sid)


func is_unlocked(sid: String) -> bool:
	if catalog.is_empty():
		_load_catalog()
	var idx := -1
	for i in catalog.size():
		if str(catalog[i]["id"]) == sid:
			idx = i
			break
	if idx < 0:
		return false
	if idx == 0:
		return true # el primer escenario siempre está abierto
	var prev := str(catalog[idx - 1]["id"])
	return bool((progress.get(prev, {}) as Dictionary).get("completed", false))


func is_completed(sid: String) -> bool:
	return bool((progress.get(sid, {}) as Dictionary).get("completed", false))


func get_best_ticks(sid: String) -> int:
	return int((progress.get(sid, {}) as Dictionary).get("best_ticks", 0))


# --------------------------------------------------------------- arranque ---

## Carga el escenario y arranca la partida vía GameManager.setup_lobby().
## Devuelve false si el id no existe o está bloqueado.
func start_scenario(sid: String) -> bool:
	if not is_unlocked(sid):
		push_warning("CampaignManager.start_scenario: escenario bloqueado: " + sid)
		return false
	var sc := _load_scenario_file(sid)
	if sc.is_empty():
		push_error("CampaignManager.start_scenario: escenario desconocido: " + sid)
		return false
	var players_cfg: Array = (sc.get("players", []) as Array).duplicate(true)
	if players_cfg.is_empty():
		push_error("CampaignManager.start_scenario: sin players en " + sid)
		return false
	# Estado fresco y determinista.
	stop_scenario()
	active = sc
	running = true
	won = false
	lost = false
	lose_reason = ""
	elapsed_ticks = 0
	obj_index = 0
	_obj_state.clear()
	_relics_secured = 0
	_waves_done = 0
	_bots = (sc.get("bots", []) as Array).duplicate(true)
	_player_pid = 0
	for i in players_cfg.size():
		var p: Dictionary = players_cfg[i]
		if bool(p.get("is_player", i == 0)):
			_player_pid = i
			break
	# Slots para GameManager (el índice = player_id, en orden).
	var slots: Array = []
	for p in players_cfg:
		var d: Dictionary = p
		slots.append({"civ": str(d.get("civ", "britones")),
			"team": int(d.get("team", 0))})
	GameManager.map_seed = int(sc.get("map_seed", 1234))
	SimAPI.reset()
	GameManager.setup_lobby(slots)
	# Overrides del escenario (recursos/edad iniciales).
	var sres: Dictionary = sc.get("starting_res", {})
	if not sres.is_empty():
		for k in sres.keys():
			var cur := float(GameManager.players[_player_pid]["res"].get(k, 0.0))
			GameManager.players[_player_pid]["res"][k] = cur + float(sres[k]) - float(GameManager.STARTING_RES.get(k, 0.0))
		GameManager._notify_resources(_player_pid)
	var sage := str(sc.get("starting_age", ""))
	if not sage.is_empty() and sage != GameManager.STARTING_AGE:
		GameManager.players[_player_pid]["age"] = sage
	# Estado runtime de objetivos secuenciales.
	for o in (sc.get("objectives", []) as Array):
		_obj_state.append({"completed": false, "progress": 0,
			"needed": _needed_for(o)})
	last_played = sid
	_save_progress()
	_emit_dialogues("intro")
	campaign_started.emit(sid)
	return true


func stop_scenario() -> void:
	active = {}
	running = false
	won = false
	lost = false
	lose_reason = ""
	elapsed_ticks = 0
	obj_index = 0
	_obj_state.clear()
	_relics_secured = 0
	_waves_done = 0
	_bots.clear()


func is_running() -> bool:
	return running and not active.is_empty()


func get_active_id() -> String:
	return str(active.get("id", ""))


func get_player_pid() -> int:
	return _player_pid


# -------------------------------------------------------------- objetivos ---

func _needed_for(obj: Dictionary) -> int:
	match str(obj.get("type", "")):
		"destroy_building", "build_building":
			return maxi(1, int(obj.get("count", 1)))
		"collect_relic":
			return maxi(1, int(obj.get("count", 1)))
		"survive_min":
			return maxi(1, int(float(obj.get("minutes", 1.0)) * 60.0 * TICK_RATE))
		"survive_ticks":
			return maxi(1, int(obj.get("ticks", 1)))
		"eliminate_player":
			return 1
	return 1


## Objetivo actual (secuencial) o {} si no hay partida / ya terminó.
func get_current_objective() -> Dictionary:
	if not is_running():
		return {}
	var objs: Array = active.get("objectives", [])
	if obj_index < 0 or obj_index >= objs.size():
		return {}
	var o: Dictionary = (objs[obj_index] as Dictionary).duplicate(true)
	var st: Dictionary = _obj_state[obj_index] if obj_index < _obj_state.size() else {}
	o["progress"] = int(st.get("progress", 0))
	o["needed"] = int(st.get("needed", 0))
	o["index"] = obj_index
	o["total"] = objs.size()
	return o


## Todos los objetivos con su estado (para HUD de campaña).
func get_objectives_state() -> Array:
	var out: Array = []
	if active.is_empty():
		return out
	var objs: Array = active.get("objectives", [])
	for i in objs.size():
		var o: Dictionary = (objs[i] as Dictionary).duplicate(true)
		var st: Dictionary = _obj_state[i] if i < _obj_state.size() else {}
		o["progress"] = int(st.get("progress", 0))
		o["needed"] = int(st.get("needed", 0))
		o["done"] = bool(st.get("completed", false))
		o["current"] = running and not won and not lost and i == obj_index
		out.append(o)
	return out


func get_elapsed_ticks() -> int:
	return elapsed_ticks


func get_elapsed_min() -> float:
	return float(elapsed_ticks) / float(TICK_RATE * 60)


func get_time_left_ticks() -> int:
	var lim := int(float(active.get("time_limit_min", 0.0)) * 60.0 * TICK_RATE)
	if lim <= 0:
		return -1 # sin límite
	return maxi(0, lim - elapsed_ticks)


# ------------------------------------------------- reportes desde la sim ---

## Llamar al destruir un edificio (construction/combat). Solo cuenta si hay
## partida en curso; el avance es secuencial sobre el objetivo actual.
func report_building_destroyed(owner_pid: int, building_id: String) -> void:
	if not is_running() or won or lost:
		return
	var cur := get_current_objective()
	if cur.is_empty() or str(cur.get("type", "")) != "destroy_building":
		return
	if int(cur.get("owner", -1)) != owner_pid:
		return
	if str(cur.get("building", "")).to_lower() != building_id.to_lower():
		return
	_bump_current(1)


## Llamar al completar una construcción (construction). Vale para maravilla
## y cualquier objetivo build_building.
func report_building_completed(owner_pid: int, building_id: String) -> void:
	if not is_running() or won or lost:
		return
	var cur := get_current_objective()
	if cur.is_empty() or str(cur.get("type", "")) != "build_building":
		return
	if int(cur.get("owner", _player_pid)) != owner_pid:
		return
	if str(cur.get("building", "")).to_lower() != building_id.to_lower():
		return
	_bump_current(1)


## Llamar al entregar una reliquia (MonkAI / monasterio). `total` = reliquias
## del jugador tras la entrega. Si total <= 0 se suma +1 al contador.
func report_relic_secured(player_id: int, total: int = 0) -> void:
	if not is_running() or won or lost:
		return
	if player_id != _player_pid:
		return
	if total > 0:
		_relics_secured = maxi(_relics_secured, total)
	else:
		_relics_secured += 1
	var cur := get_current_objective()
	if cur.is_empty() or str(cur.get("type", "")) != "collect_relic":
		return
	_set_current_progress(_relics_secured)


func _on_relic_delivered(_relic_id: int, player_id: int, _monk_id: int) -> void:
	report_relic_secured(player_id, 0)


func _bump_current(amount: int) -> void:
	if obj_index < 0 or obj_index >= _obj_state.size():
		return
	var st: Dictionary = _obj_state[obj_index]
	st["progress"] = int(st.get("progress", 0)) + maxi(0, amount)
	_set_current_progress(int(st["progress"]))


func _set_current_progress(value: int) -> void:
	if obj_index < 0 or obj_index >= _obj_state.size():
		return
	var st: Dictionary = _obj_state[obj_index]
	st["progress"] = value
	if value < int(st.get("needed", 1)):
		return
	_complete_current()


func _complete_current() -> void:
	var objs: Array = active.get("objectives", [])
	if obj_index < 0 or obj_index >= objs.size():
		return
	(_obj_state[obj_index] as Dictionary)["completed"] = true
	(_obj_state[obj_index] as Dictionary)["progress"] = int(
		(_obj_state[obj_index] as Dictionary).get("needed", 1))
	var oid := str((objs[obj_index] as Dictionary).get("id", "obj%d" % obj_index))
	objective_completed.emit(get_active_id(), oid, obj_index)
	obj_index += 1
	if obj_index >= objs.size():
		_win()


# ------------------------------------------------------------------- tick ---

func _on_tick(t: int) -> void:
	if not is_running() or won or lost:
		return
	elapsed_ticks += 1
	_tick_waves()
	_bot_tick()
	# Derrota primero (tiene prioridad sobre la victoria del mismo tick).
	var reason := _check_defeat()
	if not reason.is_empty():
		_lose(reason)
		return
	_check_passive_objectives()


## Objetivos que avanzan solos con el tiempo o el estado (survive_*,
## eliminate_player, destroy_building por eliminación del dueño).
func _check_passive_objectives() -> void:
	if won or lost:
		return
	var cur := get_current_objective()
	if cur.is_empty():
		return
	match str(cur.get("type", "")):
		"survive_min", "survive_ticks":
			_set_current_progress(elapsed_ticks)
		"eliminate_player":
			var target := int(cur.get("target", cur.get("owner", -1)))
			if target >= 0 and not GameManager.is_alive(target):
				_complete_current()
		"destroy_building":
			# Red de seguridad: dueño eliminado => sus edificios cayeron.
			var owner := int(cur.get("owner", -1))
			if owner >= 0 and owner < GameManager.players.size() \
					and not GameManager.is_alive(owner) and elapsed_ticks > 0:
				_complete_current()


## Condiciones de derrota. Devuelve "" si no hay derrota este tick.
func _check_defeat() -> String:
	# 1) Límite de tiempo (timeout implícito).
	var lim := int(float(active.get("time_limit_min", 0.0)) * 60.0 * TICK_RATE)
	if lim > 0 and elapsed_ticks >= lim and not _all_objectives_done():
		return "timeout"
	# 2) El jugador ha sido eliminado en GameManager (conquista).
	if not GameManager.is_alive(_player_pid):
		return "player_eliminated"
	# 3) Triggers de derrota del JSON.
	for d in (active.get("defeat", []) as Array):
		if typeof(d) != TYPE_DICTIONARY:
			continue
		match str(d.get("type", "")):
			"lose_building":
				# Sin censo de edificios en GameManager: el TC perdido se
				# detecta porque el jugador cae al quedarse sin nada
				# (caso 2). Si el dueño ya no está vivo, derrota.
				var owner := int(d.get("owner", _player_pid))
				if not GameManager.is_alive(owner):
					return str(d.get("id", "lose_building"))
			"eliminate_player":
				var target := int(d.get("target", d.get("owner", _player_pid)))
				if not GameManager.is_alive(target):
					return str(d.get("id", "eliminate_player"))
	return ""


func _all_objectives_done() -> bool:
	var objs: Array = active.get("objectives", [])
	return obj_index >= objs.size()


# ----------------------------------------------------------------- oleadas ---

func _tick_waves() -> void:
	var waves: Dictionary = active.get("waves", {})
	if waves.is_empty():
		return
	var total := int(waves.get("count", 0))
	if total <= 0 or _waves_done >= total:
		return
	var interval := int(float(waves.get("interval_min", 4.0)) * 60.0 * TICK_RATE)
	var first := int(float(waves.get("first_min", 3.0)) * 60.0 * TICK_RATE)
	if interval <= 0:
		return
	# Nº de oleadas que ya deberían haber salido (determinista por tick).
	var due := 0
	if elapsed_ticks >= first:
		due = 1 + (elapsed_ticks - first) / interval
	due = mini(due, total)
	while _waves_done < due:
		_spawn_wave(_waves_done + 1, total)


func _spawn_wave(n: int, total: int) -> void:
	_waves_done = n
	# Presión real: bonus de recursos a cada bot (orden de player_id).
	var ids: Array = _bot_player_ids()
	ids.sort()
	for pid in ids:
		if GameManager.is_alive(int(pid)):
			for k in WAVE_BONUS.keys():
				GameManager.add_resource(int(pid), k, float(WAVE_BONUS[k]))
	var warn := str((active.get("waves", {}) as Dictionary).get("warning",
		"¡Oleada %d de %d!" % [n, total]))
	_emit_line("Centinela", warn, "wave")
	wave_spawned.emit(get_active_id(), n, total)


# --------------------------------------------------------------- bot simple ---

func _bot_player_ids() -> Array:
	var out: Array = []
	for b in _bots:
		if typeof(b) == TYPE_DICTIONARY and (b as Dictionary).has("player_id"):
			out.append(int((b as Dictionary)["player_id"]))
	return out


## IA de campaña mínima y determinista: trickle de recursos por dificultad
## cada BOT_PERIOD ticks. La micro (aldeanos/milicia) la hacen VillagerAI /
## MilitaryAI con los comandos del escenario; las oleadas entran por
## wave_spawned para que producción/combate genere las unidades.
func _bot_tick() -> void:
	if elapsed_ticks % BOT_PERIOD != 0:
		return
	for b in _bots:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var pid := int((b as Dictionary).get("player_id", -1))
		if pid < 0 or pid >= GameManager.players.size():
			continue
		if not GameManager.is_alive(pid):
			continue
		var trickle: Dictionary = BOT_TRICKLE.get(
			str((b as Dictionary).get("difficulty", "facil")),
			BOT_TRICKLE["facil"])
		for k in trickle.keys():
			var amt := float(trickle[k])
			if amt > 0.0:
				GameManager.add_resource(pid, k, amt)


# ------------------------------------------------------- victoria/derrota ---

func _win() -> void:
	if won or lost or not is_running():
		return
	won = true
	running = false
	var sid := get_active_id()
	var prev_best := get_best_ticks(sid)
	if prev_best <= 0 or elapsed_ticks < prev_best:
		_set_progress(sid, true, elapsed_ticks)
	else:
		_set_progress(sid, true, prev_best)
	_save_progress()
	_emit_dialogues("victory")
	campaign_won.emit(sid, elapsed_ticks)


func _lose(reason: String) -> void:
	if won or lost or not is_running():
		return
	lost = true
	running = false
	lose_reason = reason
	var sid := get_active_id()
	_emit_dialogues("defeat")
	campaign_lost.emit(sid, reason)


func get_lose_reason() -> String:
	return lose_reason


## Texto de briefing + objetivos + estado, listo para CampaignMenu/HUD.
func get_briefing_text(sid: String) -> String:
	var sc := _load_scenario_file(sid) if sid != get_active_id() else active
	if sc.is_empty():
		return "Escenario desconocido: " + sid
	var lines: Array = []
	lines.append(str(sc.get("briefing", "")))
	lines.append("")
	lines.append("Objetivos (en orden):")
	var i := 1
	for o in (sc.get("objectives", []) as Array):
		lines.append("  %d. %s" % [i, str((o as Dictionary).get("text", ""))])
		i += 1
	if not (sc.get("defeat", []) as Array).is_empty():
		lines.append("")
		lines.append("Derrota si:")
		for d in (sc.get("defeat", []) as Array):
			lines.append("  - %s" % str((d as Dictionary).get("text", "")))
	var lim := float(sc.get("time_limit_min", 0.0))
	if lim > 0.0:
		lines.append("")
		lines.append("Límite: %s min." % _fmt_min(lim))
	return "\n".join(lines)


static func _fmt_min(m: float) -> String:
	if m == floorf(m):
		return str(int(m))
	return str(snappedf(m, 0.1))


# --------------------------------------------------------------- diálogos ---

func _emit_dialogues(phase: String) -> void:
	if active.is_empty():
		return
	var dlg: Dictionary = active.get("dialogues", {})
	var lines: Array = dlg.get(phase, [])
	for l in lines:
		if typeof(l) != TYPE_DICTIONARY:
			continue
		_emit_line(str((l as Dictionary).get("speaker", "???")),
			str((l as Dictionary).get("text", "")), phase)


func _emit_line(speaker: String, text: String, phase: String) -> void:
	dialogue.emit(speaker, text, phase)
	if EventBus.has_signal("chat_msg"):
		EventBus.emit_signal("chat_msg", _player_pid,
			"[%s] %s" % [speaker, text])


## Diálogos de una fase sin emitir (para el menú / tests).
func get_dialogues(sid: String, phase: String) -> Array:
	var sc := _load_scenario_file(sid) if sid != get_active_id() else active
	if sc.is_empty():
		return []
	return ((sc.get("dialogues", {}) as Dictionary).get(phase, []) as Array).duplicate(true)


# --------------------------------------------------------------- guardado ---

func _set_progress(sid: String, completed: bool, best_ticks: int) -> void:
	var p: Dictionary = (progress.get(sid, {}) as Dictionary).duplicate(true)
	if completed:
		p["completed"] = true
	if best_ticks > 0 and (int(p.get("best_ticks", 0)) <= 0 \
			or best_ticks < int(p.get("best_ticks", 0))):
		p["best_ticks"] = best_ticks
	progress[sid] = p


func _save_progress() -> void:
	var data := {"version": SAVE_VERSION, "completed": progress,
		"last_played": last_played}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("CampaignManager: no se pudo escribir " + SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	progress_saved.emit()


func _load_progress() -> void:
	progress.clear()
	last_played = ""
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("CampaignManager: guardado corrupto, se ignora.")
		return
	last_played = str(parsed.get("last_played", ""))
	for k in (parsed.get("completed", {}) as Dictionary).keys():
		var v: Dictionary = (parsed.get("completed", {}) as Dictionary)[k]
		progress[str(k)] = {"completed": bool(v.get("completed", false)),
			"best_ticks": int(v.get("best_ticks", 0))}


## Borra el progreso (botón "Reiniciar campaña" del menú).
func reset_progress() -> void:
	progress.clear()
	last_played = ""
	_save_progress()
	_load_catalog()


## Cadena canónica del estado (debug; no entra en el hash anti-desync,
## que solo cubre GameManager/Economy).
func sim_state_string() -> String:
	var parts: Array = []
	parts.append("scenario:" + get_active_id())
	parts.append("tick:%d" % elapsed_ticks)
	parts.append("obj:%d" % obj_index)
	for i in _obj_state.size():
		var st: Dictionary = _obj_state[i]
		parts.append("o%d:%d/%d" % [i, int(st.get("progress", 0)),
			int(st.get("needed", 0))])
	parts.append("relics:%d" % _relics_secured)
	parts.append("waves:%d" % _waves_done)
	if won:
		parts.append("WON")
	if not lose_reason.is_empty():
		parts.append("LOST:" + lose_reason)
	return "|".join(parts)
