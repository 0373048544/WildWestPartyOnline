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

func collect_hand_blockers(node: Node, hand: Control, blockers: Array) -> void:
	if node == hand:
		return
	if node is Control:
		var control := node as Control
		if not control.is_visible_in_tree():
			return
		var visually_hidden := control.modulate.a <= 0.01 or control.self_modulate.a <= 0.01
		if visually_hidden and control.mouse_filter == Control.MOUSE_FILTER_STOP and control.get_global_rect().intersects(hand.get_global_rect()):
			blockers.append(str(control.get_path()))
	for child in node.get_children():
		collect_hand_blockers(child, hand, blockers)

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
	for css in [Vector2i(360,640),Vector2i(360,800),Vector2i(375,667),Vector2i(390,844),Vector2i(393,852),Vector2i(412,915),Vector2i(430,932),Vector2i(844,390),Vector2i(915,412),Vector2i(932,430),Vector2i(1024,768),Vector2i(1180,820),Vector2i(1366,768),Vector2i(1440,900),Vector2i(1920,1080)]:
		get_window().size = css
		get_viewport().set_meta("match_css_size",Vector2(css))
		var layout_mode: String = LAYOUT.mode(app)
		var compact: bool = layout_mode != LAYOUT.DESKTOP
		var logical := (
			Vector2i(600,int(600.0*css.y/css.x)) if layout_mode == LAYOUT.MOBILE_PORTRAIT
			else (Vector2i(960,int(960.0*css.y/css.x)) if layout_mode == LAYOUT.MOBILE_LANDSCAPE else (Vector2i(1024,int(1024.0*css.y/css.x)) if layout_mode == LAYOUT.TABLET else Vector2i(1440,int(1440.0*css.y/css.x))))
		)
		get_window().content_scale_size = logical
		var sx: float = float(logical.x)/css.x
		var sy: float = float(logical.y)/css.y
		# Exercise asymmetric notches and home indicator in both orientations.
		var safe := Vector4(10*sx,28*sy,8*sx,20*sy) if compact else Vector4.ZERO
		get_viewport().set_meta("match_safe_insets",safe)
		app.selected = -1
		app.refresh()
		await settle()
		check(LAYOUT.mobile(app)==compact,"viewport-based classification "+str(css))
		var expected_mode := layout_mode
		check(LAYOUT.mode(app)==expected_mode,"explicit portrait/landscape/desktop mode "+str(css))
		for avatar in app.table.avatars.values():
			var avatar_center: Vector2 = app.table.camera.unproject_position(avatar.global_position+Vector3.UP*1.6)
			check(avatar_center.x>=safe.x and avatar_center.x<=logical.x-safe.z and avatar_center.y>=safe.y and avatar_center.y<=logical.y-safe.w,"all seven player centers remain framed "+str(css))
		var fan: Control = app.match_hud.hand
		var reaction := {"request_id": 700+css.x, "reaction_type": "dodge", "source_player_id": 2,
			"allowed_card_types": [9100], "remaining": 8.0}
		app.reaction_banner.present(app,reaction,NetworkManager.public_state)
		# Nameplate avoidance is deliberately deferred so a banner resize cannot
		# mutate the 3D table hierarchy during its layout pass.
		await settle()
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
		var end_turn: Control = app.match_hud.get_node("HandActions/EndTurn")
		var equipment_hud: Control = app.match_hud.loadout_panel
		check(end_turn.visible and not end_turn.get_global_rect().intersects(equipment_hud.get_global_rect()),"End Turn never intersects equipment HUD %s end=%s equipment=%s" % [css,end_turn.get_global_rect(),equipment_hud.get_global_rect()])
		check(not fan.get_global_rect().intersects(app.match_hud.get_node("TopBar").get_global_rect()),"hand never overlaps TopBar "+str(css))
		var stop_blockers: Array = []
		collect_hand_blockers(app.canvas, fan, stop_blockers)
		check(stop_blockers.is_empty(),"no visible MOUSE_FILTER_STOP node covers hand %s blockers=%s" % [css,stop_blockers])
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
			check(first.size.x/sx>=44 and first.size.y/sy>=44,"card touch target is at least 44 CSS pixels "+str(css))
			var minimum_card_width: float = 140.0 if css.y>css.x else 88.0
			var rendered_body_size: float = first.visual.get_node("CardDescription").get_theme_font_size("font_size")*first.visual.scale.y/sy
			check(first.size.x/sx>=minimum_card_width and rendered_body_size>=12,"orientation-specific mobile card and body text stay readable width=%s body=%s css=%s" % [first.size.x/sx,rendered_body_size,css])
			var visible_ratio: float = (fan.size.y-first.position.y)/first.size.y
			check(visible_ratio>=1.0,"resting hand shows the complete card body")
			var expected_fov := 59.0 if layout_mode == LAYOUT.MOBILE_PORTRAIT else (55.0 if layout_mode == LAYOUT.MOBILE_LANDSCAPE else 57.0)
			check(is_equal_approx(app.table.camera.fov,expected_fov),"mobile/tablet camera uses mode-specific framing")
			if layout_mode == LAYOUT.MOBILE_LANDSCAPE:
				check(expected_hand_height/css.y>=0.24 and expected_hand_height/css.y<=0.28,"landscape hand reserves only 24-28 percent of short side")
			app.match_hud.show_preview(NetworkManager.private_state.hand[0])
			var card_preview: Control = app.match_hud.preview
			check(is_instance_valid(card_preview) and absf(card_preview.get_rect().get_center().x-logical.x*0.5)<2,"touch preview is centered instead of relying on hover position rect="+str(card_preview.get_rect()))
			if layout_mode == LAYOUT.MOBILE_LANDSCAPE:
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
		# True character-selection modal stays inside safe viewport and suppresses
		# every interactive secondary HUD layer.
		app.selected = -1
		app.refresh()
		var definitions: Array = CharacterData.definitions().values()
		app.show_character_selection({"character_options": [definitions[0], definitions[1]], "character_remaining": 20.0, "character_chosen": false})
		await get_tree().process_frame
		var modal_frame: Control = app.root.get_node("GameModal/ModalFrame")
		var phone_choice: bool = layout_mode in [LAYOUT.MOBILE_PORTRAIT,LAYOUT.MOBILE_LANDSCAPE]
		var modal_safe: Rect2 = LAYOUT.character_choice_rect(app.root) if phone_choice else LAYOUT.modal_rect(app.root)
		check(modal_safe.encloses(modal_frame.get_global_rect()),"modal frame remains inside safe viewport "+str(css))
		if phone_choice:
			check(modal_frame.get_meta("character_choice_fullscreen",false) and modal_frame.get_global_rect().is_equal_approx(modal_safe),"mobile character choice fills safe viewport "+str(css))
			var modal_scroll: ScrollContainer = modal_frame.find_child("ModalScroll",true,false)
			check(is_instance_valid(modal_scroll) and modal_scroll.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"mobile character choice has no vertical scrolling "+str(css))
		else:
			check(not modal_frame.get_meta("character_choice_fullscreen",false) and modal_frame.size.x<logical.x,"desktop character choice remains a centered modal "+str(css))
		check(not app.match_hud.loadout_panel.visible and not app.match_hud.hand.visible and not app.match_hud.get_node("HandActions").visible,"true modal hides equipment, hand and actions")
		var confirm: Control = modal_frame.find_child("ConfirmCharacter",true,false)
		check(is_instance_valid(confirm) and modal_safe.encloses(confirm.get_global_rect()),"character confirm remains reachable in viewport %s safe=%s confirm=%s" % [css,modal_safe,confirm.get_global_rect() if is_instance_valid(confirm) else Rect2()])
		var character_panel: Control = modal_frame.find_child("CharacterChoicePanel",true,false)
		if phone_choice:
			check(confirm.size.y/sy>=44.0,"character confirm keeps a 44px mobile touch target "+str(css))
			check(character_panel.carousel_mode==LAYOUT.character_choice_carousel(app.root),"character card breakpoint follows viewport width "+str(css))
			var option_keys: Array = character_panel.cards.keys()
			if character_panel.carousel_mode:
				check(character_panel.cards[option_keys[0]].visible!=character_panel.cards[option_keys[1]].visible,"narrow portrait shows exactly one carousel card "+str(css))
				check(is_instance_valid(character_panel.navigation) and character_panel.navigation.get_global_rect().size.y/sy>=44.0,"carousel navigation remains touch sized "+str(css))
			else:
				var left_card: Control = character_panel.cards[option_keys[0]]
				var right_card: Control = character_panel.cards[option_keys[1]]
				check(left_card.visible and right_card.visible and left_card.global_position.x<right_card.global_position.x and is_equal_approx(left_card.global_position.y,right_card.global_position.y),"mobile cards remain side by side "+str(css))
				check(modal_safe.encloses(left_card.get_global_rect()) and modal_safe.encloses(right_card.get_global_rect()),"both character cards remain inside safe viewport "+str(css))
		app.clear_game_modal()
		app.refresh()
		await get_tree().process_frame
		var restored_end: Control = app.match_hud.get_node_or_null("HandActions/EndTurn") as Control
		check(is_instance_valid(app.match_hud.hand) and app.match_hud.hand.visible and is_instance_valid(restored_end) and restored_end.visible,"HUD and End Turn survive modal/orientation reflow phase=%s player=%s" % [GameManager.turns.phase,GameManager.turns.current_player])
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
