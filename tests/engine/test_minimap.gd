extends "res://tests/engine/TestCase.gd"

const MATCH := "res://game/scenes/Match.tscn"


func test_minimap_draws_and_moves_camera() -> void:
	var m = load(MATCH).instantiate()
	Engine.get_main_loop().root.add_child(m)
	var mm = m.minimap
	assert_true(mm != null and mm.visible)
	# El centro del mapa (lago) es agua en el minimapa.
	var c := Vector2i(m.sim.grid.width / 2, m.sim.grid.height / 2)
	assert_true(_near(mm._img.get_pixelv(c), mm.WATER), "agua")
	# Una casilla del jugador 0 (su centro urbano) lleva su color.
	var tile: Vector2i = m._start_tile(0)
	assert_true(_near(mm._img.get_pixelv(tile), m.layer.colors[0].darkened(0.15)), "color del jugador")
	# Clic en el minimapa sobre el inicio del jugador 1 mueve la cámara allí.
	var target: Vector2 = Vector2(m._start_tile(1))
	var local: Vector2 = mm._xform() * target
	assert_true(mm.tile_at(local).distance_to(target) < 0.01)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = local
	mm._on_input(ev)
	var want: Vector2 = m.Iso.to_screen(target)
	assert_true(m.cam.position.distance_to(want) < 1.0, "la cámara va al punto")
	m.queue_free()


## Colores de la imagen (8 bits por canal) con tolerancia.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01
