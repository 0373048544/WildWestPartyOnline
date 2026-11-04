extends Node

signal changed
var level: String = "MEDIUM" if OS.has_feature("web") or OS.has_feature("mobile") else "HIGH"
var reduced_motion: bool = false

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load("user://visual_settings.cfg") == OK:
		var saved: String = config.get_value("visual", "quality", level)
		if saved in ["LOW", "MEDIUM", "HIGH"]:
			level = saved
		reduced_motion = bool(config.get_value("visual", "reduced_motion", false))

func set_quality(value: String, persist: bool = true) -> void:
	if value not in ["LOW", "MEDIUM", "HIGH"]:
		return
	level = value
	if persist:
		var config := ConfigFile.new()
		config.set_value("visual", "quality", level)
		config.save("user://visual_settings.cfg")
	changed.emit()

func set_reduced_motion(value: bool, persist: bool = true) -> void:
	if reduced_motion == value:
		return
	reduced_motion = value
	if persist:
		var config := ConfigFile.new()
		config.load("user://visual_settings.cfg")
		config.set_value("visual", "quality", level)
		config.set_value("visual", "reduced_motion", reduced_motion)
		config.save("user://visual_settings.cfg")
	changed.emit()

func particle_count(count: int) -> int:
	var factor: float = {"LOW": 0.3, "MEDIUM": 0.6, "HIGH": 1.0}[level]
	if reduced_motion:
		factor = minf(factor, 0.25)
	return maxi(1, int(count * factor))

func constrained_device() -> bool:
	return OS.has_feature("web") or OS.has_feature("mobile")

func decorative_motion() -> bool:
	return not reduced_motion and level == "HIGH" and not constrained_device()

func camera_motion() -> bool:
	return not reduced_motion

func essential_duration(seconds: float) -> float:
	# Gameplay feedback remains visible, but reduced-motion users do not have to
	# watch broad overshoot/slide animations.
	return minf(seconds, 0.08) if reduced_motion else seconds

func ui_shadow_size(requested: int) -> int:
	if level == "LOW":
		return mini(2, requested)
	if constrained_device() or level == "MEDIUM":
		return mini(4, requested)
	return requested
