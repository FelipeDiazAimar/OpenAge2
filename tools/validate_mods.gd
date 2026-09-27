extends SceneTree
## Valida los mods y muestra errores, avisos y content_hash.
## Uso: godot --headless --path . -s tools/validate_mods.gd [-- --root=res://mods]
## Sale 0 si no hay errores, 1 si los hay.

const Registry := preload("res://engine/data/Registry.gd")


func _initialize() -> void:
	var root := "res://mods"
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--root="):
			root = str(a).get_slice("=", 1)
	var r := Registry.new()
	var ok := r.load_mods(root)
	print("[validate_mods] mods: %s" % ", ".join(PackedStringArray(r.mods.map(func(m): return "%s@%s" % [m["id"], m["version"]]))))
	for w in r.warnings:
		print("[aviso] " + w)
	for e in r.errors:
		printerr("[error] " + e)
	if ok:
		var counts := []
		for t in ["unit", "building", "resource", "tech", "age", "civ"]:
			counts.append("%s=%d" % [t, r.ids_of_type(t).size()])
		print("[validate_mods] OK  %s" % " ".join(PackedStringArray(counts)))
		print("[validate_mods] content_hash %s" % r.content_hash)
	else:
		print("[validate_mods] %d errores" % r.errors.size())
	quit(0 if ok else 1)
