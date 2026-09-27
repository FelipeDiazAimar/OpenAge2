extends "res://tests/engine/TestCase.gd"

const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const CommandPanel := preload("res://engine/ui/CommandPanel.gd")

const MATCH := "res://game/scenes/Match.tscn"


func _sim() -> Sim:
	var r := Registry.new()
	r.load_mods("res://mods")
	var s := Sim.new(r, 40, 40)
	s.add_player(0, "britones", 0)
	s.add_player(1, "francos", 1)
	return s


func test_villager_build_buttons() -> void:
	var s := _sim()
	var v := s.spawn("aldeano", 0, Vector2i(10, 10))
	var p := CommandPanel.new()
	p.setup(s, 0)
	p.show_for([v])
	assert_true(p.visible)
	assert_true(p.buttons.has("build:casa"))
	assert_false(p.buttons["build:casa"].disabled)
	assert_true(p.buttons["build:herreria"].disabled, "herrería requiere feudal")
	assert_true(p.buttons["build:herreria"].tooltip_text.begins_with("requiere"))
	var got := []
	p.action.connect(func(k, a): got.append([k, a]))
	p.buttons["build:casa"].pressed.emit()
	assert_eq(got, [["build", "casa"]])
	p.free()


func test_building_train_and_queue() -> void:
	var s := _sim()
	var tc := s.spawn("centro_urbano", 0, Vector2i(10, 10))
	var p := CommandPanel.new()
	p.setup(s, 0)
	p.show_for([tc])
	assert_true(p.buttons.has("train:aldeano"))
	assert_true(p.buttons.has("age_up:feudal"))
	assert_true(p.buttons["age_up:feudal"].disabled, "faltan edificios")
	s.queue_command(0, "train", {"id": tc, "def": "aldeano"})
	for i in 5:
		s.step()
	p.refresh()
	assert_eq(p._queue_box.get_child_count(), 1, "la cola se muestra")
	p.show_for([s.spawn("aldeano", 1, Vector2i(30, 30))])
	assert_false(p.buttons.has("train:aldeano"))
	p.free()


func test_match_place_and_build() -> void:
	var m = load(MATCH).instantiate()
	Engine.get_main_loop().root.add_child(m)
	var vs: Array = []
	for id in m.sim.world.entities:
		var e: Dictionary = m.sim.world.entities[id]
		if e["def_id"] == "aldeano" and e["owner"] == m.local_pid:
			vs.append(id)
	vs.sort()
	m.select(vs)
	m._on_panel_action("build", "casa")
	assert_eq(m.placing, "casa")
	var c: Vector2 = Vector2(m.sim.world.entities[vs[0]]["pos"]) / 1000.0 + Vector2(-5, 5)
	m.place_at(c)
	assert_eq(m.placing, "", "sin Shift sale del modo colocación")
	for i in 200:
		m.tick_once()
	var houses := 0
	for id in m.sim.world.entities:
		var e: Dictionary = m.sim.world.entities[id]
		if e["def_id"] == "casa" and e["owner"] == m.local_pid and m.sim.is_built(id):
			houses += 1
	assert_eq(houses, 1, "los 3 aldeanos construyen la casa")
	m.queue_free()


func test_match_train_rally_and_hotkey() -> void:
	var m = load(MATCH).instantiate()
	Engine.get_main_loop().root.add_child(m)
	var tc := -1
	for id in m.sim.world.entities:
		var e: Dictionary = m.sim.world.entities[id]
		if e["def_id"] == "centro_urbano" and e["owner"] == m.local_pid:
			tc = id
	m.select([tc])
	assert_true(m._train_hotkey("C"), "C entrena aldeano")
	var tcp: Vector2i = m.sim.world.entities[tc]["pos"]
	m.smart_command(m.Iso.milli_to_screen(tcp + Vector2i(6000, 0)))
	for i in 3:
		m.tick_once()
	assert_eq(m.sim.world.comp(tc, "Queue")["items"].size(), 1)
	assert_true(m.sim.world.comp(tc, "Queue")["rally"].x > tcp.x, "clic derecho con el TC = punto de reunión")
	assert_true(m.overlay.rally != null, "bandera visible")
	m.queue_free()
