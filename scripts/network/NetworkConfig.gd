class_name NetworkConfig
extends RefCounted

static func server_url() -> String:
	if OS.has_feature("web"):
		var configured: Variant = JavaScriptBridge.eval("window.WWPO_CONFIG && window.WWPO_CONFIG.serverUrl || ''")
		if configured is String and not configured.is_empty():
			return configured
	var environment := OS.get_environment("WWPO_SERVER_URL")
	if not environment.is_empty():
		return environment
	var config := ConfigFile.new()
	config.load("res://config/network.cfg")
	return str(config.get_value("network", "server_url", "ws://127.0.0.1:7000"))
