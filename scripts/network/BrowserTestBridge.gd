extends Node

# Debug Web builds only, enabled explicitly with ?e2e=1.
# Exposes only what this browser already owns/sees. No token or server registry.
var app: Node
var tick: float = 0

func _process(delta: float) -> void:
	tick += delta
	if tick < 0.12:
		return
	tick = 0
	var controls: Array = []
	collect(app.root, controls)
	var avatars: Dictionary = {}
	var objects: Dictionary = {}
	if is_instance_valid(app.table):
		for id in app.table.avatars:
			var at: Vector2 = app.table.camera.unproject_position(app.table.avatars[id].global_position + Vector3.UP * 1.65)
			avatars[str(id)] = {"x": at.x, "y": at.y}
		for key in app.table.objects.objects:
			var at: Vector2 = app.table.camera.unproject_position(app.table.objects.objects[key].global_position + Vector3.UP * 0.12)
			objects[str(key)] = {"x": at.x, "y": at.y}
	var snapshot := {"player_id": app.local_id(), "public": NetworkManager.public_state,
		"private": NetworkManager.private_state, "controls": controls, "avatars": avatars, "objects": objects,
		"selected": app.selected, "error": app.error_text, "size": {"x": app.root.size.x, "y": app.root.size.y},
		"connected": not NetworkManager.connecting, "room": NetworkManager.room_client.room_code,
		"client_registry_count": GameManager.players.size()}
	snapshot["profile"] = {"fps": Performance.get_monitor(Performance.TIME_FPS),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"audio_players": AudioManager.pool.size() + AudioManager.world_pool.size() + AudioManager.loops.size(),
		"presentation_queue": app.table.presentation_queue.size() if is_instance_valid(app.table) else 0,
		"music_allowed": AudioManager.music_allowed, "music_playing": AudioManager.loops[1].playing, "quality": VisualSettings.level}
	if is_instance_valid(app.table):
		snapshot["targeting"] = {"guide": app.table.targeting.targeting_arrow.visible,
			"reticle": app.table.targeting.reticle.visible, "style": app.table.targeting.target_style,
			"hover": app.table.targeting.hovered_target}
	if is_instance_valid(app.match_hud) and is_instance_valid(app.match_hud.hand):
		var fan: Control = app.match_hud.hand
		var rect := fan.get_global_rect()
		snapshot["layout"] = {"mobile":fan.mobile_mode,"clip":fan.clip_contents,
			"hand": {"x":rect.position.x,"y":rect.position.y,"w":rect.size.x,"h":rect.size.y},
			"safe":get_viewport().get_meta("match_safe_insets",Vector4.ZERO)}
	var serialized := JSON.stringify(snapshot)
	JavaScriptBridge.eval("window.__WWPO_TEST = JSON.parse(" + JSON.stringify(serialized) + ")")

func collect(node: Node, controls: Array) -> void:
	if node is Control and not node.is_visible_in_tree():
		return
	if node is Button or node is LineEdit:
		var at: Vector2 = node.global_position + node.size / 2
		var item := {"text": node.text, "name": str(node.name), "x": at.x, "y": at.y,
			"kind": "input" if node is LineEdit else "button"}
		if node is Button:
			item["disabled"] = node.disabled
			# Fan cards overlap; click the exposed left part, not another card's center.
			if node.has_method("compact"):
				at = node.global_position + Vector2(30, 60)
				item.x = at.x
				item.y = at.y
				item["card_index"] = node.get_index()
				if node.get_parent().get("mobile_mode") == true:
					item["needs_focus"] = true
					item["focused"] = node.get_parent().focused_uid == int(node.get_meta("mobile_uid",-1))
					var exposed: Rect2 = node.get_global_rect().intersection(node.get_parent().get_global_rect())
					if not exposed.has_area():
						return
					item.x = exposed.position.x+minf(30,exposed.size.x/2)
					item.y = exposed.position.y+minf(60,exposed.size.y/2)
		controls.append(item)
	for child in node.get_children():
		collect(child, controls)
