extends Node
# CavalryTrade - bonus caballería vs arqueros + fórmula oro comercio (AoE2 1:1).
# Determinista: sin randf/randi/Time/física. Lectura de data/actions.json trade.
# Usado por Combat (bonus_vs) y FarmingTrade/Economy (oro por viaje).
#
# Reglas:
#   - Caballería (scout, jinete, paladin, catafracta, paladin_franco):
#     +3 vs arquero (además del bonus_vs propio del JSON).
#   - Catafracta (única bizantinos): +9 vs infantería (milicia/piquero/infanteria).
#   - Comercio: oro = gold_per_trip_base + bonus_per_tile * distancia_tiles.
#     Defaults de data/actions.json: base 20, bonus 0.3.
#     Solo cobra entre mercados aliados (ver FarmingTrade.are_allied).

const ACTIONS_PATH := "res://data/actions.json"
const CAVALRY_KINDS: Array[String] = ["scout", "jinete", "paladin", "catafracta", "paladin_franco"]
const ARCHER_KINDS: Array[String] = ["arquero"]
const INFANTRY_KINDS: Array[String] = ["milicia", "piquero", "infanteria"]

const BONUS_CAV_VS_ARCHER := 3.0
const BONUS_CATAFRACTA_VS_INF := 9.0

var trade_base := 20.0
var trade_bonus_per_tile := 0.3


func _ready() -> void:
	_load_trade_rates()


func _load_trade_rates() -> void:
	if not FileAccess.file_exists(ACTIONS_PATH):
		return
	var f := FileAccess.open(ACTIONS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var trade: Dictionary = (parsed as Dictionary).get("actions", {}).get("trade", {})
	trade_base = float(trade.get("gold_per_trip_base", trade_base))
	trade_bonus_per_tile = float(trade.get("bonus_per_tile", trade_bonus_per_tile))


# --- Bonus caballería ---

static func is_cavalry(kind: String) -> bool:
	return kind.to_lower().strip_edges() in CAVALRY_KINDS


static func is_archer(kind: String) -> bool:
	return kind.to_lower().strip_edges() in ARCHER_KINDS


static func is_infantry(kind: String) -> bool:
	return kind.to_lower().strip_edges() in INFANTRY_KINDS


## Bonus extra (suma al bonus_vs del JSON + calc_damage de Combat).
## attacker/target: dicts con "kind"/"cls" o strings directos.
static func cavalry_bonus_vs(attacker_kind: String, target_kind: String) -> float:
	var a := attacker_kind.to_lower().strip_edges()
	var t := target_kind.to_lower().strip_edges()
	var bonus := 0.0
	if a in CAVALRY_KINDS and t in ARCHER_KINDS:
		bonus += BONUS_CAV_VS_ARCHER
	if a == "catafracta" and t in INFANTRY_KINDS:
		bonus += BONUS_CATAFRACTA_VS_INF
	return bonus


## Versión dict (compatible con Combat.bonus_vs_target): suma bonus caballería
## al bonus ya calculado desde el JSON.
static func bonus_total(attacker: Dictionary, target: Dictionary, base_bonus: float = 0.0) -> float:
	var ak := str(attacker.get("armor_class", attacker.get("cls", attacker.get("kind", "")))).to_lower()
	var tk := str(target.get("armor_class", target.get("cls", target.get("kind", "")))).to_lower()
	var kind_a := str(attacker.get("kind", ak)).to_lower().strip_edges()
	var kind_t := str(target.get("kind", tk)).to_lower().strip_edges()
	# Si armor_class es caballeria/arquero/infanteria también cuenta.
	var b := base_bonus
	if (kind_a in CAVALRY_KINDS or ak == "caballeria") and (kind_t in ARCHER_KINDS or tk == "arquero"):
		b += BONUS_CAV_VS_ARCHER
	if (kind_a == "catafracta") and (kind_t in INFANTRY_KINDS or tk == "infanteria"):
		# Evita doble conteo si el JSON ya trae el +9: solo suma si base < 9.
		if base_bonus < BONUS_CATAFRACTA_VS_INF:
			b += BONUS_CATAFRACTA_VS_INF - minf(base_bonus, BONUS_CATAFRACTA_VS_INF)
	return b


# --- Comercio oro ---

static func distance_tiles(a: Vector2, b: Vector2) -> float:
	return (a - b).length()


## Fórmula AoE2: oro = base + bonus * distancia. Redondeo a milésima (lockstep).
static func trade_gold_for_distance(dist_tiles: float, base: float = 20.0, bonus_per_tile: float = 0.3) -> float:
	return snappedf(base + bonus_per_tile * maxf(0.0, dist_tiles), 0.001)


func trade_gold_for_trip(from_pos: Vector2, to_pos: Vector2) -> float:
	return trade_gold_for_distance(distance_tiles(from_pos, to_pos), trade_base, trade_bonus_per_tile)
