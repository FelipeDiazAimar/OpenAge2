extends "res://tests/engine/TestCase.gd"

const EntityView := preload("res://engine/render2d/EntityView.gd")
const AssetLocator := preload("res://engine/assets/AssetLocator.gd")
const ROOT := "user://test_assets_ev/sprites"


func _make_pack(anim: String, dirs: int) -> void:
	var dir := "%s/bar/%s" % [ROOT, anim]
	DirAccess.make_dir_recursive_absolute(dir)
	var frames := []
	for d in dirs:
		for s in 2:
			var name := "p_%03d.png" % (d * 2 + s)
			var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.5, 0.5, 0.5, 1))
			img.save_png(dir + "/" + name)
			frames.append({"png": name, "dir": d, "sub": s, "hotspot": [4, 7]})
	var f := FileAccess.open(dir + "/manifest.pack.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"dirs": dirs, "kept_per_dir": 2, "size": [8, 8], "frames": frames}))
	f.close()


func _unit_def() -> Dictionary:
	return {"id": "bar", "type": "unit", "graphics": {"idle": "sprite:bar/idle", "walk": "sprite:bar/walk"}}


func test_walk_and_idle_pick_direction() -> void:
	_make_pack("idle", 16)
	_make_pack("walk", 16)
	var v := EntityView.new()
	v.setup(7, _unit_def(), Color.RED, AssetLocator.new([ROOT]))
	assert_true(v.has_sprite())
	v.update_view(true, Vector2(1, 0), 0.016)
	assert_eq(v.current_anim(), "walk")
	assert_eq(v.current_slot(), 8)
	v.update_view(false, Vector2.ZERO, 0.016)
	assert_eq(v.current_anim(), "idle")
	assert_eq(v.current_slot(), 8, "quieto conserva el rumbo")
	v.free()


func test_view_without_sprites_draws_placeholder() -> void:
	var v := EntityView.new()
	v.setup(1, {"id": "casa", "type": "building", "footprint": [2, 2], "graphics": {"idle": "sprite:nada/idle"}}, Color.BLUE, AssetLocator.new([ROOT]))
	v.update_view(false, Vector2.ZERO, 0.016)
	assert_false(v.has_sprite())
	assert_eq(v.current_anim(), "")
	assert_eq(v.footprint, Vector2i(2, 2))
	assert_true(v.pick_radius() > 40.0)
	v.free()
