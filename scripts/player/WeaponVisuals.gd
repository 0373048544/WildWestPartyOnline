extends RefCounted

# Cosmetic dimensions only: never used by targeting/range/damage rules.
const PROFILES := {
	"": {"length":0.31,"rifle":false,"body":0.17,"brass":false,"class":"SÚNG NGẮN","recoil":0.19,"draw_time":0.075},
	"schofield": {"length":0.44,"rifle":false,"body":0.21,"brass":false,"class":"Ổ QUAY NẶNG","recoil":0.24,"draw_time":0.085},
	"volcanic": {"length":0.28,"rifle":false,"body":0.24,"brass":true,"class":"LẶP NHANH","recoil":0.13,"draw_time":0.055},
	"remington": {"length":0.61,"rifle":true,"body":0.26,"brass":false,"class":"SÚNG TRƯỜNG","recoil":0.23,"draw_time":0.11},
	"carabine": {"length":0.76,"rifle":true,"body":0.29,"brass":false,"class":"CARBINE","recoil":0.21,"draw_time":0.115},
	"winchester": {"length":0.91,"rifle":true,"body":0.31,"brass":true,"class":"ĐÒN BẨY","recoil":0.27,"draw_time":0.125},
	"gatling": {"length":0.72,"rifle":true,"body":0.36,"brass":true,"class":"LIÊN THANH","recoil":0.16,"draw_time":0.09}
}
static var cache: Dictionary = {}
static var materials: Array = []
static var cube: BoxMesh
static var tube: CylinderMesh

static func profile(key: String) -> Dictionary:
	return PROFILES.get(key,PROFILES[""])

static func presentation_class(key: String) -> String:
	if key == "shoot":
		key = ""
	return str(profile(key).get("class", "SÚNG NGẮN"))

static func mesh_for(key: String) -> ArrayMesh:
	if not PROFILES.has(key):
		key = ""
	if cache.has(key):
		return cache[key]
	if not cube:
		cube = BoxMesh.new()
		cube.size = Vector3.ONE
		tube = CylinderMesh.new()
		tube.top_radius = 0.5
		tube.bottom_radius = 0.5
		tube.height = 1
		tube.radial_segments = 8
		for color in [Color("#64727a"),Color("#75462e"),Color("#d1a45b")]:
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.roughness = 0.6
			materials.append(material)
	var d := profile(key)
	var pieces: Array = [[],[],[]]
	var metal: int = 2 if d.brass else 0
	pieces[metal].append([false,Vector3(0.11,0.13,d.body),Vector3(0,0,-d.body/2),Vector3.ZERO])
	pieces[0].append([true,Vector3(0.065,d.length,0.065),Vector3(0,0.035,-d.length/2),Vector3(PI/2,0,0)])
	pieces[1].append([false,Vector3(0.1,0.2,0.09),Vector3(0,-0.13,0.015),Vector3(-0.25,0,0)])
	pieces[2].append([false,Vector3(0.025,0.045,0.04),Vector3(0,0.085,-d.length+0.035),Vector3.ZERO])
	if d.rifle:
		pieces[1].append([false,Vector3(0.12,0.13,0.26),Vector3(0,-0.015,0.16),Vector3(0.15,0,0)])
		pieces[1].append([false,Vector3(0.09,0.075,d.length*0.42),Vector3(0,-0.055,-d.length*0.5),Vector3.ZERO])
	else:
		pieces[metal].append([true,Vector3(0.14,0.13,0.14),Vector3(0,0,-0.13),Vector3(PI/2,0,0)])
	if key in ["winchester","volcanic"]:
		for offset in [-0.065,0.065]:
			pieces[2].append([false,Vector3(0.018,0.02,0.12),Vector3(offset,-0.11,-0.1),Vector3.ZERO])
		pieces[2].append([false,Vector3(0.14,0.02,0.02),Vector3(0,-0.11,-0.16),Vector3.ZERO])
	if key == "schofield":
		# Tall hammer and squared top strap make the heavy Schofield readable.
		pieces[0].append([false,Vector3(0.055,0.08,0.07),Vector3(0,0.105,0.015),Vector3(-0.28,0,0)])
	if key == "remington":
		pieces[0].append([false,Vector3(0.035,0.045,d.length*0.56),Vector3(0,0.085,-d.length*0.47),Vector3.ZERO])
	if key == "carabine":
		pieces[1].append([false,Vector3(0.16,0.10,0.18),Vector3(0,0.015,0.24),Vector3(0.12,0,0)])
	if key == "gatling":
		for offset in [-0.055, 0.0, 0.055]:
			pieces[0].append([true,Vector3(0.035,d.length,0.035),Vector3(offset,0.045,-d.length/2),Vector3(PI/2,0,0)])
		pieces[2].append([false,Vector3(0.25,0.20,0.24),Vector3(0,0.0,0.02),Vector3.ZERO])
	var result := ArrayMesh.new()
	for group in range(3):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in pieces[group]:
			surface.append_from(tube if p[0] else cube,0,Transform3D(Basis.from_euler(p[3]).scaled(p[1]),p[2]))
		surface.commit(result)
		result.surface_set_material(group,materials[group])
	cache[key] = result
	return result
