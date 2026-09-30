extends RefCounted
## Arma la simulación de una partida del motor nuevo (jugadores, centro
## urbano, aldeanos, explorador y mapa) a partir de sus opciones. La usan la
## partida (Match) y la repetición de registros (tools/replay_log.gd): así
## ambas parten exactamente del mismo estado.

const Sim := preload("res://engine/sim/Sim.gd")
const MapGen := preload("res://engine/sim/MapGen.gd")

const MAP_SIZE := 144
const START_OFFSETS: Array[Vector2i] = [
	Vector2i(-33, -33), Vector2i(33, 33), Vector2i(33, -33), Vector2i(-33, 33),
	Vector2i(0, -46), Vector2i(0, 46), Vector2i(-46, 0), Vector2i(46, 0),
]
const VILLAGER_OFFSETS: Array[Vector2i] = [Vector2i(3, -1), Vector2i(-1, 3), Vector2i(3, 3)]
const SCOUT_OFFSET := Vector2i(-4, -1)


static func start_tile(pid: int, map_size: int = MAP_SIZE) -> Vector2i:
	return Vector2i(map_size / 2, map_size / 2) + START_OFFSETS[pid % START_OFFSETS.size()]


## cfg: {slots: [{civ, team, ai}], map_seed, pop_max, lake}
static func build(registry, cfg: Dictionary) -> Sim:
	var slots: Array = cfg["slots"]
	var sim := Sim.new(registry, MAP_SIZE, MAP_SIZE)
	sim.debug_enabled = true # partida local: tropas de prueba con F9
	sim.pop_max = int(cfg.get("pop_max", 0))
	for i in slots.size():
		sim.add_player(i, str(slots[i]["civ"]), int(slots[i]["team"]))
	for i in sim.players.size():
		var c := start_tile(i)
		sim.spawn("centro_urbano", i, c - Vector2i(2, 2))
		for off in VILLAGER_OFFSETS:
			sim.spawn("aldeano", i, c + off)
		sim.spawn("scout", i, c + SCOUT_OFFSET)
	var starts: Array[Vector2i] = []
	for i in sim.players.size():
		starts.append(start_tile(i))
	MapGen.generate(sim, int(cfg.get("map_seed", 1234)), starts, bool(cfg.get("lake", true)))
	return sim
