class_name SpecialCardPresenter
extends Node

# Client-only presentation for accepted special-card events. It owns no rules,
# timers used by the authority, or network state.
var table: Node3D
var layer: CanvasLayer
var root: Control
var banner: PanelContainer
var title_label: Label
var subtitle_label: Label
var banner_tween: Tween

func setup(owner_table: Node3D) -> void:
	table = owner_table
	layer = CanvasLayer.new()
	layer.name = "SpecialCardLayer"
	# Same canvas as match UI: event banner (600) stays below reaction (700)
	# and true modal (900) layers defined by MatchLayout.
	layer.layer = 0
	add_child(layer)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = load("res://scripts/ui/MatchLayout.gd").Z_TOAST
	layer.add_child(root)
	banner = PanelContainer.new()
	banner.name = "SpecialCardBanner"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_stylebox_override("panel", SaloonTheme.panel(Color(0.055, 0.047, 0.035, 0.96), SaloonTheme.GOLD, 15))
	root.add_child(banner)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 2)
	banner.add_child(content)
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", SaloonTheme.GOLD)
	content.add_child(title_label)
	subtitle_label = Label.new()
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.add_theme_color_override("font_color", SaloonTheme.CREAM)
	content.add_child(subtitle_label)
	banner.hide()
	get_viewport().size_changed.connect(_layout_banner)
	_layout_banner()

func _layout_banner() -> void:
	if not is_instance_valid(banner):
		return
	var layout: Script = load("res://scripts/ui/MatchLayout.gd")
	var usable: Rect2 = layout.modal_rect(root)
	var width_ratio: float = 0.92 if layout.mobile(root) else 0.58
	var width: float = minf(float(layout.units(root, 620)), usable.size.x * width_ratio)
	var height: float = float(layout.units(root, 76 if layout.mobile_landscape(root) else 88))
	banner.size = Vector2(width, height)
	banner.position = Vector2(usable.get_center().x - width * 0.5, usable.position.y + layout.units(root, 12))
	title_label.add_theme_font_size_override("font_size", int(layout.units(root, 21 if layout.mobile(root) else 24)))
	subtitle_label.add_theme_font_size_override("font_size", int(layout.units(root, 14 if layout.mobile(root) else 16)))

func show_special_start(player_id: int, card_id: String) -> void:
	if not _valid_player(player_id):
		return
	var title := "BÁCH HÓA" if card_id == "department_store" else "CỬA HÀNG"
	var player_name: String = str(table.player_names.get(player_id, "Một cao bồi"))
	var subtitle := (
		"%s muốn mỗi người đưa 1 lá!" % player_name
		if card_id == "department_store"
		else "Mỗi người chọn 1 lá!"
	)
	_show_card(player_id, card_id, 0.52)
	_show_banner(title, subtitle, 1.05)
	table.avatars[player_id].act("laugh")
	table.effects.comic(table.avatars[player_id].position + Vector3.UP * 3.0, "HEHEHEHE!", Color("#f3ce73"), 0.92)

func show_heal(player_id: int, card_id: String, rescued: bool) -> void:
	if not _valid_player(player_id) or card_id not in ["drink", "iced_tea"]:
		return
	_show_card(player_id, card_id, 0.34)
	table.avatars[player_id].act("drink")
	var at: Vector3 = table.avatars[player_id].position + Vector3.UP * 2.75
	if rescued:
		var rescue_text := "UỐNG BIA CỨU MẠNG!" if card_id == "drink" else "TRÀ ĐÁ CỨU MẠNG!"
		_show_banner("BẠN ĐÃ SỐNG!" if player_id == table.local_player else rescue_text, rescue_text, 1.25)
	table.effects.comic(at, "+1 MÁU", Color("#9fe3a9"), 0.78)
	var punchline := "Ợ!" if card_id == "drink" else "BỦM!"
	var color := Color("#ffd074") if card_id == "drink" else Color("#d7c38d")
	var timing := create_tween()
	timing.tween_interval(0.42)
	timing.tween_callback(func():
		if _valid_player(player_id):
			table.effects.comic(table.avatars[player_id].position + Vector3.UP * 3.1, punchline, color, 0.72)
	)

func _show_card(player_id: int, card_id: String, hold: float) -> void:
	var face := {"card_data_id": card_id, "suit": "", "rank": ""}
	table.effects.special_card_intro(
		table.avatars[player_id].position + Vector3.UP * 1.35,
		face,
		hold
	)

func _show_banner(title: String, subtitle: String, duration: float) -> void:
	if banner_tween:
		banner_tween.kill()
	_layout_banner()
	title_label.text = title
	subtitle_label.text = subtitle
	banner.show()
	banner.modulate = Color(1, 1, 1, 0)
	var rest: Vector2 = banner.position
	banner.position.y = rest.y - 14
	banner_tween = banner.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	banner_tween.tween_property(banner, "position:y", rest.y, 0.16)
	banner_tween.parallel().tween_property(banner, "modulate:a", 1.0, 0.16)
	banner_tween.tween_interval(maxf(0.3, duration - 0.32))
	banner_tween.tween_property(banner, "modulate:a", 0.0, 0.16)
	banner_tween.tween_callback(banner.hide)

func _valid_player(player_id: int) -> bool:
	return is_instance_valid(table) and table.avatars.has(player_id) and is_instance_valid(table.avatars[player_id])
