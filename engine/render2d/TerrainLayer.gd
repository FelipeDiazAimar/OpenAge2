extends Node2D
## Terreno procedural (placeholder hasta F1b): rombos de hierba con variación
## suave. Se dibuja una vez (Godot cachea el _draw).

const Iso := preload("res://engine/render2d/Iso.gd")
const GRASS_A := Color(0.36, 0.52, 0.22)
const GRASS_B := Color(0.30, 0.45, 0.19)
const DRY := Color(0.52, 0.50, 0.30)

var width := 0
var height := 0


func setup(w: int, h: int) -> void:
	width = w
	height = h
	z_index = -100
	queue_redraw()


func _draw() -> void:
	for y in height:
		for x in width:
			var coarse := float(absi(hash(Vector2i(x / 6, y / 6))) % 100) / 100.0
			var fine := float(absi(hash(Vector2i(x, y))) % 100) / 100.0
			var c := GRASS_A.lerp(GRASS_B, fine * 0.6).lerp(DRY, coarse * coarse * 0.35)
			var pts := PackedVector2Array([
				Iso.to_screen(Vector2(x, y)), Iso.to_screen(Vector2(x + 1, y)),
				Iso.to_screen(Vector2(x + 1, y + 1)), Iso.to_screen(Vector2(x, y + 1))])
			draw_colored_polygon(pts, c)
