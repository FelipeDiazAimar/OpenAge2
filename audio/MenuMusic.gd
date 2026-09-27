extends Node
## MenuMusic — fanfarria + ambiente medieval 100% procedural, sin archivos externos.
##
## Qué hace:
##   Fanfarria corta de menú y bucle ambiente modal (dórico en Re) con laúd
##   aproximado (armónicos + envolvente punteada), todo con AudioStreamWAV
##   generado por código. Sin assets de pago ni ficheros de audio.
##
## Integración con AudioManager (no lo modifica, solo lo usa si existe):
##   Al arrancar pausa su pad ambiente con stop_music() para no duplicar
##   músicas y lo reanuda al hacer stop(). Respeta sus volúmenes
##   (music_volume / master_volume / muted) y el bus "Music".
##   Para SFX de UI en el menú sigue usando AudioManager.play("click") y
##   AudioManager.play_at("sword", pos) en 3D; el toggle global sigue siendo
##   AudioManager.toggle_music().
##
## Instalación como Autoload (NO editar project.godot desde aquí; añadir a mano
## bajo [autoload], DESPUÉS de AudioManager para que lo encuentre en /root):
##   MenuMusic="*res://audio/MenuMusic.gd"
## Uso:
##   MenuMusic.start_menu_music()
##   MenuMusic.enter_match_duck()  # baja volumen al entrar en partida, sin corte
##   MenuMusic.restore_menu_level()
##   MenuMusic.stop()
##
## Godot 4.4, GDScript con tabs, comentarios en español.

const SAMPLE_RATE: int = 22050
const BUS_NAME: String = "Music"

# Volumen propio 0..1; se combina con el de AudioManager si existe.
var music_volume: float = 0.6
# Factor de ducking 0..1 aplicado sobre el volumen base.
var _duck_factor: float = 1.0
var _am_music_was_on: bool = false

var _fanfare_stream: AudioStreamWAV
var _ambient_stream: AudioStreamWAV
var _fanfare_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _fade_tween: Tween


func _ready() -> void:
	# Persiste entre menú y partida; el ducking decide el nivel.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fanfare_stream = _gen_menu_fanfare()
	_ambient_stream = _gen_modal_loop()
	_setup_players()
	_apply_volume(true)


func _setup_players() -> void:
	_fanfare_player = AudioStreamPlayer.new()
	_fanfare_player.name = "MenuFanfare"
	_fanfare_player.bus = _bus_or_master(BUS_NAME)
	_fanfare_player.stream = _fanfare_stream
	add_child(_fanfare_player)
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MenuAmbient"
	_music_player.bus = _bus_or_master(BUS_NAME)
	_music_player.stream = _ambient_stream
	add_child(_music_player)


func _bus_or_master(want: String) -> String:
	if AudioServer.get_bus_index(want) != -1:
		return want
	return "Master"


# ------------------------------------------------------- API pública ---
## Arranca fanfarria + ambiente de menú. Pausa el pad de AudioManager.
func start_menu_music() -> void:
	_duck_factor = 1.0
	_silence_competing_ambient()
	_apply_volume(true)
	if _music_player and not _music_player.playing:
		_music_player.play()
	if _fanfare_player:
		_fanfare_player.play()


## Detiene todo con fundido corto y reanuda el ambiente de AudioManager.
func stop(fade_sec: float = 0.8) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_fade_tween.tween_property(_music_player, "volume_db", -60.0, maxf(0.05, fade_sec))
	_fade_tween.tween_callback(_stop_players_and_restore)


## Ducking al entrar en partida: baja volumen sin cortar de golpe.
func enter_match_duck(target_factor: float = 0.25, fade_sec: float = 1.5) -> void:
	_duck_factor = clampf(target_factor, 0.05, 1.0)
	_fade_to_current_level(maxf(0.1, fade_sec))


## Vuelve al nivel de menú (tras ducking).
func restore_menu_level(fade_sec: float = 1.0) -> void:
	_duck_factor = 1.0
	_fade_to_current_level(maxf(0.1, fade_sec))


## Volumen propio 0..1 (se combina con AudioManager si existe).
func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_fade_to_current_level(0.2)


func is_playing() -> bool:
	return _music_player != null and _music_player.playing


func _stop_players_and_restore() -> void:
	if _fanfare_player and _fanfare_player.playing:
		_fanfare_player.stop()
	if _music_player and _music_player.playing:
		_music_player.stop()
	_restore_competing_ambient()


# --------------------------------------- integración AudioManager ---
func _audio_manager() -> Node:
	return get_node_or_null("/root/AudioManager")


## Pausa el pad de AudioManager para no solapar dos músicas.
func _silence_competing_ambient() -> void:
	var am: Node = _audio_manager()
	if am == null:
		return
	if "music_enabled" in am:
		_am_music_was_on = bool(am.get("music_enabled"))
	else:
		_am_music_was_on = true
	if am.has_method("stop_music"):
		am.call("stop_music")
		# stop_music apaga el flag; lo dejamos como estaba para restaurar luego.
		if "music_enabled" in am:
			am.set("music_enabled", _am_music_was_on)


func _restore_competing_ambient() -> void:
	var am: Node = _audio_manager()
	if am == null:
		return
	if not _am_music_was_on:
		return
	if am.has_method("start_music"):
		am.call("start_music")


func _effective_linear() -> float:
	var lin: float = music_volume * _duck_factor
	var am: Node = _audio_manager()
	if am != null:
		# Respeta volúmenes y mute globales sin modificar AudioManager.
		var am_music: float = float(am.get("music_volume")) if "music_volume" in am else 1.0
		var am_master: float = float(am.get("master_volume")) if "master_volume" in am else 1.0
		lin *= am_music * am_master
		if ("muted" in am and bool(am.get("muted"))):
			return 0.0
		if ("music_enabled" in am and not bool(am.get("music_enabled"))):
			# El usuario apagó la música global: MenuMusic también enmudece.
			pass
	return clampf(lin, 0.0, 1.0)


func _vol_db(linear: float) -> float:
	if linear <= 0.001:
		return -60.0
	return linear_to_db(clampf(linear, 0.0, 1.0))


func _apply_volume(instant: bool = false) -> void:
	if _music_player == null:
		return
	_music_player.volume_db = _vol_db(_effective_linear())
	if _fanfare_player != null:
		_fanfare_player.volume_db = _vol_db(_effective_linear())


func _fade_to_current_level(fade_sec: float) -> void:
	if _music_player == null:
		return
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_fade_tween.tween_property(_music_player, "volume_db", _vol_db(_effective_linear()), fade_sec)
	# La fanfarria es puntual: se deja al nivel actual sin fundido largo.
	if _fanfare_player != null:
		_fanfare_player.volume_db = _vol_db(_effective_linear())


# ------------------------------------------------------- síntesis WAV ---
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


## Fundido corto en bordes para evitar clicks; en loops usar ~200 ms.
func _deflick(samples: PackedFloat32Array, fade_ms: float = 4.0) -> void:
	var n: int = int(SAMPLE_RATE * fade_ms / 1000.0)
	n = mini(n, samples.size() / 2)
	if n <= 0:
		return
	for i in n:
		var t: float = float(i) / float(n)
		samples[i] *= t
		samples[samples.size() - 1 - i] *= t


## Laúd aproximado: cuerda pulsada con armónicos que decaen desigual.
func _pluck(freq: float, t: float) -> float:
	# Ataque rápido + caída exponencial típica de púa sobre tripa.
	var env: float = minf(1.0, t * 220.0) * exp(-t * 5.5)
	var v: float = sin(TAU * freq * t) * 0.55
	v += sin(TAU * freq * 2.0 * t) * exp(-t * 4.0) * 0.24
	v += sin(TAU * freq * 3.0 * t) * exp(-t * 7.0) * 0.12
	v += sin(TAU * freq * 4.0 * t) * exp(-t * 10.0) * 0.06
	return v * env


## Fanfarria de menú: llamada dórica Re-La-Re'-Mi' con cola resonante.
func _gen_menu_fanfare() -> AudioStreamWAV:
	# D4 A4 D5 E5 (dórico en Re): suena medieval sin cromatismos.
	var freqs: Array[float] = [293.66, 440.0, 587.33, 659.26]
	var starts: Array[float] = [0.0, 0.18, 0.36, 0.60]
	var lens: Array[float] = [0.30, 0.30, 0.45, 0.90]
	var dur: float = 1.7
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for ni in freqs.size():
		var f: float = freqs[ni]
		var start: int = int(float(starts[ni]) * SAMPLE_RATE)
		var len: int = int(float(lens[ni]) * SAMPLE_RATE)
		for j in len:
			var idx: int = start + j
			if idx >= n:
				break
			var t: float = float(j) / SAMPLE_RATE
			# Metal festivo: sierra suave de 3 armónicos + brillo de laúd.
			var env: float = minf(1.0, t * 60.0) * exp(-t * (2.6 if ni == freqs.size() - 1 else 5.0))
			var v: float = sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.22 + sin(TAU * f * 3.0 * t) * 0.10
			s[idx] += (v * env + _pluck(f * 2.0, t) * 0.25) * 0.55
	_deflick(s, 6.0)
	return _wav(s)


## Bucle ambiente: melodía dórica sencilla + bordón de quintas, 16 s.
func _gen_modal_loop() -> AudioStreamWAV:
	var dur: float = 16.0
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	# Melodía modal (D dórico: D E F G A B C D), una nota cada 1 s.
	var melody: Array[float] = [
		293.66, 329.63, 349.23, 392.0, 440.0, 392.0, 349.23, 329.63,
		293.66, 329.63, 392.0, 440.0, 523.25, 440.0, 392.0, 293.66
	]
	var step: float = 1.0
	var note_len: float = 1.6
	for ni in melody.size():
		var f: float = melody[ni]
		var start: int = int(ni * step * SAMPLE_RATE)
		var len: int = int(note_len * SAMPLE_RATE)
		for j in len:
			var idx: int = start + j
			if idx >= n:
				break
			var t: float = float(j) / SAMPLE_RATE
			s[idx] += _pluck(f, t) * 0.5
			# Octava grave muy suave para dar cuerpo al laúd.
			s[idx] += _pluck(f * 0.5, t) * 0.15
	# Bordón de quintas D2+A2 durante todo el loop (gaita sorda lejana).
	var drones: Array[float] = [73.42, 110.0]
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var v: float = 0.0
		for d in drones:
			var f: float = d
			v += sin(TAU * f * t) * 0.10 + sin(TAU * f * 2.0 * t) * 0.04
		# Respiración lenta para que el loop no suene estático.
		v *= 0.8 + 0.2 * sin(TAU * 0.0625 * t)
		s[i] += v
	# Normaliza suave y funde bordes para un loop limpio.
	for i in n:
		s[i] = clampf(s[i], -1.0, 1.0) * 0.85
	_deflick(s, 200.0)
	return _wav_loop(s)
