extends "res://tests/engine/TestCase.gd"
const Registry := preload("res://engine/data/Registry.gd")
const Sim := preload("res://engine/sim/Sim.gd")
const EntityLayer := preload("res://engine/render2d/EntityLayer.gd")
const EntityView := preload("res://engine/render2d/EntityView.gd")
const AssetLocator := preload("res://engine/assets/AssetLocator.gd")
const SPR="user://test_v2_sprites"
func _sim() -> Sim:
	var r:=Registry.new();r.load_mods("res://mods");var s: Sim =Sim.new(r,40,40);s.add_player(0,"britones",0);s.add_player(1,"francos",1);return s
func _anim_pack(p: String) -> void:
	var d: String =SPR+"/"+p;DirAccess.make_dir_recursive_absolute(d)
	var im:=Image.create(6,6,false,Image.FORMAT_RGBA8);im.fill(Color(0.5,0.4,0.3));im.save_png(d+"/p_000.png")
	var f:=FileAccess.open(d+"/manifest.pack.json",FileAccess.WRITE);f.store_string(JSON.stringify({"dirs":1,"kept_per_dir":1,"size":[6,6],"frames":[{"png":"p_000.png","dir":0,"sub":0,"hotspot":[3,5]}]}));f.close()
func test_wonder_por_civi():
	var v:=EntityView.new();v.setup(1,{"id":"maravilla","type":"building","graphics":{"idle":"b","wonders_by_civ":{"britones":"w"}}},Color.WHITE,AssetLocator.new(["user://nada"],["user://nada"]),"britones");assert_eq(v._graphics["idle"],"w");v.free()
func test_resolve_cae_age3_sin_pack():
	var v:=EntityView.new();v.setup(1,{"id":"casa","type":"building","graphics":{"idle":"sprite:x/age{age}/idle"}},Color.WHITE,AssetLocator.new(["user://nada"],["user://nada"]),"",1);assert_true(v._resolve_ref("sprite:x/age{age}/idle").is_empty());v.free()
func test_rubble_cap_40():
	var s: Sim =_sim();var l:=EntityLayer.new();l.bind(s,AssetLocator.new(["user://nada"],["user://nada"]),{0:Color.BLUE,1:Color.RED})
	for i in 41:
		var h:=s.spawn("maravilla",0,Vector2i(10,10));s.kill(h);l.sync(1.0,0.0)
	assert_eq(l.rubbles.size(),40);l.free()
func test_scaffold_por_footprint():
	_anim_pack("buildings/scaffolds/b_misc_foundation_2x2_x1");var v:=EntityView.new();v.setup(1,{"id":"casa","type":"building","footprint":[2,2],"graphics":{}},Color.WHITE,AssetLocator.new([SPR],["user://nada"]));assert_false(v._scaffold_pack().is_empty());v.free()
func test_farm_frac_default(): assert_eq(EntityView.new().farm_frac,1.0)
