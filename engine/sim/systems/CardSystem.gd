extends RefCounted
## Cartas de envío: cobra coste, da res.* o parchea defs del jugador.
const FP := preload("res://engine/sim/FixedPoint.gd")
const DV := preload("res://game/cards/DeckValidator.gd")
const RES := {"madera": "wood", "alimento": "food", "oro": "gold", "piedra": "stone", "wood": "wood", "food": "food", "gold": "gold", "stone": "stone"}
static func play_card(sim, pid: int, card_id: String) -> String:
	var card := find_card(card_id)
	if card.is_empty(): return "carta desconocida: %s" % card_id
	if pid < 0 or pid >= sim.players.size(): return "jugador inválido"
	if sim.age_of(pid) + 1 < int(card.get("age", 1)): return "edad insuficiente"
	var cost := cost_en(card.get("cost", {}))
	if not sim.can_afford(pid, cost): return "recursos insuficientes"
	sim.pay(pid, cost)
	var e: Dictionary = card.get("effect", {})
	if e.is_empty(): return ""
	if str(e.get("path", "")).begins_with("res."):
		sim.add_res(pid, res_key(str(e["path"])), FP.from_data(float(e.get("value", 0))))
		return ""
	var errs: Array = sim.players[pid]["defs"].apply_effects([e])
	sim.refresh_caches(pid)
	return "; ".join(PackedStringArray(errs))
static func find_card(card_id: String) -> Dictionary:
	for c in DV.load_all_cards():
		if c is Dictionary and str((c as Dictionary).get("id", "")) == card_id: return c
	return {}
static func cost_en(cost: Variant) -> Dictionary:
	var out := {}
	for k in (cost as Dictionary):
		out[str(RES.get(str(k), str(k)))] = float((cost as Dictionary)[k])
	return out
static func res_key(path: String) -> String:
	var raw := path.get_slice(".", 1).strip_edges().to_lower()
	return str(RES.get(raw, raw))
