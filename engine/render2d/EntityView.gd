extends Node2D
## Vista de una entidad (solo cliente): elige animación según el estado de la
## simulación, dirección por rumbo en pantalla (16 slots), tiñe con el color
## del jugador y dibuja selección / placeholder. La posición del nodo es el
## punto del suelo; el EntityLayer ordena por y.

const Iso := preload("res://engine/render2d/Iso.gd")
const PLAYER_SHADER := preload("res://engine/render2d/player_color.gdshader")
const FPS := {"walk": 10.0, "idle": 6.0, "task": 8.0, "attack": 10.0, "death": 8.0, "decay": 0.0}

var entity_id := 0
var kind := "unit"
var def_id := ""
var owner_civ := ""
var owner_age := 1
## Fracción de comida restante en granjas (0..1): elige estadio visual.
var farm_frac := 1.0
## Fracción de mina restante (0..1): oscurece al agotarse.
var mine_frac := 1.0
var footprint := Vector2i.ONE
var color := Color.WHITE
var selected := false:
	set(v):
		if v != selected:
			selected = v
			queue_redraw()
var hp_ratio := 1.0:
	set(v):
		if not is_equal_approx(v, hp_ratio):
			hp_ratio = v
			queue_redraw()
## La animación no se repite: queda en el último frame (muerte).
var one_shot := false
## Animal con dueño (oveja propia): lleva la marca de bando.
var owned := false
## Obra (cimiento): 0..1. Por debajo de 1 el edificio "crece" desde el
## suelo sobre una silueta translúcida, con barra de avance.
var progress := 1.0:
	set(v):
		if not is_equal_approx(v, progress):
			progress = v
			queue_redraw()

var _graphics: Dictionary = {}
var _locator
var _anims: Dictionary = {}
## Texturas de campo del DE (user://, pueden faltar): suelo fc1, cultivo fm1.
var _farm_cache: Dictionary = {}
var _anim := ""
var _t := 0.0
var _slot := 4
var _frame := 0
var _has_mask := false
var _sprite: Sprite2D
var _ghost: Sprite2D
var _sail: Sprite2D
var _mat: ShaderMaterial


## Cambio de dueño (p. ej. oveja capturada).
func set_color(c: Color) -> void:
	if c == color:
		return
	color = c
	_mat.set_shader_parameter("player_color", c)
	queue_redraw()


## Avance de edad: invalida packs con {age} para re-resolver en _pack.
func refresh_age(p_age: int) -> void:
	if p_age == owner_age:
		return
	owner_age = p_age
	_anims.clear()
	queue_redraw()


func setup(id: int, def: Dictionary, p_color: Color, locator, p_civ: String = "", p_age: int = 1) -> void:
	entity_id = id
	kind = str(def.get("type", "unit"))
	def_id = str(def.get("id", ""))
	owner_civ = p_civ
	owner_age = p_age
	color = p_color
	_locator = locator
	_graphics = def.get("graphics", {})
	if def_id == "maravilla":
		var wb: Dictionary = _graphics.get("wonders_by_civ", {})
		if wb.has(owner_civ):
			_graphics = _graphics.duplicate()
			_graphics["idle"] = str(wb[owner_civ])
		var db: Dictionary = _graphics.get("destruction_by_civ", {})
		if db.has(owner_civ):
			_graphics = _graphics.duplicate()
			_graphics["destruction"] = str(db[owner_civ])
		var rb: Dictionary = _graphics.get("rubble_by_civ", {})
		if rb.has(owner_civ):
			_graphics = _graphics.duplicate()
			_graphics["rubble"] = str(rb[owner_civ])
	if def.get("footprint") is Array:
		footprint = Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.visible = false
	_mat = ShaderMaterial.new()
	_mat.shader = PLAYER_SHADER
	_mat.set_shader_parameter("player_color", p_color)
	_sprite.material = _mat
	_ghost = Sprite2D.new()
	_ghost.centered = false
	_ghost.visible = false
	_ghost.modulate = Color(1, 1, 1, 0.3)
	add_child(_ghost)
	add_child(_sprite)
	_sail = Sprite2D.new()
	_sail.centered = false
	_sail.visible = false
	add_child(_sail)


func has_sprite() -> bool:
	return not _pack("idle").is_empty() or not _pack("walk").is_empty()


func current_anim() -> String:
	return _anim


func current_slot() -> int:
	return _slot


func current_frame() -> int:
	return _frame


## Unidad con sprite sin máscara de color de jugador: se dibuja una elipse del
## color del jugador bajo los pies para distinguir bandos.
func team_marker() -> bool:
	return (kind == "unit" or owned) and _sprite.visible and not _has_mask and not one_shot


func pick_radius() -> float:
	if kind == "building":
		return footprint.x * Iso.TILE_W * 0.35
	if kind == "resource":
		return 22.0
	return 18.0


## action: animación de tarea pedida por la simulación ("task"...); si el
## pack no existe se usa walk/idle. Para entidades que no son unidades, un
## pack de 1 dirección con varios frames son VARIANTES (frame fijo por id).
func update_view(moving: bool, facing_screen: Vector2, delta: float, action: String = "") -> void:
	if facing_screen.length_squared() > 0.0001:
		_slot = Iso.dir16(facing_screen)
	var want := "walk" if moving else "idle"
	if action.begins_with("task_") and _pack(action).is_empty():
		action = "task"
	if action != "" and not _pack(action).is_empty():
		want = action
	if _pack(want).is_empty():
		want = "idle" if not _pack("idle").is_empty() else "walk"
	var pk := _pack(want)
	if pk.is_empty():
		_anim = ""
		if _sprite.visible:
			_sprite.visible = false
			queue_redraw()
		if _sail != null and _sail.visible:
			_sail.visible = false
		return
	if want != _anim:
		_anim = want
		_t = 0.0
	_t += delta
	var per_dir: int = pk["per_dir"]
	var dirs: int = pk["dirs"]
	var sub: int
	if kind != "unit" and dirs == 1:
		sub = posmod(entity_id * 7919, maxi(1, per_dir))
	else:
		var raw := int(_t * float(FPS.get(want, 8.0)))
		sub = mini(raw, per_dir - 1) if one_shot else raw % maxi(1, per_dir)
	var d := (_slot * dirs) / 16 if dirs > 1 else 0
	_frame = d * per_dir + sub
	var fr: Dictionary = pk["frames"][_frame]
	if not _sprite.visible:
		_sprite.visible = true
		queue_redraw()
	_sprite.texture = fr["tex"]
	_sprite.offset = -fr["hotspot"]
	_apply_progress(fr)
	var masked: bool = fr["mask"] != null
	if masked != _has_mask:
		_has_mask = masked
		queue_redraw()
	_mat.set_shader_parameter("has_mask", masked)
	if fr["mask"] != null:
		_mat.set_shader_parameter("mask_tex", fr["mask"])
	_sync_sail(d, sub)
	# mine_frac solo minas: berry_bush excluido (no entra).
	var mv := 1.0 - 0.45 * (1.0 - mine_frac)
	if mine_frac < 0.999:
		modulate = Color(mv, mv, mv, modulate.a)


## Cimiento: solo la parte inferior del sprite (proporcional al avance) va
## sólida; el resto es la silueta translúcida.
func _apply_progress(fr: Dictionary) -> void:
	var building := progress < 0.999
	_ghost.visible = building
	_sprite.region_enabled = building
	if not building:
		return
	var tex: Texture2D = fr["tex"]
	var size := tex.get_size()
	var h := size.y * clampf(0.1 + 0.9 * progress, 0.0, 1.0)
	_sprite.region_rect = Rect2(0, size.y - h, size.x, h)
	_sprite.offset = -fr["hotspot"] + Vector2(0, size.y - h)
	var sc := _scaffold_pack()
	if sc.is_empty():
		_ghost.texture = tex
		_ghost.offset = -fr["hotspot"]
	else:
		var f0: Dictionary = (sc["frames"] as Array)[0]
		_ghost.texture = f0["tex"]
		_ghost.offset = -f0["hotspot"]


## Andamio de obra por footprint (1x1..5x5,8x8); {} si no hay pack.
func _scaffold_pack() -> Dictionary:
	var n := maxi(footprint.x, footprint.y)
	if n == 6:
		n = 5
	elif n == 7:
		n = 8
	var key := "b_misc_foundation_%dx%d_x1" % [n, n]
	if not _anims.has(key):
		_anims[key] = _locator.sprite("sprite:buildings/scaffolds/" + key)
	return _anims[key]


func is_under_construction() -> bool:
	return progress < 0.999


## Vela sobre el casco: lee graphics.sail (ej. "sprite:ships_sails/medi_ship_4"),
## mismo slot/sub que el casco, hotspot PROPIO del manifest de vela, sin máscara
## de jugador. Oculta si no hay pack; si el def no trae "sail" no hace nada.
func _sail_pack() -> Dictionary:
	if not _anims.has("sail"):
		_anims["sail"] = _locator.sprite(str(_graphics["sail"])) if _graphics.has("sail") else {}
	return _anims["sail"]


func _sync_sail(d: int, sub: int) -> void:
	if _sail == null or not _graphics.has("sail"):
		return
	var sp := _sail_pack()
	if sp.is_empty() or not _sprite.visible or is_under_construction():
		_sail.visible = false
		return
	var sd := mini(d, int(sp["dirs"]) - 1)
	var ss := mini(sub, int(sp["per_dir"]) - 1)
	var fr: Dictionary = (sp["frames"] as Array)[sd * int(sp["per_dir"]) + ss]
	_sail.texture = fr["tex"]
	_sail.offset = -fr["hotspot"]
	_sail.visible = true


## Hundimiento (barco sin death), p 0..1: escora + y+ + fundido. Llamar
## DESPUES de update_view. Sin estado ni packs nuevos.
func tick_sink(p: float, base_y: float, drop: float) -> void:
	rotation = p * 0.45
	position.y = base_y + drop * p
	modulate.a = clampf(1.0 - p, 0.0, 1.0)


func _pack(anim: String) -> Dictionary:
	if not _anims.has(anim):
		_anims[anim] = _resolve_ref(str(_graphics.get(anim, "")))
	return _anims[anim]


## {age} = edad sim + 1 (1->2, 2->3, 3->4). Sin manifest cae a [want,3,2,4].
func _resolve_ref(ref: String) -> Dictionary:
	if not ref.contains("{age}"):
		return _locator.sprite(ref)
	var want := clampi(owner_age + 1, 2, 4)
	for a in [want, 3, 2, 4]:
		var pk: Dictionary = _locator.sprite(ref.replace("{age}", str(a)))
		if not pk.is_empty():
			return pk
	return {}


## Textura de campo (granja) desde user://; null si aún no se importó.
func _farm_tex(name: String) -> Texture2D:
	if not _farm_cache.has(name) and _locator != null:
		var t: Texture2D = _locator.terrain("terrain:" + name)
		if t != null:
			_farm_cache[name] = t
	return _farm_cache.get(name)


func _draw() -> void:
	var r := pick_radius()
	if team_marker():
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 11.0, Color(color, 0.55))
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 24, color.lightened(0.2), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if selected:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not _sprite.visible:
		if kind == "building":
			var hw := footprint.x * 0.5
			var hh := footprint.y * 0.5
			var pts := PackedVector2Array([
				Iso.to_screen(Vector2(-hw, -hh)), Iso.to_screen(Vector2(hw, -hh)),
				Iso.to_screen(Vector2(hw, hh)), Iso.to_screen(Vector2(-hw, hh))])
			if def_id == "granja":
				# La granja no tiene sprite en el DE (alli es overlay de
				# terreno): rombo con textura de campo según etapa (fc1 en
				# obra, fc2/fc3 brotes, fm1 maduro) o tierra plana si faltan.
				var stage := "g_fc1"
				if progress >= 0.999:
					stage = "g_fm1" if farm_frac >= 0.66 else ("g_fc3" if farm_frac >= 0.33 else "g_fc2")
				var tex: Texture2D = _farm_tex(stage)
				if tex != null:
					draw_polygon(pts, PackedColorArray(
						[Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]),
						PackedVector2Array(
						[Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)]),
						tex)
				else:
					draw_colored_polygon(pts, Color(0.45, 0.30, 0.15))
					for i in 3:
						var t := 0.25 + 0.25 * i
						draw_line(pts[0].lerp(pts[3], t), pts[1].lerp(pts[2], t),
							Color(0.26, 0.16, 0.07), 3.0)
				pts.append(pts[0])
				draw_polyline(pts, Color(0.62, 0.45, 0.24), 2.0)
			else:
				draw_colored_polygon(pts, color.darkened(0.35))
				pts.append(pts[0])
				draw_polyline(pts, color.lightened(0.3), 2.0)
		else:
			draw_circle(Vector2(0, -14), 9.0, color)
			draw_arc(Vector2(0, -14), 9.0, 0.0, TAU, 20, Color.BLACK, 1.5)
	if kind == "building" and progress < 0.999:
		var hw := footprint.x * 0.5
		var hh := footprint.y * 0.5
		var pts := PackedVector2Array([
			Iso.to_screen(Vector2(-hw, -hh)), Iso.to_screen(Vector2(hw, -hh)),
			Iso.to_screen(Vector2(hw, hh)), Iso.to_screen(Vector2(-hw, hh)), Iso.to_screen(Vector2(-hw, -hh))])
		draw_polyline(pts, Color(color, 0.8), 2.0)
		var top := -(footprint.y * Iso.TILE_H + 70.0)
		draw_rect(Rect2(-24, top, 48, 5), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-24, top, 48 * clampf(progress, 0.0, 1.0), 5), Color(0.95, 0.8, 0.3))
	if selected or (hp_ratio < 0.999 and kind != "resource"):
		var top := -(footprint.y * Iso.TILE_H + 60.0) if kind == "building" else -70.0
		draw_rect(Rect2(-16, top, 32, 4), Color(0.6, 0.0, 0.0))
		draw_rect(Rect2(-16, top, 32 * clampf(hp_ratio, 0.0, 1.0), 4), Color(0.1, 0.9, 0.1))
