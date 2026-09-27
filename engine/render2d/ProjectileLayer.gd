extends Node2D
## Flechas y piedras en vuelo (solo cliente): interpola entre ticks y dibuja
## una parábola según el avance del proyectil.

const Iso := preload("res://engine/render2d/Iso.gd")

var sim
var drawn := 0
var _alpha := 0.0


func _init() -> void:
	z_index = 50


func bind(p_sim) -> void:
	sim = p_sim


func sync(alpha: float) -> void:
	_alpha = clampf(alpha, 0.0, 1.0)
	queue_redraw()
	drawn = sim.projectiles.size()


func _draw() -> void:
	if sim == null:
		return
	for p in sim.projectiles:
		var total := float(maxi(1, int(p["total"])))
		var t := clampf((float(p["age"]) + _alpha) / total, 0.0, 1.0)
		var a := Iso.milli_to_screen(p["from"])
		var b := Iso.milli_to_screen(p["to"])
		var h := clampf(a.distance_to(b) * 0.25, 12.0, 70.0)
		var pos := a.lerp(b, t) + Vector2(0, -28.0 - 4.0 * h * t * (1.0 - t))
		var t2 := minf(1.0, t + 0.05)
		var nxt := a.lerp(b, t2) + Vector2(0, -28.0 - 4.0 * h * t2 * (1.0 - t2))
		var dir := (nxt - pos).normalized()
		if dir == Vector2.ZERO:
			dir = (b - a).normalized()
		draw_line(pos - dir * 9.0, pos + dir * 5.0, Color(0.32, 0.22, 0.12), 2.0)
		draw_line(pos + dir * 5.0, pos + dir * 5.0 - dir.rotated(0.5) * 4.0, Color(0.85, 0.85, 0.85), 1.5)
		draw_line(pos + dir * 5.0, pos + dir * 5.0 - dir.rotated(-0.5) * 4.0, Color(0.85, 0.85, 0.85), 1.5)
