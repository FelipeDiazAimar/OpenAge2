extends "res://tests/engine/TestCase.gd"

const DdsLoader := preload("res://engine/assets/DdsLoader.gd")


static func dxt1_red_4x4() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(128 + 8)
	b.encode_u32(0, 0x20534444) # "DDS "
	b.encode_u32(12, 4)
	b.encode_u32(16, 4)
	b.encode_u32(84, 0x31545844) # "DXT1"
	b.encode_u16(128, 0xF800) # color0 = rojo 565
	b.encode_u16(130, 0x0000)
	b.encode_u32(132, 0) # todos los píxeles usan color0
	return b


func test_decodes_dxt1() -> void:
	var img := DdsLoader.decode(dxt1_red_4x4())
	assert_true(img != null)
	assert_eq(img.get_size(), Vector2i(4, 4))
	assert_eq(img.get_format(), Image.FORMAT_RGBA8)
	var c := img.get_pixel(2, 2)
	assert_true(c.r > 0.9 and c.g < 0.1 and c.b < 0.1, str(c))


func test_rejects_bad_input() -> void:
	assert_true(DdsLoader.decode(PackedByteArray()) == null)
	var b := dxt1_red_4x4()
	b.encode_u32(84, 0x30315844) # "DX10": no soportado
	assert_true(DdsLoader.decode(b) == null)
	var t := dxt1_red_4x4().slice(0, 130)
	assert_true(DdsLoader.decode(t) == null, "truncado")
	assert_true(DdsLoader.load_file("user://no_existe.dds") == null)


func test_rejects_absurd_dimensions() -> void:
	var b := dxt1_red_4x4()
	b.resize(128 + 40000) # bytes suficientes para 20000x4 en DXT1
	b.encode_u32(16, 20000)
	b.encode_u32(12, 4)
	assert_true(DdsLoader.decode(b) == null, "ancho mayor al máximo de Godot (16384)")
	var c := dxt1_red_4x4()
	c.encode_u32(12, 0)
	assert_true(DdsLoader.decode(c) == null, "alto cero")
