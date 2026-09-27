extends RefCounted
## Resuelve referencias de assets de las definiciones ("sprite:<pack>/<anim>")
## a animaciones cargadas desde carpetas de sprites extraídos (primero
## user://aoe2_assets, luego res://assets/sprites). Sin assets -> {} y el
## render dibuja un placeholder.

const DEFAULT_ROOTS := ["user://aoe2_assets/sprites", "res://assets/sprites"]

var roots: Array[String] = []
var _cache: Dictionary = {}


func _init(p_roots: Array = DEFAULT_ROOTS) -> void:
	roots.assign(p_roots)


func sprite(ref: String) -> Dictionary:
	if not ref.begins_with("sprite:"):
		return {}
	if _cache.has(ref):
		return _cache[ref]
	var rel := ref.substr(7)
	var result := {}
	for r in roots:
		var dir := "%s/%s" % [r, rel]
		if FileAccess.file_exists(dir + "/manifest.pack.json"):
			result = _load_pack(dir)
			if not result.is_empty():
				break
	_cache[ref] = result
	return result


func _load_pack(dir: String) -> Dictionary:
	var man: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/manifest.pack.json"))
	if not (man is Dictionary) or not man.has("frames"):
		return {}
	var dirs := int(man.get("dirs", 1))
	var per_dir := int(man.get("kept_per_dir", 1))
	var frames: Array = []
	frames.resize(dirs * per_dir)
	for e in man["frames"]:
		var i := int(e["dir"]) * per_dir + int(e["sub"])
		if i < 0 or i >= frames.size():
			continue
		var tex := _texture("%s/%s" % [dir, e["png"]])
		if tex == null:
			return {}
		var mask: Texture2D = null
		if e.get("mask") is String:
			mask = _texture("%s/%s" % [dir, e["mask"]])
		frames[i] = {"tex": tex, "mask": mask, "hotspot": Vector2(float(e["hotspot"][0]), float(e["hotspot"][1]))}
	for f in frames:
		if f == null:
			return {}
	return {"dirs": dirs, "per_dir": per_dir, "frames": frames}


static func _texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)
