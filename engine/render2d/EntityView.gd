extends Node2D
## Vista de una entidad (solo cliente): elige animación según el estado de la
## simulación, dirección por rumbo en pantalla (16 slots), tiñe con el color
## del jugador y dibuja selección / placeholder. La posición del nodo es el
## punto del suelo; el EntityLayer ordena por y.

const Iso := preload("res://engine/render2d/Iso.gd")
const PLAYER_SHADER := preload("res://engine/render2d/player_color.gdshader")
const FPS := {"walk": 10.0, "idle": 6.0, "task": 8.0, "attack": 10.0, "death": 8.0}

var entity_id := 0
var kind := "unit"
var footprint := Vector2i.ONE
var color := Color.WHITE
var selected := false:
	set(v):
		if v != selected:
			selected = v
			queue_redraw()
var hp_ratio := 1.0

var _graphics: Dictionary = {}
var _locator
var _anims: Dictionary = {}
var _anim := ""
var _t := 0.0
var _slot := 4
var _sprite: Sprite2D
var _mat: ShaderMaterial


func setup(id: int, def: Dictionary, p_color: Color, locator) -> void:
	entity_id = id
	kind = str(def.get("type", "unit"))
	color = p_color
	_locator = locator
	_graphics = def.get("graphics", {})
	if def.get("footprint") is Array:
		footprint = Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.visible = false
	_mat = ShaderMaterial.new()
	_mat.shader = PLAYER_SHADER
	_mat.set_shader_parameter("player_color", p_color)
	_sprite.material = _mat
	add_child(_sprite)


func has_sprite() -> bool:
	return not _pack("idle").is_empty() or not _pack("walk").is_empty()


func current_anim() -> String:
	return _anim


func current_slot() -> int:
	return _slot


func pick_radius() -> float:
	if kind == "building":
		return footprint.x * Iso.TILE_W * 0.35
	return 18.0


func update_view(moving: bool, facing_screen: Vector2, delta: float) -> void:
	if facing_screen.length_squared() > 0.0001:
		_slot = Iso.dir16(facing_screen)
	var want := "walk" if moving else "idle"
	if _pack(want).is_empty():
		want = "idle" if not _pack("idle").is_empty() else "walk"
	var pk := _pack(want)
	if pk.is_empty():
		_anim = ""
		if _sprite.visible:
			_sprite.visible = false
			queue_redraw()
		return
	if want != _anim:
		_anim = want
		_t = 0.0
	_t += delta
	var per_dir: int = pk["per_dir"]
	var dirs: int = pk["dirs"]
	var sub := int(_t * float(FPS.get(want, 8.0))) % maxi(1, per_dir)
	var d := (_slot * dirs) / 16 if dirs > 1 else 0
	var fr: Dictionary = pk["frames"][d * per_dir + sub]
	if not _sprite.visible:
		_sprite.visible = true
		queue_redraw()
	_sprite.texture = fr["tex"]
	_sprite.offset = -fr["hotspot"]
	_mat.set_shader_parameter("has_mask", fr["mask"] != null)
	if fr["mask"] != null:
		_mat.set_shader_parameter("mask_tex", fr["mask"])


func _pack(anim: String) -> Dictionary:
	if not _anims.has(anim):
		_anims[anim] = _locator.sprite(str(_graphics[anim])) if _graphics.has(anim) else {}
	return _anims[anim]


func _draw() -> void:
	var r := pick_radius()
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
			draw_colored_polygon(pts, color.darkened(0.35))
			pts.append(pts[0])
			draw_polyline(pts, color.lightened(0.3), 2.0)
		else:
			draw_circle(Vector2(0, -14), 9.0, color)
			draw_arc(Vector2(0, -14), 9.0, 0.0, TAU, 20, Color.BLACK, 1.5)
	if selected:
		var top := -(footprint.y * Iso.TILE_H + 60.0) if kind == "building" else -70.0
		draw_rect(Rect2(-16, top, 32, 4), Color(0.6, 0.0, 0.0))
		draw_rect(Rect2(-16, top, 32 * clampf(hp_ratio, 0.0, 1.0), 4), Color(0.1, 0.9, 0.1))
