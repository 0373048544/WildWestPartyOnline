class_name WesternPlayerCard
extends PanelContainer

const WesternStatusBadgeScript = preload("res://scripts/ui/WesternStatusBadge.gd")

func configure(player: Dictionary, host_id: int, local_id: int, compact: bool = false) -> void:
	name = "Player%d" % int(player.player_id)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var seat_color: Color = SaloonTheme.SEATS[int(player.seat_index) % SaloonTheme.SEATS.size()]
	var connected := bool(player.get("is_connected", true))
	add_theme_stylebox_override("panel", SaloonTheme.panel(Color("#243238"), seat_color, 12))
	custom_minimum_size.y = 44 if compact else 60
	if compact:
		build_compact(player, host_id, local_id, seat_color)
		return
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var portrait := Label.new()
	portrait.text = "★" if int(player.player_id) == host_id else "♠"
	portrait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.custom_minimum_size = Vector2(34, 34)
	portrait.add_theme_font_size_override("font_size", 22)
	portrait.add_theme_color_override("font_color", SaloonTheme.GOLD if int(player.player_id) == host_id else seat_color.lightened(0.22))
	row.add_child(portrait)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 0)
	row.add_child(identity)
	var title := Label.new()
	title.text = str(player.display_name) + ("  •  BẠN" if int(player.player_id) == local_id else "")
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 17 if compact else 19)
	title.add_theme_color_override("font_color", SaloonTheme.CREAM)
	identity.add_child(title)
	var state := Label.new()
	state.text = "⌁ MẤT KẾT NỐI · Đang giữ chỗ" if not connected else ("Sẵn sàng vào bàn" if bool(player.ready) else "Chưa sẵn sàng")
	state.add_theme_font_size_override("font_size", 12 if compact else 14)
	state.add_theme_color_override("font_color", Color("#9fd4ab") if bool(player.ready) else Color("#c9b996"))
	identity.add_child(state)
	if int(player.player_id) == host_id:
		var host_badge := WesternStatusBadgeScript.new()
		host_badge.configure("CHỦ PHÒNG", "host")
		if compact:
			host_badge.text_label.text = "CHỦ"
			host_badge.text_label.add_theme_font_size_override("font_size", 11)
		row.add_child(host_badge)
	var ready_badge := WesternStatusBadgeScript.new()
	ready_badge.configure("⌁ MẤT MẠNG" if not connected else ("✓ SẴN SÀNG" if bool(player.ready) else "CHƯA SẴN SÀNG"), "danger" if not connected else ("success" if bool(player.ready) else "warning"))
	if compact:
		ready_badge.text_label.text = "✓" if bool(player.ready) else "CHỜ"
		ready_badge.text_label.add_theme_font_size_override("font_size", 11)
	row.add_child(ready_badge)

func build_compact(player: Dictionary, host_id: int, local_id: int, seat_color: Color) -> void:
	var connected := bool(player.get("is_connected", true))
	custom_minimum_size.y = 68
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	add_child(stack)
	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", 8)
	stack.add_child(identity_row)
	var icon := Label.new()
	icon.text = "★" if int(player.player_id) == host_id else "♠"
	icon.custom_minimum_size.x = 22
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color", SaloonTheme.GOLD if int(player.player_id) == host_id else seat_color.lightened(0.22))
	identity_row.add_child(icon)
	var player_name := Label.new()
	player_name.text = str(player.display_name)
	player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_name.add_theme_font_size_override("font_size", 16)
	player_name.add_theme_color_override("font_color", SaloonTheme.CREAM)
	identity_row.add_child(player_name)
	if int(player.player_id) == local_id:
		var you := WesternStatusBadgeScript.new()
		you.configure("BẠN", "neutral")
		you.text_label.add_theme_font_size_override("font_size", 10)
		identity_row.add_child(you)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	stack.add_child(status_row)
	var connection := Label.new()
	connection.text = "⌁ MẤT KẾT NỐI · Giữ chỗ" if not connected else ("Sẵn sàng vào bàn" if bool(player.ready) else "Chưa sẵn sàng")
	connection.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	connection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connection.add_theme_font_size_override("font_size", 12)
	connection.add_theme_color_override("font_color", Color("#9fd4ab") if bool(player.ready) else Color("#c9b996"))
	status_row.add_child(connection)
	if int(player.player_id) == host_id:
		var host := WesternStatusBadgeScript.new()
		host.configure("CHỦ", "host")
		host.text_label.add_theme_font_size_override("font_size", 10)
		status_row.add_child(host)
	var ready := WesternStatusBadgeScript.new()
	ready.configure("⌁" if not connected else ("✓" if bool(player.ready) else "CHỜ"), "danger" if not connected else ("success" if bool(player.ready) else "warning"))
	ready.text_label.add_theme_font_size_override("font_size", 10)
	status_row.add_child(ready)
