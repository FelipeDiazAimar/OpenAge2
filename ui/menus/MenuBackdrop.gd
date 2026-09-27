class_name MenuBackdrop
extends Control
# MenuBackdrop: fondo panorámico procedural estilo Age of Empires 2 para los menús.
# Todo 100 % procedural y sin assets externos: cielo al atardecer, colinas con
# parallax lento, castillo con almenas y banderas del jugador, nubes a la
# deriva, pájaros en V, antorchas con partículas y viñeta cinematográfica.
# Solo cliente (adorno visual): la raíz y los ColorRect ignoran el ratón para
# no tapar los botones del menú. Instanciar MenuBackdrop.tscn como primer hijo
# del menú y llamar a set_civ_color() con el color del jugador si se conoce.

# Color de la bandera del jugador: tiñe las dos banderas del castillo.
@export var color_banner: Color = Color(0.2, 0.35, 0.9):
	set(v):
		color_banner = v
		_pintar_banderas()

# Terreno generado más ancho que cualquier pantalla para no ver bordes.
const X0_COLINA := -800.0
const X1_COLINA := 2400.0
const X0_SUELO := -2000.0
const X1_SUELO := 4000.0

# Referencias a la escena (31 nodos en total, muy por debajo del límite).
@onready var _sol: ColorRect = $Sun
@onready var _lejos: Polygon2D = $HillsFar
@onready var _medias: Polygon2D = $HillsMid
@onready var _suelo: Polygon2D = $Ground
@onready var _castillo: Node2D = $Castle
@onready var _muralla: Polygon2D = $Castle/Wall
@onready var _torreon: Polygon2D = $Castle/Keep
@onready var _torre_izq: Polygon2D = $Castle/TowerL
@onready var _torre_der: Polygon2D = $Castle/TowerR
@onready var _bandera_izq: Polygon2D = $Castle/FlagL
@onready var _bandera_der: Polygon2D = $Castle/FlagR
@onready var _antorcha_izq: CPUParticles2D = $Castle/TorchL
@onready var _antorcha_der: CPUParticles2D = $Castle/TorchR
@onready var _halo_izq: ColorRect = $Castle/GlowL
@onready var _halo_der: ColorRect = $Castle/GlowR
@onready var _nubes_nodo: Node2D = $Clouds
@onready var _pajaros_nodo: Node2D = $Birds

var _t := 0.0
var _ancho := 1280.0
var _alto := 720.0
# Bases para el parallax (se recolocan con el tamaño en _layout).
var _lejos_base := Vector2.ZERO
var _medias_base := Vector2.ZERO
var _nubes: Array[ColorRect] = []
var _nube_vel: Array[float] = []
# Bandada ocasional: cruza el cielo en formación de V y se esconde.
var _bandada_activa := false
var _bandada_t := 3.0
var _bandada_pos := Vector2.ZERO
var _bandada_vel := 110.0
var _aves: Array[Line2D] = []
var _ave_offset: Array[Vector2] = [Vector2.ZERO, Vector2(-44, -28), Vector2(-44, 28)]


func _ready() -> void:
	# Recoge nubes y aves hijas para animarlas por código.
	for c in _nubes_nodo.get_children():
		var r := c as ColorRect
		if r != null:
			_nubes.append(r)
			# Las nubes grandes van "delante": derivan más deprisa.
			_nube_vel.append(9.0 + r.size.x * 0.05)
	for b in _pajaros_nodo.get_children():
		var l := b as Line2D
		if l != null:
			_aves.append(l)
	_construir_colinas()
	_construir_castillo()
	_dar_textura_antorchas()
	_pintar_banderas()
	# El tamaño real llega tras el primer layout: recolocar entonces y al redimensionar.
	resized.connect(_layout)
	call_deferred("_layout")


# API pública: tiñe las banderas con el color de la civilización del jugador.
func set_civ_color(c: Color) -> void:
	color_banner = c


func _layout() -> void:
	# Recoloca el panorama según el tamaño real; tolera tamaño aún desconocido.
	var w: float = size.x
	var h: float = size.y
	if w < 10.0 or h < 10.0:
		var vp: Vector2 = get_viewport_rect().size
		w = vp.x
		h = vp.y
	if w < 10.0 or h < 10.0:
		return
	_ancho = w
	_alto = h
	var suelo_y: float = h * 0.80
	# Sol bajo a la izquierda del castillo (composición clásica AoE2).
	var lado_sol := 220.0
	_sol.position = Vector2(w * 0.30 - lado_sol * 0.5, h * 0.62 - lado_sol * 0.5)
	_sol.size = Vector2(lado_sol, lado_sol)
	# Colinas centradas en pantalla, cada capa a su altura; el suelo tapa por debajo.
	_lejos_base = Vector2((w - X0_COLINA - X1_COLINA) * 0.5, h * 0.68)
	_medias_base = Vector2((w - X0_COLINA - X1_COLINA) * 0.5, h * 0.74)
	_lejos.position = _lejos_base
	_medias.position = _medias_base
	_suelo.position = Vector2((w - X0_SUELO - X1_SUELO) * 0.5, suelo_y)
	# Castillo a la derecha, escalado con el ancho para no empequeñecer.
	_castillo.position = Vector2(w * 0.68, suelo_y)
	var k: float = clampf(w / 1280.0, 0.7, 1.6)
	_castillo.scale = Vector2(k, k)
	# Nubes repartidas por el cielo (conservan su tamaño de la escena).
	for i in _nubes.size():
		var n: ColorRect = _nubes[i]
		n.position = Vector2(fmod(float(i) * 0.37 + 0.05, 1.0) * w, h * (0.10 + 0.09 * float(i)))
	# La bandada usa los bordes actuales; empieza oculta.
	if not _bandada_activa:
		_pajaros_nodo.visible = false


func _process(delta: float) -> void:
	_t += delta
	# Parallax lento: cada capa de colinas respira a su propio ritmo.
	_lejos.position.x = _lejos_base.x + sin(_t * 0.05) * 36.0
	_medias.position.x = _medias_base.x + sin(_t * 0.08 + 1.7) * 22.0
	# Nubes a la deriva; al salir por la derecha reentran por la izquierda.
	for i in _nubes.size():
		var n: ColorRect = _nubes[i]
		n.position.x += _nube_vel[i] * delta
		if n.position.x > _ancho + 60.0:
			n.position.x = -n.size.x - 60.0
			n.position.y = _alto * randf_range(0.08, 0.42)
	_actualizar_pajaros(delta)
	# Banderas ondeando desde el mástil (su origen está en el borde del palo).
	_bandera_izq.scale.x = 1.0 + 0.10 * sin(_t * 6.0)
	_bandera_der.scale.x = 1.0 + 0.10 * sin(_t * 6.0 + 1.3)
	# Halos de antorcha parpadeando con ritmos distintos para no ir al unísono.
	_halo_izq.modulate.a = 0.70 + 0.30 * (0.5 + 0.5 * sin(_t * 11.0) * sin(_t * 5.3 + 0.7))
	_halo_der.modulate.a = 0.70 + 0.30 * (0.5 + 0.5 * sin(_t * 12.3 + 2.0) * sin(_t * 4.7 + 1.1))


func _actualizar_pajaros(delta: float) -> void:
	# Vuelo ocasional en V: aparece, cruza el cielo y se esconde hasta la próxima.
	if not _bandada_activa:
		_bandada_t -= delta
		if _bandada_t <= 0.0:
			_bandada_activa = true
			_bandada_pos = Vector2(-120.0, _alto * randf_range(0.15, 0.35))
			_bandada_vel = randf_range(90.0, 140.0)
			_pajaros_nodo.visible = true
		return
	_bandada_pos.x += _bandada_vel * delta
	# Aleteo: la V se abre y se cierra escalando en vertical.
	var aleteo: float = 0.5 + 0.8 * abs(sin(_t * 9.0))
	for i in _aves.size():
		var a: Line2D = _aves[i]
		a.position = _bandada_pos + _ave_offset[mini(i, _ave_offset.size() - 1)]
		a.scale = Vector2(1.0, aleteo)
	if _bandada_pos.x > _ancho + 200.0:
		_bandada_activa = false
		_bandada_t = randf_range(5.0, 11.0)
		_pajaros_nodo.visible = false


func _construir_colinas() -> void:
	# Dos capas de colinas (lejana más clara) con cimas de senos mezclados.
	_lejos.polygon = _colina(70.0, 38.0, 0.0)
	_medias.polygon = _colina(95.0, 50.0, 2.1)
	# Suelo en suave pendiente; su base baja de sobra para tapar el fondo.
	_suelo.polygon = PackedVector2Array([
		Vector2(X0_SUELO, 30.0), Vector2(X1_SUELO, -20.0),
		Vector2(X1_SUELO, 1000.0), Vector2(X0_SUELO, 1000.0),
	])


func _colina(amp1: float, amp2: float, fase: float) -> PackedVector2Array:
	# Perfil ondulado entre X0_COLINA y X1_COLINA, cerrado por abajo.
	var pts := PackedVector2Array()
	var x := X0_COLINA
	while x <= X1_COLINA:
		var cima: float = amp1 * (0.5 + 0.5 * sin(x * 0.004 + fase)) + amp2 * (0.5 + 0.5 * sin(x * 0.011 + fase * 1.7))
		pts.append(Vector2(x, -cima))
		x += 60.0
	pts.append(Vector2(X1_COLINA, 500.0))
	pts.append(Vector2(X0_COLINA, 500.0))
	return pts


func _construir_castillo() -> void:
	# Silueta al atardecer con el origen en el suelo: muralla y tres torres almenadas.
	_muralla.polygon = _muro_almenado(-150.0, -64.0, 0.0, 300.0, 18.0, 12.0, 14.0)
	_torreon.polygon = _muro_almenado(-46.0, -150.0, 0.0, 92.0, 16.0, 12.0, 12.0)
	_torre_izq.polygon = _muro_almenado(-186.0, -112.0, 0.0, 66.0, 14.0, 10.0, 10.0)
	_torre_der.polygon = _muro_almenado(120.0, -112.0, 0.0, 66.0, 14.0, 10.0, 10.0)


func _muro_almenado(x0: float, arriba: float, base: float, ancho: float, diente: float, alto_diente: float, hueco: float) -> PackedVector2Array:
	# Contorno rectangular rematado con merlones centrados sobre el ancho dado.
	var pts := PackedVector2Array()
	pts.append(Vector2(x0, base))
	pts.append(Vector2(x0, arriba))
	var paso: float = diente + hueco
	var n: int = maxi(1, int((ancho + hueco) / paso))
	var total: float = float(n) * diente + float(n - 1) * hueco
	var x: float = x0 + (ancho - total) * 0.5
	for i in n:
		pts.append(Vector2(x, arriba))
		pts.append(Vector2(x, arriba - alto_diente))
		pts.append(Vector2(x + diente, arriba - alto_diente))
		pts.append(Vector2(x + diente, arriba))
		x += paso
	pts.append(Vector2(x0 + ancho, arriba))
	pts.append(Vector2(x0 + ancho, base))
	return pts


func _pintar_banderas() -> void:
	# Tiñe ambas banderas; el setter puede llamarse antes del _ready.
	if not is_node_ready():
		return
	_bandera_izq.color = color_banner
	_bandera_der.color = color_banner


func _dar_textura_antorchas() -> void:
	# Las partículas necesitan textura: disco blanco procedural, sin archivos.
	# El tono naranja de la llama lo pone el `color` del emisor en la escena.
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d: float = Vector2(float(x) - 7.5, float(y) - 7.5).length() / 7.5
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	var tex := ImageTexture.create_from_image(img)
	_antorcha_izq.texture = tex
	_antorcha_der.texture = tex
