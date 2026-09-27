extends Node2D
## Rectángulo de selección por arrastre (coordenadas de mundo del canvas).

var _rect := Rect2()
var _active := false


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
	if _active:
		draw_rect(_rect, Color(1, 1, 1, 0.08), true)
		draw_rect(_rect, Color(1, 1, 1, 0.9), false, 1.5)
