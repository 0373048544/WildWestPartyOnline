extends Node

var app: Node
var checks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error("MOBILE/RULE FAILED: "+message)
		get_tree().quit(1)
		assert(ok,message)

func give(id: int, key: String) -> Dictionary:
	var card := CardInstance.make(GameManager.deck.next_id,key,"HEART",7)
	GameManager.deck.next_id += 1
	GameManager.players[id].hand.append(card)
	return card

func setup() -> void:
	GameManager.clear()
	for id in range(1,8):
		GameManager.add_player(id,"Người chơi %d" % id)
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
	GameManager.players[1].role = PlayerState.Role.SHERIFF
	GameManager.publish()
	app.seen_role = GameManager.match_id
	app.refresh()

func finish_attack() -> void:
	for _step in range(10):
		if GameManager.reactions.active.is_empty():
			break
		GameManager.flow.resolve({"accept":false})

func _ready() -> void:
	app = load("res://scenes/menu/MainMenu.tscn").instantiate()
	add_child(app)
	setup()
	app.error_text = ""
	var shot := give(1,"shoot")
	var second := give(1,"shoot")
	GameManager.resolver.play(GameManager,1,shot.instance_id,2)
	finish_attack()
	check(GameManager.players[1].bang_played_this_turn,"authoritative BANG flag set after accepted shot")
	var hp: int = GameManager.players[2].current_hp
	for _spam in range(20):
		GameManager.resolver.play(GameManager,1,second.instance_id,2)
	check(GameManager.players[2].current_hp==hp and not GameManager.find_card(1,second.instance_id).is_empty(),"server rejects repeated second BANG before consuming it")
	check(GameManager.resolver.disabled_reason(GameManager,1,second).contains("BANG"),"private reason explains BANG restriction")
	GameManager.players[1].is_connected = false
	GameManager.players[1].is_connected = true
	check(GameManager.players[1].shoot_used_this_turn and GameManager.resolver.valid_targets(GameManager,1,second).is_empty(),"reconnect leaves authoritative turn restriction intact")
	for key in ["supply","wells_fargo"]:
		var brown := give(1,key)
		GameManager.resolver.play(GameManager,1,brown.instance_id,1)
		check(GameManager.find_card(1,brown.instance_id).is_empty(),"BANG plus multiple legal brown cards "+key)
	for exception in ["willy","volcanic"]:
		setup()
		if exception=="willy":
			GameManager.players[1].ability_id="unlimited_shoot"
		else:
			GameManager.players[1].weapon=give(1,"volcanic")
		for _shot in range(2):
			var card := give(1,"shoot")
			GameManager.resolver.play(GameManager,1,card.instance_id,2)
			finish_attack()
			check(GameManager.find_card(1,card.instance_id).is_empty(),exception+" accepts multiple BANG")
	setup()
	for key in ["schofield","winchester"]:
		var weapon := give(1,key)
		GameManager.resolver.play(GameManager,1,weapon.instance_id,1)
		check(GameManager.players[1].weapon.card_data_id==key,"one current weapon with replacement "+key)
	check(GameManager.deck.discard_pile.any(func(c): return c.card_data_id=="schofield"),"old weapon discarded")
	var barrel := give(1,"barrel")
	GameManager.resolver.play(GameManager,1,barrel.instance_id,1)
	var duplicate := give(1,"barrel")
	GameManager.resolver.play(GameManager,1,duplicate.instance_id,1)
	check(not GameManager.find_card(1,duplicate.instance_id).is_empty() and GameManager.players[1].equipment.size()==1,"duplicate Barrel rejected without mutation")
	var weapon_meshes: Dictionary = {}
	var weapon_ids: Array = ["","schofield","volcanic","remington","carabine","winchester"]
	for index in range(weapon_ids.size()):
		var avatar: PlayerAvatar = app.table.avatars[index+1]
		avatar.apply_weapon_visual(weapon_ids[index],true)
		weapon_meshes[avatar.gun.mesh.get_instance_id()] = true
		var mesh_id: int = avatar.gun.mesh.get_instance_id()
		avatar.apply_weapon_visual(weapon_ids[index])
		check(avatar.gun.mesh.get_instance_id()==mesh_id,"unchanged weapon reuses cached mesh")
		if not weapon_ids[index].is_empty():
			GameManager.players[index+1].weapon=CardInstance.make(9000+index,weapon_ids[index],"SPADE",7)
	check(weapon_meshes.size()==6,"six distinct held weapon meshes")
	app.table.avatars[1].apply_weapon_visual("winchester")
	app.table.avatars[1].apply_weapon_visual("")
	check(app.table.avatars[1].weapon_visual_id=="","discarded weapon returns to Colt presentation")
	for _card in range(10):
		give(1,"shoot")
	for dimensions in [Vector2i(390,844),Vector2i(393,852),Vector2i(430,932),Vector2i(844,390),Vector2i(1920,1080)]:
		app.error_text = ""
		get_window().size=dimensions
		get_window().content_scale_size=Vector2i(600,int(600.0*dimensions.y/dimensions.x)) if dimensions.y>dimensions.x else (Vector2i(960,int(960.0*dimensions.y/dimensions.x)) if dimensions.x<1000 else Vector2i(1440,810))
		GameManager.publish()
		app.refresh()
		await get_tree().create_timer(0.3).timeout
		check(app.table.avatars.size()==7,"seven players present "+str(dimensions))
		if dimensions.x<1000:
			var expected_hand: float = load("res://scripts/ui/MatchLayout.gd").hand_height(app, false)
			check(absf(app.match_hud.hand.size.y-app.match_hud.hand.mobile_lift-expected_hand)<=2,"mobile hand reserves the orientation-specific full-card height")
			var fan: Control = app.match_hud.hand
			check(fan.get_node("HandScroll").visible,"large hand has horizontal scroll control")
			var tapped: Button = fan.cards[1]
			var tapped_uid: int = int(tapped.get_meta("mobile_uid", -1))
			fan.drag_distance = load("res://scripts/ui/MatchLayout.gd").drag_threshold(app) + 1.0
			tapped.pressed.emit()
			check(app.selected<0,"horizontal drag release never selects or plays a card")
			fan.drag_distance = 0.0
			tapped.pressed.emit()
			check(app.selected==tapped_uid,"first card tap selects it immediately without a focus-only tap")
			app.selected = -1
			app.refresh()
		else:
			check(app.match_hud.hand.size.y>=170,"desktop fan retains original height")
		var bounds: Vector2 = get_viewport().get_visible_rect().size
		var occupied_plates: Array[Rect2] = []
		for id in app.table.avatars:
			var at: Vector2 = app.table.camera.unproject_position(app.table.avatars[id].global_position+Vector3.UP*1.6)
			var resting_top: float = app.match_hud.hand.global_position.y + (app.match_hud.hand.mobile_lift if dimensions.x<1000 else 0)
			# The local bottom seat may sit behind its own full-card hand in short
			# landscape; every opponent and the center table must remain unobscured.
			check(at.x>0 and at.x<bounds.x and at.y>50 and (id==1 or at.y<resting_top),"opponent visible above full-card hand %s:%s at=%s hand_top=%s" % [dimensions,id,at,resting_top])
			check(app.table.nameplates[id].screen_rect.get_center().distance_to(at)<maxf(bounds.x*0.3,bounds.y*0.22),"nameplate remains near its player "+str(dimensions)+":"+str(id))
			var rect: Rect2 = app.table.nameplates[id].screen_rect
			for other in occupied_plates:
				check(not rect.intersects(other),"responsive seven-player nameplates do not overlap")
			occupied_plates.append(rect)
		app.table.targeting.begin_targeting(999,1,[2,3,4,5,6,7],{})
		var target: Vector2 = app.table.camera.unproject_position(app.table.avatars[2].global_position+Vector3.UP*1.6)
		check(app.table.targeting.pick_touch_player(target+Vector2(12,0))==2,"forgiving player touch "+str(dimensions))
		if OS.get_cmdline_user_args().has("--capture"):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/artifacts/mobile-"+str(dimensions.x)+"x"+str(dimensions.y)+".png")
	GameManager.clear()
	print("PASS: %d authoritative BANG/equipment and responsive mobile checks" % checks)
	get_tree().quit()
