extends RefCounted

const DESKTOP := "desktop"
const MOBILE_PORTRAIT := "mobile_portrait"
const MOBILE_LANDSCAPE := "mobile_landscape"

static func mode(node: Node) -> String:
	var css: Vector2 = css_size(node)
	# Treat phones and compact browser windows as mobile even when an in-app
	# browser reports a slightly wider CSS viewport.
	var is_mobile := css.x <= 768 or (css.x <= 1180 and css.y <= 720)
	if not is_mobile:
		return DESKTOP
	return MOBILE_PORTRAIT if css.y >= css.x else MOBILE_LANDSCAPE

static func mobile(node: Node) -> bool:
	return mode(node) != DESKTOP

static func mobile_portrait(node: Node) -> bool:
	return mode(node) == MOBILE_PORTRAIT

static func mobile_landscape(node: Node) -> bool:
	return mode(node) == MOBILE_LANDSCAPE

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
	# Landscape uses a smaller complete card so the hand does not cover the
	# nearby seat or center table. This still includes the thin scrollbar.
	return units(node, 136.0 if targeting else 142.0)

static func touch_card_width(node: Node) -> float:
	if mobile_portrait(node):
		return units(node, 152.0)
	if mobile_landscape(node):
		return units(node, 120.0)
	return 158.0

static func hand_scrollbar_height(node: Node) -> float:
	return units(node, 12.0) if mobile(node) else 18.0

static func drag_threshold(node: Node) -> float:
	return units(node, 10.0) if mobile(node) else 12.0
