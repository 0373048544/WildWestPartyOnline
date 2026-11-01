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
	for css in [Vector2i(390,844),Vector2i(393,852),Vector2i(430,932),Vector2i(844,390),Vector2i(1920,1080)]:
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
		var fan: Control = app.match_hud.hand
		if compact:
			check(fan.clip_contents,"cards clipped at left/right safe bounds")
			check(fan.global_position.x>=safe.x and fan.global_position.x+fan.size.x<=logical.x-safe.z,"hand respects side safe areas")
			check(fan.global_position.y+fan.size.y<=logical.y-safe.w+0.5,"hand clears home indicator")
			check((fan.size.y-fan.mobile_lift)/sy<=125,"resting hand height bounded in CSS pixels")
			check(app.match_hud.get_node("TopBar/MatchStrip").position.y>=safe.y,"phase strip clears top notch")
			var footer: Control = app.match_hud.get_node("HandActions")
			check(footer.size.y/sy>=36 and footer.size.y/sy<=44,"action bar is 36-44 CSS pixels high")
			var first: Button = fan.cards[0]
			check(first.size.x/sx>=140 and first.visual.get_node("CardDescription").get_theme_font_size("font_size")*first.visual.scale.y/sy>=12,"mobile card width and body text stay readable")
			fan.scroller.value = fan.scroller.max_value-fan.scroller.page
			check(fan.cards.back().visible and not fan.cards[0].visible,"horizontal scroll reaches last card and hides offscreen cards")
			fan.cards.back().pressed.emit()
			check(fan.cards.back().position.y==0 and app.selected<0,"card focus raises without submitting action")
		else:
			check(not fan.mobile_mode and not fan.clip_contents and fan.size.y>=170,"desktop retains full fan")
			check(is_equal_approx(app.table.camera.fov,57) and app.table.camera_goal.is_equal_approx(Vector3(0,7.7,9.1)),"desktop camera unchanged")
		app.selected = 9100
		app.refresh()
		await settle()
		fan = app.match_hud.hand
		var controller: TargetingController = app.table.targeting
		check(controller.valid_target_ids.size()==6,"six valid opponents exposed in target mode")
		if compact:
			check((fan.size.y-fan.mobile_lift)/sy>=40 and (fan.size.y-fan.mobile_lift)/sy<=60,"targeting collapses hand to 40-60 viewport units / practical CSS strip")
			var cancel: Control = app.match_hud.get_node("HandActions/CancelSelection")
			check(cancel.size.y/sy>=36 and cancel.get_global_rect().end.y<=fan.global_position.y+fan.mobile_lift,"cancel stays reachable above resting hand")
		for id in range(2,8):
			var target: Vector2 = app.table.camera.unproject_position(app.table.avatars[id].global_position+Vector3.UP*1.6)
			check(app.table.rings[id].visible,"valid target ring visible")
			if compact:
				var radius: float = LAYOUT.units(app,24)
				var hit := Rect2(target-Vector2.ONE*radius,Vector2.ONE*radius*2)
				check(not hit.intersects(fan.get_global_rect()) and not hit.intersects(app.match_hud.get_node("HandActions").get_global_rect()),"48px target hit area clear of hand and actions "+str(css)+":"+str(id))
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
	print("PASS: %d safe-area, card clipping/readability, 48px target, orientation and desktop regression checks" % checks)
	get_tree().quit()
