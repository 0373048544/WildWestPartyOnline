extends Node

func _ready() -> void:
	if not OS.has_feature("web"):
		return
	get_viewport().size_changed.connect(resize)
	resize()

func resize() -> void:
	var width: int = int(JavaScriptBridge.eval("window.innerWidth"))
	var height: int = int(JavaScriptBridge.eval("window.innerHeight"))
	var target := Vector2i(960, 600) if width >= height else Vector2i(600, 960)
	if width > 1100:
		target = Vector2i(1440, 900)
	if get_window().content_scale_size != target:
		get_window().content_scale_size = target
