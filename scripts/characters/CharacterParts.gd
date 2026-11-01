extends RefCounted

# Cosmetic assembly only. All characters share the existing animation/picking rig.
func build(a: PlayerAvatar, d: Dictionary) -> void:
	var shirt := Color(d.shirt)
	var coat := Color(d.coat)
	var accent := Color(d.accent)
	var skin := Color(d.skin)
	var hair := Color(d.hair)
	var w: float = d.width
	var h: float = d.height
	a.rig = Node3D.new()
	a.rig.name = "CharacterRig"
	a.add_child(a.rig)
	a.part(a.tailored_mesh(w, 0.73*h, str(d.outfit)), Vector3(0, 0.99 * h, 0), shirt)
	if d.outfit in ["coat", "ragged", "jacket", "vest", "patched", "shoulders"]:
		for side in [-1, 1]:
			var panel := a.part(a.tailored_mesh(0.57*w, (0.9 if d.outfit in ["coat", "ragged"] else 0.57)*h, str(d.outfit)), Vector3(side * 0.24 * w, 1.0 * h, 0.015), coat)
			panel.rotation.z = side * 0.06
			var lapel := a.part(a.box(Vector3(0.09, 0.34, 0.045)), Vector3(side * 0.16 * w, 1.16 * h, -0.26), accent)
			lapel.rotation.z = side * -0.2
	if d.outfit == "poncho":
		var poncho := a.part(a.cylinder(0.32, 0.72, 0.65), Vector3(0, 1.17 * h, 0), coat)
		poncho.scale.z = 0.6
		for y in [0.92, 1.06]:
			a.part(a.box(Vector3(1.13, 0.06, 0.04)), Vector3(0, y * h, -0.39), accent)
	if d.outfit == "suspenders":
		for x in [-0.24, 0.24]:
			a.part(a.box(Vector3(0.07, 0.6, 0.04)), Vector3(x, 1.03 * h, -0.32), coat.darkened(0.2))
	if d.outfit == "shoulders":
		for side in [-1, 1]:
			a.part(a.sphere(0.26, 0.24), Vector3(side * 0.43, 1.29 * h, 0), coat)
	if d.outfit == "patched":
		a.part(a.box(Vector3(0.16, 0.16, 0.025)), Vector3(-0.27, 0.97, -0.235), accent)
	a.part(a.box(Vector3(0.76 * w, 0.13, 0.48)), Vector3(0, 0.71 * h, 0), Color("#604330"))
	a.part(a.box(Vector3(0.18, 0.14, 0.05)), Vector3(0, 0.71 * h, -0.27), accent)
	var holster := a.part(a.cylinder(0.13,0.075,0.34),Vector3(0.43*w,0.61*h,0),Color("#62412e"))
	holster.scale.z = 0.62
	holster.rotation.z = -0.18
	a.part(a.box(Vector3(0.09,0.18,0.07)),Vector3(0.44*w,0.82*h,0.015),Color("#382f2d"))
	for side in [-1, 1]:
		a.part(a.box(Vector3(0.25 * w, 0.34 * h, 0.29)), Vector3(side * 0.21 * w, 0.46 * h, 0), coat.darkened(0.2))
		var boot := a.part(a.cylinder(0.16 * w, 0.18 * w, 0.25), Vector3(side * 0.21 * w, 0.19, -0.08), Color("#59402f"))
		boot.scale.z = 1.45
		boot.rotation.x = -0.12
		var sole := a.part(a.cylinder(0.185 * w, 0.185 * w, 0.045), Vector3(side * 0.21 * w, 0.08, -0.08), Color("#382f2d"))
		sole.scale.z = 1.5
	var head_y: float = 1.7 * h
	var face_start: int = a.rig.get_child_count()
	a.part(a.sphere(0.49, 0.82), Vector3(0, head_y, -0.035), skin)
	# Hair cap and modular long shapes give readable head silhouettes.
	a.part(a.sphere(0.47, 0.28), Vector3(0, head_y + 0.25, 0.035), hair)
	if d.hair_style in ["long", "braids", "ponytail", "messy"]:
		for side in [-1, 1]:
			var strand := a.part(a.sphere(0.13 if d.hair_style != "messy" else 0.18, 0.7 if d.hair_style != "messy" else 0.32), Vector3(side * 0.37, head_y - 0.15, 0.0), hair)
			strand.rotation.z = side * 0.18
		if d.hair_style == "ponytail":
			a.part(a.sphere(0.18, 0.56), Vector3(0.28, head_y, 0.32), hair)
	for side in [-1, 1]:
		a.part(a.sphere(0.11, 0.17), Vector3(side * 0.17, head_y + 0.09, -0.443), Color("#fff3d8"))
		var pupil := a.part(a.sphere(0.045, 0.1), Vector3(side * 0.17, head_y + 0.09, -0.526), Color("#263741"))
		a.eyes.append(pupil)
		var brow := a.part(a.box(Vector3(0.2, 0.055, 0.05)), Vector3(side * 0.18, head_y + 0.24, -0.45), hair)
		brow.rotation.z = -side * 0.14
		a.brows.append(brow)
		if d.hair_style in ["stubble", "beard", "goatee", "handlebar", "large_mustache", "curled", "chin_beard"]:
			var size := Vector3(0.28 if d.hair_style in ["large_mustache", "handlebar"] else 0.17, 0.13 if d.hair_style == "large_mustache" else 0.075, 0.08)
			var mustache := a.part(a.sphere(0.13, 0.13), Vector3(side * 0.13, head_y - 0.13, -0.48), hair)
			mustache.scale = Vector3(size.x / 0.26, size.y / 0.13, size.z / 0.26)
			mustache.rotation.z = side * (0.38 if d.hair_style in ["curled", "handlebar"] else -0.15)
	if d.hair_style in ["beard", "goatee", "chin_beard"]:
		a.part(a.cylinder(0.19, 0.07, 0.34 if d.hair_style == "chin_beard" else 0.22), Vector3(0, head_y - 0.29, -0.25), hair)
	a.part(a.sphere(0.11, 0.16), Vector3(0, head_y - 0.01, -0.54), skin.darkened(0.08))
	a.mouth = a.part(a.box(Vector3(0.16, 0.035, 0.025)), Vector3(0, head_y - 0.24, -0.45), Color("#813e36"))
	var face_parts: Array = a.rig.get_children().slice(face_start)
	a.head = Node3D.new()
	a.head.name = "HeadPivot"
	a.rig.add_child(a.head)
	a.head.position.y = head_y
	for face_part in face_parts:
		face_part.reparent(a.head, true)
	a.part(a.box(Vector3(0.42, 0.13, 0.45)), Vector3(0, 1.37 * h, -0.03), accent)
	var scarf := a.part(a.box(Vector3(0.17, 0.29, 0.05)), Vector3(0.09, 1.23 * h, -0.29), accent)
	scarf.rotation.z = 0.35
	a.hat = Node3D.new()
	a.head.add_child(a.hat)
	a.hat.position.y = 0.36
	a.hat_rest_y = a.hat.position.y
	a.hat.rotation.z = d.tilt
	a.part(a.curved_brim(float(d.brim), d.outfit in ["poncho", "patched", "ragged"]), Vector3.ZERO, Color(d.hat), a.hat)
	a.part(a.tailored_mesh(1,float(d.crown),str(d.get("hat_style","creased")),true), Vector3.ZERO, Color(d.hat).lightened(0.08), a.hat)
	a.part(a.cylinder(0.42, 0.44, 0.095), Vector3(0, 0.07, 0), accent, a.hat)
	a.part(a.box(Vector3(0.12, 0.1, 0.04)), Vector3(0, 0.07, -0.44), Color("#f1cd69"), a.hat)
	prop(a, d, head_y)
	var arm_x: float = 0.44 * w
	a.left_arm = Node3D.new()
	a.rig.add_child(a.left_arm)
	a.left_arm.position = Vector3(-arm_x,1.28*h,0)
	a.part(a.sphere(0.135, 0.48), Vector3(0,-0.22,0), shirt,a.left_arm)
	a.hands.append(a.part(a.sphere(0.15, 0.24), Vector3(0,-0.49,-0.02), skin,a.left_arm))
	a.part(a.sphere(0.07,0.13),Vector3(0.11,-0.47,-0.1),skin,a.left_arm)
	a.arm = Node3D.new()
	a.rig.add_child(a.arm)
	a.arm.position = Vector3(arm_x, 1.28 * h, 0)
	a.part(a.sphere(0.135, 0.48), Vector3(0, -0.22, 0), shirt, a.arm)
	a.hands.append(a.part(a.sphere(0.15, 0.24), Vector3(0, -0.49, 0), skin, a.arm))
	a.part(a.sphere(0.07,0.13),Vector3(0.11,-0.47,-0.1),skin,a.arm)
	a.gun = a.part(a.box(Vector3(0.13, 0.18, 0.38)), Vector3(0, -0.5, -0.18), Color("#6a7f89"), a.arm)
	a.bottle = a.part(a.cylinder(0.065, 0.11, 0.34), Vector3(0, -0.55, -0.12), Color("#5aaf88"), a.arm)
	a.bottle.visible = false

func prop(a: PlayerAvatar, d: Dictionary, head_y: float) -> void:
	var accent := Color(d.accent)
	match d.prop:
		"tie":
			var knot := a.part(a.sphere(0.08,0.12),Vector3(0,1.32,-0.32),accent)
			knot.rotation.z = 0.7
			var tie := a.part(a.cylinder(0.04,0.09,0.32),Vector3(0,1.1,-0.34),accent)
			tie.scale.z = 0.3
		"scarf":
			var tail := a.part(a.sphere(0.075,0.46),Vector3(-0.31,1.19,-0.22),accent)
			tail.rotation.z = -0.65
		"stripe":
			for x in [-0.45,-0.22,0,0.22,0.45]:
				a.part(a.cylinder(0.025,0.008,0.15),Vector3(x,0.79,-0.33),accent)
		"flower":
			a.part(a.flower_mesh(),Vector3(0.34,0.21,-0.41),accent,a.hat)
			a.part(a.sphere(0.05,0.08),Vector3(0.34,0.21,-0.44),Color("#f0cf79"),a.hat)
		"coin":
			var coin := a.part(a.cylinder(0.13,0.13,0.04),Vector3(0.3,0.23,-0.32),accent,a.hat)
			coin.rotation.x = PI/2
		"feather":
			var charm := a.part(a.sphere(0.09,0.5), Vector3(0.43, 0.25, 0), accent, a.hat)
			charm.rotation.z = -0.4
		"barrel":
			var buckle := a.part(a.cylinder(0.14, 0.14, 0.23), Vector3(0.0, 0.73, -0.34), Color("#b48447"))
			buckle.rotation.x = PI / 2
		"bottle":
			a.part(a.cylinder(0.07, 0.11, 0.38), Vector3(-0.5, 0.83, -0.2), Color("#59ac7c"))
		"bone":
			for side in [-1, 1]:
				var bone := a.part(a.box(Vector3(0.37, 0.07, 0.06)), Vector3(0, 1.17, -0.31), accent)
				bone.rotation.z = side * 0.5
		"scar":
			var scar := a.part(a.box(Vector3(0.04, 0.18, 0.02)), Vector3(-0.29, head_y, -0.44), Color("#a55c47"))
			scar.rotation.z = -0.3
		"card":
			a.part(a.box(Vector3(0.16, 0.24, 0.025)), Vector3(-0.27, 1.19, -0.29), Color("#fff0cb"))
		"satchel", "pouch":
			a.part(a.box(Vector3(0.31, 0.32, 0.2)), Vector3(-0.4, 0.78, 0.02), accent.darkened(0.2))
		"belt":
			for x in [-0.3, -0.15, 0.15, 0.3]:
				a.part(a.cylinder(0.025, 0.025, 0.13), Vector3(x, 0.77, -0.28), accent)
