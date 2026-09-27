extends RefCounted
## Importa texturas de terreno del AoE2 DE instalado a user:// (PNG), una vez.
## Nunca se versionan ni se exportan: cada jugador las genera de su copia.

const DdsLoader := preload("res://engine/assets/DdsLoader.gd")

const REL := "resources/_common/terrain/textures/2x"
const DEST := "user://aoe2_assets/terrain"
const CANDIDATES := [
	"C:/XboxGames/Age of Empires II- Definitive Edition/Content/Game",
	"C:/Program Files (x86)/Steam/steamapps/common/AoE2DE",
	"D:/SteamLibrary/steamapps/common/AoE2DE",
	"E:/SteamLibrary/steamapps/common/AoE2DE",
]


static func find_install() -> String:
	var roots: Array = []
	var env := OS.get_environment("OPENAGE_AOE2_PATH")
	if env != "":
		roots.append(env)
	roots.append_array(CANDIDATES)
	for r in roots:
		if DirAccess.dir_exists_absolute("%s/%s" % [r, REL]):
			return r
	return ""


static func import(root: String, names: Array, dest: String = DEST, max_size: int = 1024) -> int:
	DirAccess.make_dir_recursive_absolute(dest)
	var written := 0
	for n in names:
		var out := "%s/%s.png" % [dest, n]
		if FileAccess.file_exists(out):
			continue
		var img := DdsLoader.load_file("%s/%s/%s.dds" % [root, REL, n])
		if img == null:
			push_warning("TerrainImporter: no se pudo leer %s.dds" % n)
			continue
		if img.get_width() > max_size:
			img.resize(max_size, max_size, Image.INTERPOLATE_LANCZOS)
		if img.save_png(out) == OK:
			written += 1
		else:
			push_warning("TerrainImporter: no se pudo escribir %s" % out)
	return written
