class_name OnlineMatchSession
extends RefCounted


static var backend_base_url: String = ""
static var match_id: String = ""


static func apply_runtime_overrides(default_backend_url: String = "", default_match_id: String = "") -> void:
	if backend_base_url.is_empty() and not default_backend_url.is_empty():
		backend_base_url = default_backend_url
	if match_id.is_empty() and not default_match_id.is_empty():
		match_id = default_match_id

	var config := _parse_runtime_config()
	var next_backend := str(config.get("backend", "")).strip_edges()
	var next_match := str(config.get("match", "")).strip_edges()

	if not next_backend.is_empty():
		backend_base_url = next_backend
	if not next_match.is_empty():
		match_id = next_match


static func store_match(base_url: String, next_match_id: String) -> void:
	backend_base_url = base_url
	match_id = next_match_id


static func clear_match() -> void:
	backend_base_url = ""
	match_id = ""


static func has_match() -> bool:
	return not backend_base_url.is_empty() and not match_id.is_empty()


static func _parse_runtime_config() -> Dictionary:
	var config := {
		"backend": "",
		"match": "",
	}

	_parse_command_line_args(config)
	_parse_web_query_params(config)
	return config


static func _parse_command_line_args(config: Dictionary) -> void:
	var args := PackedStringArray()
	if OS.has_method("get_cmdline_user_args"):
		args = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()

	var i := 0
	while i < args.size():
		var token := str(args[i])
		if token.begins_with("--"):
			var eq_index := token.find("=")
			if eq_index > -1:
				var key := token.substr(2, eq_index - 2)
				var value := token.substr(eq_index + 1)
				_apply_config_key(config, key, value)
			else:
				var key_no_value := token.substr(2)
				var next_value := ""
				if i + 1 < args.size() and not str(args[i + 1]).begins_with("--"):
					next_value = str(args[i + 1])
					i += 1
				_apply_config_key(config, key_no_value, next_value)
		i += 1


static func _apply_config_key(config: Dictionary, key: String, value: String) -> void:
	var normalized_key := key.strip_edges().to_lower().replace("-", "_")
	var normalized_value := value.strip_edges()
	if normalized_value.is_empty():
		return

	match normalized_key:
		"backend", "backend_base_url", "backend_url":
			config["backend"] = normalized_value
		"match", "match_id":
			config["match"] = normalized_value


static func _parse_web_query_params(config: Dictionary) -> void:
	if not OS.has_feature("web"):
		return
	if not Engine.has_singleton("JavaScriptBridge"):
		return

	var raw_json: Variant = JavaScriptBridge.eval("(function(){const p=new URLSearchParams(window.location.search); return JSON.stringify({backend:p.get('backend')||'',match:p.get('match')||''});})()", true)
	if typeof(raw_json) != TYPE_STRING:
		return

	var parser := JSON.new()
	if parser.parse(str(raw_json)) != OK:
		return
	if typeof(parser.data) != TYPE_DICTIONARY:
		return

	var data: Dictionary = parser.data
	_apply_config_key(config, "backend", str(data.get("backend", "")))
	_apply_config_key(config, "match", str(data.get("match", "")))
