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
		tube.radial_segments = 10
		for color in [Color("#64727a"),Color("#75462e"),Color("#d1a45b")]:
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.roughness = 0.32 if materials.is_empty() else (0.78 if materials.size() == 1 else 0.38)
			material.metallic = 0.72 if materials.is_empty() else (0.0 if materials.size() == 1 else 0.64)
			materials.append(material)
	var d := profile(key)
	var pieces: Array = [[],[],[]]
	var metal: int = 2 if d.brass else 0
	pieces[metal].append([false,Vector3(0.11,0.13,d.body),Vector3(0,0,-d.body/2),Vector3.ZERO])
	pieces[0].append([true,Vector3(0.065,d.length,0.065),Vector3(0,0.035,-d.length/2),Vector3(PI/2,0,0)])
	pieces[1].append([false,Vector3(0.1,0.2,0.09),Vector3(0,-0.13,0.015),Vector3(-0.25,0,0)])
	pieces[2].append([false,Vector3(0.025,0.045,0.04),Vector3(0,0.085,-d.length+0.035),Vector3.ZERO])
	# Muzzle collar, front sight, hammer and trigger are merged into the existing
	# three material surfaces, so the premium silhouette costs no extra draw call.
	pieces[metal].append([true,Vector3(0.078,0.045,0.078),Vector3(0,0.035,-d.length+0.025),Vector3(PI/2,0,0)])
	pieces[0].append([false,Vector3(0.018,0.055,0.026),Vector3(0,0.105,-d.length+0.055),Vector3.ZERO])
	pieces[0].append([false,Vector3(0.035,0.075,0.04),Vector3(0,0.105,0.015),Vector3(-0.3,0,0)])
	pieces[2].append([false,Vector3(0.018,0.075,0.018),Vector3(0,-0.105,-0.015),Vector3(0,0,0.55)])
	if d.rifle:
		pieces[1].append([false,Vector3(0.12,0.13,0.26),Vector3(0,-0.015,0.16),Vector3(0.15,0,0)])
		pieces[1].append([false,Vector3(0.09,0.075,d.length*0.42),Vector3(0,-0.055,-d.length*0.5),Vector3.ZERO])
		pieces[0].append([true,Vector3(0.035,d.length*0.62,0.035),Vector3(0,-0.035,-d.length*0.58),Vector3(PI/2,0,0)])
	else:
		pieces[metal].append([true,Vector3(0.14,0.13,0.14),Vector3(0,0,-0.13),Vector3(PI/2,0,0)])
		pieces[0].append([true,Vector3(0.08,0.035,0.08),Vector3(0,0,-0.13),Vector3(PI/2,0,0)])
	if key in ["winchester","volcanic"]:
		for offset in [-0.065,0.065]:
			pieces[2].append([false,Vector3(0.018,0.02,0.12),Vector3(offset,-0.11,-0.1),Vector3.ZERO])
		pieces[2].append([false,Vector3(0.14,0.02,0.02),Vector3(0,-0.11,-0.16),Vector3.ZERO])
	if key == "schofield":
		# Tall hammer and squared top strap make the heavy Schofield readable.
		pieces[0].append([false,Vector3(0.055,0.08,0.07),Vector3(0,0.105,0.015),Vector3(-0.28,0,0)])
		pieces[0].append([false,Vector3(0.14,0.035,0.23),Vector3(0,0.09,-0.12),Vector3.ZERO])
	if key == "remington":
		pieces[0].append([false,Vector3(0.035,0.045,d.length*0.56),Vector3(0,0.085,-d.length*0.47),Vector3.ZERO])
		pieces[1].append([false,Vector3(0.135,0.115,0.23),Vector3(0,-0.025,-0.12),Vector3.ZERO])
	if key == "carabine":
		pieces[1].append([false,Vector3(0.16,0.10,0.18),Vector3(0,0.015,0.24),Vector3(0.12,0,0)])
		pieces[0].append([false,Vector3(0.12,0.12,0.20),Vector3(0,0.02,-0.19),Vector3.ZERO])
	if key == "winchester":
		pieces[2].append([true,Vector3(0.12,0.035,0.12),Vector3(0,-0.095,-0.08),Vector3(PI/2,0,0)])
		pieces[1].append([false,Vector3(0.15,0.12,0.30),Vector3(0,-0.02,-0.22),Vector3.ZERO])
	if key == "gatling":
		for offset in [-0.09, -0.045, 0.0, 0.045, 0.09]:
			pieces[0].append([true,Vector3(0.026,d.length,0.026),Vector3(offset,0.045,-d.length/2),Vector3(PI/2,0,0)])
		pieces[2].append([false,Vector3(0.25,0.20,0.24),Vector3(0,0.0,0.02),Vector3.ZERO])
		pieces[1].append([false,Vector3(0.24,0.13,0.30),Vector3(0,-0.055,0.22),Vector3.ZERO])
		pieces[2].append([false,Vector3(0.26,0.025,0.025),Vector3(0.17,-0.02,0.13),Vector3(0,0,0.35)])
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
