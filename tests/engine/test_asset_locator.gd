extends "res://tests/engine/TestCase.gd"

const AssetLocator := preload("res://engine/assets/AssetLocator.gd")
const ROOT := "user://test_assets/sprites"


func _make_pack() -> void:
	var dir := ROOT + "/foo/walk"
	DirAccess.make_dir_recursive_absolute(dir)
	var frames := []
	for d in 2:
		var img := Image.create(4 + d, 6, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 0, 0, 1))
		img.save_png("%s/p_%03d.png" % [dir, d])
		frames.append({"png": "p_%03d.png" % d, "dir": d, "sub": 0, "hotspot": [2, 5]})
	var m := Image.create(4, 6, false, Image.FORMAT_RGBA8)
	m.fill(Color(1, 1, 1, 1))
	m.save_png(dir + "/m_000.png")
	frames[0]["mask"] = "m_000.png"
	var man := {"dirs": 2, "kept_per_dir": 1, "size": [4, 6], "frames": frames}
	var f := FileAccess.open(dir + "/manifest.pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(man))
	f.close()


func test_loads_pack_with_mask_and_hotspot() -> void:
	_make_pack()
	var loc := AssetLocator.new([ROOT])
	var pk := loc.sprite("sprite:foo/walk")
	assert_eq(pk["dirs"], 2)
	assert_eq(pk["per_dir"], 1)
	assert_eq(pk["frames"].size(), 2)
	assert_eq(pk["frames"][1]["tex"].get_size(), Vector2(5, 6))
	assert_eq(pk["frames"][0]["hotspot"], Vector2(2, 5))
	assert_true(pk["frames"][0]["mask"] != null)
	assert_true(pk["frames"][1]["mask"] == null)
	assert_true(is_same(loc.sprite("sprite:foo/walk"), pk), "cacheado")


func test_missing_pack_returns_empty() -> void:
	var loc := AssetLocator.new([ROOT])
	assert_eq(loc.sprite("sprite:nada/walk"), {})
	assert_eq(loc.sprite("icon:x"), {})
	assert_eq(loc.sprite(""), {})
