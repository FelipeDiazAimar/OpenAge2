extends Node
# FarmingTrade - granjas, pesca, comercio y tributo (AoE2 1:1).
# Determinista: sin randf/Time, todo avanza en tick 10Hz via EventBus.tick_finished.
# Rates leídos de data/actions.json (gather.rates_per_sec, trade.gold_per_trip_base/bonus).
# Suscrito a SimAPI.queue_command tipos: build_farm, replant_toggle, gather_farm,
# gather_fish, trade_trip, tribute.

const TICK_RATE := 10
const ACTIONS_PATH := "res://data/actions.json"

# Granjas AoE2: solo alrededor del TC.
const FARM_COST := {"wood": 60.0}
const FARM_FOOD_MAX := 250.0
const FARM_RADIUS_TC := 8.0 # tiles
const FARM_SIZE_TILES := Vector2i(2, 2)

# Pesca: banco costero infinito por defecto; rate se carga de JSON.
const FISH_BANK_INFINITE := true

# Tributo AoE2 estándar con impuesto 0% entre aliados.
const TRIBUTE_TAX := 0.0

# Rates (sobrescritos desde actions.json en _ready).
var rate_farm := 0.32
var rate_fish := 0.43
var rate_forage := 0.41
var trade_base := 20.0
var trade_bonus_per_tile := 0.3
var carry_capacity := 10.0

# Estado simulado (solo datos, sin nodos 3D).
# farms: {farm_id: {owner, tc_id, pos:Vector2, food_left, worker_id (-1 libre), auto_replant:bool}}
# tcs: {tc_id: {owner, pos:Vector2}}
# markets: {market_id: {owner, pos:Vector2}}
# replant_queue: {player_id: [farm_id...]} — cola de replantado pendiente de pago
# boats: {boat_id: {owner, bank_id, carried:float}}
# carts: {cart_id: {owner, from_market, to_market, carried:float, progress:float}}
# fish_banks: {bank_id: {pos:Vector2, amount:float (-1 = infinito), coastal:bool}}
var farms := {}
var tcs := {}
var markets := {}
var replant_queue := {} # player_id -> Array de farm_id
var boats := {}
var carts := {}
var fish_banks := {}
var _next_farm_id := 1
var _accum := {} # "kind:unit_id" -> float resto fraccional para entrega determinista

func _ready() -> void:
	_load_rates()
	EventBus.command_issued.connect(_on_cmd)
	EventBus.tick_finished.connect(_on_tick)

# --- Carga de rates ---

func _load_rates() -> void:
	if not FileAccess.file_exists(ACTIONS_PATH):
		push_warning("[FarmingTrade] sin actions.json, uso defaults.")
		return
	var f := FileAccess.open(ACTIONS_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[FarmingTrade] actions.json inválido, uso defaults.")
		return
	var acts: Dictionary = (parsed as Dictionary).get("actions", {})
	var gather: Dictionary = acts.get("gather", {})
	var rates: Dictionary = gather.get("rates_per_sec", {})
	rate_farm = float(rates.get("food_farm", rate_farm))
	rate_fish = float(rates.get("food_fish", rate_fish))
	rate_forage = float(rates.get("food_forage", rate_forage))
	carry_capacity = float(gather.get("carry_capacity", carry_capacity))
	var trade: Dictionary = acts.get("trade", {})
	trade_base = float(trade.get("gold_per_trip_base", trade_base))
	trade_bonus_per_tile = float(trade.get("bonus_per_tile", trade_bonus_per_tile))

# --- Registro de mundo (llamado por Construction/Mapa al colocar edificios) ---

func register_tc(tc_id: int, owner: int, pos: Vector2) -> void:
	tcs[tc_id] = {"owner": owner, "pos": pos}

func register_market(market_id: int, owner: int, pos: Vector2) -> void:
	markets[market_id] = {"owner": owner, "pos": pos}

func unregister_market(market_id: int) -> void:
	markets.erase(market_id)

func register_fish_bank(bank_id: int, pos: Vector2, coastal: bool = true, amount: float = -1.0) -> void:
	# amount < 0 = infinito (banco costero estándar).
	fish_banks[bank_id] = {"pos": pos, "coastal": coastal, "amount": amount}

func register_boat(boat_id: int, owner: int, bank_id: int = -1) -> void:
	boats[boat_id] = {"owner": owner, "bank_id": bank_id, "carried": 0.0}

func register_cart(cart_id: int, owner: int) -> void:
	carts[cart_id] = {"owner": owner, "from_market": -1, "to_market": -1, "carried": 0.0, "progress": 0.0}

# --- Granjas ---

func can_place_farm(owner: int, pos: Vector2) -> bool:
	# Solo si hay un TC propio a <= radio 8.
	for tc_id in tcs.keys():
		var tc: Dictionary = tcs[tc_id]
		if int(tc["owner"]) != owner:
			continue
		if (pos - (tc["pos"] as Vector2)).length() <= FARM_RADIUS_TC + 0.001:
			return true
	return false

func try_build_farm(owner: int, pos: Vector2, tc_id: int = -1) -> int:
	# Valida radio y cobra 60 madera via GameManager. Devuelve farm_id o -1.
	if not can_place_farm(owner, pos):
		return -1
	if not GameManager.try_spend(owner, FARM_COST):
		return -1
	var fid := _next_farm_id
	_next_farm_id += 1
	var linked_tc := tc_id
	if linked_tc == -1:
		linked_tc = nearest_tc(owner, pos)
	farms[fid] = {
		"owner": owner, "tc_id": linked_tc, "pos": pos,
		"food_left": FARM_FOOD_MAX, "worker_id": -1, "auto_replant": true,
	}
	return fid

func nearest_tc(owner: int, pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for tc_id in tcs.keys():
		var tc: Dictionary = tcs[tc_id]
		if int(tc["owner"]) != owner:
			continue
		var d := (pos - (tc["pos"] as Vector2)).length()
		if d < best_d:
			best_d = d
			best = tc_id
	return best

func set_auto_replant(farm_id: int, auto: bool) -> void:
	if farms.has(farm_id):
		(farms[farm_id] as Dictionary)["auto_replant"] = auto

func queue_replant(owner: int, farm_id: int) -> void:
	if not replant_queue.has(owner):
		replant_queue[owner] = []
	if not (replant_queue[owner] as Array).has(farm_id):
		(replant_queue[owner] as Array).append(farm_id)

func farm_food_left(farm_id: int) -> float:
	if farms.has(farm_id):
		return float((farms[farm_id] as Dictionary)["food_left"])
	return 0.0

# --- Pesca ---

func fish_rate() -> float:
	return rate_fish

func assign_boat_to_bank(boat_id: int, bank_id: int) -> bool:
	if not boats.has(boat_id) or not fish_banks.has(bank_id):
		return false
	# Solo bancos costeros (bote no entra a tierra).
	if not bool((fish_banks[bank_id] as Dictionary)["coastal"]):
		return false
	(boats[boat_id] as Dictionary)["bank_id"] = bank_id
	return true

# --- Comercio ---

static func distance_tiles(a: Vector2, b: Vector2) -> float:
	return (a - b).length() # 1 unidad mundo = 1 tile en este proyecto

func trade_gold_for_trip(from_pos: Vector2, to_pos: Vector2) -> float:
	var d := distance_tiles(from_pos, to_pos)
	return snappedf(trade_base + trade_bonus_per_tile * d, 0.001)

func are_allied(p1: int, p2: int) -> bool:
	if p1 == p2:
		return false # mismo jugador no comercia consigo mismo
	if p1 >= GameManager.players.size() or p2 >= GameManager.players.size():
		return false
	# Aliados = mismo team (diplomacia ampliable).
	return int(GameManager.players[p1]["team"]) == int(GameManager.players[p2]["team"])

func compute_trade_gold(cart_owner: int, from_market: int, to_market: int) -> float:
	# Oro = 20 + 0.3 * distancia_tiles. 0 si mercados no aliados o inexistentes.
	if not markets.has(from_market) or not markets.has(to_market):
		return 0.0
	var m1: Dictionary = markets[from_market]
	var m2: Dictionary = markets[to_market]
	var o1 := int(m1["owner"])
	var o2 := int(m2["owner"])
	# Al menos un extremo del dueño de la carreta y el otro aliado.
	var allied := (are_allied(o1, o2)) and (cart_owner == o1 or cart_owner == o2)
	if not allied:
		return 0.0
	return trade_gold_for_trip(m1["pos"], m2["pos"])

# --- Tributo ---

func send_tribute(from_pid: int, to_pid: int, res_kind: String, amount: float) -> bool:
	# Solo entre aliados, impuesto 0%: el receptor recibe íntegro.
	if not are_allied(from_pid, to_pid):
		return false
	if amount <= 0.0:
		return false
	if not GameManager.try_spend(from_pid, {res_kind: amount}):
		return false
	# Impuesto 0% -> sin descuento.
	var net := snappedf(amount * (1.0 - TRIBUTE_TAX), 0.001)
	GameManager.add_resource(to_pid, res_kind, net)
	return true

# --- Comandos (via SimAPI.queue_command) ---

func _on_cmd(cmd: Dictionary) -> void:
	var t := str(cmd.get("type", ""))
	var pid := int(cmd.get("player_id", -1))
	var p: Dictionary = cmd.get("payload", {})
	match t:
		"build_farm":
			try_build_farm(pid, p.get("pos", Vector2.ZERO), int(p.get("tc_id", -1)))
		"replant_toggle":
			set_auto_replant(int(p.get("farm_id", -1)), bool(p.get("auto", true)))
		"gather_farm":
			_assign_worker(int(p.get("farm_id", -1)), int(p.get("worker_id", -1)))
		"gather_fish":
			assign_boat_to_bank(int(p.get("boat_id", -1)), int(p.get("bank_id", -1)))
		"trade_trip":
			_start_trade_trip(int(p.get("cart_id", -1)), int(p.get("from_market", -1)), int(p.get("to_market", -1)))
		"tribute":
			send_tribute(pid, int(p.get("to", -1)), str(p.get("res", "food")), float(p.get("amount", 0.0)))

func _assign_worker(farm_id: int, worker_id: int) -> void:
	if farms.has(farm_id):
		(farms[farm_id] as Dictionary)["worker_id"] = worker_id

func _start_trade_trip(cart_id: int, from_market: int, to_market: int) -> void:
	if not carts.has(cart_id):
		return
	var c: Dictionary = carts[cart_id]
	c["from_market"] = from_market
	c["to_market"] = to_market
	c["progress"] = 0.0
	c["carried"] = compute_trade_gold(int(c["owner"]), from_market, to_market)

# --- Tick determinista ---

func _on_tick(tick: int) -> void:
	var dt := 1.0 / float(TICK_RATE)
	_tick_farms(dt)
	_tick_fishing(dt)
	_tick_trade(dt)
	_tick_replant_queue()

func _tick_farms(dt: float) -> void:
	# Claves ordenadas = orden determinista.
	var ids := farms.keys()
	ids.sort()
	for fid in ids:
		var f: Dictionary = farms[fid]
		var wid := int(f["worker_id"])
		if wid == -1:
			continue
		var left := float(f["food_left"])
		if left <= 0.0:
			continue
		var gain: float = minf(rate_farm * dt, left)
		gain = snappedf(gain, 0.001)
		f["food_left"] = snappedf(left - gain, 0.001)
		_deposit(f[int(f["owner"])], "food", gain)
		if float(f["food_left"]) <= 0.001:
			f["food_left"] = 0.0
			f["worker_id"] = -1 # aldeano queda idle; replantado en _tick_replant_queue
			queue_replant(int(f["owner"]), fid)

func _tick_fishing(dt: float) -> void:
	var ids := boats.keys()
	ids.sort()
	for bid in ids:
		var b: Dictionary = boats[bid]
		var bank_id := int(b["bank_id"])
		if bank_id == -1 or not fish_banks.has(bank_id):
			continue
		var bank: Dictionary = fish_banks[bank_id]
		var gain := snappedf(rate_fish * dt, 0.001)
		if float(bank["amount"]) >= 0.0 and not FISH_BANK_INFINITE:
			gain = minf(gain, float(bank["amount"]))
			bank["amount"] = snappedf(float(bank["amount"]) - gain, 0.001)
		# Banco infinito costero: nunca se agota.
		b["carried"] = snappedf(float(b["carried"]) + gain, 0.001)
		# Entrega inmediata al stock (bote descarga continuo; carry visual aparte).
		if float(b["carried"]) >= carry_capacity:
			_deposit(int(b["owner"]), "food", float(b["carried"]))
			b["carried"] = 0.0

func _tick_trade(dt: float) -> void:
	# Viaje simplificado determinista: 1 viaje = distancia / velocidad carreta.
	# Velocidad carreta 1.2 tiles/s (AoE2 aprox). Al completar, paga oro calculado.
	const CART_SPEED := 1.2
	var ids := carts.keys()
	ids.sort()
	for cid in ids:
		var c: Dictionary = carts[cid]
		var fm := int(c["from_market"])
		var tm := int(c["to_market"])
		if fm == -1 or tm == -1:
			continue
		if not markets.has(fm) or not markets.has(tm):
			c["from_market"] = -1
			c["to_market"] = -1
			continue
		var m1: Dictionary = markets[fm]
		var m2: Dictionary = markets[tm]
		var dist := distance_tiles(m1["pos"], m2["pos"])
		if dist <= 0.001:
			continue
		c["progress"] = float(c["progress"]) + CART_SPEED * dt / dist
		if float(c["progress"]) >= 1.0:
			c["progress"] = 0.0
			# Ida y vuelta: cobra al llegar a cada extremo (oro ida, oro vuelta).
			var gold := compute_trade_gold(int(c["owner"]), fm, tm)
			_deposit(int(c["owner"]), "gold", gold)
			# Invierte ruta para el retorno continuo.
			c["from_market"] = tm
			c["to_market"] = fm
			c["carried"] = gold

func _tick_replant_queue() -> void:
	# Replantado automático con cola: procesa en orden de llegada,
	# cobra 60 madera por granja si auto_replant activo.
	var owners := replant_queue.keys()
	owners.sort()
	for owner in owners:
		var q: Array = replant_queue[owner]
		var kept: Array = []
		for fid in q:
			if not farms.has(fid):
				continue
			var f: Dictionary = farms[fid]
			if float(f["food_left"]) > 0.0:
				continue
			if not bool(f["auto_replant"]):
				kept.append(fid) # espera a reactivar auto
				continue
			if GameManager.try_spend(int(owner), FARM_COST):
				f["food_left"] = FARM_FOOD_MAX
			else:
				kept.append(fid) # sin madera: sigue en cola
		replant_queue[owner] = kept

func _deposit(owner: int, kind: String, amount: float) -> void:
	if amount <= 0.0:
		return
	# Acumulador fraccional determinista por jugador+recurso (evita deriva float).
	var key := "%d:%s" % [owner, kind]
	_accum[key] = snappedf(float(_accum.get(key, 0.0)) + amount, 0.001)
	GameManager.add_resource(owner, kind, amount)

# --- Hash para desync (lockstep) ---

func state_string() -> String:
	var parts: Array = []
	var ids := farms.keys()
	ids.sort()
	for fid in ids:
		var f: Dictionary = farms[fid]
		parts.append("%d:%d:%.3f" % [fid, int(f["worker_id"]), float(f["food_left"])])
	return "farms[%s] trade_base=%.3f bonus=%.3f" % [",".join(parts), trade_base, trade_bonus_per_tile]
