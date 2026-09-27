extends PanelContainer
## Barra superior estilo AoE2: cada recurso con la cantidad de aldeanos
## asignados entre paréntesis, y la población. Solo lee Sim. (La skin con
## la UI extraída del DE llega en F5.)

const ORDER := ["wood", "food", "gold", "stone"]
const NAMES := {"wood": "Madera", "food": "Alimento", "gold": "Oro", "stone": "Piedra"}
const COLORS := {"wood": Color("#9a6a35"), "food": Color("#d0503a"), "gold": Color("#f0c84a"), "stone": Color("#a8a8a8")}

var sim
var pid := 0
var _labels: Dictionary = {}


func setup(p_sim, p_pid: int) -> void:
	sim = p_sim
	pid = p_pid
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.04, 0.9)
	sb.border_color = Color(0.72, 0.58, 0.3)
	sb.border_width_bottom = 2
	sb.set_content_margin_all(6)
	sb.content_margin_left = 14
	add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 26)
	add_child(hb)
	for key in ORDER + ["pop", "age"]:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(14, 14)
		icon.color = COLORS.get(key, Color("#e8dcc0"))
		box.add_child(icon)
		var l := Label.new()
		l.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 3)
		box.add_child(l)
		hb.add_child(box)
		_labels[key] = l
	refresh()


func refresh() -> void:
	var res: Dictionary = sim.res_of(pid)
	var cnt: Dictionary = sim.gatherer_counts(pid)
	for key in ORDER:
		_labels[key].text = "%s %d (%d)" % [NAMES[key], res[key], cnt[key]]
	var p: Vector2i = sim.population(pid)
	_labels["pop"].text = "Población %d/%d" % [p.x, p.y]
	_labels["age"].text = age_name()


func age_name() -> String:
	for id in sim.registry.ids_of_type("age"):
		var a: Dictionary = sim.registry.get_def(id)
		if int(a.get("index", -1)) == sim.age_of(pid):
			return str(a.get("name", id))
	return ""


func text_of(key: String) -> String:
	return _labels[key].text
