extends Node

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("V30 VISUAL FAILED: " + message)

func _ready() -> void:
	var presets: Dictionary = CharacterVisualData.presets()
	check(presets.size() == 16, "all 16 character visual presets remain available")
	var silhouettes: Dictionary = {}
	for character_id in presets:
		var preset: Dictionary = presets[character_id]
		silhouettes[str([preset.width, preset.height, preset.brim, preset.crown, preset.outfit, preset.hair_style, preset.prop])] = true
		var avatar := PlayerAvatar.new()
		add_child(avatar)
		avatar.build(Color("#9b6847"))
		avatar.apply_character(character_id, false)
		check(is_instance_valid(avatar.rig.find_child("BootShaftL", true, false)), character_id + " has a shaped left boot")
		check(is_instance_valid(avatar.rig.find_child("BootToeR", true, false)), character_id + " has a readable right boot toe")
		check(avatar.picking_area.get_child_count() == 1, character_id + " keeps one unchanged targeting collision")
		avatar.queue_free()
	check(silhouettes.size() == 16, "all character silhouettes remain data-distinct")

	var weapon_visuals: Script = load("res://scripts/player/WeaponVisuals.gd")
	var weapon_ids := ["", "schofield", "volcanic", "remington", "carabine", "winchester", "gatling"]
	var proportions: Dictionary = {}
	for weapon_id in weapon_ids:
		var mesh: ArrayMesh = weapon_visuals.mesh_for(weapon_id)
		check(mesh == weapon_visuals.mesh_for(weapon_id), "%s reuses one cached mesh" % weapon_id)
		check(mesh.get_surface_count() == 3, "%s keeps the three-surface draw-call budget" % weapon_id)
		var metal := mesh.surface_get_material(0) as StandardMaterial3D
		var wood := mesh.surface_get_material(1) as StandardMaterial3D
		var brass := mesh.surface_get_material(2) as StandardMaterial3D
		check(metal.metallic > 0.6 and metal.roughness < 0.5, "%s metal reads as finished steel" % weapon_id)
		check(wood.metallic == 0.0 and wood.roughness > 0.7, "%s stock reads as warm wood" % weapon_id)
		check(brass.metallic > 0.5, "%s brass details use a distinct finish" % weapon_id)
		var bounds := mesh.get_aabb().size
		proportions[str([snappedf(bounds.x, 0.01), snappedf(bounds.y, 0.01), snappedf(bounds.z, 0.01)])] = true
	check(proportions.size() >= 6, "weapon families have at least six distinct silhouettes")

	var card := load("res://scripts/ui/CardView.gd").new() as Button
	add_child(card)
	var face := {"instance_id": 30, "card_data_id": "winchester", "suit": "SPADE", "rank": 8}
	card.configure(face, CardData.data("winchester"), true, false)
	check(is_instance_valid(card.visual.get_node_or_null("PaperGrain")), "card uses one lightweight parchment grain layer")
	check(is_instance_valid(card.visual.get_node_or_null("BrassInlay")), "card uses the premium inset border")
	check(SaloonTheme.card_paper_texture() == SaloonTheme.card_paper_texture(), "card paper texture is shared")
	card.queue_free()

	var old_quality: String = VisualSettings.level
	for quality in ["LOW", "MEDIUM", "HIGH"]:
		VisualSettings.set_quality(quality, false)
		check(VisualSettings.geometry_segments(16) >= 6, quality + " has a bounded geometry budget")
		check(VisualSettings.character_update_hz() > 0.0, quality + " has an explicit character update budget")
		check(VisualSettings.pooled_vfx_limit() <= 32, quality + " caps pooled transient meshes")
	check(not VisualSettings.realtime_character_shadows() or not VisualSettings.constrained_device(), "realtime character shadow is never forced on constrained devices")
	VisualSettings.set_quality(old_quality, false)

	var room: Node = load("res://scripts/game/SaloonRoom.gd").new()
	add_child(room)
	await get_tree().process_frame
	var rendered_meshes: Array[Node] = room.find_children("*", "MeshInstance3D", true, false)
	var room_mesh_cache: Dictionary = room.get("meshes")
	var room_material_cache: Dictionary = room.get("materials")
	check(rendered_meshes.size() > room_mesh_cache.size(), "saloon instances reuse a smaller cached mesh set")
	check(room_material_cache.size() < rendered_meshes.size(), "saloon reuses finish-aware materials")
	room.queue_free()

	if failures.is_empty():
		print("PASS: %d V30 character, weapon, saloon, material, card and quality-budget checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d V30 visual checks" % [failures.size(), checks])
		get_tree().quit(1)
