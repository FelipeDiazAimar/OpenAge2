extends "res://tests/engine/TestCase.gd"

const TerrainImporter := preload("res://engine/assets/TerrainImporter.gd")
const DdsTest := preload("res://tests/engine/test_dds_loader.gd")
const ROOT := "user://test_install"
const DEST := "user://test_terrain_out"


func _fake_install() -> void:
	var dir := ROOT + "/" + TerrainImporter.REL
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/g_test.dds", FileAccess.WRITE)
	f.store_buffer(DdsTest.dxt1_red_4x4())
	f.close()
	if FileAccess.file_exists(DEST + "/g_test.png"):
		DirAccess.remove_absolute(DEST + "/g_test.png")


func test_import_writes_png_once() -> void:
	_fake_install()
	assert_eq(TerrainImporter.import(ROOT, ["g_test", "g_falta"], DEST), 1)
	assert_true(FileAccess.file_exists(DEST + "/g_test.png"))
	assert_eq(TerrainImporter.import(ROOT, ["g_test"], DEST), 0, "ya importada")


func test_find_install_honors_env() -> void:
	_fake_install()
	OS.set_environment("OPENAGE_AOE2_PATH", ROOT)
	assert_eq(TerrainImporter.find_install(), ROOT)
	OS.set_environment("OPENAGE_AOE2_PATH", "user://no_hay_juego")
	assert_true(TerrainImporter.find_install() != "user://no_hay_juego")
	OS.unset_environment("OPENAGE_AOE2_PATH")
