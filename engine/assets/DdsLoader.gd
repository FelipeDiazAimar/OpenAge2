extends RefCounted
## Decodifica texturas DDS del AoE2 DE (DXT1/DXT5, nivel 0) a Image RGBA8.
## Godot 4.4 no carga DDS en tiempo de ejecución: se arma la imagen con los
## bytes comprimidos y se descomprime con el decodificador BC de Godot.

const HEADER := 128
const MAX_DIM := 16384 # máximo de Image en Godot


static func decode(bytes: PackedByteArray) -> Image:
	if bytes.size() < HEADER or bytes.decode_u32(0) != 0x20534444:
		return null
	var h := bytes.decode_u32(12)
	var w := bytes.decode_u32(16)
	var fmt := -1
	var block := 0
	match bytes.decode_u32(84):
		0x31545844:
			fmt = Image.FORMAT_DXT1
			block = 8
		0x35545844:
			fmt = Image.FORMAT_DXT5
			block = 16
	if fmt < 0 or w <= 0 or h <= 0 or w > MAX_DIM or h > MAX_DIM:
		return null
	var size := maxi(1, (w + 3) / 4) * maxi(1, (h + 3) / 4) * block
	if bytes.size() < HEADER + size:
		return null
	var img := Image.create_from_data(w, h, false, fmt, bytes.slice(HEADER, HEADER + size))
	if img.is_empty():
		return null
	img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func load_file(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	return decode(FileAccess.get_file_as_bytes(path))
