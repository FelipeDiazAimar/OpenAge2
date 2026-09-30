extends Control
## Pantalla "Nueva partida" (antes de jugar con el motor nuevo): jugadores
## (2 a 4) con civilización, equipo y humano/IA; tope de población, semilla
## del mapa y lago. Deja las opciones en MatchConfig y abre Match.

const MatchConfig := preload("res://game/MatchConfig.gd")
const Registry := preload("res://engine/data/Registry.gd")
const MenuStyle := preload("res://ui/menus/MenuStyle.gd")

const MATCH := "res://game/scenes/Match.tscn"
const MENU := "res://ui/menus/MainMenu.tscn"
const MAX_PLAYERS := 4
const POP_OPTIONS := [[0, "Sin límite"], [200, "200 (AoE2)"], [500, "500"], [1000, "1000"]]
const PLAYER_COLORS: Array[Color] = [Color("#2a4bff"), Color("#ff2020"), Color("#20c020"), Color("#ffe020")]

## [[id, nombre]] ordenadas por nombre.
var civs: Array = []
var rows: Array = [] # [{civ: OptionButton, team: OptionButton, ai: OptionButton, box}]
var _rows_box: VBoxContainer
var _filter: LineEdit
var _civ_filter := ""
var _pop: OptionButton
var _seed: SpinBox
var _lake: CheckBox
var _add: Button
var _remove: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_load_civs()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", MenuStyle.panel_madera())
	center.add_child(frame)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	frame.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)
	var title := MenuStyle.titulo_medieval("Nueva partida", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	vb.add_child(_terrain_preview())
	_filter = LineEdit.new()
	_filter.placeholder_text = "Buscar civilización… (filtra las 50+ del mod)"
	_filter.text_changed.connect(_on_civ_filter)
	_filter.custom_minimum_size = Vector2(320, 0)
	vb.add_child(_filter)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 8)
	vb.add_child(_rows_box)
	var prev: Array = MatchConfig.active_slots()
	for i in prev.size():
		_add_row(prev[i])
	var pm := HBoxContainer.new()
	pm.alignment = BoxContainer.ALIGNMENT_CENTER
	_add = MenuStyle.boton_medieval("+ Jugador")
	_add.pressed.connect(func(): _add_row({"civ": civs[rows.size() % civs.size()][0], "team": rows.size(), "ai": true}))
	_remove = MenuStyle.boton_medieval("− Jugador")
	_remove.pressed.connect(_remove_row)
	pm.add_child(_add)
	pm.add_child(_remove)
	vb.add_child(pm)
	vb.add_child(HSeparator.new())
	var opts := GridContainer.new()
	opts.columns = 2
	opts.add_theme_constant_override("h_separation", 16)
	vb.add_child(opts)
	opts.add_child(_label("Población máxima"))
	_pop = OptionButton.new()
	for o in POP_OPTIONS:
		_pop.add_item(str(o[1]))
		if int(o[0]) == MatchConfig.pop_max:
			_pop.select(_pop.item_count - 1)
	opts.add_child(_pop)
	opts.add_child(_label("Semilla del mapa"))
	var sb := HBoxContainer.new()
	_seed = SpinBox.new()
	_seed.min_value = 1
	_seed.max_value = 999999
	_seed.value = MatchConfig.map_seed
	sb.add_child(_seed)
	var rnd := Button.new()
	rnd.text = "Aleatoria"
	rnd.pressed.connect(func(): _seed.value = randi_range(1, 999999))
	sb.add_child(rnd)
	opts.add_child(sb)
	opts.add_child(_label("Lago central (muelles y barcos)"))
	_lake = CheckBox.new()
	_lake.button_pressed = MatchConfig.lake
	opts.add_child(_lake)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 24)
	var back := MenuStyle.boton_medieval("Volver")
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU))
	var play := MenuStyle.boton_medieval("¡Jugar!")
	play.pressed.connect(start)
	actions.add_child(back)
	actions.add_child(play)
	vb.add_child(actions)
	_update_buttons()
	play.call_deferred("grab_focus")


## Preview de mapa: un swatch por terreno con el color de cada def (sin fallback gris/negro).
func _terrain_preview() -> HBoxContainer:
	var r := Registry.new()
	r.load_mods("res://mods")
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for id in r.ids_of_type("terrain"):
		var def: Dictionary = r.get_def(id)
		var sw := ColorRect.new()
		sw.color = Color(str(def.get("color", "#6a8a3a")))
		sw.custom_minimum_size = Vector2(20, 20)
		sw.tooltip_text = "%s (%s)" % [str(def.get("name", id)), str(id)]
		bar.add_child(sw)
	return bar


func _load_civs() -> void:
	var r := Registry.new()
	r.load_mods("res://mods")
	for id in r.ids_of_type("civ"):
		civs.append([id, str(r.get_def(id).get("name", id))])
	civs.sort_custom(func(a, b): return str(a[1]) < str(b[1]))


func _fill_civ_items(ob: OptionButton, keep_id: String) -> void:
	ob.clear()
	var q := _civ_filter.strip_edges().to_lower()
	for c in civs:
		# La ya elegida siempre queda en la lista: filtrar no cambia la elección.
		if q != "" and str(c[0]) != keep_id and not (str(c[0]).to_lower().contains(q) or str(c[1]).to_lower().contains(q)):
			continue
		ob.add_item(str(c[1]))
		ob.set_item_metadata(ob.item_count - 1, str(c[0]))
		if str(c[0]) == keep_id:
			ob.select(ob.item_count - 1)
	if ob.item_count > 0 and ob.selected < 0:
		ob.select(0)


func _on_civ_filter(t: String) -> void:
	_civ_filter = t
	for r in rows:
		_fill_civ_items(r["civ"], str(r["civ_id"]))


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	return l


func _add_row(slot: Dictionary) -> void:
	if rows.size() >= MAX_PLAYERS:
		return
	var i := rows.size()
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var swatch := ColorRect.new()
	swatch.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
	swatch.custom_minimum_size = Vector2(18, 18)
	box.add_child(swatch)
	var name := _label("Jugador %d" % (i + 1))
	name.custom_minimum_size = Vector2(90, 0)
	box.add_child(name)
	var civ := OptionButton.new()
	civ.custom_minimum_size = Vector2(220, 0)
	civ.clip_text = true # popup nativo con scroll para la lista larga
	var civ_id := str(slot.get("civ", civs[0][0] if not civs.is_empty() else ""))
	_fill_civ_items(civ, civ_id)
	box.add_child(civ)
	var team := OptionButton.new()
	for t in MAX_PLAYERS:
		team.add_item("Equipo %d" % (t + 1))
	team.select(clampi(int(slot.get("team", i)), 0, MAX_PLAYERS - 1))
	box.add_child(team)
	var ai := OptionButton.new()
	ai.add_item("Tú")
	ai.add_item("IA")
	ai.select(1 if bool(slot.get("ai", false)) else 0)
	# Local: el jugador 1 es quien juega en esta PC y el resto, la IA
	# (otros humanos llegan con el lobby LAN).
	ai.disabled = true
	ai.select(0 if i == 0 else 1)
	box.add_child(ai)
	_rows_box.add_child(box)
	var row := {"civ": civ, "civ_id": civ_id, "team": team, "ai": ai, "box": box}
	civ.item_selected.connect(func(idx: int): row["civ_id"] = str(civ.get_item_metadata(idx)))
	rows.append(row)
	_update_buttons()


func _remove_row() -> void:
	if rows.size() <= 2:
		return
	var r: Dictionary = rows.pop_back()
	r["box"].queue_free()
	_update_buttons()


func _update_buttons() -> void:
	if _add != null:
		_add.disabled = rows.size() >= MAX_PLAYERS
	if _remove != null:
		_remove.disabled = rows.size() <= 2


## Opciones elegidas (para MatchConfig y pruebas).
func chosen_slots() -> Array:
	var out: Array = []
	for r in rows:
		out.append({"civ": str(r["civ_id"]), "team": r["team"].selected, "ai": r["ai"].selected == 1})
	return out


func start() -> void:
	MatchConfig.slots = chosen_slots()
	MatchConfig.pop_max = int(POP_OPTIONS[maxi(0, _pop.selected)][0])
	MatchConfig.map_seed = int(_seed.value)
	MatchConfig.lake = _lake.button_pressed
	get_tree().change_scene_to_file(MATCH)
