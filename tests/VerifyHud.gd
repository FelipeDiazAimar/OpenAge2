extends SceneTree
# tests/VerifyHud.gd - verifica estructura y rects del HUD en headless.
# Uso: godot --headless --path . -s res://tests/VerifyHud.gd
# Solo instancia HUD (tolera autoloads ausentes). Sale con código 0/1.

var _frames := 0
var _hud: Control = null


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var s: GDScript = load("res://ui/hud/HUD.gd")
	_hud = s.new()
	root.add_child(_hud)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	var fails := 0
	print("HUD rect size=", _hud.size, " visible=", _hud.visible)
	fails += _check_top_bar()
	fails += _check_bottom_bar()
	if fails == 0:
		print("VERIFY_HUD PASS")
	else:
		print("VERIFY_HUD FAIL fails=", fails)
	return true


func _check_top_bar() -> int:
	var fails := 0
	var panels: Array = []
	_collect_panels(_hud, panels)
	if panels.is_empty():
		print("FAIL: sin barra superior")
		return 1
	var top: Control = panels[0]
	# El primer PanelContainer es la barra superior.
	print("TOP pos=", top.position, " size=", top.size)
	# Nota headless: viewport 0x0, el panel mide solo su contenido. Valen los labels.
	var hb = (top as Control).get_child(0)
	var labels := 0
	for c in hb.get_children():
		if c is Label:
			labels += 1
			print("  label '", (c as Label).text.left(24), "'")
	print("TOP labels=", labels)
	if labels != 8:
		print("FAIL: se esperaban 8 labels, hay ", labels)
		fails += 1
	return fails


func _check_bottom_bar() -> int:
	var fails := 0
	var panels: Array = []
	_collect_panels(_hud, panels)
	print("Paneles HUD: ", panels.size())
	for p in panels:
		print("PANEL pos=", (p as Control).position, " size=", (p as Control).size, " visible=", (p as Control).visible)
	if panels.size() < 2:
		print("FAIL: falta la barra inferior")
		return 1
	var bottom: Control = panels[1]
	if bottom.size.y < 100.0:
		print("FAIL: barra inferior sin altura")
		fails += 1
	var grid = _hud.find_child("CommandGrid", true, false)
	if grid == null:
		print("FAIL: sin CommandGrid")
		fails += 1
	else:
		print("GRID hijos=", (grid as Control).get_child_count())
		if (grid as Control).get_child_count() < 10:
			print("FAIL: grid con pocos botones")
			fails += 1
	var slot = _hud.find_child("MinimapSlot", true, false)
	if slot == null:
		print("FAIL: sin MinimapSlot")
		fails += 1
	return fails


func _collect_panels(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is PanelContainer:
			out.append(c)
		_collect_panels(c, out)
