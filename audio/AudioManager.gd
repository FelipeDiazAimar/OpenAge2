extends Node
## AudioManager — 100% procedural, sin archivos externos.
## Genera SFX con AudioStreamWAV sintetizado en código + música ambiente stub.
##
## Instalación como Autoload (añadir a project.godot):
##   AudioManager="*res://audio/AudioManager.gd"
##
## Uso:
##   AudioManager.play("click")
##   AudioManager.play_at("sword", global_position)
##   AudioManager.play_combat("sword", attacker_pos)  # con culling por distancia
##   AudioManager.toggle_music()
##   AudioManager.apply_settings()  # re-lee volúmenes de Settings si existe
##
## SFX disponibles: click, sword, arrow, build, bell, error, fanfare, coin
## Todo gratis: osciladores + ruido generados por código, sin assets.

class_name OpenAgeAudioManager

const SAMPLE_RATE: int = 22050
const POOL_2D: int = 8
const POOL_3D: int = 8

const SFX_NAMES: Array[String] = ["click", "sword", "arrow", "build", "bell", "error", "fanfare", "coin"]

# Volúmenes internos (0.0..1.0). Se sobrescriben con Settings si existe el autoload.
var master_volume: float = 1.0
var sfx_volume: float = 0.9
var music_volume: float = 0.6
var muted: bool = false
var music_enabled: bool = true

# Distancia máxima para audio 3D de combate (unidades de mundo).
var max_distance_3d: float = 60.0

var _sfx: Dictionary = {}          # String -> AudioStreamWAV
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _idx_2d: int = 0
var _idx_3d: int = 0
var _music_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234567 # determinista: mismo sonido en todas las máquinas
	_ensure_buses()
	_generate_all_sfx()
	_setup_pools()
	_setup_music()
	_connect_eventbus()
	apply_settings()
	if music_enabled:
		start_music()


# ---------------------------------------------------------------- buses ---
func _ensure_buses() -> void:
	# Crea buses SFX y Music si no existen, enrutados a Master.
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus(AudioServer.bus_count)
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.get_bus_index(bus_name), "Master")


func _bus_or_master(want: String) -> String:
	return want if AudioServer.get_bus_index(want) != -1 else "Master"


# ------------------------------------------------------- generación WAV ---
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size())
	for i in samples.size():
		var v: float = clampf(samples[i], -1.0, 1.0)
		data[i] = int(v * 120.0 + 128.0) as int & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _wav_loop(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := _wav(samples)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples.size()
	return wav


## Aplica fade-in/out corto para evitar clicks en bordes.
func _deflick(samples: PackedFloat32Array, fade_ms: float = 4.0) -> void:
	var n: int = int(SAMPLE_RATE * fade_ms / 1000.0)
	n = mini(n, samples.size() / 2)
	if n <= 0:
		return
	for i in n:
		var t: float = float(i) / float(n)
		samples[i] *= t
		samples[samples.size() - 1 - i] *= t


func _generate_all_sfx() -> void:
	_sfx["click"] = _gen_click()
	_sfx["sword"] = _gen_sword()
	_sfx["arrow"] = _gen_arrow()
	_sfx["build"] = _gen_build()
	_sfx["bell"] = _gen_bell()
	_sfx["error"] = _gen_error()
	_sfx["fanfare"] = _gen_fanfare()
	_sfx["coin"] = _gen_coin()


## click UI: blip corto 2 kHz con decay exponencial.
func _gen_click() -> AudioStreamWAV:
	var dur: float = 0.06
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 90.0)
		s[i] = sin(TAU * 2000.0 * t) * env * 0.7
	_deflick(s, 2.0)
	return _wav(s)


## espada clang: metálico = parciales inarmónicos + burst de ruido.
func _gen_sword() -> AudioStreamWAV:
	var dur: float = 0.35
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var partials: Array = [1244.0, 1866.0, 2607.0, 3415.0, 522.0]
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 14.0)
		var v: float = 0.0
		for p in partials:
			var f: float = p
			v += sin(TAU * f * t) * exp(-t * (6.0 + f * 0.004))
		v *= 0.22
		# burst de ruido al inicio (choque)
		if t < 0.03:
			v += (_rng.randf() * 2.0 - 1.0) * exp(-t * 160.0) * 0.5
		s[i] = v * env * 2.2
	_deflick(s)
	return _wav(s)


## flecha whoosh: ruido con barrido de amplitud sube-baja + tono descendente.
func _gen_arrow() -> AudioStreamWAV:
	var dur: float = 0.28
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var last: float = 0.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var k: float = float(i) / float(n) # 0..1
		# envolvente whoosh: ataque rápido, caída suave
		var env: float = sin(PI * pow(k, 0.7))
		var noise: float = _rng.randf() * 2.0 - 1.0
		# pasa-bajos simple cuyo corte "barre" hacia abajo
		var alpha: float = lerpf(0.5, 0.08, k)
		last = last + alpha * (noise - last)
		# silbido descendente 3000 -> 900 Hz mezclado bajo
		var sweep: float = sin(TAU * (3000.0 - 2100.0 * k) * t) * 0.15
		s[i] = (last * 1.4 + sweep) * env * 0.9
	_deflick(s)
	return _wav(s)


## construir golpe: thud grave 110 Hz + click de madera (ruido corto).
func _gen_build() -> AudioStreamWAV:
	var dur: float = 0.18
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var thud: float = sin(TAU * 110.0 * t) * exp(-t * 28.0)
		var knock: float = sin(TAU * 780.0 * t) * exp(-t * 90.0) * 0.4
		var grit: float = 0.0
		if t < 0.015:
			grit = (_rng.randf() * 2.0 - 1.0) * exp(-t * 300.0) * 0.6
		s[i] = (thud + knock + grit) * 0.9
	_deflick(s, 2.0)
	return _wav(s)


## campana de pueblo: fundamental + armónicos con decay largo.
func _gen_bell() -> AudioStreamWAV:
	var dur: float = 1.4
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var f0: float = 660.0
	var amps: Array = [1.0, 0.5, 0.3, 0.18, 0.1]
	var ratios: Array = [1.0, 2.02, 2.74, 3.76, 5.4]
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var v: float = 0.0
		for h in amps.size():
			v += sin(TAU * f0 * float(ratios[h]) * t) * float(amps[h]) * exp(-t * (2.2 + float(h) * 1.4))
		s[i] = v * 0.45
	_deflick(s, 6.0)
	return _wav(s)


## error: buzz cuadrado 180 Hz doble pulso.
func _gen_error() -> AudioStreamWAV:
	var dur: float = 0.32
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		# dos pulsos: 0-0.12s y 0.16-0.28s
		var gate: float = 1.0 if (t < 0.12 or (t >= 0.16 and t < 0.28)) else 0.0
		var sq: float = 1.0 if sin(TAU * 185.0 * t) > 0.0 else -1.0
		var sq2: float = 1.0 if sin(TAU * 92.0 * t) > 0.0 else -1.0
		s[i] = (sq * 0.35 + sq2 * 0.25) * gate
	_deflick(s, 5.0)
	return _wav(s)


## age-up fanfarria simple: arpegio Do-Mi-Sol-Do' con trompeta sintética.
func _gen_fanfare() -> AudioStreamWAV:
	var notes: Array[float] = [261.63, 329.63, 392.0, 523.25] # C4 E4 G4 C5
	var note_dur: float = 0.16
	var dur: float = note_dur * notes.size() + 0.45
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for ni in notes.size():
		var f: float = notes[ni]
		var start: int = int(ni * note_dur * SAMPLE_RATE)
		var len: int = int((note_dur + (0.45 if ni == notes.size() - 1 else 0.05)) * SAMPLE_RATE)
		for j in len:
			var idx: int = start + j
			if idx >= n:
				break
			var t: float = float(j) / SAMPLE_RATE
			var env: float = minf(1.0, t * 40.0) * exp(-t * (3.0 if ni == notes.size() - 1 else 6.0))
			# trompeta: sierra aproximada con 4 armónicos
			var v: float = sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.25 + sin(TAU * f * 3.0 * t) * 0.12 + sin(TAU * f * 4.0 * t) * 0.06
			s[idx] += v * env * 0.7
	_deflick(s, 6.0)
	return _wav(s)


## moneda: ding agudo de dos tonos (2450 -> 3250 Hz).
func _gen_coin() -> AudioStreamWAV:
	var dur: float = 0.22
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var f: float = 2450.0 if t < 0.08 else 3250.0
		var local_t: float = t if t < 0.08 else t - 0.08
		var v: float = sin(TAU * f * t) * exp(-local_t * 22.0)
		v += sin(TAU * f * 1.5 * t) * exp(-local_t * 30.0) * 0.3
		s[i] = v * 0.6
	_deflick(s, 2.0)
	return _wav(s)


# ------------------------------------------------- música ambiente (stub) ---
## Pad suave en loop: acorde Am (A2+E3+A3+C4+E4) con trémolo lento.
## Stub intencionado: dura 8 s en loop, sin percusión. Cambiar por
## pistas reales cuando haya assets libres.
func _gen_ambient_loop() -> AudioStreamWAV:
	var dur: float = 8.0
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var freqs: Array[float] = [110.0, 164.81, 220.0, 261.63, 329.63]
	var amps: Array[float] = [0.22, 0.18, 0.16, 0.12, 0.10]
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var v: float = 0.0
		for k in freqs.size():
			# fase ajustada para cerrar el loop sin click grueso
			v += sin(TAU * float(freqs[k]) * t) * float(amps[k])
		# trémolo lento (respiración)
		v *= 0.75 + 0.25 * sin(TAU * 0.125 * t)
		s[i] = v * 0.8
	# fade de 200 ms en bordes para loop limpio
	_deflick(s, 200.0)
	return _wav_loop(s)


func _setup_music() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = _bus_or_master("Music")
	_music_player.stream = _gen_ambient_loop()
	_music_player.volume_db = _vol_db(music_volume * master_volume)
	add_child(_music_player)


func start_music() -> void:
	if _music_player and not _music_player.playing:
		_music_player.play()
	music_enabled = true


func stop_music() -> void:
	if _music_player and _music_player.playing:
		_music_player.stop()
	music_enabled = false


func toggle_music() -> bool:
	if music_enabled:
		stop_music()
	else:
		start_music()
	return music_enabled


func set_music_enabled(on: bool) -> void:
	if on:
		start_music()
	else:
		stop_music()


# ------------------------------------------------------------- pools 2D/3D ---
func _setup_pools() -> void:
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.name = "SFX2D_%d" % i
		p.bus = _bus_or_master("SFX")
		add_child(p)
		_players_2d.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.name = "SFX3D_%d" % i
		p3.bus = _bus_or_master("SFX")
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		p3.unit_size = 8.0
		p3.max_distance = max_distance_3d
		add_child(p3)
		_players_3d.append(p3)


func _vol_db(linear: float) -> float:
	if muted or linear <= 0.001:
		return -60.0
	return linear_to_db(clampf(linear, 0.0, 1.0))


func _refresh_volumes() -> void:
	var v2d: float = _vol_db(sfx_volume * master_volume)
	for p in _players_2d:
		p.volume_db = v2d
	for p3 in _players_3d:
		# el 3D ya atenúa por distancia; aquí solo el volumen base
		p3.volume_db = v2d
	if _music_player:
		_music_player.volume_db = _vol_db(music_volume * master_volume)


# ------------------------------------------------------------------ API ---
func has_sfx(sfx_name: String) -> bool:
	return _sfx.has(sfx_name)


func sfx_list() -> Array[String]:
	return SFX_NAMES.duplicate()


## Reproduce un SFX en 2D (UI, avisos, fanfarrias).
func play(sfx_name: String, volume_scale: float = 1.0, pitch: float = 1.0) -> void:
	if not _sfx.has(sfx_name):
		push_warning("[AudioManager] SFX desconocido: %s" % sfx_name)
		return
	if muted:
		return
	var p: AudioStreamPlayer = _players_2d[_idx_2d]
	_idx_2d = (_idx_2d + 1) % POOL_2D
	p.stream = _sfx[sfx_name]
	p.volume_db = _vol_db(sfx_volume * master_volume * clampf(volume_scale, 0.0, 1.0))
	p.pitch_scale = pitch * _slight_pitch(sfx_name)
	p.play()


## Reproduce un SFX en una posición 3D del mundo (combate, construcción).
func play_at(sfx_name: String, world_pos: Vector3, volume_scale: float = 1.0, pitch: float = 1.0) -> void:
	if not _sfx.has(sfx_name):
		push_warning("[AudioManager] SFX desconocido: %s" % sfx_name)
		return
	if muted:
		return
	var p3: AudioStreamPlayer3D = _players_3d[_idx_3d]
	_idx_3d = (_idx_3d + 1) % POOL_3D
	p3.stream = _sfx[sfx_name]
	p3.max_distance = max_distance_3d
	p3.volume_db = _vol_db(sfx_volume * master_volume * clampf(volume_scale, 0.0, 1.0))
	p3.pitch_scale = pitch * _slight_pitch(sfx_name)
	# AudioManager suele ser autoload: igual fijamos posición global.
	if p3 is Node3D:
		(p3 as Node3D).global_position = world_pos
	p3.play()


## Combate con culling por distancia a la cámara: fuera de max_distance se ignora.
func play_combat(sfx_name: String, from_pos: Vector3, volume_scale: float = 1.0) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam != null:
		if cam.global_position.distance_to(from_pos) > max_distance_3d:
			return # demasiado lejos: silencio (ahorra voces)
	play_at(sfx_name, from_pos, volume_scale)


## Variación leve de pitch para que golpes repetidos no suenen robóticos.
func _slight_pitch(sfx_name: String) -> float:
	match sfx_name:
		"sword", "arrow", "build":
			return _rng.randf_range(0.94, 1.06)
		_:
			return 1.0


# Atajos legibles desde gameplay:
func play_click() -> void: play("click")
func play_sword(world_pos: Variant = null) -> void:
	if world_pos is Vector3: play_at("sword", world_pos)
	else: play("sword")
func play_arrow(world_pos: Variant = null) -> void:
	if world_pos is Vector3: play_at("arrow", world_pos)
	else: play("arrow")
func play_build(world_pos: Variant = null) -> void:
	if world_pos is Vector3: play_at("build", world_pos)
	else: play("build")
func play_bell() -> void: play("bell")
func play_error() -> void: play("error")
func play_fanfare() -> void: play("fanfare")
func play_coin() -> void: play("coin")


# ------------------------------------------------------- volumen/Settings ---
## Lee volúmenes del autoload Settings si existe; si no, conserva internos.
## Claves esperadas (todas opcionales): master_volume, sfx_volume,
## music_volume, muted, music_enabled, max_distance_3d.
func apply_settings() -> void:
	var s: Node = get_node_or_null("/root/Settings")
	if s != null:
		master_volume = _read_setting(s, "master_volume", master_volume)
		sfx_volume = _read_setting(s, "sfx_volume", sfx_volume)
		music_volume = _read_setting(s, "music_volume", music_volume)
		max_distance_3d = _read_setting(s, "max_distance_3d", max_distance_3d)
		var m: Variant = _read_setting(s, "muted", muted)
		muted = bool(m)
		var me: Variant = _read_setting(s, "music_enabled", music_enabled)
		music_enabled = bool(me)
		if music_enabled and not muted:
			start_music()
		elif not music_enabled or muted:
			if _music_player and _music_player.playing and (not music_enabled or muted):
				# si muteado, pausamos música pero recordamos preferencia
				_music_player.stop()
	_refresh_volumes()


func _read_setting(s: Node, key: String, fallback: Variant) -> Variant:
	# 1) método get_setting(key, default)
	if s.has_method("get_setting"):
		return s.call("get_setting", key, fallback)
	# 2) método get(key)
	if s.has_method("get"):
		var v: Variant = s.get(key)
		return fallback if v == null else v
	# 3) propiedad directa
	if key in s:
		return s.get(key)
	return fallback


func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	_write_setting("master_volume", master_volume)
	_refresh_volumes()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_write_setting("sfx_volume", sfx_volume)
	_refresh_volumes()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_write_setting("music_volume", music_volume)
	_refresh_volumes()


func set_muted(m: bool) -> void:
	muted = m
	_write_setting("muted", muted)
	if muted and _music_player:
		_music_player.stop()
	elif music_enabled and _music_player and not _music_player.playing:
		_music_player.play()
	_refresh_volumes()


func set_max_distance(d: float) -> void:
	max_distance_3d = maxf(5.0, d)
	_write_setting("max_distance_3d", max_distance_3d)
	for p3 in _players_3d:
		p3.max_distance = max_distance_3d


func _write_setting(key: String, value: Variant) -> void:
	var s: Node = get_node_or_null("/root/Settings")
	if s == null:
		return
	if s.has_method("set_setting"):
		s.call("set_setting", key, value)
	elif s.has_method("set"):
		s.set(key, value)


# ------------------------------------------------------- EventBus (auto) ---
func _connect_eventbus() -> void:
	var eb: Node = get_node_or_null("/root/EventBus")
	if eb == null:
		return
	# Conexiones defensivas: solo si la señal existe.
	if eb.has_signal("building_placed"):
		eb.connect("building_placed", _on_building_placed)
	if eb.has_signal("age_up"):
		eb.connect("age_up", _on_age_up)
	if eb.has_signal("unit_died"):
		eb.connect("unit_died", _on_unit_died)


func _on_building_placed(_player_id: int, _building: String, pos: Vector3) -> void:
	play_at("build", pos)


func _on_age_up(_player_id: int, _new_age: String) -> void:
	play("fanfare")
	play("bell", 0.7)


func _on_unit_died(_unit_id: int, _killer_id: int) -> void:
	play("sword", 0.5, 0.9)
