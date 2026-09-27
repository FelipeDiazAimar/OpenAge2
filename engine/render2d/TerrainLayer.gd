extends Node2D
## Terreno estilo AoE2 DE (solo cliente): el rombo del mapa con un shader que
## mezcla texturas del DE (o el color de respaldo de cada terreno) según un
## mapa de control: suelo de bosque bajo los árboles de la simulación y
## parches de pasto seco / tierra por ruido.

const Iso := preload("res://engine/render2d/Iso.gd")
const SHADER := preload("res://engine/render2d/terrain.gdshader")
const LAYERS := ["grass", "grass_dry", "dirt", "forest_floor"]
const TILES_PER_TEX := 12.0

var width := 0
var height := 0
var control: Image
var _mat: ShaderMaterial


func setup(sim, registry, locator, p_seed: int) -> void:
	width = sim.grid.width
	height = sim.grid.height
	z_index = -100
	control = build_control(sim, p_seed)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("control_tex", ImageTexture.create_from_image(control))
	_mat.set_shader_parameter("noise_tex", _noise(p_seed))
	_mat.set_shader_parameter("map_size", Vector2(width, height))
	_mat.set_shader_parameter("tiles_per_tex", TILES_PER_TEX)
	for i in LAYERS.size():
		var def: Dictionary = registry.get_def(LAYERS[i])
		var tex: Texture2D = locator.terrain(str(def.get("texture", "")))
		if tex == null:
			tex = _flat(Color(str(def.get("color", "#6a8a3a"))))
		_mat.set_shader_parameter("tex_%d" % i, tex)
	material = _mat
	queue_redraw()


func material_param(p_name: String) -> Variant:
	return _mat.get_shader_parameter(p_name)


## R = pasto seco, G = tierra, B = suelo de bosque (1 texel por casilla).
static func build_control(sim, p_seed: int) -> Image:
	var w: int = sim.grid.width
	var h: int = sim.grid.height
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var dry := FastNoiseLite.new()
	dry.seed = p_seed
	dry.frequency = 0.045
	var dirt := FastNoiseLite.new()
	dirt.seed = p_seed + 101
	dirt.frequency = 0.06
	var forest := PackedFloat32Array()
	forest.resize(w * h)
	for id in sim.world.ids_with("ResourceSource"):
		if str(sim.world.comp(id, "ResourceSource")["params"]["rate_key"]) != "wood":
			continue
		var p: Vector2i = sim.world.entities[id]["pos"]
		var t := Vector2i(p.x / 1000, p.y / 1000)
		# Núcleo 1.0, primer anillo 0.6 y segundo 0.25: el suelo de bosque se
		# desvanece en vez de cortar en escalones.
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x := t.x + dx
				var y := t.y + dy
				if x < 0 or y < 0 or x >= w or y >= h:
					continue
				var ring := maxi(absi(dx), absi(dy))
				var v := 1.0 if ring == 0 else (0.6 if ring == 1 else 0.25)
				forest[y * w + x] = maxf(forest[y * w + x], v)
	for y in h:
		for x in w:
			var r := smoothstep(0.15, 0.45, dry.get_noise_2d(x, y))
			var g := smoothstep(0.35, 0.6, dirt.get_noise_2d(x, y))
			img.set_pixel(x, y, Color(r, g, forest[y * w + x], 1.0))
	return img


func _draw() -> void:
	var pts := PackedVector2Array([
		Iso.to_screen(Vector2(0, 0)), Iso.to_screen(Vector2(width, 0)),
		Iso.to_screen(Vector2(width, height)), Iso.to_screen(Vector2(0, height))])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(width, 0), Vector2(width, height), Vector2(0, height)])
	draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs)


static func _flat(c: Color) -> Texture2D:
	var img := Image.create(4, 4, true, Image.FORMAT_RGBA8)
	img.fill(c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _noise(p_seed: int) -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = p_seed + 7
	n.frequency = 0.08
	var img := n.get_seamless_image(128, 128)
	return ImageTexture.create_from_image(img)
