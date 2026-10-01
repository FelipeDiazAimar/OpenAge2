extends "res://tests/engine/TestCase.gd"

const PM := preload("res://ui/menus/PauseMenu.gd")


func _menu() -> CanvasLayer:
	var m: CanvasLayer = PM.new()
	Engine.get_main_loop().root.add_child(m)
	return m


func _free(m: CanvasLayer) -> void:
	m.hide_menu()
	Engine.get_main_loop().root.remove_child(m)
	m.free()


func test_instancia_cerrada_por_defecto() -> void:
	var m := _menu()
	assert_false(m.is_menu_open(), "cerrado al instanciar headless")
	_free(m)


func test_toggle_abre_y_cierra() -> void:
	var m := _menu()
	m.toggle()
	assert_true(m.is_menu_open(), "toggle abre")
	m.toggle()
	assert_false(m.is_menu_open(), "toggle cierra")
	_free(m)


func test_paused_acompana_menu() -> void:
	var m := _menu()
	m.show_menu()
	assert_true(Engine.get_main_loop().root.get_tree().paused, "abierto pausa")
	m.hide_menu()
	assert_false(Engine.get_main_loop().root.get_tree().paused, "cerrado reanuda")
	_free(m)


func test_botones_y_opciones() -> void:
	var m := _menu()
	var texts: Array = []
	for b in m.find_children("*", "Button", true, false):
		texts.append(str(b.text))
	assert_true(texts.any(func(t): return "Continuar" in t), "existe Continuar: %s" % [texts])
	assert_true(texts.any(func(t): return "Salir" in t), "existe Salir: %s" % [texts])
	assert_false(m._options_box.visible, "opciones plegado")
	m._on_options()
	assert_true(m._options_box.visible, "Opciones despliega")
	_free(m)
