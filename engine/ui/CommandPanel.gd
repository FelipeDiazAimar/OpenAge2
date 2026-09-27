extends PanelContainer
## Panel de órdenes (abajo a la izquierda, estilo AoE2): con aldeanos,
## páginas de edificios (Q económicos, W militares; dentro, la tecla de cada
## edificio viene de su campo "hotkey" y la página de "build_menu"); con un edificio propio, unidades, tecnologías y
## edad, y su cola (clic en un puesto = cancelar). Solo lee Sim; las órdenes
## salen por la señal `action` (la partida las convierte en comandos).
## (Los iconos y la skin del DE llegan en F5.)

signal action(kind: String, arg: Variant)

const RES_SHORT := {"wood": "M", "food": "A", "gold": "O", "stone": "P"}
const COLS := 5
## Páginas del menú de construir: id -> [nombre, tecla]. Edificios sin
## build_menu van a la económica.
const MENUS := {"economico": ["Edificios económicos", "Q"], "militar": ["Edificios militares", "W"]}
const MENU_ORDER := ["economico", "militar"]

var sim
var pid := 0
## "kind:id" -> Button (para refrescar estados y para pruebas).
var buttons: Dictionary = {}
var _checks: Dictionary = {}
var _title: Label
var _grid: GridContainer
var _queue_box: HBoxContainer
var _status: Label
var _ids: Array = []
var _building := -1
var _queue_sig := ""
var _state_sig := ""
## Página abierta del menú de construir ("" = elegir página).
var page := ""


func setup(p_sim, p_pid: int) -> void:
	sim = p_sim
	pid = p_pid
	custom_minimum_size = Vector2(520, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.04, 0.88)
	sb.border_color = Color(0.72, 0.58, 0.3)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	_title = _label(16)
	vb.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(_grid)
	_queue_box = HBoxContainer.new()
	vb.add_child(_queue_box)
	_status = _label(13)
	vb.add_child(_status)
	visible = false


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	return l


static func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in ["food", "wood", "gold", "stone"]:
		if cost.has(k) and float(cost[k]) > 0.0:
			parts.append("%d%s" % [int(cost[k]), RES_SHORT[k]])
	return " ".join(parts)


func _defs():
	return sim.players[pid]["defs"]


## Selección nueva: reconstruye los botones (keep_page: conserva la página).
func show_for(ids: Array, keep_page: bool = false) -> void:
	if not keep_page:
		page = ""
	_ids = ids.duplicate()
	for c in _grid.get_children():
		c.queue_free()
	for c in _queue_box.get_children():
		c.queue_free()
	_queue_sig = ""
	_state_sig = _state_signature()
	buttons.clear()
	_checks.clear()
	_building = -1
	var w = sim.world
	var alive: Array = _ids.filter(func(i): return w.entities.has(i))
	if alive.is_empty():
		visible = false
		return
	visible = true
	var first: int = alive[0]
	var def: Dictionary = sim.def_for(first)
	_title.text = str(def.get("name", def.get("id", "")))
	if alive.size() > 1:
		_title.text += " ×%d" % alive.size()
	if alive.any(func(i): return w.has_ability(i, "Build") and int(w.entities[i]["owner"]) == pid):
		_build_buttons()
	elif alive.size() == 1 and w.has_ability(first, "Queue") and int(w.entities[first]["owner"]) == pid:
		_building = first
		_production_buttons(first)
	refresh()


func _build_buttons() -> void:
	if page == "":
		for m in MENU_ORDER:
			_add("menu", m, "%s\n(%s)" % [MENUS[m][0], MENUS[m][1]], func() -> String: return "")
		return
	_add("menu", "", "Atrás\n(Esc)", func() -> String: return "")
	for id in _page_buildings(page):
		var d: Dictionary = _defs().get_def(id)
		var hk := str(d.get("hotkey", ""))
		_add("build", id, "%s%s\n%s" % [d.get("name", id), " (%s)" % hk if hk != "" else "", cost_text(d.get("cost", {}))],
			func() -> String:
				var why: String = sim.requirements_met(pid, d)
				if why == "" and not sim.can_afford(pid, d.get("cost", {})):
					why = "recursos insuficientes"
				return why)


## Edificios de una página, disponibles para la civilización del jugador.
func _page_buildings(p: String) -> Array[String]:
	var out: Array[String] = []
	for id in sim.registry.ids_of_type("building"):
		var d: Dictionary = _defs().get_def(id)
		if d.is_empty() or bool(d.get("abstract", false)) or not _defs().is_available(id):
			continue
		var m := str(d.get("build_menu", "economico"))
		if not MENUS.has(m):
			m = "economico"
		if m == p:
			out.append(id)
	return out


func open_page(p: String) -> void:
	page = p
	show_for(_ids, true)


## Tecla con aldeanos seleccionados: abre una página o elige un edificio.
## true si la tecla se usó.
func press_key(key: String) -> bool:
	if not visible or _building >= 0 or key == "" or buttons.is_empty():
		return false
	if page == "":
		for m in MENU_ORDER:
			if MENUS[m][1] == key:
				open_page(m)
				return true
		return false
	for id in _page_buildings(page):
		if str(_defs().get_def(id).get("hotkey", "")) == key:
			var btn: Button = buttons.get("build:" + id)
			if btn != null and not btn.disabled:
				_choose_building(id)
			return true # tecla del menú aunque el edificio esté bloqueado
	return false


## Esc dentro de una página: vuelve a elegir página. true si se usó.
func back() -> bool:
	if page == "" or not visible:
		return false
	open_page("")
	return true


func _choose_building(id: String) -> void:
	action.emit("build", id)
	open_page("")


func _production_buttons(b: int) -> void:
	var w = sim.world
	var tr: Dictionary = w.comp(b, "Train")
	if not tr.is_empty():
		for u in tr["params"]["units"]:
			var d: Dictionary = _defs().get_def(str(u))
			if d.is_empty() or not _defs().is_available(str(u)):
				continue
			var hk := str(d.get("hotkey", ""))
			var label := "%s%s\n%s" % [d.get("name", u), " (%s)" % hk if hk != "" else "", cost_text(d.get("cost", {}))]
			_add("train", str(u), label, func() -> String: return sim.train_error(pid, b, str(u)))
	var rs: Dictionary = w.comp(b, "Research")
	if not rs.is_empty():
		for t in rs["params"]["techs"]:
			var d: Dictionary = _defs().get_def(str(t))
			if d.is_empty() or not _defs().is_available(str(t)) or sim.researched(pid).has(str(t)):
				continue
			_add("research", str(t), "%s\n%s" % [d.get("name", t), cost_text(d.get("cost", {}))],
				func() -> String: return sim.research_error(pid, b, str(t)))
	if w.has_ability(b, "AgeAdvance"):
		var a: Dictionary = sim.next_age(pid)
		if not a.is_empty():
			_add("age_up", str(a["id"]), "Avanzar a\n%s %s" % [a.get("name", a["id"]), cost_text(a.get("cost", {}))],
				func() -> String: return sim.age_error(pid, b))


func _add(kind: String, id: String, text: String, check: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(96, 44)
	btn.add_theme_font_size_override("font_size", 11)
	btn.focus_mode = Control.FOCUS_NONE
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	if kind == "menu":
		btn.pressed.connect(func(): open_page.call_deferred(id))
	elif kind == "build":
		btn.pressed.connect(func(): _choose_building.call_deferred(id))
	else:
		btn.pressed.connect(func(): action.emit(kind, id))
	_grid.add_child(btn)
	buttons["%s:%s" % [kind, id]] = btn
	_checks[btn] = check


## Por tick: habilitado/motivo de cada botón, cola y avance de obra.
## Cambia lo que el panel ofrece (edad, techs investigadas, obra terminada).
func _state_signature() -> String:
	var built := 0
	for i in _ids:
		if sim.is_built(i):
			built += 1
	return "%d|%d|%d" % [sim.age_of(pid), sim.researched(pid).size(), built]


func refresh() -> void:
	if not visible:
		return
	if _state_signature() != _state_sig:
		show_for(_ids, true)
		return
	for btn in _checks:
		var why: String = _checks[btn].call()
		btn.disabled = why != ""
		btn.tooltip_text = why
	_status.text = ""
	var w = sim.world
	if _ids.size() == 1 and w.entities.has(_ids[0]):
		var f: Dictionary = w.comp(_ids[0], "Foundation")
		if not f.is_empty():
			_status.text = "En construcción: %d%%" % (100 * int(f["progress"]) / maxi(1, int(f["total"])))
	if _building < 0 or not w.entities.has(_building):
		return
	var q: Dictionary = w.comp(_building, "Queue")
	var items: Array = q["items"]
	# Los botones de la cola solo se recrean si cambia su contenido (si no, un
	# clic que cruza un tick caería sobre un botón ya liberado).
	var sig := ",".join(items.map(func(it): return str(it["id"])))
	if sig != _queue_sig:
		_queue_sig = sig
		for c in _queue_box.get_children():
			c.queue_free()
		for i in items.size():
			var btn := Button.new()
			btn.tooltip_text = "Cancelar"
			btn.focus_mode = Control.FOCUS_NONE
			btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
			btn.add_theme_font_size_override("font_size", 11)
			var idx := i
			btn.pressed.connect(func(): action.emit("cancel", idx))
			_queue_box.add_child(btn)
	var kids := _queue_box.get_children().filter(func(c): return not c.is_queued_for_deletion())
	for i in mini(items.size(), kids.size()):
		var it: Dictionary = items[i]
		var t := str(_defs().get_def(str(it["id"])).get("name", it["id"]))
		if i == 0:
			t += " %d%%" % (100 * int(q["progress"]) / maxi(1, int(it["total"])))
		kids[i].text = t
	if bool(q["housed"]):
		_status.text = "¡Sin casas! Construye más para seguir entrenando."


func building() -> int:
	return _building
