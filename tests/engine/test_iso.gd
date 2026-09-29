extends "res://tests/engine/TestCase.gd"

const Iso := preload("res://engine/render2d/Iso.gd")


func test_projection_roundtrip() -> void:
	assert_eq(Iso.to_screen(Vector2(0, 0)), Vector2(0, 0))
	assert_eq(Iso.to_screen(Vector2(1, 0)), Vector2(48, 24))
	assert_eq(Iso.to_screen(Vector2(0, 1)), Vector2(-48, 24))
	assert_eq(Iso.milli_to_screen(Vector2i(2000, 2000)), Vector2(0, 96))
	var t := Vector2(12.25, 40.5)
	assert_true(Iso.to_tiles(Iso.to_screen(t)).is_equal_approx(t))


func test_dir16_cardinals_and_negative_angles() -> void:
	# Orden de los .sld del DE: E=0 y horario (una unidad que va a la derecha
	# mira a la derecha).
	assert_eq(Iso.dir16(Vector2(1, 0)), 0, "E")
	assert_eq(Iso.dir16(Vector2(1, 1)), 2, "SE")
	assert_eq(Iso.dir16(Vector2(0, 1)), 4, "S")
	assert_eq(Iso.dir16(Vector2(-1, 1)), 6, "SW")
	assert_eq(Iso.dir16(Vector2(-1, 0)), 8, "W")
	assert_eq(Iso.dir16(Vector2(-1, -1)), 10, "NW")
	assert_eq(Iso.dir16(Vector2(0, -1)), 12, "N")
	assert_eq(Iso.dir16(Vector2(1, -1)), 14, "NE")
	assert_eq(Iso.dir16(Vector2(10, -1)), 0, "casi E por arriba no da negativo")
