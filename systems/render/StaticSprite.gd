class_name StaticSprite
extends RefCounted
## StaticSprite: billboard estático de 1 frame (árboles, minas, arbustos).
## Usa el primer PNG del pack. Null si no hay sprites extraídos (fallback 3D).


static func make(pack_dir: String, pixel_size: float = 0.03) -> Node3D:
	var man_path := pack_dir + "/manifest.pack.json"
	if not FileAccess.file_exists(man_path):
		return null
	var man: Dictionary = JSON.parse_string(FileAccess.open(man_path, FileAccess.READ).get_as_text())
	if typeof(man) != TYPE_DICTIONARY or not man.has("frames") or (man["frames"] as Array).is_empty():
		return null
	var e: Dictionary = (man["frames"] as Array)[0]
	var tex := load(pack_dir + "/" + str(e["png"])) as Texture2D
	if tex == null:
		return null
	var root := Node3D.new()
	root.name = "Static_" + pack_dir.get_file()
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.centered = true
	spr.pixel_size = pixel_size
	root.add_child(spr)
	var sz: Vector2 = spr.get_item_rect().size
	var hs: Array = e.get("hotspot", [sz.x * 0.5, sz.y])
	if sz.x > 0.0 and sz.y > 0.0:
		spr.offset = Vector2(float(hs[0]) - sz.x * 0.5, float(hs[1]) - sz.y * 0.5)
	return root
