extends RefCounted

# All tweens are cosmetic and use the existing rig, never game timers.
func play(a: PlayerAvatar, kind: String) -> bool:
	var t: Tween = a.motion
	if kind == "shoot":
		var d: Dictionary = load("res://scripts/player/WeaponVisuals.gd").profile(a.weapon_visual_id)
		var rifle: bool = d.rifle
		var fast: bool = a.weapon_visual_id == "volcanic"
		a.rig.rotation.y = a.aim_yaw
		t.tween_property(a.arm,"rotation:x",1.57,0.07 if fast else 0.085).set_trans(Tween.TRANS_SINE)
		if rifle and is_instance_valid(a.left_arm):
			t.parallel().tween_property(a.left_arm,"rotation",Vector3(1.42,0,-0.42),0.085)
		t.parallel().tween_property(a.rig,"rotation:x",0.05 if rifle else 0.02,0.085)
		t.tween_interval(0.012)
		t.tween_property(a.arm,"rotation:x",1.72 if rifle else 1.88,0.045)
		t.parallel().tween_property(a.rig,"position:z",0.12 if rifle else 0.065,0.045)
		t.parallel().tween_property(a.hat,"rotation:z",0.22 if rifle else 0.15,0.045)
		t.tween_interval(0.06 if fast else 0.11)
		t.tween_property(a.arm,"rotation:x",0.0,0.17 if fast else 0.23).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(a.rig,"rotation",Vector3.ZERO,0.23)
		t.parallel().tween_property(a.rig,"position:z",0.0,0.23)
		t.parallel().tween_property(a.hat,"rotation:z",float(a.visual_preset.get("tilt",0)),0.23)
		if is_instance_valid(a.left_arm):
			t.parallel().tween_property(a.left_arm,"rotation",Vector3.ZERO,0.23)
		return true
	if kind in ["draw","equip","snatch","discard","store","duel","jail","dynamite"]:
		var reach: float = {"draw":0.7,"equip":1.0,"snatch":1.3,"discard":0.9,"store":0.85,"duel":1.25,"jail":0.6,"dynamite":0.8}[kind]
		t.tween_property(a.arm,"rotation:x",reach,0.12).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(a.rig,"rotation:z",-0.08 if kind in ["snatch","discard"] else 0.05,0.12)
		t.parallel().tween_property(a.hat,"rotation:z",0.2,0.12)
		if kind == "discard":
			t.tween_property(a.arm,"rotation:z",-0.4,0.09)
		elif kind in ["jail","dynamite"]:
			a.set_expression("panic",700)
			t.tween_property(a.rig,"scale",Vector3(1.08,0.92,1.08),0.08)
		t.tween_interval(0.08)
		t.tween_property(a.arm,"rotation",Vector3.ZERO,0.22).set_trans(Tween.TRANS_BACK)
		t.parallel().tween_property(a.rig,"rotation",Vector3.ZERO,0.22)
		t.parallel().tween_property(a.rig,"scale",Vector3.ONE,0.22)
		t.parallel().tween_property(a.hat,"rotation:z",float(a.visual_preset.get("tilt",0)),0.22)
		return true
	if kind == "laugh":
		a.set_expression("laugh", 900)
		t.tween_property(a.rig, "scale", Vector3.ONE * 1.045, 0.10).set_trans(Tween.TRANS_BACK)
		t.parallel().tween_property(a.rig, "rotation:z", -0.055, 0.10)
		t.tween_property(a.rig, "rotation:z", 0.065, 0.13)
		t.tween_property(a.rig, "rotation:z", -0.04, 0.13)
		t.tween_property(a.rig, "rotation:z", 0.0, 0.13)
		t.parallel().tween_property(a.rig, "scale", Vector3.ONE, 0.13)
		return true
	return false
