extends SceneTree
# tests/BalanceTester.gd - Test de balance/datos headless (Godot 4.4).
#
# Uso:
#   godot --headless --path . -s tests/BalanceTester.gd
#   sh tests/run_all.sh
#
# Test PURO de datos: no toca autoloads, simulacion ni red. Verifica:
#   1. Costes: ninguna unidad/edificio/tecnologia/edad con coste negativo.
#   2. Tiempos: train/build/research > 0 (WARN si falta la clave).
#   3. Sanidad: hp/pop/ataque no negativos, referencias cruzadas
#      (trained_at, actions, upgrade_from, trains, requiere) resueltas.
#   4. Win-rate aproximado: duelos 1 grupo vs 1 grupo a IGUALDAD DE COSTE
#      (presupuesto 600 recursos, ley de Lanchester con fuego de aproximacion
#      para el alcance y bonus_vs/armadura aplicados). No modela micro,
#      colinas ni formaciones: es una red de seguridad contra errores de
#      tecleo (un cero de mas en ataque/hp/coste), no un veredicto de meta.
#
# Severidad: FAIL = dato roto (negativos, tiempos <= 0, win-rate 0%/100%
# combinado con eficiencia absurda). WARN = sospechoso a revisar por
# diseno (counter units, asedio/naval excluidos de los duelos).
# Salida: 0 = PASS (0 errores), 1 = FAIL, 2 = error de entorno.

const UNITS_DIR := "res://data/units"
const BUILDINGS_DIR := "res://data/buildings"
const TECHS_DIR := "res://data/techs"
const AGES_PATH := "res://data/ages/ages.json"
const ACTIONS_PATH := "res://data/actions.json"
const BUILDING_ALIAS := {"caballeriza": "establo"} # trained_at usa el nombre comun

const DUEL_BUDGET := 600.0
const DUEL_DEF_CD := 2.0 # cadencia cuerpo a cuerpo estandar (sin micro)
const DUEL_RANGE_K := 0.05 # ventaja de alcance sobre hp efectiva
const DUEL_MIN_DMG := 0.5 # dano minimo por golpe (nunca 0)
const DUEL_EXCLUDE_IDS := ["aldeano", "carreta_comercio", "barco_pesquero", "ariete", "catapulta", "trebuchet"]
const DUEL_EXCLUDE_AT := ["muelle", "puerto"] # naval: otro balance
const DUEL_EXCLUDE_ARMOR := ["ariete", "asedio"] # asedio: bonus vs edificios
const WR_WARN_LO := 0.30
const WR_WARN_HI := 0.70

var _fails: Array = []
var _warns: Array = []
var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	quit(_main())
	return true


func _main() -> int:
	var actions: Variant = _load_json(ACTIONS_PATH)
	if actions == null:
		return 2
	var action_ids := _action_ids(actions)
	_check_actions(actions, action_ids)
	var building_ids := _building_ids()
	var units := _check_units(action_ids, building_ids)
	_check_buildings()
	_check_techs()
	_check_ages()
	if not units.is_empty():
		_check_duels(units)
	_print_report(units.size())
	if _fails.is_empty():
		print("[Balance] BALANCE PASS: 0 errores, %d avisos" % _warns.size())
		return 0
	printerr("[Balance] BALANCE FAIL: %d errores, %d avisos" % [_fails.size(), _warns.size()])
	return 1


# --- Carga y utilidades ---

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_fail("falta archivo: " + path)
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		_fail("JSON invalido: " + path)
	return parsed


func _list_json(dir: String) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		_fail("falta directorio: " + dir)
		return out
	for f in DirAccess.get_files_at(dir):
		if str(f).ends_with(".json"):
			out.append(str(f))
	out.sort()
	return out


func _fail(msg: String) -> void:
	_fails.append(msg)
	printerr("[Balance] FAIL: " + msg)


func _warn(msg: String) -> void:
	_warns.append(msg)
	print("[Balance] WARN: " + msg)


func _check_cost(cost: Variant, what: String) -> float:
	if typeof(cost) != TYPE_DICTIONARY or (cost as Dictionary).is_empty():
		_warn(what + ": sin coste definido (gratis?)")
		return 0.0
	var total := 0.0
	for k in (cost as Dictionary).keys():
		var v := float((cost as Dictionary)[k])
		if v < 0.0:
			_fail("%s: coste negativo %s=%s" % [what, str(k), str(v)])
		else:
			total += v
	if total <= 0.0:
		_warn(what + ": coste total 0 (gratis)")
	return total


func _check_time(d: Dictionary, keys: Array, what: String) -> float:
	for k in keys:
		if d.has(k):
			var v := float(d[k])
			if v <= 0.0:
				_fail("%s: tiempo no positivo %s=%s" % [what, str(k), str(v)])
			return v
	_warn(what + ": sin clave de tiempo %s" % str(keys))
	return -1.0


func _check_hp_atk(d: Dictionary, what: String) -> void:
	if not d.has("hp"):
		_warn(what + ": sin hp")
	elif float(d["hp"]) <= 0.0:
		_fail("%s: hp no positivo (%s)" % [what, str(d["hp"])])
	if not d.has("attack"):
		_warn(what + ": sin attack")
	elif float(d["attack"]) < 0.0:
		_fail("%s: attack negativo (%s)" % [what, str(d["attack"])])
	if d.has("pop_cost") and float(d["pop_cost"]) < 0.0:
		_fail("%s: pop_cost negativo (%s)" % [what, str(d["pop_cost"])])


# --- actions.json ---

func _action_ids(actions: Variant) -> Dictionary:
	var ids := {}
	if typeof(actions) == TYPE_DICTIONARY and (actions as Dictionary).has("actions"):
		for k in ((actions as Dictionary)["actions"] as Dictionary).keys():
			ids[str(k)] = true
	return ids


func _check_actions(actions: Variant, action_ids: Dictionary) -> void:
	if typeof(actions) != TYPE_DICTIONARY or not (actions as Dictionary).has("actions"):
		_fail("actions.json: sin bloque 'actions'")
		return
	var acts: Dictionary = (actions as Dictionary)["actions"]
	if not acts.has("train"):
		_fail("actions.json: falta accion 'train'")
	if acts.has("gather"):
		var g: Dictionary = acts["gather"]
		if g.has("rates_per_sec"):
			for k in (g["rates_per_sec"] as Dictionary).keys():
				if float((g["rates_per_sec"] as Dictionary)[k]) <= 0.0:
					_fail("actions.json: gather rate no positiva %s" % str(k))
		if not g.has("carry_capacity") or float(g.get("carry_capacity", 0.0)) <= 0.0:
			_fail("actions.json: carry_capacity ausente o no positiva")
	print("[Balance] actions.json OK (%d acciones)" % action_ids.size())


# --- Unidades / edificios / techs / edades ---

func _building_ids() -> Dictionary:
	var ids := {}
	for f in _list_json(BUILDINGS_DIR):
		var d: Variant = _load_json(BUILDINGS_DIR + "/" + f)
		if typeof(d) == TYPE_DICTIONARY and (d as Dictionary).has("id"):
			ids[str((d as Dictionary)["id"])] = true
	return ids


func _check_units(action_ids: Dictionary, building_ids: Dictionary) -> Dictionary:
	var units := {}
	var files := _list_json(UNITS_DIR)
	if files.is_empty():
		_fail("sin unidades en " + UNITS_DIR)
		return units
	for f in files:
		var d: Variant = _load_json(UNITS_DIR + "/" + f)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var what := "unidad %s" % f
		if not (d as Dictionary).has("id"):
			_fail(what + ": sin id")
			continue
		var uid := str((d as Dictionary)["id"])
		what = "unidad " + uid
		units[uid] = d
		_check_hp_atk(d, what)
		_check_cost((d as Dictionary).get("cost", (d as Dictionary).get("coste", null)), what)
		_check_time(d, ["train_time_sec"], what)
		for a in ((d as Dictionary).get("actions", []) as Array):
			if not action_ids.has(str(a)):
				_warn("%s: accion desconocida '%s' (no esta en actions.json)" % [what, str(a)])
		var ta := str((d as Dictionary).get("trained_at", ""))
		if not ta.is_empty():
			var norm: String = BUILDING_ALIAS.get(ta.to_lower(), ta.to_lower())
			if not building_ids.has(norm):
				_warn("%s: trained_at '%s' sin edificio de datos" % [what, ta])
		var up = (d as Dictionary).get("upgrade_from", null)
		if up != null and str(up) != "":
			if not FileAccess.file_exists(UNITS_DIR + "/" + str(up) + ".json"):
				_warn("%s: upgrade_from '%s' no existe" % [what, str(up)])
	print("[Balance] unidades OK: %d revisadas" % units.size())
	return units


func _check_buildings() -> void:
	var n := 0
	for f in _list_json(BUILDINGS_DIR):
		var d: Variant = _load_json(BUILDINGS_DIR + "/" + f)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		n += 1
		var what := "edificio " + str((d as Dictionary).get("id", f))
		_check_cost((d as Dictionary).get("cost", (d as Dictionary).get("coste", null)), what)
		_check_time(d, ["build_time_sec"], what)
		if not (d as Dictionary).has("hp"):
			_warn(what + ": sin hp")
		elif float((d as Dictionary)["hp"]) <= 0.0:
			_fail(what + ": hp no positiva")
		for u in ((d as Dictionary).get("trains", []) as Array):
			if not FileAccess.file_exists(UNITS_DIR + "/" + str(u) + ".json"):
				_warn("%s: trains '%s' sin ficha de unidad" % [what, str(u)])
	print("[Balance] edificios OK: %d revisados" % n)


func _check_techs() -> void:
	var n := 0
	for f in _list_json(TECHS_DIR):
		var d: Variant = _load_json(TECHS_DIR + "/" + f)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var ids := {}
		for t in ((d as Dictionary).get("techs", []) as Array):
			if typeof(t) == TYPE_DICTIONARY and (t as Dictionary).has("id"):
				ids[str((t as Dictionary)["id"])] = true
		for t in ((d as Dictionary).get("techs", []) as Array):
			if typeof(t) != TYPE_DICTIONARY:
				continue
			n += 1
			var what := "tech " + str((t as Dictionary).get("id", "?"))
			_check_cost((t as Dictionary).get("coste", (t as Dictionary).get("cost", null)), what)
			_check_time(t, ["tiempo_sec"], what)
			for r in ((t as Dictionary).get("requiere", []) as Array):
				if not ids.has(str(r)):
					_warn("%s: requiere '%s' inexistente en %s" % [what, str(r), f])
	print("[Balance] tecnologias OK: %d revisadas" % n)


func _check_ages() -> void:
	var d: Variant = _load_json(AGES_PATH)
	if typeof(d) != TYPE_DICTIONARY or not (d as Dictionary).has("ages"):
		_fail("ages.json: sin bloque 'ages'")
		return
	var ages: Array = (d as Dictionary)["ages"]
	if ages.is_empty():
		_fail("ages.json: lista vacia")
		return
	for i in ages.size():
		var a = ages[i]
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var what := "edad " + str((a as Dictionary).get("id", i))
		var acost: Dictionary = (a as Dictionary).get("cost", {})
		if not acost.is_empty() or i > 0:
			_check_cost(acost, what)
		if (a as Dictionary).has("research_time_sec"):
			if float((a as Dictionary)["research_time_sec"]) < 0.0:
				_fail(what + ": research_time_sec negativo")
			elif float((a as Dictionary)["research_time_sec"]) <= 0.0 and i > 0:
				_warn(what + ": research_time_sec 0 fuera de la edad inicial")
	print("[Balance] edades OK: %d revisadas" % ages.size())


# --- Duelos a igualdad de coste (win-rate aproximado) ---

func _duel_cost(u: Dictionary) -> float:
	var total := 0.0
	for k in (u.get("cost", {}) as Dictionary).keys():
		total += maxf(0.0, float((u["cost"] as Dictionary)[k]))
	return total


func _duel_cd(u: Dictionary) -> float:
	return maxf(0.5, float(u.get("fire_cooldown_sec", DUEL_DEF_CD)))


func _duel_eff_hp(u: Dictionary) -> float:
	return maxf(1.0, float(u.get("hp", 1.0))) * (1.0 + DUEL_RANGE_K * float(u.get("range", 1.0)))


func _duel_is_melee(u: Dictionary) -> bool:
	return float(u.get("range", 1.0)) <= 1.5


func _duel_raw_dmg(att: Dictionary, dfd: Dictionary) -> float:
	var arm := float(dfd.get("armor_melee", 0.0)) if _duel_is_melee(att) else float(dfd.get("armor_pierce", 0.0))
	var dmg := maxf(DUEL_MIN_DMG, float(att.get("attack", 0.0)) - arm)
	for k in (att.get("bonus_vs", {}) as Dictionary).keys():
		if str(k) == str(dfd.get("id", "")) or str(k) == str(dfd.get("armor_class", "")):
			dmg += float((att["bonus_vs"] as Dictionary)[k])
	return dmg


func _duel_ttk(att: Dictionary, dfd: Dictionary) -> float:
	# Segundos que tarda el grupo att en aniquilar al grupo dfd (foco de fuego,
	# sin overkill). El de mayor alcance descuenta fuego gratis de aproximacion.
	var na := maxi(1, int(DUEL_BUDGET / _duel_cost(att) + 0.5))
	var nb := maxi(1, int(DUEL_BUDGET / _duel_cost(dfd) + 0.5))
	var gap := maxf(0.0, float(att.get("range", 1.0)) - float(dfd.get("range", 1.0)))
	var pool := float(nb) * _duel_eff_hp(dfd)
	if gap > 0.0:
		var closer := maxf(maxf(float(att.get("speed", 0.9)), float(dfd.get("speed", 0.9))), 0.1)
		var volleys := int(gap / closer / _duel_cd(att))
		pool = maxf(1.0, pool - float(na * volleys) * _duel_raw_dmg(att, dfd))
	return pool / maxf(0.000001, float(na) * _duel_raw_dmg(att, dfd) / _duel_cd(att))


func _duel_roster(units: Dictionary) -> Array:
	var roster: Array = []
	for uid in units.keys():
		var u: Dictionary = units[uid]
		if float(u.get("attack", 0.0)) <= 0.0:
			continue
		if str(uid) in DUEL_EXCLUDE_IDS:
			continue
		if str(u.get("trained_at", "")) in DUEL_EXCLUDE_AT:
			continue
		if str(u.get("armor_class", "")) in DUEL_EXCLUDE_ARMOR:
			continue
		if _duel_cost(u) <= 0.0:
			continue
		roster.append(u)
	roster.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	return roster


func _check_duels(units: Dictionary) -> void:
	var roster := _duel_roster(units)
	if roster.size() < 4:
		_warn("duelos: roster insuficiente (%d), se omite win-rate" % roster.size())
		return
	var effs: Array = []
	for u in roster:
		effs.append(maxf(0.000001, _duel_raw_dmg(u, {}) / _duel_cd(u) * _duel_eff_hp(u) / _duel_cost(u)))
	effs.sort()
	var median: float = effs[effs.size() / 2]
	print("[Balance] duelos: %d unidades, presupuesto %.0f, mediana eficiencia=%.2f" % [roster.size(), DUEL_BUDGET, median])
	print("[Balance] id                   WR    eff   n  veredicto")
	var rows: Array = []
	for u in roster:
		var wins := 0.0
		for v in roster:
			if str(v["id"]) == str(u["id"]):
				continue
			var ta := _duel_ttk(u, v)
			var tb := _duel_ttk(v, u)
			if ta < tb:
				wins += 1.0
			elif ta == tb:
				wins += 0.5
		var wr: float = wins / float(roster.size() - 1)
		var eff: float = maxf(0.000001, _duel_raw_dmg(u, {}) / _duel_cd(u) * _duel_eff_hp(u) / _duel_cost(u))
		var n: int = maxi(1, int(DUEL_BUDGET / _duel_cost(u) + 0.5))
		rows.append({"id": str(u["id"]), "wr": wr, "eff": eff, "n": n})
	rows.sort_custom(func(a, b): return float(a["wr"]) > float(b["wr"]))
	for r in rows:
		var verdict := "ok"
		if float(r["wr"]) < WR_WARN_LO or float(r["wr"]) > WR_WARN_HI:
			verdict = "revisar"
			_warn("%s: win-rate aproximado %.2f fuera de [%.2f, %.2f] (modelo sin micro)" % [str(r["id"]), float(r["wr"]), WR_WARN_LO, WR_WARN_HI])
		if (float(r["wr"]) <= 0.0 or float(r["wr"]) >= 1.0) and (float(r["eff"]) < median / 10.0 or float(r["eff"]) > median * 10.0):
			verdict = "ROTO"
			_fail("%s: dominancia total (WR=%.2f) con eficiencia absurda (%.2f vs mediana %.2f)" % [str(r["id"]), float(r["wr"]), float(r["eff"]), median])
		elif float(r["eff"]) < median / 20.0 or float(r["eff"]) > median * 20.0:
			verdict = "revisar"
			_warn("%s: eficiencia %.2f a >20x de la mediana (%.2f)" % [str(r["id"]), float(r["eff"]), median])
		elif float(r["eff"]) < median / 6.0 or float(r["eff"]) > median * 6.0:
			if verdict == "ok":
				verdict = "revisar"
			_warn("%s: eficiencia %.2f a >6x de la mediana (%.2f)" % [str(r["id"]), float(r["eff"]), median])
		print("[Balance] " + str(r["id"]) + " WR=%.2f eff=%.2f n=%d %s" % [float(r["wr"]), float(r["eff"]), int(r["n"]), verdict])


func _print_report(n_units: int) -> void:
	print("[Balance] resumen: %d unidades revisadas, %d errores, %d avisos" % [n_units, _fails.size(), _warns.size()])
	for m in _fails:
		print("[Balance]   ERROR: " + m)
