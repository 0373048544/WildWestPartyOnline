extends Node

const OUTPUT := "res://tests/artifacts/equipment_v16"

var app: Node
var checks := 0
var uid := 94000

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error("EQUIPMENT VISIBILITY FAILED: " + message)
		get_tree().quit(1)
		assert(ok, message)

func card(id: String) -> Dictionary:
	uid += 1
	return CardInstance.make(uid, id, "SPADE", 7)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.18).timeout

func refresh() -> void:
	GameManager.publish()
	app.match_hud.top_signature = ""
	app.table.state_signature = ""
	app.refresh()
	await settle()

func set_view(css: Vector2i, mobile: bool) -> void:
	get_window().size = css
	get_viewport().set_meta("match_css_size", Vector2(css))
	get_viewport().set_meta("match_force_mobile_device", mobile)
	var logical := Vector2i(600, int(600.0 * css.y / css.x)) if css.y > css.x and mobile else (Vector2i(960, int(960.0 * css.y / css.x)) if mobile else css)
	get_window().content_scale_size = logical
	get_viewport().set_meta("match_safe_insets", Vector4(8, 24, 8, 18) * maxf(float(logical.x) / css.x, float(logical.y) / css.y) if mobile else Vector4.ZERO)
	await refresh()

func assert_public_card(key: String, expected_id: String) -> void:
	check(app.table.objects.objects.has(key), key + " has a persistent 3D table object")
	var object: TableObject = app.table.objects.objects[key]
	check(object.visible and object.is_visible_in_tree(), key + " is visible without hover")
	check(not object.hovered and is_zero_approx(object.lift), key + " does not rely on hover lift")
	check(is_instance_valid(object.artwork) and object.artwork.visible and object.artwork.texture != null, key + " has permanent dedicated artwork")
	check(object.title.visible and not object.title.text.is_empty() and object.title.outline_size >= 3, key + " has a high-contrast permanent title")
	check(str(object.artwork.texture.resource_path).contains(expected_id) or CardArt.texture(expected_id) == object.artwork.texture, key + " artwork matches the authoritative card id")
	var center: Vector2 = app.table.camera.unproject_position(object.global_position + Vector3.UP * 0.08)
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	check(not app.table.camera.is_position_behind(object.global_position) and viewport_rect.has_point(center), key + " projects inside the current camera frame")

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("CAPTURE SKIPPED (headless): ", label)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := OUTPUT + "/" + label + ".png"
	check(image.save_png(path) == OK, "captured " + path)
	print("CAPTURED ", path, " ", image.get_size())

func clear_loadout() -> void:
	GameManager.players[1].weapon = {}
	GameManager.players[1].equipment.clear()
	GameManager.players[1].dynamite = {}

func verify_compact_panel(css: Vector2i, mobile: bool, label: String) -> void:
	await set_view(css, mobile)
	var panel = app.match_hud.loadout_panel
	if panel.expanded:
		panel.title_button.pressed.emit()
		await settle()
	var logical := get_viewport().get_visible_rect().size
	var scale := maxf(logical.x / css.x, logical.y / css.y)
	var collapsed_rect: Rect2 = panel.get_global_rect()
	check(not panel.expanded and not panel.details_scroll.visible, label + " starts collapsed")
	check(collapsed_rect.size.x / scale <= (155.5 if mobile else 210.5), "%s collapsed width stays within target: %.2f CSS px" % [label, collapsed_rect.size.x / scale])
	check(collapsed_rect.size.y / scale <= 85.0, label + " collapsed height stays within target")
	check("WINCHESTER" in panel.title_button.text and "TẦM 5" in panel.title_button.text and "5 LÁ" in panel.title_button.text, label + " summary shows weapon, range and count")
	check(not collapsed_rect.intersects(app.match_hud.hand.get_global_rect()), label + " collapsed panel clears hand")
	check(not collapsed_rect.intersects(app.match_hud.get_node("HandActions").get_global_rect()), label + " collapsed panel clears gameplay buttons")
	check(not collapsed_rect.intersects(app.match_hud.get_node("TopBar").get_global_rect()), label + " collapsed panel clears top HUD")
	await capture(label + "_collapsed")

	panel.title_button.pressed.emit()
	await settle()
	var expanded_rect: Rect2 = panel.get_global_rect()
	check(panel.expanded and panel.details_scroll.visible, label + " opens on first click")
	check(expanded_rect.size.x / scale <= (195.0 if mobile else 215.0), label + " expanded width remains compact")
	check(panel.details_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and panel.items.columns == 1, label + " uses a vertical list without horizontal growth")
	check(not expanded_rect.intersects(app.match_hud.hand.get_global_rect()), "%s expanded panel clears hand panel=%s hand=%s" % [label, expanded_rect, app.match_hud.hand.get_global_rect()])
	check(not expanded_rect.intersects(app.match_hud.get_node("HandActions").get_global_rect()), "%s expanded panel clears gameplay buttons panel=%s actions=%s" % [label, expanded_rect, app.match_hud.get_node("HandActions").get_global_rect()])
	check(not expanded_rect.intersects(app.match_hud.get_node("TopBar").get_global_rect()), "%s expanded panel clears top HUD" % label)
	var panel_id: int = panel.get_instance_id()
	GameManager.publish()
	app.refresh()
	await settle()
	check(panel.get_instance_id() == panel_id and panel.expanded and panel.details_scroll.visible, label + " snapshot preserves expanded state")
	await capture(label + "_expanded")
	panel.title_button.pressed.emit()
	await settle()
	check(not panel.expanded and not panel.details_scroll.visible, label + " closes on second click")
	panel.title_button.pressed.emit()
	await settle()
	var first_real_card: Button = panel.items.get_child(0) as Button
	first_real_card.pressed.emit()
	await settle()
	check(is_instance_valid(app.match_hud.preview), label + " equipment row can be inspected")
	app.match_hud.close_preview()
	await settle()
	check(not panel.expanded and not panel.details_scroll.visible, label + " inspect preview returns to compact state")

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	NetworkManager.mode = "offline"
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	GameManager.clear()
	for id in range(1, 5):
		GameManager.add_player(id, "Cao bồi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	for player in GameManager.players.values():
		player.current_hp = player.max_hp
		player.hand.clear()
	app.seen_role = GameManager.match_id

	# No equipment: the default Colt is visible UI information, never a fake
	# authoritative weapon card or a table-zone object.
	clear_loadout()
	await refresh()
	check(GameManager.players[1].weapon.is_empty(), "default Colt does not enter authoritative weapon state")
	check(not app.table.objects.objects.has("1:weapon"), "default Colt does not create a fake table card")
	check(app.match_hud.loadout_panel.visible and app.match_hud.loadout_panel.current_equipment_count == 0, "default Colt/range summary remains visible")
	check("COLT .45" in app.match_hud.loadout_panel.title_button.text, "default Colt is named in the compact summary")

	# Each shipped public equipment category must independently create a readable
	# non-hover representation.
	for id in ["horse", "spyglass", "barrel"]:
		clear_loadout()
		GameManager.players[1].equipment[id] = card(id)
		await refresh()
		assert_public_card("1:" + id, id)

	clear_loadout()
	GameManager.players[1].weapon = card("winchester")
	await refresh()
	assert_public_card("1:weapon", "winchester")
	check("WINCHESTER" in app.match_hud.loadout_panel.title_button.text, "equipped weapon replaces Colt in visible summary")

	# Multiple equipment plus both delayed/effect slots remain distinct.
	GameManager.players[1].equipment["horse"] = card("horse")
	GameManager.players[1].equipment["spyglass"] = card("spyglass")
	GameManager.players[1].equipment["barrel"] = card("barrel")
	GameManager.players[1].equipment["jail"] = card("jail")
	GameManager.players[1].dynamite = card("dynamite")
	await refresh()
	for pair in [["1:weapon", "winchester"], ["1:horse", "horse"], ["1:spyglass", "spyglass"], ["1:barrel", "barrel"], ["1:jail", "jail"], ["1:delayed_dynamite", "dynamite"]]:
		assert_public_card(pair[0], pair[1])
	check(app.match_hud.loadout_panel.current_equipment_count == 6, "weapon, equipment and delayed cards have exact public count")

	# Repeated snapshot/reconnect-style rehydration must neither duplicate nor
	# hide cards. Clearing presentation nodes simulates a fresh client scene.
	var public_zone_count: int = app.table.objects.objects.keys().filter(func(key): return str(key).begins_with("1:")).size()
	app.table.objects.clear()
	app.table.state_signature = ""
	app.refresh()
	await settle()
	check(app.table.objects.objects.keys().filter(func(key): return str(key).begins_with("1:")).size() == public_zone_count, "snapshot rehydrate recreates each public card exactly once")
	assert_public_card("1:delayed_dynamite", "dynamite")

	# Weapon replacement updates artwork/state once; removal and rematch-like
	# clear leave no phantom object while restoring the presentation-only Colt.
	GameManager.players[1].weapon = card("schofield")
	await refresh()
	assert_public_card("1:weapon", "schofield")
	check("SCHOFIELD" in app.match_hud.loadout_panel.title_button.text, "replacement weapon updates visible summary")
	clear_loadout()
	await refresh()
	check(not app.table.objects.objects.has("1:weapon") and not app.table.objects.objects.has("1:horse") and not app.table.objects.objects.has("1:delayed_dynamite"), "removed/rematch-cleared equipment leaves no phantom card")
	check(app.match_hud.loadout_panel.current_equipment_count == 0 and "COLT .45" in app.match_hud.loadout_panel.title_button.text, "cleared match state restores only default Colt information")

	# Compact/expanded screenshots and bounds at every required viewport.
	GameManager.players[1].weapon = card("winchester")
	GameManager.players[1].equipment["horse"] = card("horse")
	GameManager.players[1].equipment["spyglass"] = card("spyglass")
	GameManager.players[1].equipment["barrel"] = card("barrel")
	GameManager.players[1].dynamite = card("dynamite")
	GameManager.players[2].equipment["barrel"] = card("barrel")
	await verify_compact_panel(Vector2i(1440, 900), false, "desktop_1440x900")
	await verify_compact_panel(Vector2i(1366, 768), false, "desktop_1366x768")
	await verify_compact_panel(Vector2i(390, 844), true, "mobile_390x844")
	check(app.table.objects.objects["1:weapon"].visible and app.table.objects.objects["2:barrel"].visible, "first-person keeps local and opponent public equipment physically visible")
	check(app.table.objects.objects["1:weapon"].scale.x <= 0.5, "first-person local public row is compact instead of filling the camera")
	app.reaction_banner.present(app, {"request_id": 9916, "reaction_type": "dodge", "source_player_id": 2, "allowed_card_types": [], "remaining": 8.0}, NetworkManager.public_state)
	await settle()
	check(not app.match_hud.loadout_panel.get_global_rect().intersects(app.reaction_banner.get_node("Banner").get_global_rect()), "compact panel does not cover reaction prompt")
	app.reaction_banner.hide_banner()
	await verify_compact_panel(Vector2i(844, 390), true, "mobile_844x390")

	print("PASS: %d persistent public equipment, replacement, removal, rehydrate and viewport checks" % checks)
	get_tree().quit(0)
