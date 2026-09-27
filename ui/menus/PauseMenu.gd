extends CanvasLayer
# PauseMenu AoE2: Esc = continuar / guardar / salir.
# CanvasLayer + process_mode ALWAYS para funcionar con get_tree().paused = true.
# Guardar: serializa GameManager (players, map_seed, tick) a user://savegame.json.

const SAVE_PATH := "user://savegame.json"
const MAIN_MENU := "res://ui/menus/MainMenu.tscn"

var _panel: PanelContainer
var _visible_menu := false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	set_menu_visible(false)

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(320, 0)
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)

	var t := Label.new()
	t.text = "⏸ Pausa"
	t.add_theme_font_size_override("font_size", 24)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)

	var cont := Button.new()
	cont.text = "Continuar (Esc)"
	cont.pressed.connect(_on_continue)
	vb.add_child(cont)

	var save := Button.new()
	save.text = "💾 Guardar partida"
	save.pressed.connect(_on_save)
	vb.add_child(save)

	var load := Button.new()
	load.text = "📂 Cargar partida"
	load.pressed.connect(_on_load)
	vb.add_child(load)

	var quit := Button.new()
	quit.text = "🚪 Salir al menú"
	quit.pressed.connect(_on_quit)
	vb.add_child(quit)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	set_menu_visible(not _visible_menu)

func set_menu_visible(v: bool) -> void:
	_visible_menu = v
	_panel.visible = v
	get_tree().paused = v

func _on_continue() -> void:
	set_menu_visible(false)

func _on_quit() -> void:
	set_menu_visible(false)
	get_tree().paused = false
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	NetManager.is_host = false
	get_tree().change_scene_to_file(MAIN_MENU)

# ------------------------------------------------------------ Guardado --

func _on_save() -> void:
	var data := {
		"map_seed": GameManager.map_seed,
		"tick": SimAPI.tick,
		"players": GameManager.players,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("PauseMenu: no se pudo abrir " + SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("PauseMenu: partida guardada en " + SAVE_PATH)
	set_menu_visible(false)

func _on_load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		push_error("PauseMenu: no hay guardado en " + SAVE_PATH)
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("PauseMenu: guardado corrupto.")
		return
	GameManager.map_seed = int(parsed.get("map_seed", 1234))
	SimAPI.tick = int(parsed.get("tick", 0))
	var cfgs: Array = []
	for p in (parsed.get("players", []) as Array):
		if typeof(p) == TYPE_DICTIONARY:
			cfgs.append({"civ": str(p.get("civ", "britones")), "team": int(p.get("team", 0))})
	if not cfgs.is_empty():
		GameManager.setup_lobby(cfgs)
		# Restaura recursos/poblacion/edad exactas del guardado.
		for i in mini(cfgs.size(), (parsed["players"] as Array).size()):
			var src: Dictionary = (parsed["players"] as Array)[i]
			GameManager.players[i]["res"] = (src.get("res", {}) as Dictionary).duplicate(true)
			GameManager.players[i]["pop"] = int(src.get("pop", 3))
			GameManager.players[i]["pop_cap"] = int(src.get("pop_cap", 5))
			GameManager.players[i]["age"] = str(src.get("age", "alta_edad_media"))
			GameManager.players[i]["alive"] = bool(src.get("alive", true))
	print("PauseMenu: partida cargada de " + SAVE_PATH)
	set_menu_visible(false)
