extends Control
## HUD clon AoE2 — OpenAge-LAN.
##
## TOP-CENTER: barra recursos estilo AoE2:
##   [♣ Madera] [♥ Alimento] [● Oro] [▲ Piedra] [Pob actual/cap] [Edad] [tiempo] [FPS]
## BOTTOM (ancho completo, estilo AoE2):
##   [slot minimapa 200px izq] [info selección: retrato color, nombre, HP bar, atk/armor]
##   [grid comandos 3x5] [panel edad / menú]
##
## - Iconos: texto unicode seguro (fuente default, sin assets) + labels coloreados.
## - Grid principal: Atacar(A) Patrulla(P) Stop(S) Guarecer(G) Reparar(R) Construir(B-submenú)
##   + extras Campana(T) Desguarecer(U) Ir-a-TC(H) Aldeano-inactivo(.) Avanzar-edad.
## - Submenú Construir (B): 12 edificios de BuildingDefs + Atrás + Cancelar.
## - Tooltips en todos los botones (hotkey + efecto + coste).
## - Conectado a EventBus.resources_changed / selection_changed / age_up (+ tick_finished).
## - Comandos salen por SimAPI.queue_command(pid, type, payload) — lockstep 10 Hz.
## - Sin randf/Time en lógica sim; el HUD (UI) sí puede usar Time/Engine FPS.

const LOCAL_DEFAULT_PID := 0
const TICKS_PER_SEC := 10

# Iconos texto (unicode de fuente default; evita emoji que no renderiza en GL Compat).
const ICON_WOOD := "♣"
const ICON_FOOD := "♥"
const ICON_GOLD := "●"
const ICON_STONE := "▲"
const ICON_POP := "⌂"
const ICON_AGE := "✦"
const ICON_TIME := "◷"

# Edificios del submenú construir. Debe coincidir con BuildingDefs.BUILDING_IDS.
const BUILD_MENU_IDS: Array[String] = [
	"casa", "centro_urbano", "cuartel", "campamento_maderero",
	"molino", "campamento_minero", "granja", "mercado",
	"monasterio", "herreria", "universidad", "muelle",
]

const BUILD_PRETTY := {
	"casa": "Casa", "centro_urbano": "Centro Urbano", "cuartel": "Cuartel",
	"campamento_maderero": "Camp. Maderero", "molino": "Molino",
	"campamento_minero": "Camp. Minero", "granja": "Granja", "mercado": "Mercado",
	"monasterio": "Monasterio", "herreria": "Herrería",
	"universidad": "Universidad", "muelle": "Muelle",
}

var local_player_id := LOCAL_DEFAULT_PID
var selection_ref: Control = null # Selection con get_selected()/get_unit_type()
var cur_res := {"wood": 200.0, "food": 200.0, "gold": 100.0, "stone": 200.0}
var cur_pop := 3
var cur_pop_cap := 5
var cur_age := "alta_edad_media"
var game_tick := 0
var current_selection: Array = []
var in_build_submenu := false
var pending_action := "" # "attack_move" | "patrol" | "repair" | "build:<id>" | ""

# --- Nodos top ---
var lbl_wood: Label
var lbl_food: Label
var lbl_gold: Label
var lbl_stone: Label
var lbl_pop: Label
var lbl_age: Label
var lbl_time: Label
var lbl_fps: Label
var lbl_hint: Label

# --- Nodos bottom ---
var portrait: ColorRect
var lbl_sel_name: Label
var hp_bar: ProgressBar
var lbl_sel_hp: Label
var lbl_sel_stats: Label
var lbl_sel_count: Label
var cmd_grid: GridContainer
var btn_age_up: Button
var lbl_age_progress: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit_to_viewport()
	_build_top_bar()
	_build_bottom_bar()
	_connect_bus()
	_refresh_from_gamemanager()
	_refresh_commands()
	_update_selection_panel()


func _process(_delta: float) -> void:
	_fit_to_viewport() # blindaje: si los anclajes fallan, fuerza tamaño viewport
	# Reloj + FPS (UI pura, no lógica sim: permitido usar Engine).
	var secs := game_tick / TICKS_PER_SEC
	lbl_time.text = "%s %02d:%02d" % [ICON_TIME, secs / 60, secs % 60]
	lbl_fps.text = "%d FPS" % Engine.get_frames_per_second()


func _unhandled_input(event: InputEvent) -> void:
	# Hotkeys espejo de project.godot [input] + R (reparar) por teclado directo.
	if event.is_action_pressed("attack_move"):
		_on_cmd_attack()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("patrol"):
		_on_cmd_patrol()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("stop_action"):
		_on_cmd_stop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("garrison"):
		_on_cmd_garrison()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_menu"):
		_toggle_build_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("bell"):
		_on_cmd_bell()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("go_tc"):
		_on_cmd_go_tc()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("idle_villager"):
		_on_cmd_idle_villager()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_R:
				_on_cmd_repair()
				get_viewport().set_input_as_handled()
			KEY_U:
				_on_cmd_ungarrison()
				get_viewport().set_input_as_handled()
			KEY_F9:
				_dump_debug()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if in_build_submenu or pending_action != "":
					pending_action = ""
					lbl_hint.text = ""
					_show_main_commands()
					get_viewport().set_input_as_handled()


# ======================================================================
# Construcción UI
# ======================================================================

## Fuerza al HUD raíz al tamaño del viewport (blindaje contra anclajes rotos:
## con tamaño 0 la barra inferior cae fuera de pantalla y la superior se corta).
func _fit_to_viewport() -> void:
	if not is_inside_tree():
		return
	var vs := get_viewport_rect().size
	if vs.x > 10.0 and vs.y > 10.0 and size != vs:
		position = Vector2.ZERO
		size = vs


func _aoe_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.05, 0.92)
	sb.border_color = Color(0.55, 0.42, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	return p


func _aoe_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(92, 44)
	b.focus_mode = Control.FOCUS_NONE
	# Marrón piedra AoE2.
	b.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.8))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.47, 0.42))
	return b


func _res_label(text: String, tip: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.tooltip_text = tip
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _build_top_bar() -> void:
	var panel := _aoe_panel()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 6
	panel.offset_top = 6
	panel.offset_right = -6
	panel.offset_bottom = 44
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 18)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hb)
	lbl_wood = _res_label("♣ 200", "Madera: tala de aldeanos. Hotkey aldeano: B → campamento.", Color(0.55, 0.85, 0.45))
	lbl_food = _res_label("♥ 200", "Alimento: granjas, caza, pesca. Crea aldeanos y avanza de edad.", Color(0.95, 0.75, 0.4))
	lbl_gold = _res_label("● 100", "Oro: minería y comercio. Tropas, tecnologías y Castillos.", Color(1.0, 0.85, 0.25))
	lbl_stone = _res_label("▲ 200", "Piedra: torres, castillos y murallas.", Color(0.75, 0.75, 0.78))
	lbl_pop = _res_label("⌂ 3/5", "Población actual / límite. Construye Casas (+5) para no bloquearte.", Color(0.9, 0.9, 0.9))
	lbl_age = _res_label("✦ Alta Edad Media", "Edad actual. Investiga en el Centro Urbano para avanzar.", Color(0.6, 0.85, 1.0))
	lbl_time = _res_label("◷ 00:00", "Tiempo de partida (reloj sim 10 Hz).", Color(0.85, 0.85, 0.85))
	lbl_fps = _res_label("60 FPS", "Fotogramas por segundo (solo render, no afecta a la sim).", Color(0.6, 0.6, 0.6))
	for l in [lbl_wood, lbl_food, lbl_gold, lbl_stone, lbl_pop, lbl_age, lbl_time, lbl_fps]:
		hb.add_child(l)


func _build_bottom_bar() -> void:
	var panel := _aoe_panel()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -196
	panel.offset_left = 6
	panel.offset_right = -6
	add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)

	# --- Slot minimapa (el minimapa real lo incrusta el agente 26 / FogOfWar) ---
	var mm := SubViewportContainer.new()
	mm.name = "MinimapSlot"
	mm.custom_minimum_size = Vector2(200, 178)
	mm.stretch = true
	mm.tooltip_text = "Minimapa. Click: mover cámara. Alt+Click: ping a aliados."
	hb.add_child(mm)

	# --- Info selección ---
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(330, 178)
	info.add_theme_constant_override("separation", 4)
	hb.add_child(info)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	info.add_child(top_row)
	portrait = ColorRect.new()
	portrait.custom_minimum_size = Vector2(56, 56)
	portrait.color = Color("#2a4bff")
	portrait.tooltip_text = "Retrato: color del jugador dueño de la selección."
	top_row.add_child(portrait)
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(name_col)
	lbl_sel_name = Label.new()
	lbl_sel_name.text = "Sin selección"
	lbl_sel_name.add_theme_font_size_override("font_size", 16)
	lbl_sel_name.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	lbl_sel_name.tooltip_text = "Nombre de la unidad / edificio seleccionado (o nº de unidades)."
	name_col.add_child(lbl_sel_name)
	lbl_sel_count = Label.new()
	lbl_sel_count.text = ""
	lbl_sel_count.add_theme_font_size_override("font_size", 13)
	lbl_sel_count.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7))
	name_col.add_child(lbl_sel_count)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 16)
	hp_bar.min_value = 0
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.show_percentage = false
	hp_bar.tooltip_text = "Puntos de vida. Verde > 60%, amarillo > 30%, rojo = crítico."
	info.add_child(hp_bar)
	lbl_sel_hp = Label.new()
	lbl_sel_hp.text = "HP —"
	lbl_sel_hp.add_theme_font_size_override("font_size", 13)
	info.add_child(lbl_sel_hp)
	lbl_sel_stats = Label.new()
	lbl_sel_stats.text = "Atk —   Arm —   Alc —"
	lbl_sel_stats.add_theme_font_size_override("font_size", 13)
	lbl_sel_stats.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	lbl_sel_stats.tooltip_text = "Ataque / armadura cuerpo a cuerpo y perforante / alcance."
	info.add_child(lbl_sel_stats)

	# --- Grid comandos 3x5 ---
	var grid_wrap := VBoxContainer.new()
	grid_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(grid_wrap)
	cmd_grid = GridContainer.new()
	cmd_grid.name = "CommandGrid"
	cmd_grid.columns = 5
	cmd_grid.add_theme_constant_override("h_separation", 6)
	cmd_grid.add_theme_constant_override("v_separation", 6)
	grid_wrap.add_child(cmd_grid)
	lbl_hint = Label.new()
	lbl_hint.text = ""
	lbl_hint.add_theme_font_size_override("font_size", 12)
	lbl_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid_wrap.add_child(lbl_hint)

	# --- Panel edad / menú ---
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(210, 178)
	right.add_theme_constant_override("separation", 6)
	hb.add_child(right)
	btn_age_up = _aoe_button("Avanzar Edad", "Investiga la siguiente edad en el Centro Urbano.")
	btn_age_up.custom_minimum_size = Vector2(210, 44)
	btn_age_up.pressed.connect(_on_cmd_age_up)
	right.add_child(btn_age_up)
	lbl_age_progress = Label.new()
	lbl_age_progress.text = ""
	lbl_age_progress.add_theme_font_size_override("font_size", 12)
	lbl_age_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(lbl_age_progress)
	var btn_menu := _aoe_button("Menú (F10)", "Abrir menú de partida: guardar, opciones, rendirse.")
	btn_menu.custom_minimum_size = Vector2(210, 44)
	btn_menu.pressed.connect(func() -> void: lbl_hint.text = "Menú: usa Guardar / Rendirse desde el menú principal (agente UI).")
	right.add_child(btn_menu)


func _connect_bus() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus == null:
		push_warning("HUD: EventBus no encontrado (¿falta autoload?). HUD en modo local.")
		return
	if not bus.is_connected("resources_changed", _on_resources_changed):
		bus.connect("resources_changed", _on_resources_changed)
	if not bus.is_connected("selection_changed", _on_selection_changed):
		bus.connect("selection_changed", _on_selection_changed)
	if not bus.is_connected("age_up", _on_age_up):
		bus.connect("age_up", _on_age_up)
	if bus.has_signal("tick_finished") and not bus.is_connected("tick_finished", _on_tick):
		bus.connect("tick_finished", _on_tick)


func _refresh_from_gamemanager() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return
	if gm.get("players") is Array and local_player_id < (gm.get("players") as Array).size():
		var p: Dictionary = (gm.get("players") as Array)[local_player_id]
		if p.has("res"):
			_on_resources_changed(local_player_id, (p["res"] as Dictionary).duplicate(true))
		cur_pop = int(p.get("pop", cur_pop))
		cur_pop_cap = int(p.get("pop_cap", cur_pop_cap))
		cur_age = str(p.get("age", cur_age))
		_update_top_bar()


# ======================================================================
# Top bar
# ======================================================================

func _on_resources_changed(player_id: int, res: Dictionary) -> void:
	if player_id != local_player_id:
		return
	cur_res = res.duplicate(true)
	# GameManager re-notifica pop vía resources_changed: relee pop/cap si hay GM.
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("get_player"):
		var p: Dictionary = gm.call("get_player", local_player_id)
		if not p.is_empty():
			cur_pop = int(p.get("pop", cur_pop))
			cur_pop_cap = int(p.get("pop_cap", cur_pop_cap))
	_update_top_bar()


func _on_tick(t: int) -> void:
	game_tick = t
	# Refresca progreso de edad sin SceneTreeTimer (determinista, por tick).
	_update_age_progress()


func _on_age_up(player_id: int, new_age: String) -> void:
	if player_id != local_player_id:
		return
	cur_age = new_age
	_update_top_bar()
	_update_age_progress()
	_refresh_commands()
	lbl_hint.text = "¡Avanzaste a %s!" % pretty_age(new_age)


func _update_top_bar() -> void:
	lbl_wood.text = "%s %d" % [ICON_WOOD, int(float(cur_res.get("wood", 0.0)))]
	lbl_food.text = "%s %d" % [ICON_FOOD, int(float(cur_res.get("food", 0.0)))]
	lbl_gold.text = "%s %d" % [ICON_GOLD, int(float(cur_res.get("gold", 0.0)))]
	lbl_stone.text = "%s %d" % [ICON_STONE, int(float(cur_res.get("stone", 0.0)))]
	lbl_pop.text = "%s %d/%d" % [ICON_POP, cur_pop, cur_pop_cap]
	lbl_age.text = "%s %s" % [ICON_AGE, pretty_age(cur_age)]
	# Rojo si población bloqueada (estilo AoE2).
	lbl_pop.add_theme_color_override(
		"font_color", Color(1.0, 0.35, 0.3) if cur_pop >= cur_pop_cap else Color(0.9, 0.9, 0.9)
	)


func pretty_age(age_id: String) -> String:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("get_age_data"):
		var d: Dictionary = gm.call("get_age_data", age_id)
		if d.has("name"):
			return str(d["name"])
	# Fallback espejo de data/ages/ages.json.
	match age_id:
		"alta_edad_media":
			return "Alta Edad Media"
		"feudal":
			return "Feudal"
		"castillos":
			return "Castillos"
		"imperial":
			return "Imperial"
	return age_id


func _update_age_progress() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("get_age_progress"):
		lbl_age_progress.text = ""
		btn_age_up.disabled = false
		return
	var prog: Dictionary = gm.call("get_age_progress", local_player_id)
	if prog.is_empty():
		lbl_age_progress.text = ""
		var chk: Dictionary = gm.call("can_advance_age", local_player_id, "")
		if bool(chk.get("ok", false)):
			var cost: Dictionary = chk.get("cost", {})
			btn_age_up.disabled = false
			btn_age_up.text = "Avanzar Edad"
			btn_age_up.tooltip_text = "Avanza a la siguiente edad. Coste: %s." % _cost_text(cost)
		else:
			btn_age_up.disabled = true
			btn_age_up.text = "Avanzar Edad"
			btn_age_up.tooltip_text = "No puedes avanzar: %s." % str(chk.get("reason", "?"))
	else:
		var left: int = int(prog.get("ticks_left", 0))
		var total: int = maxi(1, int(prog.get("ticks_total", 1)))
		var pct := 100.0 * float(total - left) / float(total)
		lbl_age_progress.text = "Investigando %s… %d%%" % [pretty_age(str(prog.get("target", ""))), int(pct)]
		btn_age_up.disabled = false
		btn_age_up.text = "Cancelar (%d%% dev.)" % 50
		btn_age_up.tooltip_text = "Cancela la investigación. Reembolso del 50% (regla GameManager)."


func _cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "gratis"
	var parts: PackedStringArray = []
	for k in ["food", "wood", "gold", "stone"]:
		if cost.has(k) and float(cost[k]) > 0.0:
			parts.append("%d %s" % [int(float(cost[k])), str(k)])
	return ", ".join(parts) if not parts.is_empty() else "gratis"


# ======================================================================
# Selección
# ======================================================================

func _on_selection_changed(units: Array) -> void:
	current_selection = units.duplicate()
	_update_selection_panel()
	_refresh_commands()


func _sel_field(u: Variant, key: String, fallback: Variant = 0) -> Variant:
	# La selección puede ser Dictionary (IA/tests) o Node (mundo 3D). Soporta ambos.
	if u is Dictionary:
		return (u as Dictionary).get(key, fallback)
	if u is Object and (u as Object).has_method("get"):
		var v = (u as Object).get(key)
		return v if v != null else fallback
	return fallback


func _update_selection_panel() -> void:
	if current_selection.is_empty():
		lbl_sel_name.text = "Sin selección"
		lbl_sel_count.text = "Arrastra para seleccionar. Click: una unidad."
		hp_bar.value = 0
		lbl_sel_hp.text = "HP —"
		lbl_sel_stats.text = "Atk —   Arm —   Alc —"
		portrait.color = Color(0.2, 0.2, 0.2, 1.0)
		return
	var first: Variant = current_selection[0]
	var uname := str(_sel_field(first, "name", _sel_field(first, "unit_id", _sel_field(first, "id", "Unidad"))))
	var pid := int(_sel_field(first, "player_id", _sel_field(first, "owner", local_player_id)))
	if current_selection.size() == 1:
		lbl_sel_name.text = uname.capitalize()
		lbl_sel_count.text = "Jugador %d" % (pid + 1)
	else:
		lbl_sel_name.text = "%s ×%d" % [uname.capitalize(), current_selection.size()]
		lbl_sel_count.text = "Grupo de %d unidades" % current_selection.size()
	# HP: media del grupo (AoE2 muestra la unidad principal; media = más útil en grupo).
	var hp_sum := 0.0
	var max_sum := 0.0
	for u in current_selection:
		hp_sum += float(_sel_field(u, "hp", 0.0))
		max_sum += float(_sel_field(u, "max_hp", _sel_field(u, "hp_max", 0.0)))
	if max_sum <= 0.0:
		hp_bar.value = 0
		lbl_sel_hp.text = "HP —"
	else:
		var pct := 100.0 * hp_sum / max_sum
		hp_bar.value = pct
		lbl_sel_hp.text = "HP %d/%d (%d%%)" % [int(hp_sum), int(max_sum), int(pct)]
		hp_bar.modulate = Color(0.35, 0.9, 0.35) if pct > 60.0 else (Color(0.95, 0.85, 0.3) if pct > 30.0 else Color(0.9, 0.3, 0.25))
	var atk := float(_sel_field(first, "attack", _sel_field(first, "atk", 0.0)))
	var armor := float(_sel_field(first, "armor", _sel_field(first, "armadura", 0.0)))
	var prange := float(_sel_field(first, "range", _sel_field(first, "alcance", 0.0)))
	lbl_sel_stats.text = "Atk %d   Arm %d   Alc %s" % [int(atk), int(armor), ("%d" % int(prange)) if prange > 0.0 else "—"]
	# Retrato = color del jugador (clon barato sin sprites; agente 26 pone iconos CC0).
	portrait.color = _player_color(pid)


func _player_color(pid: int) -> Color:
	var api := get_node_or_null("/root/SimAPI")
	if api != null and api.has_method("get_player_color"):
		return api.call("get_player_color", pid) as Color
	var cols := [Color("#2a4bff"), Color("#ff0000"), Color("#00ff00"), Color("#ffff00"),
		Color("#00c8ff"), Color("#c800ff"), Color("#969696"), Color("#ff8c00")]
	return cols[pid % cols.size()] as Color


# ======================================================================
# Grid comandos 3x5
# ======================================================================

func _clear_grid() -> void:
	for c in cmd_grid.get_children():
		c.queue_free()


func _refresh_commands() -> void:
	_clear_grid()
	if in_build_submenu:
		_show_build_submenu()
	else:
		_show_main_commands()


func _toggle_build_menu() -> void:
	in_build_submenu = not in_build_submenu
	if not in_build_submenu:
		pending_action = ""
		lbl_hint.text = ""
	_refresh_commands()


func _fill_empty_slots(used: int) -> void:
	# El grid es 3x5 = 15 slots. Rellena vacíos con botones desactivados
	# semitransparentes para mantener la forma AoE2 aunque haya pocos comandos.
	for i in range(used, 15):
		var f := Button.new()
		f.text = ""
		f.disabled = true
		f.focus_mode = Control.FOCUS_NONE
		f.custom_minimum_size = Vector2(92, 44)
		f.modulate = Color(1, 1, 1, 0.25)
		cmd_grid.add_child(f)


func _show_main_commands() -> void:
	in_build_submenu = false
	if pending_action != "" and not pending_action.begins_with("build:"):
		lbl_hint.text = "Orden %s: CLICK DERECHO en el mapa para indicar el objetivo. Esc cancela." % pending_action
	if _show_train_commands():
		return
	var defs: Array = [
		{"t": "⚔ Atacar (A)", "tip": "Atacar / movimiento de ataque (A).\nClick derecho en enemigo tras pulsar, o A + click en suelo.\nCola con Shift.", "fn": _on_cmd_attack},
		{"t": "➤ Patrulla (P)", "tip": "Patrullar entre dos puntos atacando enemigos (P).\nPulsa P y marca el destino.", "fn": _on_cmd_patrol},
		{"t": "■ Stop (S)", "tip": "Detener la unidad al instante (S). Cancela la orden actual.", "fn": _on_cmd_stop},
		{"t": "⌂ Guarecer (G)", "tip": "Guarecer en edificio aliado (G).\nPulsa G y click en el edificio.", "fn": _on_cmd_garrison},
		{"t": "🔧 Reparar (R)", "tip": "Reparar edificio/asedio aliado dañado (R).\n15 HP/s, cuesta 50% del coste. Pulsa R y click en objetivo.", "fn": _on_cmd_repair},
		{"t": "🏠 Construir (B)", "tip": "Abrir submenú de edificios (B).\nEl aldeano construye el blueprint.", "fn": _toggle_build_menu},
		{"t": "🔔 Campana (T)", "tip": "Tocar campana (T): los aldeanos se refugian en el Centro Urbano. Pulsa de nuevo para salir.", "fn": _on_cmd_bell},
		{"t": "⤓ Salir (U)", "tip": "Desguarecer (U): saca las unidades del edificio seleccionado.", "fn": _on_cmd_ungarrison},
		{"t": "★ TC (H)", "tip": "Ir al Centro Urbano (H): selecciona y centra la cámara.", "fn": _on_cmd_go_tc},
		{"t": "• Inactivo (.)", "tip": "Seleccionar aldeano inactivo (.).", "fn": _on_cmd_idle_villager},
	]
	for d in defs:
		var b := _aoe_button(str(d["t"]), str(d["tip"]))
		b.pressed.connect(d["fn"] as Callable)
		b.disabled = current_selection.is_empty() and not (str(d["t"]).contains("TC") or str(d["t"]).contains("Inactivo"))
		cmd_grid.add_child(b)
	_fill_empty_slots(defs.size())


func _show_build_submenu() -> void:
	lbl_hint.text = "Submenú construir: elige edificio. B / Esc para volver."
	for bid in BUILD_MENU_IDS:
		var pretty := str(BUILD_PRETTY.get(bid, bid.capitalize()))
		var cost := _building_cost(bid)
		var tip := "Construir %s (B → click).\nCoste: %s.\nClick en el mapa para colocar el blueprint." % [pretty, _cost_text(cost)]
		var b := _aoe_button(pretty, tip)
		var id_copy := bid
		b.pressed.connect(func() -> void: _on_cmd_build(id_copy))
		b.disabled = current_selection.is_empty()
		cmd_grid.add_child(b)
	var back := _aoe_button("◀ Atrás (B)", "Volver a los comandos principales (B o Esc).")
	back.pressed.connect(_toggle_build_menu)
	cmd_grid.add_child(back)
	var cancel := _aoe_button("✖ Cancelar", "Cancelar orden pendiente (Esc).")
	cancel.pressed.connect(_on_cancel_pending)
	cmd_grid.add_child(cancel)
	_fill_empty_slots(BUILD_MENU_IDS.size() + 2)


func _on_cancel_pending() -> void:
	pending_action = ""
	lbl_hint.text = ""
	_show_main_commands()


## Edificio seleccionado -> botones de entrenar sus tropas. True si los mostró.
func _show_train_commands() -> bool:
	if current_selection.size() != 1 or selection_ref == null:
		return false
	if not selection_ref.has_method("get_unit_type"):
		return false
	var uid := int(current_selection[0]) if current_selection[0] is int else -1
	if uid < 0:
		return false
	var trains: Array = _trains_for(selection_ref.get_unit_type(uid))
	if trains.is_empty():
		return false
	_clear_grid()
	for u in trains:
		var b := _aoe_button(str(u.get("label", u.get("id", "?"))), str(u.get("tip", "")))
		var unit_id := str(u.get("id", ""))
		var bld := uid
		b.pressed.connect(func() -> void: _on_cmd_train(bld, unit_id))
		cmd_grid.add_child(b)
	_fill_empty_slots(trains.size())
	return true


## Qué entrena cada edificio (igual que data/buildings/*.json trains).
func _trains_for(building_type: String) -> Array:
	match building_type.to_lower().strip_edges():
		"centro_urbano":
			return [{"id": "aldeano", "label": "Aldeano (50F)", "tip": "Crear aldeano. Click para entrenar."}]
		"cuartel":
			return [
				{"id": "milicia", "label": "Milicia", "tip": "Infantería cuerpo a cuerpo."},
				{"id": "lancero", "label": "Lancero", "tip": "Bonus contra caballería."}]
		"arqueria":
			return [
				{"id": "arquero", "label": "Arquero", "tip": "Ataque a distancia."},
				{"id": "guerrillero", "label": "Guerrillero", "tip": "Bonus contra arqueros."}]
		"establo":
			return [
				{"id": "scout", "label": "Scout", "tip": "Caballería rápida de exploración."},
				{"id": "jinete", "label": "Jinete", "tip": "Caballería de choque."}]
		"monasterio":
			return [{"id": "monje", "label": "Monje (100O)", "tip": "Convierte y cura."}]
		"taller_asedio":
			return [
				{"id": "ariete", "label": "Ariete", "tip": "Derriba edificios."},
				{"id": "catapulta", "label": "Catapulta", "tip": "Daño en área."}]
		"mercado":
			return [{"id": "carreta_comercio", "label": "Carreta", "tip": "Comercia oro entre mercados."}]
		"muelle":
			return [
				{"id": "barco_pesquero", "label": "Pesquero", "tip": "Pesca alimento."},
				{"id": "galera", "label": "Galera", "tip": "Barco de guerra."}]
		"castillo":
			return [{"id": "trebuchet", "label": "Trabuquete", "tip": "Asedio de largo alcance."}]
	return []


func _on_cmd_train(building_uid: int, unit_id: String) -> void:
	_issue("train", {"building_id": building_uid, "unit_id": unit_id})
	_refresh_commands()


func _building_cost(bid: String) -> Dictionary:
	# Lee coste sin instanciar: prueba BuildingDefs autoload/node, si no, coste vacío.
	var bd := get_node_or_null("/root/BuildingDefs")
	if bd != null and bd.has_method("cost_of"):
		return bd.call("cost_of", bid) as Dictionary
	return {}


func _selected_ids() -> Array:
	var out: Array = []
	for u in current_selection:
		if u is int:
			out.append(int(u))
			continue
		out.append(int(_sel_field(u, "id", out.size())))
	return out


func _issue(cmd_type: String, payload: Dictionary = {}) -> void:
	var api := get_node_or_null("/root/SimAPI")
	if api == null or not api.has_method("queue_command"):
		lbl_hint.text = "SimAPI no disponible: comando %s no enviado." % cmd_type
		return
	if current_selection.is_empty() and cmd_type not in ["bell", "go_tc", "idle_villager"]:
		lbl_hint.text = "Sin selección: selecciona unidades primero."
		return
	var p := payload.duplicate(true)
	if not p.has("unit_ids") and not current_selection.is_empty():
		p["unit_ids"] = _selected_ids()
	api.call("queue_command", local_player_id, cmd_type, p)
	lbl_hint.text = "Orden enviada: %s." % cmd_type


# --- Handlers de comandos (data/actions.json) ---

func _on_cmd_attack() -> void:
	# Orden con objetivo: solo arma pending_action, SmartController la envía
	# con click DERECHO sobre el mapa (nada se envía sin destino).
	pending_action = "attack_move"
	lbl_hint.text = "⚔ Atacar: CLICK DERECHO en enemigo o suelo (A). Esc cancela."


func _on_cmd_patrol() -> void:
	pending_action = "patrol"
	lbl_hint.text = "➤ Patrulla: CLICK DERECHO en el punto destino (P). Esc cancela."


func _on_cmd_stop() -> void:
	pending_action = ""
	_issue("stop", {})


func _on_cmd_garrison() -> void:
	pending_action = "garrison"
	lbl_hint.text = "⌂ Guarecer: CLICK DERECHO en edificio aliado (G). Esc cancela."


func _on_cmd_repair() -> void:
	pending_action = "repair"
	lbl_hint.text = "🔧 Reparar: CLICK DERECHO en edificio aliado dañado (R). Esc cancela."


func _on_cmd_build(building_id: String) -> void:
	pending_action = "build:" + building_id
	lbl_hint.text = "🏠 %s: CLICK DERECHO en el mapa para colocar. Esc cancela." % str(BUILD_PRETTY.get(building_id, building_id))


func _on_cmd_bell() -> void:
	_issue("bell", {})


func _on_cmd_ungarrison() -> void:
	_issue("ungarrison", {})


func _on_cmd_go_tc() -> void:
	lbl_hint.text = "Centrando Centro Urbano (H)…"
	_issue("go_tc", {})


func _on_cmd_idle_villager() -> void:
	lbl_hint.text = "Buscando aldeano inactivo (.)…"
	# VillagerAI resuelve la selección y emite selection_changed + focus_camera.
	_issue("idle_villager", {})


func _on_cmd_age_up() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("advance_age"):
		return
	if gm.has_method("is_researching") and bool(gm.call("is_researching", local_player_id)):
		if gm.has_method("cancel_age_up"):
			gm.call("cancel_age_up", local_player_id)
			lbl_hint.text = "Investigación cancelada (reembolso 50%)."
			_update_age_progress()
		return
	var api := get_node_or_null("/root/SimAPI")
	if api != null and api.has_method("queue_command"):
		api.call("queue_command", local_player_id, "age_up", {})
	else:
		gm.call("advance_age", local_player_id, "")
	_update_age_progress()


## Cambia el jugador local observado (LAN / tests). Relee recursos y edad.
func set_local_player(pid: int) -> void:
	local_player_id = maxi(0, pid)
	_refresh_from_gamemanager()
	_update_age_progress()
	_refresh_commands()


## F9: vuelca el árbol del HUD (rects, visibilidad, textos) a user://hud_debug.txt.
## Seguro para pedir al jugador si algo no se ve.
func _dump_debug() -> void:
	var txt := "HUD debug %s viewport=%s\n" % [Time.get_datetime_string_from_system(), str(get_viewport().get_visible_rect().size)]
	txt += _debug_node(self, 0)
	var f := FileAccess.open("user://hud_debug.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(txt)
	lbl_hint.text = "Debug volcado en hud_debug.txt (F9). Mándame ese archivo."


func _debug_node(n: Node, depth: int) -> String:
	var s := ""
	if depth > 3:
		return s
	var info := ""
	if n is Control:
		var c := n as Control
		info = " vis=%s pos=%s size=%s" % [str(c.visible), str(c.position), str(c.size)]
	s += "%s%s%s kids=%d\n" % ["  ".repeat(depth), n.name, info, n.get_child_count()]
	if n is Label:
		s += "%s  text='%s'\n" % ["  ".repeat(depth), (n as Label).text]
	elif n is Button:
		s += "%s  btn='%s' disabled=%s\n" % ["  ".repeat(depth), (n as Button).text.left(40), str((n as Button).disabled)]
	for ch in n.get_children():
		s += _debug_node(ch, depth + 1)
	return s
