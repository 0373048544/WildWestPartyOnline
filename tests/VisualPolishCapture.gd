extends Node

const LAYOUT = preload("res://scripts/ui/MatchLayout.gd")
const OUTPUT := "res://tests/artifacts/mobile_polish"

var app: Node
var next_uid := 88000

func settle(seconds: float = 0.18) -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw

func set_view(css: Vector2i, force_phone: bool) -> void:
	get_window().size = css
	get_viewport().set_meta("match_css_size", Vector2(css))
	get_viewport().set_meta("match_force_mobile_device", force_phone)
	var logical := (
		Vector2i(600, int(600.0 * css.y / css.x))
		if css.y >= css.x and force_phone
		else (Vector2i(960, int(960.0 * css.y / css.x)) if force_phone else css)
	)
	get_window().content_scale_size = logical
	get_viewport().set_meta(
		"match_safe_insets",
		Vector4(8, 24, 8, 18) * maxf(float(logical.x) / css.x, float(logical.y) / css.y)
		if force_phone else Vector4.ZERO
	)
	app.match_hud.top_signature = ""
	app.match_hud.hand_signature = ""
	app.table.state_signature = ""
	app.refresh()
	await settle()

func set_hand(count: int) -> void:
	var ids := ["shoot", "dodge", "drink", "panic", "cat_balou", "iced_tea", "jail", "barrel", "general_store", "department_store"]
	GameManager.players[1].hand.clear()
	for index in range(count):
		next_uid += 1
		GameManager.players[1].hand.append(CardInstance.make(next_uid, ids[index % ids.size()], "HEART", 7))
	GameManager.publish()
	app.selected = -1
	app.refresh()
	await settle()

func capture(label: String) -> void:
	await settle()
	var image: Image = get_viewport().get_texture().get_image()
	var path := OUTPUT + "/" + label + ".png"
	var error := image.save_png(path)
	if error != OK:
		push_error("CAPTURE FAILED %s: %s" % [path, error_string(error)])
	else:
		print("CAPTURED ", path, " ", image.get_size())

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_viewport().set_meta("match_force_mobile_device", true)
	get_viewport().set_meta("match_css_size", Vector2(390, 844))
	NetworkManager.mode = "offline"
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	GameManager.clear()
	for id in range(1, 8):
		GameManager.add_player(id, "Cao boi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	for player in GameManager.players.values():
		player.current_hp = player.max_hp
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.refresh()
	await settle()

	# Required portrait card-count states.
	await set_view(Vector2i(390, 844), true)
	for count in [1, 2, 5, 7, 10]:
		await set_hand(count)
		await capture("portrait_390_hand_%02d" % count)

	# Remaining phone breakpoints with a realistic seven-card hand.
	for css in [Vector2i(360, 640), Vector2i(375, 667), Vector2i(430, 932)]:
		await set_view(css, true)
		await set_hand(7)
		await capture("portrait_%dx%d" % [css.x, css.y])
	for css in [Vector2i(667, 375), Vector2i(844, 390), Vector2i(932, 430)]:
		await set_view(css, true)
		await set_hand(7)
		await capture("landscape_%dx%d" % [css.x, css.y])

	# Overlay priority and interaction states.
	await set_view(Vector2i(390, 844), true)
	await set_hand(7)
	app.reaction_banner.present(app, {
		"request_id": 551,
		"reaction_type": "dodge",
		"source_player_id": 2,
		"allowed_card_types": [GameManager.players[1].hand[1].instance_id],
		"remaining": 8.0
	}, NetworkManager.public_state)
	await capture("portrait_reaction")
	app.reaction_banner.hide_banner()
	app.match_hud.show_preview(NetworkManager.private_state.hand[0])
	await capture("portrait_preview")
	app.match_hud.close_preview()
	var department_card: Dictionary = CardInstance.make(99123, "department_store", "CLUB", 5)
	app.match_hud.show_preview(department_card)
	await capture("portrait_department_store_preview")
	app.match_hud.close_preview()
	app.reaction_banner.present(app, {
		"request_id": 661, "reaction_type": "dodge", "source_player_id": 2,
		"allowed_card_types": [GameManager.players[1].hand[1].instance_id],
		"required_count": 2, "resolved_count": 0, "remaining": 8.0
	}, NetworkManager.public_state)
	await capture("portrait_slab_dodge_0_of_2")
	app.reaction_banner.present(app, {
		"request_id": 662, "reaction_type": "dodge", "source_player_id": 2,
		"allowed_card_types": [GameManager.players[1].hand[1].instance_id],
		"required_count": 2, "resolved_count": 1, "remaining": 6.5
	}, NetworkManager.public_state)
	await capture("portrait_slab_dodge_1_of_2")
	app.reaction_banner.hide_banner()
	app.chat_panel.open_chat()
	await capture("portrait_chat_open")
	app.chat_panel.close_chat()

	# Target selection must stay readable above the hand and in first-person.
	app.selected = int(GameManager.players[1].hand[0].instance_id)
	app.refresh()
	await settle()
	await capture("portrait_target_selection")
	app.selected = -1
	app.refresh()

	# A rotated first-person view verifies that off-screen nameplates are not
	# clamped over the table and that another opponent can be inspected by swipe.
	app.table.mobile_camera.yaw += deg_to_rad(58.0)
	app.table.mobile_camera.apply_camera()
	app.table.plate_layout_key = ""
	await capture("portrait_camera_rotated")
	app.table.mobile_camera.reset_toward_table()
	app.table.plate_layout_key = ""
	var slab_row: Dictionary = NetworkManager.public_state.players[1].duplicate(true)
	slab_row["character_id"] = "slab_the_killer"
	slab_row["character"] = CharacterData.get_data("slab_the_killer").duplicate(true)
	app.show_character_info(slab_row)
	await capture("portrait_slab_character_panel")
	var info: Node = app.root.get_node_or_null("PlayerInfoCard")
	if info:
		app.root.remove_child(info)
		info.queue_free()

	# Desktop must keep its established camera/layout.
	for css in [Vector2i(1366, 768), Vector2i(1440, 900), Vector2i(1920, 1080)]:
		await set_view(css, false)
		await set_hand(7)
		await capture("desktop_%dx%d" % [css.x, css.y])

	# Result/rematch modal at the mobile breakpoint. This is a visual state
	# capture only; gameplay/rematch authority remains covered by its tests.
	await set_view(Vector2i(390, 844), true)
	GameManager.winner = "SHERIFF TEAM WINS"
	GameManager.publish()
	app.refresh()
	await capture("portrait_game_over")
	GameManager.players[1].ready = true
	GameManager.publish()
	app.refresh()
	await capture("portrait_rematch_ready")

	print("VISUAL POLISH CAPTURE PASS")
	get_tree().quit(0)
