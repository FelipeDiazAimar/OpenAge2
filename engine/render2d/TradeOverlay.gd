extends Node2D
## Rutas comerciales (solo lectura): linea home->target por carreta activa.
const Iso := preload("res://engine/render2d/Iso.gd")
var sim
var _pulse := 0.0
func _init() -> void:
	z_index = 40
func bind(p_sim) -> void:
	sim = p_sim
func sync(alpha: float) -> void:
	_pulse = 0.35 + 0.25 * sin(Time.get_ticks_msec() / 400.0 + alpha)
	queue_redraw()
func _draw() -> void:
	if sim == null or sim.get("world") == null:
		return
	var w = sim.world
	if not w.has_method("ids_with"):
		return
	for cart in w.ids_with("Trade"):
		var t: Dictionary = w.comp(cart, "Trade")
		if t.is_empty() or str(t.get("state", "idle")) == "idle":
			continue
		var a: int = int(t.get("home", -1))
		var b: int = int(t.get("target", -1))
		if not w.entities.has(a) or not w.entities.has(b):
			continue
		var pa := Iso.milli_to_screen(w.entities[a]["pos"])
		var pb := Iso.milli_to_screen(w.entities[b]["pos"])
		draw_line(pa, pb, Color(1.0, 0.85, 0.2, _pulse), 2.0)
		draw_circle(pb, 4.0, Color(1.0, 0.85, 0.2, _pulse + 0.2))
