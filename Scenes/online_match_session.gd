class_name OnlineMatchSession
extends RefCounted


static var backend_base_url: String = ""
static var match_id: String = ""


static func store_match(base_url: String, next_match_id: String) -> void:
	backend_base_url = base_url
	match_id = next_match_id


static func clear_match() -> void:
	backend_base_url = ""
	match_id = ""


static func has_match() -> bool:
	return not backend_base_url.is_empty() and not match_id.is_empty()