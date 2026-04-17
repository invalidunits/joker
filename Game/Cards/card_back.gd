@tool
class_name CardBack
extends Card

func _get_card_spr_index() -> int:
	return 3

func _get_card_value() -> int:
	return 0

func _describe_suite() -> StringName:
	return ""

func _describe_card() -> String:
	return "Unrevealed"

func _describe_ability() -> StringName:
	return ""
