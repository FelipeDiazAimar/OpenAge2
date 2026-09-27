extends "res://tests/engine/TestCase.gd"

const IsoCamera := preload("res://engine/render2d/IsoCamera.gd")


func test_edge_dir_only_inside_window() -> void:
	var vs := Vector2(1280, 720)
	assert_eq(IsoCamera.edge_dir(Vector2(5, 300), vs), Vector2(-1, 0))
	assert_eq(IsoCamera.edge_dir(Vector2(1275, 715), vs), Vector2(1, 1))
	assert_eq(IsoCamera.edge_dir(Vector2(640, 360), vs), Vector2.ZERO)
	assert_eq(IsoCamera.edge_dir(Vector2(-300, 360), vs), Vector2.ZERO, "cursor fuera de la ventana no desplaza")
	assert_eq(IsoCamera.edge_dir(Vector2(640, 900), vs), Vector2.ZERO)
