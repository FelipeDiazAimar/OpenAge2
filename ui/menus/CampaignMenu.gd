extends Control
# CampaignMenu clon AoE2: lista de campañas, briefing y botón Jugar.
# Fuente de datos: CampaignManager (autoload /root/CampaignManager).
# Si el autoload no existe (tests), se instancia el script como fallback.
# TOP: título. LEFT: lista de escenarios (🔒 bloqueado, ✅ completado).
# RIGHT: briefing + objetivos + diálogos intro. BOTTOM: Jugar / Volver.

const MAIN_MENU := "res://ui/menus/MainMenu.tscn"
const MANAGER_PATH := "/root/CampaignManager"
const MANAGER_SCRIPT := "res://systems/campaign/CampaignManager.gd"

var _manager: Node = null
var _fallback_owned := false
var _selected := ""
var _list_vb: VBoxContainer
var _briefing: RichTextLabel
var _status: Label
var _play_btn: Button


func _ready() -> void:
	_manager = get_node_or_null(MANAGER_PATH)
	if _manager == null:
		_manager = (load(MANAGER_SCRIPT) as GDScript).new()
		_fallback_owned = true
		add_child(_manager)
	_build_ui()
	refresh_list()
	if _manager.has_signal("campaign_won"):
		_manager.campaign_won.connect(_on_won)
	if _manager.has_signal("campaign_lost"):
		_manager.campaign_lost.connect(_on_lost)


func _exit_tree() -> void:
	if _fallback_owned and is_instance_valid(_manager):
		_manager.queue_free()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "⚔️ Campaña: Sangre del Norte"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	_list_vb = VBoxContainer.new()
	_list_vb.add_theme_constant_override("separation", 8)
	_list_vb.custom_minimum_size = Vector2(340, 0)
	cols.add_child(_list_vb)

	_briefing = RichTextLabel.new()
	_briefing.bbcode_enabled = true
	_briefing.scroll_active = true
	_briefing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_briefing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(_briefing)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(bar)

	_play_btn = Button.new()
	_play_btn.text = "▶ Jugar escenario"
	_play_btn.custom_minimum_size = Vector2(260, 48)
	_play_btn.pressed.connect(_on_play)
	bar.add_child(_play_btn)

	var back := Button.new()
	back.text = "← Volver"
	back.custom_minimum_size = Vector2(180, 48)
	back.pressed.connect(_on_back)
	bar.add_child(back)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)


## Reconstruye la lista desde CampaignManager.list_campaigns().
func refresh_list() -> void:
	for c in _list_vb.get_children():
		c.remove_from_parent()
		c.queue_free()
	var items: Array = _manager.call("list_campaigns")
	if items.is_empty():
		var none := Label.new()
		none.text = "(no hay campañas en data/campaigns/*.json)"
		_list_vb.add_child(none)
		return
	for e in items:
		var d: Dictionary = e
		var sid := str(d.get("id", "?"))
		var btn := Button.new()
		var prefix := "🔒 "
		if bool(d.get("completed", false)):
			prefix = "✅ "
		elif bool(d.get("unlocked", false)):
			prefix = "▶ "
		btn.text = prefix + str(d.get("name", sid))
		btn.disabled = not bool(d.get("unlocked", false))
		btn.custom_minimum_size = Vector2(340, 44)
		btn.pressed.connect(_on_select.bind(sid))
		_list_vb.add_child(btn)
		if _selected.is_empty() and bool(d.get("unlocked", false)):
			_selected = sid
	if not _selected.is_empty():
		_show_briefing(_selected)


func _on_select(sid: String) -> void:
	_selected = sid
	_show_briefing(sid)


func _show_briefing(sid: String) -> void:
	var text: String = _manager.call("get_briefing_text", sid)
	var intro: Array = _manager.call("get_dialogues", sid, "intro")
	var bb := "[b]BRIEFING[/b]\n" + text.strip_edges()
	if not intro.is_empty():
		bb += "\n\n[b]INTRO[/b]\n"
		for l in intro:
			bb += "[i]%s:[/i] %s\n" % [str((l as Dictionary).get("speaker", "?")),
				str((l as Dictionary).get("text", ""))]
	_briefing.text = bb
	_status.text = ""


func _on_play() -> void:
	if _selected.is_empty():
		_status.text = "Selecciona un escenario primero."
		return
	var ok: bool = _manager.call("start_scenario", _selected)
	if not ok:
		_status.text = "No se pudo iniciar (¿bloqueado?): " + _selected
		return
	_status.text = "¡En marcha! Intro en el chat. Cambia a la escena de juego para luchar."
	# TODO agente 26: change_scene_to_file("res://ui/game/Game.tscn") al arrancar.


func _on_won(sid: String, ticks_used: int) -> void:
	var mins := snappedf(float(ticks_used) / 600.0, 0.1)
	_status.text = "🏆 ¡Victoria en %s (%s min)! Siguiente escenario desbloqueado." % [sid, str(mins)]
	refresh_list()


func _on_lost(sid: String, reason: String) -> void:
	_status.text = "💀 Derrota en %s (%s). Inténtalo de nuevo." % [sid, reason]


func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
