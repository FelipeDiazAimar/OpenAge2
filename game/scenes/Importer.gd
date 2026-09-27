extends Control
## Importador de sprites del AoE2:DE (escena Control, solo cliente).
## No toca red ni la partida: solo extrae PNG a user://aoe2_assets/sprites.
## Cómo lo usa Match (motor nuevo F1, ver docs/SPRITES.md):
## engine/assets/AssetLocator.gd busca "sprite:<pack>/<anim>" primero en
## user://aoe2_assets/sprites/<pack>/<anim>/manifest.pack.json y luego en
## res://assets/sprites/...; Match se lo pasa a EntityLayer en _ready.
## Formato por carpeta: manifest.pack.json + p_*.png (+ m_*.png de máscara).

# Rutas típicas de la carpeta drs/graphics del juego comprado.
const STEAM_SRC := "C:/Program Files (x86)/Steam/steamapps/common/AoE2DE/resources/_common/drs/graphics"
const XBOX_SRC := "C:/XboxGames/Age of Empires II- Definitive Edition/Content/Game/resources/_common/drs/graphics"
# Destino que lee el juego (AssetLocator: user:// primero, res:// después).
const DEST_USER := "user://aoe2_assets/sprites"
# Script extractor del proyecto (stdlib, ver tools/extract_aoe2_sprites.py).
const SCRIPT_RES := "res://tools/extract_aoe2_sprites.py"

# Sets extraíbles: base .sld (sin extensión) -> carpeta <pack>/<anim> de destino.
const SETS := {
	"aldeano": {
		"label": "Aldeano (walk, idle, task, death)",
		"bases": ["u_vil_male_farmer_walkA_x1", "u_vil_male_farmer_idleA_x1", "u_vil_male_farmer_taskA_x1", "u_vil_male_farmer_deathA_x1"],
		"dests": ["villager/walk", "villager/idle", "villager/task", "villager/death"],
	},
	"milicia": {
		"label": "Milicia (walk, idle, attack)",
		"bases": ["u_inf_militia_walkA_x1", "u_inf_militia_idleA_x1", "u_inf_militia_attackA_x1"],
		"dests": ["militia/walk", "militia/idle", "militia/attack"],
	},
	"arquero": {
		"label": "Arquero (walk, idle, attack)",
		"bases": ["u_arc_archer_walkA_x1", "u_arc_archer_idleA_x1", "u_arc_archer_attackA_x1"],
		"dests": ["archer/walk", "archer/idle", "archer/attack"],
	},
	"edificios": {
		"label": "Edificios (centro urbano, casa, cuartel)",
		"bases": ["b_west_town_center_age3_x1", "b_west_house_age3_x1", "b_west_barracks_age3_x1"],
		"dests": ["buildings/tc/b_west_town_center_age3_x1", "buildings/house/b_west_house_age3_x1", "buildings/barracks/b_west_barracks_age3_x1"],
	},
	"naturaleza": {
		"label": "Naturaleza (roble, pino, oro, piedra, arbusto)",
		"bases": ["tree_oak_x1", "tree_pine_x1", "gold_mine_x1", "stone_mine_x1", "berry_bush_x1"],
		"dests": ["nature/oak", "nature/pine", "nature/goldmine", "nature/stonemine", "nature/bush"],
	},
}
const ORDEN := ["aldeano", "milicia", "arquero", "edificios", "naturaleza"]

# Origen elegido (drs/graphics) y comando de Python detectado.
var _src := ""
var _python := ""
var _trabajando := false

@onready var _src_edit: LineEdit = $Center/Marco/Margen/Caja/FilaOrigen/SrcEdit
@onready var _auto_label: Label = $Center/Marco/Margen/Caja/AutoLabel
@onready var _progreso: ProgressBar = $Center/Marco/Margen/Caja/Progreso
@onready var _estado: Label = $Center/Marco/Margen/Caja/Estado
@onready var _extraer_btn: Button = $Center/Marco/Margen/Caja/FilaBotones/ExtraerButton
@onready var _explorador: FileDialog = $Explorador


func _ready() -> void:
	# Escena a pantalla completa y estilo medieval acorde al menú.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_aplicar_estilo()
	# Autodetecta Steam/Xbox; si no hay, el usuario elige carpeta.
	_src = _detectar_origen()
	if _src != "":
		_src_edit.text = _src
		_auto_label.text = "Instalación detectada: " + _src
	else:
		_auto_label.text = "No se encontró instalación automática: pulsa «Elegir carpeta…»."
	# Detecta intérprete para OS.execute (py en Windows, python3/python en resto).
	_python = _detectar_python()
	if _python == "":
		_estado.text = "No se encontró Python (probé py, python3 y python). Instala Python 3 y reintenta."
	else:
		_estado.text = "Python detectado: " + _python + ". Elige sets y pulsa Extraer."
	# Conexiones de botones y diálogo de carpeta.
	_extraer_btn.pressed.connect(_on_extraer)
	$Center/Marco/Margen/Caja/FilaOrigen/ElegirButton.pressed.connect(_on_elegir)
	$Center/Marco/Margen/Caja/FilaBotones/VolverButton.pressed.connect(_on_volver)
	_src_edit.text_changed.connect(_on_src_escrito)
	_explorador.dir_selected.connect(_on_dir_elegido)
	_explorador.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_progreso.min_value = 0
	_progreso.max_value = 100
	_progreso.value = 0


func _detectar_origen() -> String:
	# Devuelve la primera ruta drs/graphics que exista, o "" si no hay.
	if DirAccess.dir_exists_absolute(STEAM_SRC):
		return STEAM_SRC
	if DirAccess.dir_exists_absolute(XBOX_SRC):
		return XBOX_SRC
	return ""


func _detectar_python() -> String:
	# Prueba lanzadores comunes con --version; "" si ninguno responde.
	for cmd in ["py", "python3", "python"]:
		var salida: Array = []
		var codigo: int = OS.execute(cmd, ["--version"], salida, true)
		if codigo == 0:
			return cmd
	return ""


func _on_src_escrito(texto: String) -> void:
	# El usuario puede pegar la ruta a mano además del diálogo.
	_src = texto.strip_edges()


func _on_elegir() -> void:
	# Abre el explorador de carpetas partiendo del origen actual si vale.
	if _src != "" and DirAccess.dir_exists_absolute(_src):
		_explorador.current_dir = _src
	_explorador.popup_centered(Vector2i(720, 480))


func _on_dir_elegido(dir: String) -> void:
	# Guarda la carpeta elegida y la muestra en el campo de texto.
	_src = dir
	_src_edit.text = dir
	_auto_label.text = "Carpeta elegida: " + dir


func _on_volver() -> void:
	# Vuelve al menú principal sin tocar nada más.
	get_tree().change_scene_to_file("res://ui/menus/MainMenu.tscn")


func _sets_marcados() -> Array:
	# Lee las casillas y devuelve los ids de SETS seleccionados en ORDEN.
	var out: Array = []
	for id in ORDEN:
		var caja := get_node_or_null("Center/Marco/Margen/Caja/Check" + id.capitalize()) as CheckBox
		# "naturaleza" capitaliza a "Naturaleza": el nodo se llama CheckNaturaleza.
		if caja == null:
			continue
		if caja.button_pressed:
			out.append(id)
	return out


func _on_extraer() -> void:
	# Valida, extrae con tools/extract_aoe2_sprites.py vía OS.execute y mueve a user://.
	if _trabajando:
		return
	if _src == "" or not DirAccess.dir_exists_absolute(_src):
		_estado.text = "Elige primero una carpeta drs/graphics válida del juego comprado."
		return
	if _python == "":
		_python = _detectar_python()
		if _python == "":
			_estado.text = "No se encontró Python (probé py, python3 y python). Instala Python 3 y reintenta."
			return
	var marcados := _sets_marcados()
	if marcados.is_empty():
		_estado.text = "Marca al menos un set (aldeano, milicia, arquero, edificios o naturaleza)."
		return
	_trabajando = true
	_extraer_btn.disabled = true
	# Destino user:// y temporal dentro del mismo disco para mover rápido.
	var dest_abs := ProjectSettings.globalize_path(DEST_USER)
	var tmp_abs := dest_abs + "/_tmp_import"
	DirAccess.make_dir_recursive_absolute(dest_abs)
	DirAccess.make_dir_recursive_absolute(tmp_abs)
	var script_abs := ProjectSettings.globalize_path(SCRIPT_RES)
	if not FileAccess.file_exists(script_abs):
		_estado.text = "No se encontró el extractor: " + SCRIPT_RES
		_trabajando = false
		_extraer_btn.disabled = false
		return
	# Cuenta el total de archivos para la barra de progreso.
	var total := 0
	for id in marcados:
		total += int((SETS[id]["bases"] as Array).size())
	var hechos := 0
	var ok := 0
	var fallos: Array = []
	_progreso.max_value = maxi(1, total)
	_progreso.value = 0
	for id in marcados:
		var bases: Array = SETS[id]["bases"]
		var dests: Array = SETS[id]["dests"]
		for i in bases.size():
			var base := str(bases[i])
			var rel := str(dests[i])
			_estado.text = "Extrayendo %s (%d/%d)…" % [base, hechos + 1, total]
			await get_tree().process_frame
			# Lanza el extractor ya empaquetado (--pack --step 2 ahorra VRAM).
			var args := ["--src", _src, "--out", tmp_abs, "--files", base, "--pack", "--step", "2"]
			# Prefija el script: OS.execute necesita el exe de Python aparte.
			var full := [script_abs] + args
			var salida: Array = []
			var codigo: int = OS.execute(_python, full, salida, true)
			hechos += 1
			_progreso.value = hechos
			var tmp_base := tmp_abs + "/" + base
			if codigo != 0 or not DirAccess.dir_exists_absolute(tmp_base):
				fallos.append(base)
				continue
			# Mueve tmp/<base> a destino final <pack>/<anim>.
			var final_abs := dest_abs + "/" + rel
			if not _mover_carpeta(tmp_base, final_abs):
				fallos.append(base)
				continue
			ok += 1
	_borrar_recursivo(tmp_abs)
	_trabajando = false
	_extraer_btn.disabled = false
	# Resumen claro con la ruta que lee Match vía AssetLocator.
	if fallos.is_empty():
		_estado.text = "Listo: %d archivos en %s. Match los usa desde user://aoe2_assets/sprites." % [ok, DEST_USER]
	else:
		_estado.text = "Terminado con avisos: %d ok, %d fallos (%s). Revisa nombres con --list." % [ok, fallos.size(), ", ".join(fallos)]


func _mover_carpeta(origen_abs: String, destino_abs: String) -> bool:
	# Prepara el padre, borra el destino previo y renombra (mismo disco).
	var padre := destino_abs.get_base_dir()
	DirAccess.make_dir_recursive_absolute(padre)
	if DirAccess.dir_exists_absolute(destino_abs):
		_borrar_recursivo(destino_abs)
	if DirAccess.rename_absolute(origen_abs, destino_abs) == OK:
		return true
	return false


func _borrar_recursivo(ruta_abs: String) -> void:
	# Borra archivo o carpeta recursiva sin salir de user:// ni del destino.
	if FileAccess.file_exists(ruta_abs):
		DirAccess.remove_absolute(ruta_abs)
		return
	if not DirAccess.dir_exists_absolute(ruta_abs):
		return
	var dir := DirAccess.open(ruta_abs)
	if dir == null:
		return
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if n != "." and n != "..":
			_borrar_recursivo(ruta_abs + "/" + n)
		n = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ruta_abs)


func _aplicar_estilo() -> void:
	# Fondo oscuro cálido y marco piedra/madera con borde dorado (como MainMenu).
	var fondo := get_node_or_null("Fondo") as ColorRect
	if fondo != null:
		fondo.color = Color(0.05, 0.03, 0.02, 1.0)
	var marco := get_node_or_null("Center/Marco") as PanelContainer
	if marco != null:
		var caja := StyleBoxFlat.new()
		caja.bg_color = Color(0.13, 0.09, 0.06, 0.95)
		caja.border_width_left = 3
		caja.border_width_top = 3
		caja.border_width_right = 3
		caja.border_width_bottom = 3
		caja.border_color = Color(0.72, 0.58, 0.30)
		caja.corner_radius_top_left = 10
		caja.corner_radius_top_right = 10
		caja.corner_radius_bottom_right = 10
		caja.corner_radius_bottom_left = 10
		caja.shadow_color = Color(0, 0, 0, 0.6)
		caja.shadow_size = 18
		marco.add_theme_stylebox_override("panel", caja)
	var titulo := get_node_or_null("Center/Marco/Margen/Caja/Titulo") as Label
	if titulo != null:
		titulo.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
		titulo.add_theme_font_size_override("font_size", 32)
	for ruta in ["Center/Marco/Margen/Caja/FilaOrigen/ElegirButton", "Center/Marco/Margen/Caja/FilaBotones/ExtraerButton", "Center/Marco/Margen/Caja/FilaBotones/VolverButton"]:
		var b := get_node_or_null(ruta) as Button
		if b != null:
			_estilo_boton(b)


func _estilo_boton(btn: Button) -> void:
	# Botón madera oscura con borde dorado apagado y hover brillante.
	btn.add_theme_font_size_override("font_size", 18)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.28, 0.19, 0.11)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(0.62, 0.48, 0.26)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_right = 6
	normal.corner_radius_bottom_left = 6
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.52, 0.36, 0.18)
	hover.border_color = Color(1.0, 0.86, 0.48)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.18, 0.12, 0.07)
	btn.add_theme_stylebox_override("pressed", pressed)
