extends SceneTree
## Corre res://tests/engine/test_*.gd. Sale 0 si todo pasa, 1 si algo falla.
## Uso: godot --headless --path . -s tests/engine/run_tests.gd [-- --only=test_world]

const TEST_DIR := "res://tests/engine"


var _started := false


## Corre en el primer frame (no en _initialize) para que el árbol ya esté
## listo y los tests puedan instanciar escenas con _ready.
func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	quit(_run_all())
	return false


func _run_all() -> int:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--only="):
			only = str(a).get_slice("=", 1)
	var files: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and (only == "" or f.get_basename() == only):
			files.append(f)
	files.sort()
	var total := 0
	var failed: Array[String] = []
	for f in files:
		var script: GDScript = load(TEST_DIR + "/" + f)
		if script == null or not script.can_instantiate():
			failed.append("%s: no carga (error de parseo, ver arriba)" % f)
			print("FAIL " + f)
			continue
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			var inst = script.new()
			inst.current = "%s::%s" % [f.get_basename(), mname]
			inst.call(mname)
			total += 1
			if inst.asserts == 0:
				inst.fail("no ejecutó ningún assert (¿error de script?)")
			failed.append_array(inst.failures)
			print(("FAIL " if inst.failures.size() > 0 else "ok   ") + inst.current)
	for e in failed:
		printerr(e)
	print("%d tests, %d fallos" % [total, failed.size()])
	return 1 if failed.size() > 0 or total == 0 else 0
