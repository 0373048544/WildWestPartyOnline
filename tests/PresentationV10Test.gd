extends Node

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("PRESENTATION V10 FAILED: " + message)

func settle(seconds: float = 0.7) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame

func _ready() -> void:
	var old_level: String = VisualSettings.level
	var old_reduced: bool = VisualSettings.reduced_motion
	VisualSettings.set_quality("HIGH", false)
	VisualSettings.set_reduced_motion(true, false)
	check(VisualSettings.reduced_motion, "reduced motion can be enabled without changing gameplay")
	check(not VisualSettings.decorative_motion(), "reduced motion disables decorative loops")
	check(not VisualSettings.camera_motion(), "reduced motion disables camera shake")
	check(VisualSettings.essential_duration(0.4) <= 0.08, "essential feedback duration is shortened")
	check(VisualSettings.particle_count(20) <= 5, "particle budget is reduced")

	VisualSettings.set_reduced_motion(false, false)
	var effects := TableEffects.new()
	add_child(effects)
	effects.spark(Vector3.ZERO, Color.WHITE, 6)
	var first_created: int = effects.created_mesh_count
	check(first_created == 6, "first spark burst allocates its bounded pool")
	await settle()
	check(effects.mesh_pool.size() == 6, "spark nodes return to pool")
	effects.spark(Vector3.ZERO, Color.WHITE, 6)
	check(effects.created_mesh_count == first_created, "second burst reuses pooled meshes")
	effects.smoke(Vector3.ZERO)
	effects.starburst(Vector3.ZERO)
	check(effects.get_child_count() <= 13, "active VFX count remains bounded")
	effects.reset_for_match()
	await get_tree().process_frame
	await get_tree().process_frame
	check(effects.get_child_count() == 0, "rematch cleanup removes active and pooled VFX")
	check(effects.mesh_pool.is_empty() and effects.floating_pool.is_empty(), "rematch cleanup clears pool references")
	check(effects.judgement_cards.is_empty(), "rematch cleanup clears reserved judgement visuals")

	var table: Node = load("res://scenes/game/GameTable.tscn").instantiate()
	add_child(table)
	await get_tree().process_frame
	table.set_process(false)
	table.built_match = 77
	var event := {"event_id": "v10:dedupe", "match_id": 77, "kind": "draw", "player": 1, "count": 1}
	table.presentation(event)
	table.presentation(event.duplicate(true))
	check(table.presentation_queue.size() == 1, "same authoritative event is queued once")
	table.presentation({"event_id": "v10:old", "match_id": 76, "kind": "draw", "player": 1})
	check(table.presentation_queue.size() == 1, "event from old match is rejected")
	table.effects.spark(Vector3.ZERO, Color.WHITE, 3)
	table.effects.reset_for_match()
	await get_tree().process_frame
	check(table.effects.get_child_count() == 0, "table rematch cleanup cancels presentation VFX")

	var avatar := PlayerAvatar.new()
	add_child(avatar)
	avatar.build(Color("#9a6040"))
	VisualSettings.set_reduced_motion(true, false)
	avatar.rig.position.y = 0.2
	avatar._process(0.1)
	check(is_zero_approx(avatar.rig.position.y), "reduced motion removes idle bob")
	check(avatar.rig.scale.is_equal_approx(Vector3.ONE), "reduced motion keeps avatar scale stable")

	VisualSettings.set_quality(old_level, false)
	VisualSettings.set_reduced_motion(old_reduced, false)
	print("PASS: %d V10 presentation dedupe, pooling, cleanup and reduced-motion checks" % checks)
	get_tree().quit(1 if failures > 0 else 0)
