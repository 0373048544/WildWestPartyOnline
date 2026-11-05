extends Node

var checks: int = 0
var failures: int = 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CARD ARTWORK FAILED: " + message)


func _ready() -> void:
	var definitions: Dictionary = CardData.definitions()
	var expected_ids: Array[String] = [
		"shoot", "dodge", "drink", "panic", "cat_balou", "showdown",
		"jail", "schofield", "barrel", "horse", "volcanic", "supply",
		"general_store", "indians", "dynamite", "spyglass", "remington",
		"carabine", "winchester", "gatling", "saloon", "wells_fargo",
		"department_store", "iced_tea"
	]
	expected_ids.sort()
	var actual_ids: Array[String] = []
	for id in definitions:
		actual_ids.append(str(id))
	actual_ids.sort()
	check(actual_ids == expected_ids, "audit lists every current CardData id")
	check(CardArt.PATHS.size() == definitions.size(), "one artwork mapping exists per definition")
	check(CardArt.missing_ids().is_empty(), "MISSING ARTWORK = 0; missing=%s" % [CardArt.missing_ids()])

	var hashes: Dictionary = {}
	for id in actual_ids:
		var path: String = str(CardArt.PATHS.get(id, ""))
		check(FileAccess.file_exists(path), "%s artwork file exists" % id)
		var digest := FileAccess.get_md5(path)
		check(not digest.is_empty() and not hashes.has(digest), "%s uses a dedicated, non-duplicated artwork file" % id)
		hashes[digest] = id
		var texture: Texture2D = CardArt.texture(id)
		check(is_instance_valid(texture) and texture.get_width() == 512 and texture.get_height() == 384, "%s loads optimized 512x384 texture" % id)

		var view: Button = load("res://scripts/ui/CardView.gd").new()
		add_child(view)
		view.configure({"card_data_id": id, "suit": "HEART", "rank": 7}, definitions[id], true, false)
		var artwork: TextureRect = view.visual.get_node("ArtworkFrame/CardArtwork") as TextureRect
		check(is_instance_valid(artwork) and artwork.texture == texture and artwork.visible, "%s CardView displays mapped artwork" % id)
		check(view.visual.get_node("ArtworkFrame").size.y >= 0.35 * 214.0, "%s artwork occupies at least 35 percent of card height" % id)
		view.touch_compact(152.0)
		check(not view.visual.get_node("CardDescription").visible and artwork.visible, "%s mobile compact prioritizes artwork and hides long description" % id)
		var header: Control = view.visual.get_node("HeaderRegion") as Control
		var title: Label = header.get_node("CardName") as Label
		var corner: Label = header.get_node("RankSuitCorner") as Label
		var art_frame: Control = artwork.get_parent() as Control
		var type_region: Control = view.visual.get_node("TypeRegion") as Control
		check(title.visible and title.clip_text and title.max_lines_visible == 1, "%s mobile uses one clipped/ellipsis title renderer" % id)
		check(title.get_theme_font_size("font_size") * view.visual.scale.y >= 10.0, "%s portrait mobile title remains legible" % id)
		var header_local := Rect2(Vector2.ZERO, header.size)
		check(header_local.encloses(title.get_rect()) and header_local.encloses(corner.get_rect()), "%s title and rank/suit remain inside header header=%s title=%s corner=%s" % [id, header_local, title.get_rect(), corner.get_rect()])
		check(not header.get_rect().intersects(art_frame.get_rect()) and not art_frame.get_rect().intersects(type_region.get_rect()), "%s fixed header/artwork/type regions never overlap" % id)
		check(not title.get_rect().intersects(corner.get_rect()), "%s title never occupies rank/suit corner" % id)
		check(view.visual.find_children("CardName", "Label", true, false).size() == 1, "%s has exactly one title renderer" % id)
		check(str(title.get_meta("full_title", "")) == str(definitions[id].name), "%s preserves its full Vietnamese title for preview" % id)
		view.touch_compact(88.0)
		check(title.visible and title.size.y > 0.0, "%s narrow landscape never collapses the fixed header" % id)
		check(not header.get_rect().intersects(art_frame.get_rect()), "%s narrow layout cannot move artwork into header" % id)
		view.queue_free()

	check(is_instance_valid(CardArt.texture("unknown_future_card")), "unknown artwork uses safe category fallback")
	print("PASS: %d card artwork checks; definitions=%d dedicated=%d missing=%d" % [checks, definitions.size(), CardArt.PATHS.size(), CardArt.missing_ids().size()])
	get_tree().quit(1 if failures > 0 else 0)

