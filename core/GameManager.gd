extends Node
# GameManager - loop principal, economias, edades, poblacion y victoria.
# Determinista (lockstep 10 Hz): NADA de randf/randi/Time/SceneTreeTimer en logica.
# Todo tiempo de investigacion se mide en ticks via _on_tick() (TICK_RATE = 10).
# Todo cambio de estado relevante se notifica via EventBus.
#
# Estado por jugador:
# {id, civ, team, color, res:{wood,food,gold,stone}, pop, pop_cap, age,
#  alive, buildings:Array[String], census:{tc,villager,military},
#  research: {} o {target, ticks_left, ticks_total, cost}}

const MAX_PLAYERS := 8
const TICK_RATE := 10 # debe coincidir con SimAPI.TICK_RATE
const STARTING_RES := {"wood": 200.0, "food": 200.0, "gold": 100.0, "stone": 200.0}
const STARTING_POP := 3
const STARTING_POP_CAP := 5
const STARTING_AGE := "alta_edad_media"
const REFUND_FACTOR := 0.5 # reembolso del 50% al cancelar
const HOUSE_SUPPLY := 5 # cada casa da +5 pop_cap (estandar AoE2)
const MAX_POP_CAP := 200
const AGE_ORDER := ["alta_edad_media", "feudal", "castillos", "imperial"]

# Fallback si data/ages/ages.json no es legible. Debe coincidir con el JSON.
const FALLBACK_AGES := [
	{"id": "alta_edad_media", "name": "Alta Edad Media", "cost": {}, "requires": [], "research_time_sec": 0},
	{"id": "feudal", "name": "Feudal", "cost": {"food": 500}, "requires": [], "research_time_sec": 130},
	{"id": "castillos", "name": "Castillos", "cost": {"food": 800, "gold": 200}, "requires": ["herreria_o_mercado"], "research_time_sec": 160},
	{"id": "imperial", "name": "Imperial", "cost": {"food": 1000, "gold": 800}, "requires": ["castillo_o_monasterio"], "research_time_sec": 190},
]

var players: Array = [] # Array[Dictionary], ordenado por id (determinista)
var ages_db: Array = [] # Array[Dictionary] cargado de ages.json
var is_host := false
var map_seed := 1234
var game_over := false
var winner_team := -1 # -1 = sin decidir, -2 = empate (todos eliminados)

func _ready() -> void:
	_load_ages_db()
	_reset_to_default_2p()

# ------------------------------------------------------------------
# Datos de edades
# ------------------------------------------------------------------

func _load_ages_db() -> void:
	ages_db = []
	var path := "res://data/ages/ages.json"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("ages"):
				for a in parsed["ages"]:
					if typeof(a) == TYPE_DICTIONARY and a.has("id"):
						ages_db.append({
							"id": str(a["id"]),
							"name": str(a.get("name", a["id"])),
							"cost": (a.get("cost", {}) as Dictionary).duplicate(true),
							"requires": (a.get("requires", []) as Array).duplicate(true),
							"research_time_sec": int(a.get("research_time_sec", 0)),
						})
	if ages_db.is_empty():
		for a in FALLBACK_AGES:
			ages_db.append((a as Dictionary).duplicate(true))

func get_age_data(age_id: String) -> Dictionary:
	for a in ages_db:
		if str(a["id"]) == age_id:
			return a
	return {}

func get_age_index(age_id: String) -> int:
	return AGE_ORDER.find(age_id)

func get_next_age(current: String) -> String:
	var i := get_age_index(current)
	if i < 0 or i + 1 >= AGE_ORDER.size():
		return ""
	return AGE_ORDER[i + 1]

func get_age_cost(age_id: String) -> Dictionary:
	return (get_age_data(age_id).get("cost", {}) as Dictionary).duplicate(true)

func get_age_time_ticks(age_id: String) -> int:
	var secs := int(get_age_data(age_id).get("research_time_sec", 0))
	return maxi(0, secs * TICK_RATE)

# ------------------------------------------------------------------
# Setup de partida (8 jugadores)
# ------------------------------------------------------------------

func _make_player(pid: int, civ: String, team: int) -> Dictionary:
	return {
		"id": pid, "civ": civ, "team": team,
		"color": _color_hex_for(pid),
		"res": STARTING_RES.duplicate(true),
		"pop": STARTING_POP, "pop_cap": STARTING_POP_CAP, "age": STARTING_AGE,
		"alive": true,
		"buildings": [], # Array[String] ids en minusculas, para requisitos
		"census": {"tc": 1, "villager": STARTING_POP, "military": 0},
		"research": {}, # vacio = sin investigacion en curso
	}

func _color_hex_for(pid: int) -> String:
	# Replica SimAPI.PLAYER_COLORS sin depender del orden de autoloads.
	var cols := ["#2a4bff", "#ff0000", "#00ff00", "#ffff00", "#00c8ff", "#c800ff", "#969696", "#ff8c00"]
	return cols[pid % cols.size()]

func _reset_to_default_2p() -> void:
	setup_lobby([{"civ": "britones", "team": 0}, {"civ": "francos", "team": 1}])

func setup_lobby(slots: Array) -> void:
	# slots: [{civ, team}] de 1 a 8. Recursos iniciales AoE2:
	# madera 200, alimento 200, oro 100, piedra 200, pop 3/5.
	if slots.is_empty() or slots.size() > MAX_PLAYERS:
		push_error("GameManager.setup_lobby: slots debe ser 1..8, recibido %d" % slots.size())
		return
	players.clear()
	game_over = false
	winner_team = -1
	for i in slots.size():
		var s: Dictionary = slots[i] if typeof(slots[i]) == TYPE_DICTIONARY else {}
		players.append(_make_player(i, str(s.get("civ", "britones")), int(s.get("team", i))))
		_notify_resources(i)
		_notify_pop(i)
	_seed_rng()

func setup_match(slots: Array, seed: int = -1) -> void:
	# Alias explicito para partida 8p / tests. Si seed >= 0, lo adopta.
	if seed >= 0:
		map_seed = seed
	setup_lobby(slots)

func _seed_rng() -> void:
	# SimRNG cuelga de SimAPI (autoload previo a GameManager). Guardia por tests.
	if SimAPI != null and SimAPI.get("SimRNGNode") != null:
		SimAPI.SimRNGNode.set_seed(map_seed)

func get_player(pid: int) -> Dictionary:
	if not _is_valid_pid(pid):
		return {}
	return players[pid]

func _is_valid_pid(pid: int) -> bool:
	return pid >= 0 and pid < players.size()

func is_alive(pid: int) -> bool:
	return _is_valid_pid(pid) and bool(players[pid].get("alive", false))

func get_alive_players() -> Array:
	var out: Array = []
	for p in players:
		if bool(p.get("alive", false)):
			out.append(int(p["id"]))
	out.sort()
	return out

# ------------------------------------------------------------------
# Recursos: try_spend + reembolso 50%
# ------------------------------------------------------------------

func has_resources(pid: int, cost: Dictionary) -> bool:
	if not _is_valid_pid(pid):
		return false
	for k in cost.keys():
		if float(players[pid]["res"].get(k, 0.0)) < float(cost[k]):
			return false
	return true

func add_resource(pid: int, kind: String, amount: float) -> void:
	if not _is_valid_pid(pid):
		return
	players[pid]["res"][kind] = maxf(0.0, float(players[pid]["res"].get(kind, 0.0)) + amount)
	_notify_resources(pid)

func try_spend(pid: int, cost: Dictionary) -> bool:
	if not _is_valid_pid(pid) or not is_alive(pid):
		return false
	if not has_resources(pid, cost):
		return false
	for k in cost.keys():
		players[pid]["res"][k] = float(players[pid]["res"][k]) - float(cost[k])
	_notify_resources(pid)
	return true

func refund_cancel(pid: int, cost: Dictionary) -> void:
	# Reembolso determinista del 50% (redondeo hacia abajo) al cancelar
	# una cola de produccion / investigacion / edificio.
	if not _is_valid_pid(pid):
		return
	for k in cost.keys():
		var back := floori(float(cost[k]) * REFUND_FACTOR)
		if back > 0:
			players[pid]["res"][k] = float(players[pid]["res"].get(k, 0.0)) + float(back)
	_notify_resources(pid)

func _refund_amount(value: float) -> int:
	return floori(value * REFUND_FACTOR)

func _notify_resources(pid: int) -> void:
	EventBus.resources_changed.emit(pid, (players[pid]["res"] as Dictionary).duplicate(true))

# ------------------------------------------------------------------
# Poblacion / supply (casas)
# ------------------------------------------------------------------

func can_train(pid: int, pop_cost: int = 1) -> bool:
	if not is_alive(pid):
		return false
	return int(players[pid]["pop"]) + pop_cost <= int(players[pid]["pop_cap"])

func get_free_supply(pid: int) -> int:
	if not _is_valid_pid(pid):
		return 0
	return int(players[pid]["pop_cap"]) - int(players[pid]["pop"])

func add_pop(pid: int, amount: int = 1) -> bool:
	# Devuelve false si no hay supply (no se entrena). Nunca supera pop_cap.
	if not _is_valid_pid(pid) or amount <= 0:
		return false
	if not can_train(pid, amount):
		return false
	players[pid]["pop"] = int(players[pid]["pop"]) + amount
	_notify_pop(pid)
	return true

func remove_pop(pid: int, amount: int = 1) -> void:
	if not _is_valid_pid(pid) or amount <= 0:
		return
	players[pid]["pop"] = maxi(0, int(players[pid]["pop"]) - amount)
	_notify_pop(pid)

func add_pop_cap(pid: int, amount: int = HOUSE_SUPPLY) -> void:
	# Llamar al completar una casa (+5). Tope MAX_POP_CAP.
	if not _is_valid_pid(pid) or amount <= 0:
		return
	players[pid]["pop_cap"] = mini(MAX_POP_CAP, int(players[pid]["pop_cap"]) + amount)
	_notify_pop(pid)

func remove_pop_cap(pid: int, amount: int = HOUSE_SUPPLY) -> void:
	# Llamar al perder una casa. pop se mantiene (bloquea entrenar hasta recuperar).
	if not _is_valid_pid(pid) or amount <= 0:
		return
	players[pid]["pop_cap"] = maxi(0, int(players[pid]["pop_cap"]) - amount)
	_notify_pop(pid)

# Alias "supply" para agentes que hablan en terminos de supply AoE2.
func add_supply(pid: int, amount: int = HOUSE_SUPPLY) -> void:
	add_pop_cap(pid, amount)

func remove_supply(pid: int, amount: int = HOUSE_SUPPLY) -> void:
	remove_pop_cap(pid, amount)

func on_house_completed(pid: int) -> void:
	add_pop_cap(pid, HOUSE_SUPPLY)

func on_house_destroyed(pid: int) -> void:
	remove_pop_cap(pid, HOUSE_SUPPLY)

func _notify_pop(pid: int) -> void:
	# resources_changed existe siempre; pop_changed es opcional (guardia has_signal).
	_notify_resources(pid)
	if EventBus.has_signal("pop_changed"):
		EventBus.emit_signal("pop_changed", pid, int(players[pid]["pop"]), int(players[pid]["pop_cap"]))
	if EventBus.has_signal("supply_changed"):
		EventBus.emit_signal("supply_changed", pid, int(players[pid]["pop"]), int(players[pid]["pop_cap"]))

# ------------------------------------------------------------------
# Edades: validacion de coste/tiempo con timers por tick
# ------------------------------------------------------------------

func is_researching(pid: int) -> bool:
	return _is_valid_pid(pid) and not (players[pid].get("research", {}) as Dictionary).is_empty()

func get_age_progress(pid: int) -> Dictionary:
	# Para HUD (solo lectura, no usa SceneTreeTimer): {target, ticks_left, ticks_total}
	if not _is_valid_pid(pid):
		return {}
	return (players[pid].get("research", {}) as Dictionary).duplicate(true)

func register_building(pid: int, building_id: String) -> void:
	if not _is_valid_pid(pid):
		return
	var b := building_id.to_lower().strip_edges()
	var arr: Array = players[pid]["buildings"]
	if not arr.has(b):
		arr.append(b)

func unregister_building(pid: int, building_id: String) -> void:
	if not _is_valid_pid(pid):
		return
	(players[pid]["buildings"] as Array).erase(building_id.to_lower().strip_edges())

func has_requirement(pid: int, req: String) -> bool:
	# Requisitos del JSON usan "_o_" como OR: "herreria_o_mercado".
	var r := req.to_lower().strip_edges()
	if r.is_empty():
		return true
	var owned: Array = players[pid]["buildings"] if _is_valid_pid(pid) else []
	if "_o_" in r:
		for alt in r.split("_o_"):
			if owned.has(alt.strip_edges()):
				return true
		return false
	return owned.has(r)

func can_advance_age(pid: int, target_age: String = "") -> Dictionary:
	# Devuelve {ok: bool, reason: String}. No muta estado.
	if not _is_valid_pid(pid):
		return {"ok": false, "reason": "bad_player"}
	if game_over or not is_alive(pid):
		return {"ok": false, "reason": "dead_or_over"}
	var target := target_age if not target_age.is_empty() else get_next_age(str(players[pid]["age"]))
	if target.is_empty():
		return {"ok": false, "reason": "max_age"}
	if get_age_index(target) != get_age_index(str(players[pid]["age"])) + 1:
		return {"ok": false, "reason": "must_advance_in_order"}
	if is_researching(pid):
		return {"ok": false, "reason": "already_researching"}
	var cost := get_age_cost(target)
	if not has_resources(pid, cost):
		return {"ok": false, "reason": "no_resources"}
	for req in get_age_data(target).get("requires", []):
		if not has_requirement(pid, str(req)):
			return {"ok": false, "reason": "missing_requirement:" + str(req)}
	return {"ok": true, "reason": "ok", "cost": cost, "ticks": get_age_time_ticks(target)}

func advance_age(pid: int, new_age: String = "") -> bool:
	# Valida coste + requisitos y arranca el timer por ticks (no SceneTreeTimer).
	# Al completarse los ticks se aplica el cambio y se emite EventBus.age_up.
	# new_age vacio = siguiente edad en AGE_ORDER.
	if not _is_valid_pid(pid):
		return false
	var target := new_age if not new_age.is_empty() else get_next_age(str(players[pid]["age"]))
	var chk := can_advance_age(pid, target)
	if not bool(chk.get("ok", false)):
		return false
	var cost: Dictionary = (chk.get("cost", {}) as Dictionary).duplicate(true)
	if not try_spend(pid, cost):
		return false
	var total: int = int(chk.get("ticks", 0))
	if total <= 0:
		_complete_age_up(pid, target)
		return true
	players[pid]["research"] = {"target": target, "ticks_left": total, "ticks_total": total, "cost": cost}
	if EventBus.has_signal("age_progress"):
		EventBus.emit_signal("age_progress", pid, target, total, total)
	return true

func cancel_age_up(pid: int) -> bool:
	# Cancela la investigacion en curso y reembolsa el 50% del coste.
	if not is_researching(pid):
		return false
	var r: Dictionary = players[pid]["research"]
	players[pid]["research"] = {}
	refund_cancel(pid, (r.get("cost", {}) as Dictionary))
	if EventBus.has_signal("age_cancelled"):
		EventBus.emit_signal("age_cancelled", pid, str(r.get("target", "")))
	return true

func force_advance_age(pid: int, new_age: String) -> void:
	# Trucos/tests: cambio inmediato sin coste ni tiempo.
	if not _is_valid_pid(pid):
		return
	players[pid]["research"] = {}
	_complete_age_up(pid, new_age)

func _process_age_research() -> void:
	# Orden determinista por id. Resta 1 tick por _on_tick.
	for p in players:
		var r: Dictionary = p.get("research", {})
		if r.is_empty():
			continue
		r["ticks_left"] = int(r["ticks_left"]) - 1
		if int(r["ticks_left"]) <= 0:
			_complete_age_up(int(p["id"]), str(r["target"]))

func _complete_age_up(pid: int, target: String) -> void:
	players[pid]["research"] = {}
	players[pid]["age"] = target
	EventBus.age_up.emit(pid, target)

# ------------------------------------------------------------------
# Victoria por conquista
# ------------------------------------------------------------------

func report_census(pid: int, tc_count: int, villager_count: int, military_count: int) -> void:
	# Los sistemas (o tests) informan el censo; la eliminacion se resuelve
	# en _check_conquest() durante el tick para mantener determinismo.
	if not _is_valid_pid(pid):
		return
	players[pid]["census"] = {
		"tc": maxi(0, tc_count),
		"villager": maxi(0, villager_count),
		"military": maxi(0, military_count),
	}

func eliminate_player(pid: int, reason: String = "conquista") -> void:
	if not _is_valid_pid(pid) or not bool(players[pid]["alive"]):
		return
	players[pid]["alive"] = false
	players[pid]["research"] = {}
	if EventBus.has_signal("player_eliminated"):
		EventBus.emit_signal("player_eliminated", pid, reason)
	_check_game_over()

func _check_conquest() -> void:
	# Elimina (en orden de id) a todo jugador vivo sin TC ni aldeanos ni militares.
	for p in players:
		if not bool(p.get("alive", false)):
			continue
		var c: Dictionary = p.get("census", {"tc": 1, "villager": 1, "military": 0})
		if int(c.get("tc", 0)) <= 0 and int(c.get("villager", 0)) <= 0 and int(c.get("military", 0)) <= 0:
			eliminate_player(int(p["id"]), "conquista")
	# eliminate_player ya llama a _check_game_over; llamada extra por si no hubo bajas.
	_check_game_over()

func _check_game_over() -> void:
	if game_over:
		return
	var teams_alive := {}
	for p in players:
		if bool(p.get("alive", false)):
			teams_alive[int(p["team"])] = true
	if players.size() >= 2 and teams_alive.size() <= 1:
		game_over = true
		winner_team = teams_alive.keys()[0] if teams_alive.size() == 1 else -2
		if EventBus.has_signal("game_over"):
			EventBus.emit_signal("game_over", winner_team)

func is_game_over() -> bool:
	return game_over

func get_winner_team() -> int:
	return winner_team

# ------------------------------------------------------------------
# Tick lockstep (llamado por NetManager) + hash anti-desync
# ------------------------------------------------------------------

func _on_tick(t: int) -> void:
	SimAPI.tick = t
	var cmds: Array = SimAPI.pop_commands_for_tick(t)
	for c in cmds:
		_apply_command(c)
	_process_age_research()
	_check_conquest()
	EventBus.tick_finished.emit(t)

func _apply_command(c: Dictionary) -> void:
	# Punto unico de aplicacion determinista. Los sistemas pesados
	# (economy/combat/construction) se suscriben a command_issued, pero
	# las transiciones de GameManager (edad, tributo, rendicion) se
	# resuelven aqui para garantizar el mismo orden en todos los peers.
	if typeof(c) != TYPE_DICTIONARY:
		return
	var pid := int(c.get("player_id", -1))
	var t := str(c.get("type", ""))
	var payload: Dictionary = c.get("payload", {})
	if not _is_valid_pid(pid):
		return
	match t:
		"research", "age_up":
			advance_age(pid, str(payload.get("age", payload.get("target", ""))))
		"cancel_research", "cancel_age":
			cancel_age_up(pid)
		"tribute":
			_tribute(pid, int(payload.get("to", -1)), str(payload.get("res", "")), float(payload.get("amount", 0.0)))
		"resign", "defeat":
			eliminate_player(pid, "rendicion")
		_:
			pass # resto de tipos los aplican los sistemas suscritos

func _tribute(from_pid: int, to_pid: int, res: String, amount: float) -> bool:
	if not _is_valid_pid(from_pid) or not _is_valid_pid(to_pid):
		return false
	if from_pid == to_pid or amount <= 0.0 or res.is_empty():
		return false
	if not is_alive(from_pid) or not is_alive(to_pid):
		return false
	if float(players[from_pid]["res"].get(res, 0.0)) < amount:
		return false
	players[from_pid]["res"][res] = float(players[from_pid]["res"][res]) - amount
	players[to_pid]["res"][res] = float(players[to_pid]["res"].get(res, 0.0)) + amount
	_notify_resources(from_pid)
	_notify_resources(to_pid)
	return true

func sim_hash_state() -> int:
	# Estado canonico ordenado por id para deteccion de desync.
	var parts: PackedStringArray = []
	for p in players:
		var r: Dictionary = p["res"]
		var rs: Dictionary = p.get("research", {})
		parts.append("%d:%d,%d,%d,%d|%d/%d|%s|%d|%s:%d" % [
			int(p["id"]), int(float(r.get("wood", 0.0))), int(float(r.get("food", 0.0))),
			int(float(r.get("gold", 0.0))), int(float(r.get("stone", 0.0))),
			int(p["pop"]), int(p["pop_cap"]), str(p["age"]),
			1 if bool(p.get("alive", false)) else 0,
			str(rs.get("target", "-")), int(rs.get("ticks_left", 0)),
		])
	return (";".join(parts)).hash()
