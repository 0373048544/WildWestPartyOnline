extends Node

signal changed
var level: String = "MEDIUM" if OS.has_feature("web") or OS.has_feature("mobile") else "HIGH"

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load("user://visual_settings.cfg") == OK:
		var saved: String = config.get_value("visual", "quality", level)
		if saved in ["LOW", "MEDIUM", "HIGH"]:
			level = saved

func set_quality(value: String, persist: bool = true) -> void:
	if value not in ["LOW", "MEDIUM", "HIGH"]:
		return
	level = value
	if persist:
		var config := ConfigFile.new()
		config.set_value("visual", "quality", level)
		config.save("user://visual_settings.cfg")
	changed.emit()

func particle_count(count: int) -> int:
	return maxi(2, int(count * {"LOW": 0.4, "MEDIUM": 0.7, "HIGH": 1.0}[level]))
