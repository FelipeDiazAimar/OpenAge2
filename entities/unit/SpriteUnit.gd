extends Node3D
class_name SpriteUnit
## SpriteUnit - unidad 2D estilo AoE2 (billboard animado, SOLO CLIENTE).
## Lee manifest.pack.json de tools/extract_aoe2_sprites.py:
##   16 slots x N frames (slots 8-15 = espejos de 0-7 con flip_h).
## Animaciones: idle / walk (por estado de movimiento) + attack / task
## opcionales (solo si existe la carpeta del pack). Dirección por
## rumbo en pantalla (como el AoE original). Sin lógica sim.

const WALK_FPS := 8.0
const IDLE_FPS := 3.0
const ATTACK_FPS := 10.0
const TASK_FPS := 6.0
const STILL_TIME := 0.4 # quieto este tiempo -> pasa a idle
const ATTACK_TIME := 1.2 # duración visible de attack tras play_attack()

var spr: Sprite3D
var packs := {} # anim -> {frames: Array, dirs, kept}
var cur_anim := ""
var frame_f := 0.0
var slot := 0
var _slot5 := [0, false] # (slot, flip) para packs de 5 dirs
var _slot8 := 0 # octante clásico para packs de 8 dirs


## Rumbo mundo (dx,dz) -> slot. Archivo DE: W(0) antihorario hasta ESE(7),
## E(8)..WNW(15). Clásico 5 dirs: S,SW,W,NW,N + espejos.
func _dir_from_world(d: Vector3) -> void:
	var c := rad_to_deg(atan2(d.x, -d.z)) # 0=N, horario hacia E
	if c < 0.0:
		c += 360.0
	slot = int(round((270.0 - c) / 22.5)) % 16
	var oct := int(round(c / 45.0)) % 8 # 0=N,1=NE,2=E,3=SE,4=S,5=SW,6=W,7=NW
	_slot8 = oct
	# oct -> (slot5, flip) clásico
	match oct:
		0:
			_slot5 = [4, false] # N
		1:
			_slot5 = [3, true] # NE = espejo NW
		2:
			_slot5 = [2, true] # E = espejo W
		3:
			_slot5 = [1, true] # SE = espejo SW
		4:
			_slot5 = [0, false] # S
		5:
			_slot5 = [1, false] # SW
		6:
			_slot5 = [2, false] # W
		_:
			_slot5 = [3, false] # NW
var _last_pos := Vector3.ZERO
var _still := 0.0
var _started := false
var _attack_t := 0.0
var _task_mode := false


static var _pack_cache := {}

## path_base: res://assets/sprites/villager (contiene walk/, idle/ con manifest.pack.json)
static func with_pack(path_base: String) -> SpriteUnit:
	var u := SpriteUnit.new()
	u.set_meta("sprite_base", path_base)
	return u


func _ready() -> void:
	spr = Sprite3D.new()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = 0.028 # 61px -> ~1.7m (aldeano AoE2)
	spr.centered = true
	add_child(spr)
	_last_pos = global_position
	_started = true
	_use_anim("idle")


func _anim_pack(anim: String) -> Dictionary:
	var base := str(get_meta("sprite_base", ""))
	var key := base + "/" + anim
	if _pack_cache.has(key):
		return _pack_cache[key]
	var man_path := key + "/manifest.pack.json"
	if not FileAccess.file_exists(man_path):
		return {}
	var man: Dictionary = JSON.parse_string(FileAccess.open(man_path, FileAccess.READ).get_as_text())
	if typeof(man) != TYPE_DICTIONARY or not man.has("frames"):
		return {}
	var frames: Array = []
	for e in (man["frames"] as Array):
		var tex := load(key + "/" + str(e["png"])) as Texture2D
		frames.append({"tex": tex, "dir": int(e["dir"]), "sub": int(e["sub"]),
			"hotspot": e["hotspot"], "size": man["size"]})
	var pack := {"frames": frames, "dirs": int(man.get("dirs", 16)),
		"kept": int(man.get("kept_per_dir", 1))}
	_pack_cache[key] = pack
	return pack


func _use_anim(anim: String) -> void:
	if anim == cur_anim and packs.has(anim):
		return
	if not packs.has(anim):
		packs[anim] = _anim_pack(anim)
		if (packs[anim] as Dictionary).is_empty():
			return
	cur_anim = anim
	frame_f = 0.0


## Llamar desde GameWorld/SmartController al ordenar ataque. Sin acceso a sim.
func play_attack() -> void:
	_attack_t = ATTACK_TIME


## Activa modo tarea (recolectar/construir). _process muestra "task" si el pack existe.
func play_task() -> void:
	_task_mode = true


func stop_task() -> void:
	_task_mode = false


func _process(delta: float) -> void:
	if not _started or spr == null:
		return
	# Movimiento y rumbo en pantalla (como el AoE original).
	var cam := get_viewport().get_camera_3d()
	var d: Vector3 = global_position - _last_pos
	_last_pos = global_position
	if d.length() > 0.005:
		moving = true
		_still = 0.0
		_dir_from_world(d)
	else:
		_still += delta
		if _still >= STILL_TIME:
			moving = false
	if _attack_t > 0.0:
		_attack_t = maxf(0.0, _attack_t - delta)
	# Prioridad: attack 1.2s > task (solo si task_mode) > walk/idle. attack/task opcionales.
	var want := "walk" if moving else "idle"
	if _task_mode:
		want = "task"
	if _attack_t > 0.0:
		want = "attack"
	_use_anim(want)
	if want == "attack" and cur_anim != "attack":
		if _task_mode:
			_use_anim("task")
		if cur_anim != "attack" and not (cur_anim == "task" and _task_mode):
			_use_anim("walk" if moving else "idle")
	elif want == "task" and cur_anim != "task":
		_use_anim("walk" if moving else "idle")
	var pk: Dictionary = packs.get(cur_anim, {})
	if pk.is_empty():
		return
	var kept: int = pk["kept"]
	var dirs: int = pk.get("dirs", 16)
	var fps := IDLE_FPS
	if cur_anim == "walk":
		fps = WALK_FPS
	elif cur_anim == "attack":
		fps = ATTACK_FPS
	elif cur_anim == "task":
		fps = TASK_FPS
	frame_f += delta * fps
	var sub := int(frame_f) % maxi(1, kept)
	var real_slot := slot
	flipped = false
	if dirs == 5:
		# Clásico S,SW,W,NW,N + espejos. _slot5 ya trae (slot, flip).
		real_slot = _slot5[0]
		flipped = _slot5[1]
	elif dirs == 8:
		real_slot = (_slot8 + 4) % 8 # nuestro octante 0=N -> clásico 4=N
	# dirs == 16: slot directo 0-15 (8-15 ya vienen espejados en el archivo).
	var tex: Texture2D = null
	var hs := [30, 55]
	for e in (pk["frames"] as Array):
		if int(e["dir"]) == real_slot and int(e["sub"]) == sub:
			tex = e["tex"]
			hs = e["hotspot"]
			break
	if tex == null:
		return
	spr.texture = tex
	spr.flip_h = flipped
	var sz: Vector2 = spr.get_item_rect().size
	if sz.x > 0.0 and sz.y > 0.0:
		spr.offset = Vector2(float(hs[0]) - sz.x * 0.5, float(hs[1]) - sz.y * 0.5)
