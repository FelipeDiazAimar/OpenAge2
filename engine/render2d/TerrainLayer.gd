extends Node2D
## Terreno estilo AoE2 DE (solo cliente): el rombo del mapa con un shader que
## mezcla texturas del DE (o el color de respaldo de cada terreno) según un
## mapa de control: suelo de bosque bajo los árboles de la simulación y
## parches de pasto seco / tierra por ruido.

const Iso := preload("res://engine/render2d/Iso.gd")
const SHADER := preload("res://engine/render2d/terrain.gdshader")
const LAYERS := ["grass", "grass_dry", "dirt", "forest_floor"]
const MAX_LAYERS := 8
const TILES_PER_TEX := 12.0

var width := 0
var height := 0
var control: Image
var control2: Image
var _mat: ShaderMaterial
var _t := 0.0
var _water := 0


func setup(sim, registry, locator, p_seed: int) -> void:
	width = sim.grid.width
	height = sim.grid.height
	z_index = -100
	var layers: Array = _resolve_layers(registry)
	control = build_control(sim, p_seed)
	control2 = build_control2(sim, p_seed, layers)
	_water = _water_mask(registry, layers)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("control_tex", ImageTexture.create_from_image(control))
	_mat.set_shader_parameter("control_tex2", ImageTexture.create_from_image(control2))
	_mat.set_shader_parameter("noise_tex", _noise(p_seed))
	_mat.set_shader_parameter("map_size", Vector2(width, height))
	_mat.set_shader_parameter("tiles_per_tex", TILES_PER_TEX)
	_mat.set_shader_parameter("t_scroll", 0.0)
	_mat.set_shader_parameter("water_mask", _water)
	_t = 0.0
	for i in MAX_LAYERS:
		var tex: Texture2D = null
		if i < layers.size():
			var def: Dictionary = registry.get_def(layers[i])
			if def.is_empty():
				push_warning("TerrainLayer: el mod no define el terreno '%s'; se usa un color genérico" % layers[i])
			tex = locator.terrain(str(def.get("texture", "")))
			if tex == null:
				tex = _flat(Color(str(def.get("color", "#6a8a3a"))))
		if tex == null:
			tex = _mat.get_shader_parameter("tex_0") as Texture2D
			if tex == null:
				tex = _flat(Color("#6a8a3a"))
		_mat.set_shader_parameter("tex_%d" % i, tex)
	material = _mat
	queue_redraw()


func _process(delta: float) -> void:
	if _mat == null:
		return
	_t += delta
	_mat.set_shader_parameter("t_scroll", _t)


## Orden FIJO 0-7 = [grass,grass_dry,dirt,forest_floor,agua,playa,bajios,nieve]:
## 0-3 idéntico a LAYERS (pixel-idéntico hoy); 4-7 activan guards de build_control2.
## Visual: parches de agua/playa/bajíos/nieve donde el ruido de control2 pegue.
static func _resolve_layers(registry) -> Array:
	var fixed: Array = ["grass", "grass_dry", "dirt", "forest_floor", "agua", "playa", "bajios", "nieve"]
	if registry != null and registry.has_method("get_def"):
		for t in fixed:
			if (registry.call("get_def", str(t)) as Dictionary).is_empty():
				push_warning("TerrainLayer: falta '%s'; fallback fijo 8 (flat)" % str(t))
				break
	return fixed.slice(0, MAX_LAYERS)


static func _is_water(def: Dictionary) -> bool:
	return str(def.get("kind", "")) == "water" or bool(def.get("scroll", false))


static func _water_mask(registry, layers: Array) -> int:
	var m := 0
	for i in layers.size():
		var def: Dictionary = registry.get_def(layers[i])
		if _is_water(def):
			m |= (1 << i)
	return m


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


## Pesos capas 4-7 (RGBA). Recorte: ceros = inertes = pixel-idéntico hoy.
## Futuro: pintar aquí por def sin tocar build_control (mismo ruido/semillas).
static func build_control2(sim, p_seed: int, layers: Array) -> Image:
	var w: int = sim.grid.width
	var h: int = sim.grid.height
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ns: Array = []
	for i in 4:
		var n := FastNoiseLite.new()
		n.seed = p_seed + 201 + i * 17
		n.frequency = 0.045 + float(i) * 0.005
		ns.append(n)
	for y in h:
		for x in w:
			var r := 0.0
			var g := 0.0
			var b := 0.0
			var a := 0.0
			if layers.size() > 4 and str(layers[4]) == "agua":
				r = smoothstep(0.55, 0.75, (ns[0] as FastNoiseLite).get_noise_2d(x, y))
			if layers.size() > 5 and str(layers[5]) == "playa":
				g = smoothstep(0.45, 0.65, (ns[1] as FastNoiseLite).get_noise_2d(x, y)) * (1.0 - r)
			if layers.size() > 6 and str(layers[6]) == "bajios":
				b = smoothstep(0.5, 0.7, (ns[2] as FastNoiseLite).get_noise_2d(x, y)) * (1.0 - r)
			if layers.size() > 7 and str(layers[7]) == "nieve":
				a = smoothstep(0.55, 0.75, (ns[3] as FastNoiseLite).get_noise_2d(x, y))
			img.set_pixel(x, y, Color(r, g, b, a))
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
