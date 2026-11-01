extends RefCounted

const DESKTOP := "desktop"
const TABLET := "tablet"
const MOBILE_PORTRAIT := "mobile_portrait"
const MOBILE_LANDSCAPE := "mobile_landscape"

static func mode(node: Node) -> String:
	var css: Vector2 = css_size(node)
	# Treat phones and compact browser windows as mobile even when an in-app
	# browser reports a slightly wider CSS viewport.
	var is_mobile := css.x <= 768 or (css.x <= 1180 and css.y <= 720)
	if is_mobile:
		return MOBILE_PORTRAIT if css.y >= css.x else MOBILE_LANDSCAPE
	if minf(css.x, css.y) <= 900.0 and maxf(css.x, css.y) <= 1366.0:
		return TABLET
	return DESKTOP

static func mobile(node: Node) -> bool:
	return mode(node) != DESKTOP

static func mobile_portrait(node: Node) -> bool:
	return mode(node) == MOBILE_PORTRAIT

static func mobile_landscape(node: Node) -> bool:
	return mode(node) == MOBILE_LANDSCAPE

static func is_mobile_landscape(node: Node) -> bool:
	return mobile_landscape(node)

static func tablet(node: Node) -> bool:
	return mode(node) == TABLET

static func css_size(node: Node) -> Vector2:
	return node.get_viewport().get_meta("match_css_size", Vector2(node.get_window().size))

static func units(node: Node, pixels: float) -> float:
	var logical: Vector2 = node.get_viewport().get_visible_rect().size
	var css: Vector2 = css_size(node)
	return pixels * maxf(logical.x / maxf(1.0, css.x), logical.y / maxf(1.0, css.y))

static func safe_insets(node: Node) -> Vector4:
	# left, top, right, bottom, already converted to viewport coordinates.
	return node.get_viewport().get_meta("match_safe_insets", Vector4.ZERO)

static func action_height(node: Node) -> float:
	if mobile_portrait(node):
		return units(node, 48.0)
	if mobile_landscape(node):
		return units(node, 44.0)
	return 42.0

static func get_mobile_banner_height(node: Node) -> float:
	return units(node, 46.0 if mobile_landscape(node) else 52.0)

static func hand_lift(node: Node, targeting: bool) -> float:
	if not mobile(node):
		return 0.0
	# The old 82px lift pushed most of each touch card below the clipped hand area.
	# Keep cards almost flush with the top edge of the mobile hand.
	if targeting:
		return 0.0
	return units(node, 6.0 if mobile_portrait(node) else 4.0)

static func portrait(node: Node) -> bool:
	var size: Vector2 = node.get_viewport().get_visible_rect().size
	return size.y > size.x

static func hand_height(node: Node, targeting: bool = false) -> float:
	if not mobile(node):
		return 182.0
	# Portrait gets enough room for a full touch card + scrollbar.
	if mobile_portrait(node):
		return units(node, 172.0 if targeting else 194.0)
	# Landscape is proportional to the short side: a real phone gets 24–28%
	# instead of the old fixed 142px zone that could consume over one third.
	var css: Vector2 = css_size(node)
	var ratio := 0.25 if targeting else 0.27
	return units(node, clampf(css.y * ratio, 96.0, 150.0))

static func get_hand_zone_height(node: Node, targeting: bool = false) -> float:
	return hand_height(node, targeting)

static func touch_card_width(node: Node) -> float:
	if mobile_portrait(node):
		return units(node, 152.0)
	if mobile_landscape(node):
		var css: Vector2 = css_size(node)
		var hand_css := clampf(css.y * 0.27, 96.0, 150.0)
		var height_limited := (hand_css - 10.0) * 210.0 / 214.0
		return units(node, clampf(minf(css.x * 0.11, height_limited), 88.0, 118.0))
	return 158.0

static func get_mobile_card_width(node: Node) -> float:
	return touch_card_width(node)

static func get_mobile_nameplate_scale(node: Node) -> float:
	return 0.84 if mobile_landscape(node) else (0.9 if mobile_portrait(node) else 1.0)

static func get_equipment_compact_mode(node: Node) -> bool:
	return mobile_landscape(node)

static func get_table_focus_rect(node: Node) -> Rect2:
	var viewport_size := node.get_viewport().get_visible_rect().size
	var safe := safe_insets(node) if mobile(node) else Vector4.ZERO
	var top := safe.y + (get_mobile_banner_height(node) if mobile(node) else 52.0)
	var bottom_reserve := safe.w + hand_height(node) + action_height(node)
	return Rect2(
		Vector2(safe.x, top),
		Vector2(
			maxf(1.0, viewport_size.x - safe.x - safe.z),
			maxf(1.0, viewport_size.y - top - bottom_reserve)
		)
	)

static func hand_scrollbar_height(node: Node) -> float:
	if mobile_landscape(node):
		return units(node, 8.0)
	return units(node, 12.0) if mobile(node) else 18.0

static func drag_threshold(node: Node) -> float:
	return units(node, 10.0) if mobile(node) else 12.0
