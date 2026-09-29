extends Node2D
## Rectángulo de selección por arrastre (coordenadas de mundo del canvas).

const Iso := preload("res://engine/render2d/Iso.gd")

var _rect := Rect2()
var _active := false
## Punto de reunión del edificio seleccionado (null: ninguno).
var rally: Variant = null
var rally_from := Vector2.ZERO


func set_rally(p: Variant, from: Vector2 = Vector2.ZERO) -> void:
	if p == rally and from == rally_from:
		return
	rally = p
	rally_from = from
	queue_redraw()


## Vista previa de un muro en línea: rombos por casilla (verde = se puede).
var _line_tiles: Array = []
var _line_ok: Array = []


func set_line_preview(tiles: Array, oks: Array) -> void:
	_line_tiles = tiles.duplicate()
	_line_ok = oks.duplicate()
	queue_redraw()


func _init() -> void:
	z_index = 100


func show_rect(r: Rect2) -> void:
	_rect = r.abs()
	_active = true
	queue_redraw()


func hide_rect() -> void:
	_active = false
	queue_redraw()


func _draw() -> void:
	if rally != null:
		var p: Vector2 = rally
		draw_dashed_line(rally_from, p, Color(1, 1, 1, 0.5), 2.0, 8.0)
		draw_line(p, p + Vector2(0, -34), Color(0.35, 0.25, 0.15), 3.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -34), p + Vector2(20, -28), p + Vector2(0, -21)]), Color(1.0, 0.85, 0.2))
	for i in _line_tiles.size():
		var t: Vector2i = _line_tiles[i]
		var col := Color(0.4, 1.0, 0.4, 0.45) if bool(_line_ok[i]) else Color(1.0, 0.3, 0.3, 0.45)
		var pts := PackedVector2Array([Iso.to_screen(Vector2(t)), Iso.to_screen(Vector2(t) + Vector2(1, 0)),
			Iso.to_screen(Vector2(t) + Vector2(1, 1)), Iso.to_screen(Vector2(t) + Vector2(0, 1))])
		draw_colored_polygon(pts, col)
	if _active:
		draw_rect(_rect, Color(1, 1, 1, 0.08), true)
		draw_rect(_rect, Color(1, 1, 1, 0.9), false, 1.5)
