extends RefCounted
## Comercio estilo AoE2: la carreta (Trade {gold_base, gold_per_tile}) va y
## viene entre el mercado propio más cercano y un mercado (Market) de otro
## jugador que no sea enemigo. Al llegar al ajeno carga oro según la distancia
## entre ambos mercados; al volver al propio lo entrega y repite.
## Estados: idle, to_target, to_home.

const FP := preload("res://engine/sim/FixedPoint.gd")
const MoveSystem := preload("res://engine/sim/systems/MoveSystem.gd")
const GatherSystem := preload("res://engine/sim/systems/GatherSystem.gd")

const REACH := 800


static func _market_ok(sim, b: int) -> bool:
	var w = sim.world
	return w.entities.has(b) and w.has_ability(b, "Market") and sim.is_built(b)


## Mercado propio terminado más cercano a pos (-1 si no hay).
static func home_market(sim, owner: int, pos: Vector2i) -> int:
	var w = sim.world
	var best := -1
	var best_d := 0
	for b in w.ids_with("Market"):
		if int(w.entities[b]["owner"]) != owner or not sim.is_built(b):
			continue
		var d := FP.dist(pos, w.entities[b]["pos"])
		if best < 0 or d < best_d:
			best = b
			best_d = d
	return best


static func trade_error(sim, cart: int, market: int) -> String:
	var w = sim.world
	if not w.has_ability(cart, "Trade") or not _market_ok(sim, market):
		return "no es un mercado"
	var owner := int(w.entities[cart]["owner"])
	var other := int(w.entities[market]["owner"])
	if other == owner:
		return "comercia con el mercado de otro jugador"
	if sim.is_enemy(owner, other):
		return "mercado enemigo"
	if home_market(sim, owner, w.entities[cart]["pos"]) < 0:
		return "necesitas un mercado propio"
	return ""


static func order_trade(sim, cart: int, market: int) -> void:
	if trade_error(sim, cart, market) != "":
		return
	var w = sim.world
	var t: Dictionary = w.comp(cart, "Trade")
	t["home"] = home_market(sim, int(w.entities[cart]["owner"]), w.entities[cart]["pos"])
	t["target"] = market
	t["state"] = "to_target"
	_go(sim, cart, market)


static func stop(sim, cart: int) -> void:
	var t: Dictionary = sim.world.comp(cart, "Trade")
	if not t.is_empty():
		t["state"] = "idle"
		t["target"] = -1
		t["home"] = -1


static func _go(sim, cart: int, b: int) -> void:
	var w = sim.world
	var pos: Vector2i = w.entities[cart]["pos"]
	var r := GatherSystem._rect(sim, b)
	var lo: Vector2i = r[0]
	var hi: Vector2i = r[1]
	MoveSystem.order_move(w, sim.grid, cart, Vector2i(clampi(pos.x, lo.x, hi.x - 1), clampi(pos.y, lo.y, hi.y - 1)))


## Oro (milésimas) por viaje entre dos mercados.
static func trip_gold(sim, cart: int, a: int, b: int) -> int:
	var w = sim.world
	var p: Dictionary = w.comp(cart, "Trade")["params"]
	var dist := FP.dist(w.entities[a]["pos"], w.entities[b]["pos"])
	return FP.from_data(float(p["gold_base"])) + FP.from_data(float(p["gold_per_tile"])) * dist / FP.SCALE


static func step(sim) -> void:
	var w = sim.world
	for cart in w.ids_with("Trade"):
		var t: Dictionary = w.comp(cart, "Trade")
		var st := str(t["state"])
		if st == "idle":
			continue
		var home: int = t["home"]
		var target: int = t["target"]
		if not _market_ok(sim, home) or int(w.entities[home]["owner"]) != int(w.entities[cart]["owner"]) \
				or trade_error(sim, cart, target) != "":
			stop(sim, cart) # mercado destruido o ahora enemigo
			continue
		if bool(w.comp(cart, "Move")["moving"]):
			continue
		var dest := target if st == "to_target" else home
		if GatherSystem._rect_dist(w.entities[cart]["pos"], GatherSystem._rect(sim, dest)) > REACH:
			stop(sim, cart) # inalcanzable
			continue
		if st == "to_target":
			t["carry"] = trip_gold(sim, cart, home, target)
			t["state"] = "to_home"
			_go(sim, cart, home)
		else:
			sim.add_res(int(w.entities[cart]["owner"]), "gold", int(t["carry"]))
			t["carry"] = 0
			t["state"] = "to_target"
			_go(sim, cart, target)
