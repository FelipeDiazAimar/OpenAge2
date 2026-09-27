extends "res://tests/engine/TestCase.gd"
## engine/sim y engine/data deben ser deterministas y sin dependencias visuales.

const DIRS := ["res://engine/sim", "res://engine/data"]
const FORBIDDEN := ["Node2D", "Node3D", "Sprite2D", "Sprite3D", "Time.", "randf(", "randi(",
	"randomize(", "OS.get_ticks", "RandomNumberGenerator"]


func test_sim_and_data_are_pure() -> void:
	var violations: Array[String] = []
	for d in DIRS:
		for path in _gd_files(d):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				var code := lines[i].get_slice("#", 0)
				for tok in FORBIDDEN:
					if tok in code:
						violations.append("%s:%d: %s" % [path, i + 1, tok])
	assert_eq(violations, [])


func test_lint_detects_forbidden_token() -> void:
	var code := "var x := randf()  # comentario".get_slice("#", 0)
	assert_true("randf(" in code)
	assert_false("Time." in "var t := 1 # Time.get_ticks_msec()".get_slice("#", 0))


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, f])
	for s in dir.get_directories():
		out.append_array(_gd_files("%s/%s" % [dir_path, s]))
	return out
