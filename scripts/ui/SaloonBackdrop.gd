extends Control

var age: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(VisualSettings.decorative_motion())
	VisualSettings.changed.connect(func(): set_process(VisualSettings.decorative_motion()); queue_redraw())

func _process(delta: float) -> void:
	age += delta
	if VisualSettings.decorative_motion():
		queue_redraw()

func _draw() -> void:
	# Vector-only saloon: warm sunset, timber and a readable quiet center.
	for band in range(48):
		var blend := float(band) / 47.0
		draw_rect(Rect2(0, size.y * blend, size.x, size.y / 47 + 1), Color("#1c3443").lerp(Color("#71472f"), blend))
	for side in [0.13, 0.87]:
		var x: float = size.x * side
		draw_circle(Vector2(x, size.y * 0.34), 118, Color(0.95, 0.62, 0.25, 0.035))
		draw_circle(Vector2(x, size.y * 0.34), 76, Color(0.95, 0.62, 0.25, 0.05))
		draw_rect(Rect2(x - 35, size.y * 0.2, 70, size.y * 0.27), Color("#d6a564"))
		for column in [-1, 0, 1]:
			draw_line(Vector2(x + column * 26, size.y * 0.2), Vector2(x + column * 26, size.y * 0.47), Color("#382e2b"), 8)
		draw_line(Vector2(x - 35, size.y * 0.33), Vector2(x + 35, size.y * 0.33), Color("#382e2b"), 8)
	draw_rect(Rect2(0, size.y * 0.72, size.x, size.y * 0.28), Color("#302c2c"))
	for plank in range(15):
		var x: float = size.x * float(plank) / 14
		draw_line(Vector2(size.x * 0.5 + (x - size.x * 0.5) * 0.3, size.y * 0.72), Vector2(x, size.y), Color("#5c4232"), 2)
	for beam in [0.06, 0.25, 0.75, 0.94]:
		draw_rect(Rect2(size.x * beam, 0, 16, size.y * 0.74), Color("#352e2c"))
	# Brass wall lamps and a quiet halo frame the notice board without competing
	# with its text. Everything remains cheap canvas drawing for Web/mobile.
	for lamp_x in [0.31, 0.69]:
		var lamp := Vector2(size.x * lamp_x, size.y * 0.12)
		draw_circle(lamp, 54, Color(1.0, 0.68, 0.25, 0.025))
		draw_circle(lamp, 25, Color(1.0, 0.72, 0.30, 0.055))
		draw_line(lamp + Vector2(0, -28), lamp + Vector2(0, -7), Color("#6f5134"), 4)
		draw_circle(lamp, 6, Color("#e7b86d"))
	# Subtle edge vignette makes the center panel feel intentionally lit.
	for edge in range(9):
		var alpha := 0.018 * float(9 - edge)
		draw_rect(Rect2(edge * 7, edge * 5, size.x - edge * 14, size.y - edge * 10), Color(0.02, 0.025, 0.028, alpha), false, 10)
	# The foreground screen owns the notice-board frame. An open backdrop avoids
	# doubled borders and gives narrow phones calmer space around the content.
	draw_line(Vector2(0, size.y * 0.73), Vector2(size.x, size.y * 0.73), Color("#a27746"), 7)
	var mote_count: int = 20 if VisualSettings.decorative_motion() else 0
	for mote in range(mote_count):
		var x: float = fmod(mote * 137.7 + age * (5 + mote % 4), maxf(1, size.x))
		var y: float = fmod(mote * 79.3 - age * 8 + size.y * 10, maxf(1, size.y))
		draw_circle(Vector2(x, y), 1.2 + mote % 2, Color(1, 0.81, 0.5, 0.16))
