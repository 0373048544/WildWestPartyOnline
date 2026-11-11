extends Node

var checks: int = 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("WEAPON PRESENTATION FAILED: " + message)

func _ready() -> void:
	var visuals: Script = load("res://scripts/player/WeaponVisuals.gd")
	var ids := ["", "schofield", "volcanic", "remington", "carabine", "winchester", "gatling"]
	var signatures: Dictionary = {}
	for id in ids:
		var profile: Dictionary = visuals.profile(id)
		var mesh: ArrayMesh = visuals.mesh_for(id)
		check(is_instance_valid(mesh) and mesh.get_surface_count() == 3, "%s has a cached three-material low-poly mesh" % id)
		check(not str(profile.get("class", "")).is_empty(), "%s exposes a presentation class" % id)
		check(float(profile.get("draw_time", 0.0)) > 0.0 and float(profile.get("recoil", 0.0)) > 0.0, "%s has draw/recoil presentation timing" % id)
		var aabb := mesh.get_aabb()
		signatures[str([snappedf(aabb.size.x, 0.01), snappedf(aabb.size.y, 0.01), snappedf(aabb.size.z, 0.01)])] = true
	check(signatures.size() >= 5, "weapon families retain visibly distinct proportions")

	var avatar := PlayerAvatar.new()
	add_child(avatar)
	avatar.build(Color("#9b6847"))
	avatar.apply_character("bart_cassidy", false)
	var rig_children: int = avatar.rig.get_child_count()
	for id in ids.slice(0, 6):
		avatar.apply_weapon_visual(id, true)
		check(not avatar.gun.visible and avatar.holstered_gun.visible, "%s rests in holster/back outside fire animation" % id)
		check(avatar.gun.mesh == visuals.mesh_for(id) and avatar.holstered_gun.mesh == visuals.mesh_for(id), "%s hand and stowed copies share the cached mesh" % id)
		check(avatar.rig.get_child_count() == rig_children, "%s swap creates no duplicate visual node" % id)

	avatar.apply_weapon_visual("schofield", true)
	avatar.prepare_fire_visual()
	avatar.act("shoot")
	check(avatar.fire_delay() < 0.32, "draw-to-fire remains short and does not slow gameplay")
	await get_tree().create_timer(0.18).timeout
	check(avatar.weapon_pose == "ready" and avatar.gun.visible and not avatar.holstered_gun.visible, "draw animation transfers weapon from holster to hand")
	check(avatar.arm.rotation.x > 0.8, "shooting arm raises clearly toward the target")
	await get_tree().create_timer(0.72).timeout
	check(avatar.weapon_pose == "stowed" and not avatar.gun.visible and avatar.holstered_gun.visible, "recover animation returns weapon to holster")
	check(avatar.gun.mesh == visuals.mesh_for("schofield"), "temporary fire visual restores authoritative equipped weapon")

	avatar.prepare_fire_visual("gatling")
	avatar.act("shoot")
	await get_tree().create_timer(0.12).timeout
	check(avatar.gun.mesh == visuals.mesh_for("gatling") and avatar.gun.visible, "Gatling action receives its distinct temporary presentation mesh")
	await get_tree().create_timer(0.75).timeout
	check(avatar.gun.mesh == visuals.mesh_for("schofield") and avatar.weapon_pose == "stowed", "Gatling presentation cannot replace equipped weapon state")

	for id in ["shoot", "schofield", "volcanic", "remington", "carabine", "winchester", "gatling"]:
		var card: Button = load("res://scripts/ui/CardView.gd").new()
		add_child(card)
		card.configure({"instance_id": 7, "card_data_id": id, "suit": "HEART", "rank": 7}, CardData.data(id), true, false)
		check(not is_instance_valid(card.visual.find_child("GunClassBadge", true, false)), "%s artwork has no empty overlay strip" % id)
		card.queue_free()

	var effects := TableEffects.new()
	add_child(effects)
	for shot in range(3):
		effects.muzzle(Vector3.ZERO)
		effects.gun_smoke(Vector3.ZERO)
		await get_tree().create_timer(0.62).timeout
	check(effects.puff_pool.size() <= 12 and effects.mesh_pool.size() <= 32, "flash/smoke return to bounded pools")
	var created_before: int = effects.created_mesh_count
	effects.muzzle(Vector3.ZERO)
	await get_tree().create_timer(0.15).timeout
	check(effects.created_mesh_count <= created_before + 1, "repeated muzzle flash reuses pooled meshes")

	if failures.is_empty():
		print("PASS: %d weapon mesh, holster/draw/fire/recoil/recover, card preview and pooled VFX checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d weapon presentation checks failed" % [failures.size(), checks])
		get_tree().quit(1)
