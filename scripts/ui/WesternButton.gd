extends Button

var feedback: Tween
var hovered: bool = false

func _ready() -> void:
	resized.connect(func(): pivot_offset = size / 2)
	mouse_entered.connect(func(): hovered = true; animate_scale(Vector2.ONE * 1.018))
	mouse_exited.connect(func(): hovered = false; animate_scale(Vector2.ONE))
	button_down.connect(func(): animate_scale(Vector2(0.98, 0.94)))
	button_up.connect(func(): animate_scale(Vector2.ONE * (1.018 if hovered else 1.0)))

func animate_scale(value: Vector2) -> void:
	if disabled:
		return
	if feedback:
		feedback.kill()
	pivot_offset = size / 2
	feedback = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	feedback.tween_property(self, "scale", value, 0.12)
