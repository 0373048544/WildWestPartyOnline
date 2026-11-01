extends Node

var app: Node
var checks: int = 0
const LAYOUT = preload("res://scripts/ui/MatchLayout.gd")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error("RESPONSIVE FAILED: "+message)
		get_tree().quit(1)
		assert(ok,message)

func settle() -> void:
	await get_tree().create_timer(0.35).timeout
	await get_tree().physics_frame

func _ready() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	GameManager.clear()
	for id in range(1,8):
		GameManager.add_player(id,"Cao bồi %d" % id)
		GameManager.players[id].ready = true
	GameManager.start_match()
	GameManager.selection.expire(GameManager)
	GameManager.flow.jobs.clear()
	GameManager.reactions.active = {}
	GameManager.turns.current_player = 1
	GameManager.turns.phase = "ACTION_PHASE"
	for p in GameManager.players.values():
		p.ability_id = ""
		p.hand.clear()
		p.current_hp = 4
		p.max_hp = 4
	GameManager.players[1].weapon = CardInstance.make(9001,"winchester","HEART",7)
	for index in range(14):
		GameManager.players[1].hand.append(CardInstance.make(9100+index,"shoot","HEART",7))
	GameManager.publish()
	app.seen_role = GameManager.match_id
	for css in [Vector2i(360,800),Vector2i(390,844),Vector2i(393,852),Vector2i(412,915),Vector2i(430,932),Vector2i(844,390),Vector2i(932,430),Vector2i(1920,1080)]:
		var compact: bool = css.x < 1000
		get_window().size = css
		var logical := Vector2i(600,int(600.0*css.y/css.x)) if css.y>css.x else (Vector2i(960,int(960.0*css.y/css.x)) if compact else Vector2i(1440,810))
		get_window().content_scale_size = logical
		get_viewport().set_meta("match_css_size",Vector2(css))
		var sx: float = float(logical.x)/css.x
		var sy: float = float(logical.y)/css.y
		# Exercise asymmetric notches and home indicator in both orientations.
		var safe := Vector4(10*sx,28*sy,8*sx,20*sy) if compact else Vector4.ZERO
		get_viewport().set_meta("match_safe_insets",safe)
		app.selected = -1
		app.refresh()
		await settle()
		check(LAYOUT.mobile(app)==compact,"viewport-based classification "+str(css))
		var expected_mode := LAYOUT.DESKTOP if not compact else (LAYOUT.MOBILE_PORTRAIT if css.y>css.x else LAYOUT.MOBILE_LANDSCAPE)
		check(LAYOUT.mode(app)==expected_mode,"explicit portrait/landscape/desktop mode "+str(css))
		for avatar in app.table.avatars.values():
			var avatar_center: Vector2 = app.table.camera.unproject_position(avatar.global_position+Vector3.UP*1.6)
			check(avatar_center.x>=safe.x and avatar_center.x<=logical.x-safe.z and avatar_center.y>=safe.y and avatar_center.y<=logical.y-safe.w,"all seven player centers remain framed "+str(css))
		var fan: Control = app.match_hud.hand
		var reaction := {"request_id": 700+css.x, "reaction_type": "dodge", "source_player_id": 2,
			"allowed_card_types": [9100], "remaining": 8.0}
		app.reaction_banner.present(app,reaction,NetworkManager.public_state)
		await get_tree().process_frame
		var banner_panel: Control = app.reaction_banner.get_node("Banner")
		var banner_rect: Rect2 = banner_panel.get_global_rect()
		check(app.reaction_banner.visible and "Cao bồi 2" in app.reaction_banner.get_node("Banner/Content/TitleRow/Title").text,"reaction banner names attacker "+str(css))
		check(not banner_rect.intersects(fan.get_global_rect()),"reaction banner never covers hand "+str(css))
		for plate in app.table.nameplates.values():
			check(not banner_rect.intersects(plate.screen_rect),"reaction banner clears player name/HP "+str(css)+" banner="+str(banner_rect)+" plate="+str(plate.screen_rect))
		if compact:
			check(banner_rect.position.y>=safe.y and banner_rect.end.y<logical.y*0.5,"mobile reaction banner stays in safe upper area")
			check(app.reaction_banner.get_node("Banner/Content/Actions/Primary").size.y/sy>=44 and app.reaction_banner.get_node("Banner/Content/Actions/Skip").size.y/sy>=44,"mobile reaction buttons are at least 44 CSS pixels")
			check(app.reaction_banner.get_node("Banner/Content/Detail").get_line_count()<=2,"reaction copy stays within two lines")
			if css.y>css.x:
				check(banner_rect.size.x/logical.x>=0.80 and banner_rect.size.x/logical.x<=0.92,"portrait reaction banner uses about 80-90 percent width")
		app.reaction_banner.present(app,{"request_id": 900+css.x, "reaction_type": "dodge", "source_player_id": 2,
			"allowed_card_types": [], "remaining": 8.0},NetworkManager.public_state)
		check(app.reaction_banner.get_node("Banner/Content/Actions/Primary").disabled and not app.reaction_banner.get_node("Banner/Content/Actions/Skip").disabled,"no Dodge disables primary but leaves Skip")
		app.reaction_banner.hide_banner()
		if compact:
			check(fan.clip_contents,"cards clipped at left/right safe bounds")
			check(fan.global_position.x>=safe.x and fan.global_position.x+fan.size.x<=logical.x-safe.z,"hand respects side safe areas")
			check(fan.global_position.y+fan.size.y<=logical.y-safe.w+0.5,"hand clears home indicator")
			var expected_hand_height: float = LAYOUT.hand_height(app, false) / sy
			check(absf((fan.size.y-fan.mobile_lift)/sy-expected_hand_height)<=2,"resting hand uses the orientation-specific full-card height")
			check(app.match_hud.get_node("TopBar/MatchStrip").position.y>=safe.y,"phase strip clears top notch")
			var footer: Control = app.match_hud.get_node("HandActions")
			var expected_action_height: float = LAYOUT.action_height(app) / sy
			check(absf(footer.size.y/sy-expected_action_height)<=2,"action bar uses the mobile orientation height")
			var first: Button = fan.cards[0]
			var minimum_card_width: float = 140.0 if css.y>css.x else 88.0
			var rendered_body_size: float = first.visual.get_node("CardDescription").get_theme_font_size("font_size")*first.visual.scale.y/sy
			check(first.size.x/sx>=minimum_card_width and rendered_body_size>=12,"orientation-specific mobile card and body text stay readable width=%s body=%s css=%s" % [first.size.x/sx,rendered_body_size,css])
			var visible_ratio: float = (fan.size.y-first.position.y)/first.size.y
			check(visible_ratio>=1.0,"resting hand shows the complete card body")
			check(is_equal_approx(app.table.camera.fov,59.0 if css.y>css.x else 55.0),"mobile camera uses orientation-specific framing")
			if css.x>css.y:
				check(expected_hand_height/css.y>=0.24 and expected_hand_height/css.y<=0.28,"landscape hand reserves only 24-28 percent of short side")
			app.match_hud.show_preview(NetworkManager.private_state.hand[0])
			var card_preview: Control = app.match_hud.preview
			check(is_instance_valid(card_preview) and absf(card_preview.get_rect().get_center().x-logical.x*0.5)<2,"touch preview is centered instead of relying on hover position rect="+str(card_preview.get_rect()))
			if css.x>css.y:
				var preview_ratio: float = card_preview.size.x/logical.x
				check(preview_ratio>=0.28 and preview_ratio<=0.34,"landscape preview stays within 28-34 percent width")
				var loadout: Control = app.match_hud.loadout_panel
				check(loadout.custom_minimum_size.x/sx<=180.5 and not loadout.details_scroll.visible,"landscape equipment starts as a <=180px chip")
				loadout.title_button.pressed.emit()
				check(loadout.details_scroll.visible,"equipment details expand only after tap")
				loadout.title_button.pressed.emit()
			var close_touch := InputEventScreenTouch.new()
			close_touch.pressed = true
			close_touch.position = Vector2(logical.x*0.5,logical.y*0.5)
			app.match_hud._input(close_touch)
			check(not is_instance_valid(app.match_hud.preview),"tap outside closes touch preview")
			fan.scroller.value = fan.scroller.max_value-fan.scroller.page
			check(fan.cards.back().visible and not fan.cards[0].visible,"horizontal scroll reaches last card and hides offscreen cards")
			var tapped_uid: int = int(fan.cards.back().get_meta("mobile_uid", -1))
			fan.cards.back().pressed.emit()
			check(app.selected==tapped_uid,"first mobile tap selects the card without a focus-only tap")
		else:
			check(not fan.mobile_mode and not fan.clip_contents and fan.size.y>=170,"desktop retains full fan")
			check(is_equal_approx(app.table.camera.fov,57) and app.table.camera_goal.is_equal_approx(Vector3(0,7.7,9.1)),"desktop camera unchanged")
			app.match_hud.show_preview(NetworkManager.private_state.hand[0])
			var desktop_preview: Control = app.match_hud.preview
			check(is_instance_valid(desktop_preview) and desktop_preview.size.x>=220 and desktop_preview.size.x<=280 and desktop_preview.size.y<=180,"desktop uses one compact custom card preview")
			check(fan.cards[0].tooltip_text.is_empty(),"native tooltip disabled to prevent duplicate preview")
			app.match_hud.close_preview()
		app.selected = 9100
		app.refresh()
		await settle()
		fan = app.match_hud.hand
		var controller: TargetingController = app.table.targeting
		check(controller.valid_target_ids.size()==6,"six valid opponents exposed in target mode")
		if compact:
			var expected_target_hand: float = LAYOUT.hand_height(app, true) / sy
			check(absf((fan.size.y-fan.mobile_lift)/sy-expected_target_hand)<=2,"targeting preserves a full touchable card in the orientation-specific hand")
			var cancel: Control = app.match_hud.get_node("HandActions/CancelSelection")
			check(cancel.size.y/sy>=42 and cancel.get_global_rect().end.y<=fan.global_position.y+fan.mobile_lift,"cancel stays reachable above the full-card hand")
		for id in range(2,8):
			var target: Vector2 = app.table.camera.unproject_position(app.table.avatars[id].global_position+Vector3.UP*1.6)
			check(app.table.rings[id].visible,"valid target ring visible")
			if compact:
				var radius: float = LAYOUT.units(app,28)
				var hit := Rect2(target-Vector2.ONE*radius,Vector2.ONE*radius*2)
				check(not hit.intersects(fan.get_global_rect()) and not hit.intersects(app.match_hud.get_node("HandActions").get_global_rect()),"48px target hit clear %s:%s hit=%s hand=%s actions=%s" % [css,id,hit,fan.get_global_rect(),app.match_hud.get_node("HandActions").get_global_rect()])
				check(controller.pick_touch_player(target+Vector2(radius*0.85,0))==id,"forgiving avatar touch "+str(css)+":"+str(id)+" got "+str(controller.pick_touch_player(target+Vector2(radius*0.85,0)))+" at "+str(target))
				var panel: Rect2 = app.table.nameplates[id].screen_rect
				check(controller.pick_touch_player(Vector2(panel.position.x+4,panel.get_center().y))==id,"entire name/HP panel selects player "+str(id))
		controller.valid_target_ids = [2]
		var invalid: Vector2 = app.table.camera.unproject_position(app.table.avatars[3].global_position+Vector3.UP*1.6)
		check(controller.pick_touch_player(invalid)!=3,"invalid opponent cannot intercept touch")
		if OS.get_cmdline_user_args().has("--capture"):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/artifacts/safe-target-"+str(css.x)+"x"+str(css.y)+".png")
	get_viewport().remove_meta("match_css_size")
	get_viewport().remove_meta("match_safe_insets")
	GameManager.clear()
	print("PASS: %d safe-area, card clipping/readability, 56px target, orientation and desktop regression checks" % checks)
	get_tree().quit()
