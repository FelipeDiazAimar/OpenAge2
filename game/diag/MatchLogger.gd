extends Node
## Registro de diagnóstico de una partida (solo cliente, no toca la simulación).
##
## Escribe user://logs/partidas/partida_<fecha>.log, una línea JSON por
## evento, con flush inmediato: sobrevive a un cierre inesperado (si falta la
## línea "fin", la partida terminó mal). Contiene:
##  - inicio: versión, Godot, SO, GPU, pantalla y opciones de la partida
##    (civs, equipos, IA, semilla, lago, tope) -> la partida se puede rearmar.
##  - cmd: cada orden encolada (jugador o IA) con su tick -> con la semilla y
##    las órdenes, tools/replay_log.gd reproduce la partida exacta.
##  - pulso: cada PULSE_TICKS, huella del estado (state_hash), población,
##    recursos, entidades, FPS, peor frame y costo de simulación/IA.
##  - lento: frames que tardaron más de SLOW_FRAME_MS (y en qué fase).
##  - congelado / descongelado: el vigilante (otro hilo) ve que el juego no
##    dibuja un frame hace más de FREEZE_MS; anota fase y tick.
##  - anomalia: cosas que no deberían pasar (recursos negativos, unidades
##    sobre agua o muros, barcos en tierra, obras pasadas de 100 %...).
##  - error: líneas ERROR / SCRIPT ERROR que Godot escribió en su log.
##  - marca: el jugador apretó F12 (con captura de pantalla).
##  - fin: cierre normal.

const DIR := "user://logs/partidas"
const GODOT_LOG := "user://logs/godot.log"
const KEEP := 30 # registros que se conservan
const PULSE_TICKS := 100 # 10 s de juego
const SLOW_FRAME_MS := 300
const FREEZE_MS := 2500
const MAX_PER_KIND := 20 # anomalías del mismo tipo que se anotan

var path := ""
## Carpeta de registros (las pruebas usan otra).
var dir := DIR
var sim
var local_pid := 0
var ai_pids: Array = []
## Fase del cliente (la del motor se lee de sim.phase_id).
var phase := "inicio"

var _file: FileAccess
var _mutex := Mutex.new()
var _thread: Thread
var _running := false
var _last_beat_ms := 0
var _frozen_since := 0
var _frames := 0
var _worst_frame_ms := 0.0
var _fps_acc := 0.0
var _sim_us := 0
var _ai_us := 0
var _kinds: Dictionary = {}
var _moving_since: Dictionary = {} # id -> [pos, tick] para unidades trabadas
var _godot_log_pos := -1
var _marks := 0
var freeze_ms := FREEZE_MS
## El vigilante empieza tras los primeros frames (la carga inicial no cuenta).
const ARM_FRAMES := 30
var _total_frames := 0
var _armed := false


## Abre el registro y escribe el encabezado. cfg = opciones de la partida.
func start(p_sim, cfg: Dictionary, p_local: int, p_ai_pids: Array, registry = null) -> void:
	sim = p_sim
	local_pid = p_local
	ai_pids = p_ai_pids.duplicate()
	DirAccess.make_dir_recursive_absolute(dir)
	_rotate()
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	path = "%s/partida_%s_%03d.log" % [dir, stamp, Time.get_ticks_msec() % 1000]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("MatchLogger: no se pudo abrir %s" % path)
		return
	var info := {
		"t": "inicio",
		"juego": str(ProjectSettings.get_setting("application/config/name", "")),
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"commit": _commit(),
		"godot": Engine.get_version_info().get("string", ""),
		"so": OS.get_name() + " " + OS.get_version(),
		"cpu": OS.get_processor_name(),
		"nucleos": OS.get_processor_count(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"pantalla": str(DisplayServer.screen_get_size()),
		"ventana": str(DisplayServer.window_get_size()),
		"exportado": OS.has_feature("template"),
		"fecha": Time.get_datetime_string_from_system(),
		"cfg": cfg,
		"jugador_local": local_pid,
		"ias": ai_pids,
		"content_hash": registry.content_hash if registry != null and "content_hash" in registry else "",
	}
	_write(info)
	sim.on_command = _on_command
	_godot_log_pos = _godot_log_size()
	_last_beat_ms = Time.get_ticks_msec()
	_running = true
	_thread = Thread.new()
	_thread.start(_watchdog)
	print("[registro] partida en ", ProjectSettings.globalize_path(path))


func _commit() -> String:
	var f := FileAccess.open("res://version_commit.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else ""


func _write(d: Dictionary) -> void:
	_mutex.lock()
	if _file != null:
		_file.store_line(JSON.stringify(d))
		_file.flush()
	_mutex.unlock()


func _on_command(tick: int, pid: int, type: String, payload: Dictionary) -> void:
	_write({"t": "cmd", "tick": tick, "pid": pid, "src": "ia" if ai_pids.has(pid) else "jugador",
		"type": type, "payload": payload})


## Cada frame (desde Match._process): latido para el vigilante y tiempos.
func frame(delta: float) -> void:
	var ms := delta * 1000.0
	_total_frames += 1
	_mutex.lock()
	_last_beat_ms = Time.get_ticks_msec()
	_armed = _total_frames >= ARM_FRAMES
	var was_frozen := _frozen_since
	_frozen_since = 0
	_mutex.unlock()
	if was_frozen > 0:
		_write({"t": "descongelado", "tick": _tick(), "duro_ms": Time.get_ticks_msec() - was_frozen})
	_frames += 1
	_fps_acc += delta
	_worst_frame_ms = maxf(_worst_frame_ms, ms)
	if ms > SLOW_FRAME_MS and _frames > 5:
		_note("lento", {"ms": int(ms), "fase": phase})


## Después de cada tick de simulación, con lo que tardaron sim e IA (µs).
func after_tick(sim_us: int, ai_us: int) -> void:
	_sim_us += sim_us
	_ai_us += ai_us
	var t := _tick()
	if t % PULSE_TICKS != 0:
		return
	var pops := []
	var res := []
	for p in sim.players:
		pops.append(str(sim.population(int(p["id"]))))
		res.append(sim.res_of(int(p["id"])))
	_write({
		"t": "pulso", "tick": t, "hash": sim.state_hash(),
		"entidades": sim.world.entities.size(), "proyectiles": sim.projectiles.size(),
		"poblacion": pops, "recursos": res,
		"fps": int(_frames / maxf(_fps_acc, 0.001)), "peor_frame_ms": int(_worst_frame_ms),
		"sim_ms_por_tick": snappedf(_sim_us / 1000.0 / PULSE_TICKS, 0.01),
		"ia_ms_por_tick": snappedf(_ai_us / 1000.0 / PULSE_TICKS, 0.01),
		"memoria_mb": int(OS.get_static_memory_usage() / 1048576),
	})
	_frames = 0
	_fps_acc = 0.0
	_worst_frame_ms = 0.0
	_sim_us = 0
	_ai_us = 0
	check_invariants()
	_copy_godot_errors()


func _tick() -> int:
	return int(sim.world.tick) if sim != null else -1


## Anota una anomalía (como mucho MAX_PER_KIND por tipo).
func _note(kind: String, data: Dictionary) -> void:
	var n := int(_kinds.get(kind, 0)) + 1
	_kinds[kind] = n
	if n > MAX_PER_KIND:
		return
	var d := {"t": "anomalia" if kind != "lento" else "lento", "que": kind, "tick": _tick()}
	d.merge(data)
	if n == MAX_PER_KIND:
		d["nota"] = "no se anotan más de este tipo"
	_write(d)


## Cosas que no deberían pasar nunca (se revisan en cada pulso).
func check_invariants() -> void:
	var w = sim.world
	for p in sim.players:
		for k in ["wood", "food", "gold", "stone"]:
			if int(p["res"][k]) < 0:
				_note("recurso_negativo", {"jugador": p["id"], "recurso": k, "valor": int(p["res"][k])})
	var gw: int = sim.grid.width
	var gh: int = sim.grid.height
	for id in w.ids_with("Hitpoints"):
		var e: Dictionary = w.entities[id]
		var pos: Vector2i = e["pos"]
		var t := Vector2i(floori(pos.x / 1000.0), floori(pos.y / 1000.0))
		if t.x < 0 or t.y < 0 or t.x >= gw or t.y >= gh:
			_note("fuera_del_mapa", {"id": id, "def": e["def_id"], "pos": str(pos)})
			continue
		if str(e["type"]) != "unit" or not w.has_ability(id, "Move"):
			continue
		var g: Dictionary = w.comp(id, "Garrisoned")
		if not g.is_empty() and bool(g["inside"]):
			continue
		var naval: bool = w.has_ability(id, "Naval")
		if naval and not sim.grid.is_water(t):
			_note("barco_en_tierra", {"id": id, "def": e["def_id"], "casilla": str(t)})
		elif not naval and not sim.grid.is_walkable(t):
			_note("unidad_en_casilla_bloqueada", {"id": id, "def": e["def_id"], "casilla": str(t),
				"agua": sim.grid.is_water(t)})
		# Trabada: dice que se mueve pero no avanzó en 2 pulsos (20 s).
		var m: Dictionary = w.comp(id, "Move")
		if bool(m["moving"]):
			var prev: Array = _moving_since.get(id, [])
			if not prev.is_empty() and prev[0] == pos and _tick() - int(prev[1]) >= 2 * PULSE_TICKS:
				_note("unidad_trabada", {"id": id, "def": e["def_id"], "pos": str(pos), "desde_tick": prev[1]})
				_moving_since[id] = [pos, _tick()]
			elif prev.is_empty() or prev[0] != pos:
				_moving_since[id] = [pos, _tick()]
		else:
			_moving_since.erase(id)
	for f in w.ids_with("Foundation"):
		var fd: Dictionary = w.comp(f, "Foundation")
		if int(fd["progress"]) > int(fd["total"]):
			_note("obra_pasada", {"id": f, "progreso": fd["progress"], "total": fd["total"]})
	for b in w.ids_with("Garrison"):
		for u in w.comp(b, "Garrison")["units"]:
			if not w.entities.has(u):
				_note("guarnicion_fantasma", {"edificio": b, "unidad": u})


## Copia al registro los errores nuevos que Godot escribió en su log.
func _copy_godot_errors() -> void:
	if _godot_log_pos < 0 or not FileAccess.file_exists(GODOT_LOG):
		return
	var f := FileAccess.open(GODOT_LOG, FileAccess.READ)
	if f == null:
		return
	var size := f.get_length()
	if size < _godot_log_pos:
		_godot_log_pos = 0 # rotó
	f.seek(_godot_log_pos)
	var text := f.get_buffer(size - _godot_log_pos).get_string_from_utf8()
	_godot_log_pos = size
	var lines := text.split("\n")
	for i in lines.size():
		var l := lines[i]
		if l.contains("ERROR") or l.contains("SCRIPT ERROR"):
			var where := lines[i + 1].strip_edges() if i + 1 < lines.size() else ""
			_note("error_godot", {"linea": l.strip_edges(), "donde": where})


func _godot_log_size() -> int:
	var f := FileAccess.open(GODOT_LOG, FileAccess.READ)
	return f.get_length() if f != null else -1


## F12: el jugador marca "acá pasó algo raro" (con captura).
func mark(viewport: Viewport, note: String = "") -> String:
	_marks += 1
	var shot := path.trim_suffix(".log") + "_marca%d.png" % _marks
	if viewport != null:
		var img := viewport.get_texture().get_image()
		if img != null:
			img.save_png(shot)
	_write({"t": "marca", "tick": _tick(), "captura": shot.get_file(), "nota": note, "fase": phase})
	return shot


## Vigilante (otro hilo): si el juego no dibuja un frame hace FREEZE_MS,
## anota el congelamiento con la fase en la que quedó.
func _watchdog() -> void:
	while true:
		OS.delay_msec(200)
		_mutex.lock()
		var running := _running
		var armed := _armed
		var since := Time.get_ticks_msec() - _last_beat_ms
		var already := _frozen_since
		_mutex.unlock()
		if not running:
			return
		if armed and since > freeze_ms and already == 0:
			_mutex.lock()
			_frozen_since = _last_beat_ms
			_mutex.unlock()
			var eng := ""
			if sim != null and int(sim.phase_id) < sim.PHASES.size():
				eng = str(sim.PHASES[int(sim.phase_id)])
			_write({"t": "congelado", "sin_frame_ms": since, "fase_cliente": phase, "fase_motor": eng,
				"tick": _tick()})


## Cierre normal (si falta en el archivo, la partida se cortó).
func finish(reason: String = "salida normal") -> void:
	if _file == null:
		return
	_mutex.lock()
	_running = false
	_mutex.unlock()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_copy_godot_errors()
	_write({"t": "fin", "motivo": reason, "tick": _tick()})
	_mutex.lock()
	_file.close()
	_file = null
	_mutex.unlock()
	if sim != null:
		sim.on_command = Callable()


func _exit_tree() -> void:
	finish("partida cerrada")


## Deja solo los KEEP registros más nuevos (y sus capturas).
func _rotate() -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	var logs: Array = []
	for f in d.get_files():
		if f.begins_with("partida_") and f.ends_with(".log"):
			logs.append(f)
	logs.sort()
	while logs.size() >= KEEP:
		var old: String = logs.pop_front()
		d.remove(old)
		for f in d.get_files():
			if f.begins_with(old.trim_suffix(".log") + "_marca"):
				d.remove(f)
