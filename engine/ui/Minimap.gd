extends PanelContainer
## Minimapa estilo AoE2 (abajo a la derecha): el mapa como rombo isométrico
## con terreno, agua, recursos, edificios y unidades en el color de cada
## jugador, y el rectángulo de lo que ve la cámara. Clic o arrastre mueve la
## cámara. Solo lee Sim; se redibuja cada pocos ticks.

const Iso := preload("res://engine/render2d/Iso.gd")
const Grid := preload("res://engine/sim/Grid.gd")

const MAP_SIZE := Vector2(260, 130)
const EVERY := 5 # ticks entre redibujos
const GRASS := Color("#4f7d31")
const WATER := Color("#2d5fa8")
const RES_COLORS := {
	"tree": Color("#1d4a17"), "gold_mine": Color("#e0c040"), "stone_mine": Color("#a8a8a8"),
	"berry_bush": Color("#c84848"), "shore_fish": Color("#8fc0f0"), "deep_fish": Color("#8fc0f0"),
	"reliquia": Color("#ffffff"),
}
const ANIMAL := Color("#e8d8b0")

var sim
var pid := 0
var colors: Dictionary = {}
var cam
var _base: Image
var _img: Image
var _tex: ImageTexture
var _map: Control
var _last_tick := -1000


func setup(p_sim, p_pid: int, p_colors: Dictionary, p_cam) -> void:
	sim = p_sim
	pid = p_pid
	colors = p_colors
	cam = p_cam
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.03, 0.9)
	sb.border_color = Color(0.72, 0.58, 0.3)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(6)
	add_theme_stylebox_override("panel", sb)
	_map = Control.new()
	_map.custom_minimum_size = MAP_SIZE
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_input)
	add_child(_map)
	_build_base()
	refresh(true)


## Terreno y agua: fijos durante la partida.
func _build_base() -> void:
	var w: int = sim.grid.width
	var h: int = sim.grid.height
	_base = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_base.fill(GRASS)
	for y in h:
		for x in w:
			if sim.grid.is_water(Vector2i(x, y)):
				_base.set_pixel(x, y, WATER)
	_img = _base.duplicate()
	_tex = ImageTexture.create_from_image(_img)


## Redibuja las entidades (cada EVERY ticks, o ya si force).
func refresh(force: bool = false) -> void:
	var t: int = sim.world.tick
	if not force and t - _last_tick < EVERY:
		_map.queue_redraw() # la cámara se mueve aunque no haya tick
		return
	_last_tick = t
	_img.copy_from(_base)
	var w = sim.world
	for id in w.ids_with("ResourceSource"):
		if w.has_ability(id, "Held") or w.has_ability(id, "Farm"):
			continue
		var d := str(w.entities[id]["def_id"])
		var c: Color = RES_COLORS.get(d, ANIMAL if w.has_ability(id, "Move") else Color("#7a9a40"))
		_plot(Grid.tile_of(w.entities[id]["pos"]), c, 1)
	for id in w.ids_with("Hitpoints"):
		var e: Dictionary = w.entities[id]
		var owner := int(e["owner"])
		if owner < 0 or not colors.has(owner) or _hidden(id):
			continue
		var col: Color = colors[owner]
		if str(e["type"]) == "building":
			var def: Dictionary = sim.def_for(id)
			var size := Vector2i(int(def["footprint"][0]), int(def["footprint"][1]))
			var origin := Grid.tile_of(e["pos"] - size * 500)
			for y in size.y:
				for x in size.x:
					_plot(origin + Vector2i(x, y), col.darkened(0.15), 1)
		elif str(e["type"]) == "unit":
			_plot(Grid.tile_of(e["pos"]), col.lightened(0.25), 2)
	_tex.update(_img)
	_map.queue_redraw()


func _hidden(id: int) -> bool:
	var g: Dictionary = sim.world.comp(id, "Garrisoned")
	return not g.is_empty() and bool(g["inside"])


func _plot(t: Vector2i, c: Color, r: int) -> void:
	for y in range(t.y, t.y + r):
		for x in range(t.x, t.x + r):
			if x >= 0 and y >= 0 and x < _img.get_width() and y < _img.get_height():
				_img.set_pixel(x, y, c)


## Casillas -> píxeles del minimapa (rombo 2:1).
func _xform() -> Transform2D:
	var sx := MAP_SIZE.x / float(sim.grid.width + sim.grid.height)
	var sy := MAP_SIZE.y / float(sim.grid.width + sim.grid.height)
	return Transform2D(Vector2(sx, sy), Vector2(-sx, sy), Vector2(float(sim.grid.height) * sx, 0))


func _draw_map() -> void:
	var xf := _xform()
	_map.draw_set_transform_matrix(xf)
	_map.draw_texture(_tex, Vector2.ZERO)
	_map.draw_set_transform_matrix(Transform2D.IDENTITY)
	# Lo que ve la cámara.
	var vp := get_viewport()
	if vp == null:
		return
	var inv: Transform2D = vp.get_canvas_transform().affine_inverse()
	var r: Rect2 = vp.get_visible_rect()
	var pts := PackedVector2Array()
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]:
		pts.append(xf * Iso.to_tiles(inv * corner))
	_map.draw_polyline(pts, Color(1, 1, 1, 0.9), 1.5)


func _on_input(event: InputEvent) -> void:
	var press: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var drag: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if not press and not drag:
		return
	var tiles: Vector2 = _xform().affine_inverse() * event.position
	tiles = tiles.clamp(Vector2.ZERO, Vector2(sim.grid.width, sim.grid.height))
	if cam != null:
		cam.focus(Iso.to_screen(tiles))
	_map.accept_event()
	_map.queue_redraw()


## Casilla del mapa bajo un punto del minimapa (para pruebas).
func tile_at(local: Vector2) -> Vector2:
	return _xform().affine_inverse() * local
