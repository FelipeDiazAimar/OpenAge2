extends SceneTree
## Repite una partida desde su registro (game/diag/MatchLogger) y resume lo
## que pasó. Uso:
##   godot --headless --path . -s tools/replay_log.gd -- <registro.log> [--hasta=TICK] [--estado]
##
## Rearma la partida con la misma semilla y opciones (game/MatchSetup) y le da
## las mismas órdenes en los mismos ticks. Como la simulación es determinista,
## la huella (state_hash) de cada pulso debe coincidir: si no coincide, el
## motor cambió o hay no-determinismo (se informa el primer tick distinto).
## --estado imprime al final un resumen de entidades por jugador.

const Registry := preload("res://engine/data/Registry.gd")
const MatchSetup := preload("res://game/MatchSetup.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("uso: -s tools/replay_log.gd -- <registro.log> [--hasta=TICK] [--estado]")
		quit(2)
		return
	var until := -1
	var dump := false
	for a in args.slice(1):
		if str(a).begins_with("--hasta="):
			until = int(str(a).get_slice("=", 1))
		elif str(a) == "--estado":
			dump = true
	quit(run(str(args[0]), until, dump))


## Devuelve 0 si la repetición coincide con el registro, 1 si diverge.
static func run(path: String, until: int = -1, dump: bool = false) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("no se pudo abrir ", path)
		return 2
	var header := {}
	var cmds := {} # tick -> [cmd]
	var pulses := {} # tick -> hash
	var events: Array = []
	var last := 0
	var ended := false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var d = JSON.parse_string(line)
		if not (d is Dictionary):
			continue
		match str(d.get("t", "")):
			"inicio":
				header = d
			"cmd":
				var t := int(d["tick"])
				if not cmds.has(t):
					cmds[t] = []
				cmds[t].append(d)
				last = maxi(last, t)
			"pulso":
				pulses[int(d["tick"])] = str(d["hash"])
				last = maxi(last, int(d["tick"]))
			"fin":
				ended = true
				events.append(d)
				last = maxi(last, int(d.get("tick", 0)))
			_:
				events.append(d)
				last = maxi(last, int(d.get("tick", 0)))
	if header.is_empty():
		print("registro sin encabezado")
		return 2
	print("== Partida: ", header.get("fecha", "?"), "  commit ", header.get("commit", "?"), "  exportado=", header.get("exportado", "?"))
	print("   PC: ", header.get("so", ""), " | ", header.get("cpu", ""), " | ", header.get("gpu", ""))
	print("   opciones: ", JSON.stringify(header.get("cfg", {})))
	print("   ", _count(cmds), " órdenes, ", pulses.size(), " pulsos, último tick ", last,
		"  ", "(cerró bien)" if ended else "(NO CERRÓ: se cortó o se colgó)")
	for e in events:
		if str(e.get("t", "")) in ["anomalia", "congelado", "descongelado", "marca", "lento", "fin"]:
			print("   · ", JSON.stringify(e))
	var r := Registry.new()
	r.load_mods("res://mods")
	if str(header.get("content_hash", "")) != "" and r.content_hash != str(header["content_hash"]):
		print("   AVISO: los datos (mods) cambiaron desde la partida; la repetición puede divergir")
	var cfg: Dictionary = header["cfg"]
	var sim = MatchSetup.build(r, cfg)
	var stop := last if until < 0 else mini(until, last)
	var ok := 0
	var bad := -1
	while int(sim.world.tick) < stop:
		for c in cmds.get(int(sim.world.tick), []):
			sim.queue_command(int(c["pid"]), str(c["type"]), c["payload"])
		sim.step()
		var t := int(sim.world.tick)
		if pulses.has(t):
			if sim.state_hash() == pulses[t]:
				ok += 1
			elif bad < 0:
				bad = t
	if bad >= 0:
		print("== DIVERGE en el tick ", bad, " (", ok, " pulsos coinciden antes)")
	else:
		print("== Repetición idéntica hasta el tick ", stop, " (", ok, " pulsos coinciden)")
	if dump:
		_dump(sim)
	return 0 if bad < 0 else 1


static func _count(cmds: Dictionary) -> int:
	var n := 0
	for t in cmds:
		n += (cmds[t] as Array).size()
	return n


static func _dump(sim) -> void:
	for p in sim.players:
		var pid := int(p["id"])
		var kinds := {}
		for id in sim.world.ids_with("Hitpoints"):
			var e: Dictionary = sim.world.entities[id]
			if int(e["owner"]) == pid:
				kinds[e["def_id"]] = int(kinds.get(e["def_id"], 0)) + 1
		print("   jugador ", pid, " (", p["civ"], ") edad ", sim.age_of(pid), " pob ", sim.population(pid),
			" recursos ", sim.res_of(pid), " -> ", kinds)
