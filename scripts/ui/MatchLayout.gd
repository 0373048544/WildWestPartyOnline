extends RefCounted

const DESKTOP := "desktop"
const TABLET := "tablet"
const MOBILE_PORTRAIT := "mobile_portrait"
const MOBILE_LANDSCAPE := "mobile_landscape"

# Shared canvas layer contract. UI scripts must use these instead of inventing
# unrelated z-index values that can cover actions or true modals.
const Z_TABLE := 0
const Z_NAMEPLATE := 100
const Z_HAND := 200
const Z_EQUIPMENT := 250
const Z_ACTION := 300
const Z_CHAT := 500
const Z_TOAST := 600
const Z_REACTION := 700
const Z_PREVIEW := 750
const Z_MODAL_BACKDROP := 900
const Z_MODAL_CONTENT := 910

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
		return units(node, 46.0)
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
	if tablet(node):
		return units(node, 176.0 if targeting else 190.0)
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
	if tablet(node):
		return units(node, 150.0)
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
	return 0.84 if mobile_landscape(node) else (0.9 if mobile_portrait(node) else (0.92 if tablet(node) else 1.0))

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

static func safe_rect(node: Node, margin_css: float = 0.0) -> Rect2:
	var viewport_size := node.get_viewport().get_visible_rect().size
	var safe := safe_insets(node) if mobile(node) else Vector4.ZERO
	var margin := units(node, margin_css) if mobile(node) else margin_css
	return Rect2(
		Vector2(safe.x + margin, safe.y + margin),
		Vector2(
			maxf(1.0, viewport_size.x - safe.x - safe.z - margin * 2.0),
			maxf(1.0, viewport_size.y - safe.y - safe.w - margin * 2.0)
		)
	)

static func top_hud_rect(node: Node) -> Rect2:
	var safe := safe_rect(node)
	var height := get_mobile_banner_height(node) if mobile(node) else 52.0
	return Rect2(safe.position, Vector2(safe.size.x, height))

static func hand_rect(node: Node, targeting: bool = false) -> Rect2:
	var safe := safe_rect(node)
	var height := hand_height(node, targeting)
	return Rect2(Vector2(safe.position.x, safe.end.y - height), Vector2(safe.size.x, height))

static func action_rect(node: Node, targeting: bool = false) -> Rect2:
	var hand_zone := hand_rect(node, targeting)
	var height := action_height(node)
	return Rect2(Vector2(hand_zone.position.x, hand_zone.position.y - height - units(node, 4.0)), Vector2(hand_zone.size.x, height))

static func chat_button_rect(node: Node) -> Rect2:
	var safe := safe_rect(node, 8.0)
	var action_zone := action_rect(node)
	var width := units(node, 94.0 if mobile(node) else 124.0)
	var height := units(node, 46.0 if mobile(node) else 42.0)
	return Rect2(
		Vector2(safe.position.x, maxf(safe.position.y, action_zone.position.y - height - units(node, 6.0))),
		Vector2(width, height)
	)

static func chat_panel_rect(node: Node) -> Rect2:
	var safe := safe_rect(node, 8.0)
	var action_zone := action_rect(node)
	var gap := units(node, 8.0)
	var width: float
	var height: float
	if mobile_portrait(node):
		width = safe.size.x * 0.92
		height = safe.size.y * 0.36
	elif mobile_landscape(node):
		width = safe.size.x * 0.42
		height = safe.size.y * 0.55
	else:
		width = minf(380.0, safe.size.x * 0.32)
		height = minf(300.0, safe.size.y * 0.36)
	var bottom := action_zone.position.y - gap
	var top_limit := top_hud_rect(node).end.y + gap
	height = minf(height, maxf(1.0, bottom - top_limit))
	var y := maxf(top_limit, bottom - height)
	return Rect2(Vector2(safe.position.x, y), Vector2(width, height))

static func equipment_rect(node: Node, expanded: bool = false) -> Rect2:
	var safe := safe_rect(node, 8.0 if mobile(node) else 16.0)
	var action_zone := action_rect(node)
	var width: float = (
		minf(units(node, 180.0), safe.size.x * 0.30)
		if mobile_landscape(node)
		else minf(320.0, safe.size.x * 0.30)
	)
	var height := units(node, 136.0 if expanded else 52.0) if mobile(node) else (124.0 if expanded else 76.0)
	return Rect2(Vector2(safe.end.x - width, action_zone.position.y - height - units(node, 6.0)), Vector2(width, height))

static func modal_rect(node: Node) -> Rect2:
	var margin_css := 12.0 if mobile_landscape(node) else (16.0 if mobile(node) else 28.0)
	return safe_rect(node, margin_css)

static func hand_scrollbar_height(node: Node) -> float:
	if mobile_landscape(node):
		return units(node, 8.0)
	return units(node, 12.0) if mobile(node) else 18.0

static func drag_threshold(node: Node) -> float:
	return units(node, 10.0) if mobile(node) else 12.0
