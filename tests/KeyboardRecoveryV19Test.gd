extends Node

const WEB_LAYOUT = preload("res://scripts/ui/WebLayout.gd")

var checks := 0
var failures: Array[String] = []

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("KEYBOARD RECOVERY V19 FAILED: " + message)

func geometry(width: float, height: float, left: float = 0.0, top: float = 0.0) -> Dictionary:
	return {"width": width, "height": height, "left": left, "top": top}

func _ready() -> void:
	var layout: Node = WEB_LAYOUT.new()
	add_child(layout)
	# A changing keyboard/toolbar viewport must never be accepted as stable.
	layout._recovery_stable_samples = 0
	layout._recovery_last_sample = Vector4.ZERO
	expect(not layout._observe_recovery_sample(geometry(390, 510)), "first keyboard-sized sample is not stable")
	expect(not layout._observe_recovery_sample(geometry(390, 575)), "changing close animation resets stability")
	expect(not layout._observe_recovery_sample(geometry(390, 844)), "first restored full-height sample is not committed")
	expect(not layout._observe_recovery_sample(geometry(390, 844)), "second restored sample still waits")
	expect(layout._observe_recovery_sample(geometry(390, 844)), "third equal restored sample completes recovery")

	# Rapid focus switching starts a fresh generation and cannot reuse old samples.
	layout._recovery_stable_samples = 2
	layout._recovery_last_sample = Vector4(390, 844, 0, 0)
	layout._recovery_generation += 1
	layout._recovery_stable_samples = 0
	layout._recovery_last_sample = Vector4.ZERO
	expect(not layout._observe_recovery_sample(geometry(390, 844)), "new focus generation discards previous stability count")

	expect(layout._geometry_close(Vector4(390, 844, 0, 0), Vector4(390.4, 843.6, 0.2, 0.1)),
		"sub-pixel Safari jitter is treated as stable")
	expect(not layout._geometry_close(Vector4(390, 844, 0, 0), Vector4(390, 820, 0, 0)),
		"real viewport height change is not treated as jitter")

	var css := FileAccess.get_file_as_string("res://web/mobile-shell.css")
	var bootstrap := FileAccess.get_file_as_string("res://web/viewport-bootstrap.js")
	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	expect(css.contains("--wwpo-viewport-height") and css.contains("--wwpo-viewport-top"),
		"canvas CSS uses the shared measured visual viewport geometry")
	expect(bootstrap.contains("visualViewport.addEventListener") and bootstrap.contains("--wwpo-viewport-height"),
		"browser bootstrap updates geometry before and during Safari viewport changes")
	expect(not preset.contains("head_include=\"<meta name=\\\"viewport\\\""),
		"export head include no longer injects a duplicate viewport meta tag")

	if failures.is_empty():
		print("PASS: %d Safari keyboard recovery and web shell checks" % checks)
		get_tree().quit(0)
	else:
		print("FAIL: %d/%d keyboard recovery checks" % [failures.size(), checks])
		get_tree().quit(1)
