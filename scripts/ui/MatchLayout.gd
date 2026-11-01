extends RefCounted

static func mobile(node: Node) -> bool:
	var logical: Vector2 = node.get_viewport().get_visible_rect().size
	var css: Vector2 = css_size(node)
	return logical.y > logical.x or css.x <= 600 or (css.x <= 1024 and css.y <= 600)

static func css_size(node: Node) -> Vector2:
	return node.get_viewport().get_meta("match_css_size",Vector2(node.get_window().size))

static func units(node: Node, pixels: float) -> float:
	var logical: Vector2 = node.get_viewport().get_visible_rect().size
	var css: Vector2 = css_size(node)
	return pixels * maxf(logical.x / maxf(1,css.x),logical.y / maxf(1,css.y))

static func safe_insets(node: Node) -> Vector4:
	# left, top, right, bottom, already converted to viewport coordinates.
	return node.get_viewport().get_meta("match_safe_insets",Vector4.ZERO)

static func action_height(node: Node) -> float:
	return units(node,42) if mobile(node) else 42.0

static func hand_lift(node: Node, targeting: bool) -> float:
	return (20.0 if targeting else units(node,82)) if mobile(node) else 0.0

static func portrait(node: Node) -> bool:
	var size: Vector2 = node.get_viewport().get_visible_rect().size
	return size.y > size.x

static func hand_height(node: Node, targeting: bool = false) -> float:
	return units(node,44 if targeting else 72) if mobile(node) else 182.0
