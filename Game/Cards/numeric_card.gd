@tool
class_name NumericCard
extends Card

@export var suite:CardSuite
@export_range(1, 13) var number:int = 1


func _get_card_spr_index() -> int:
	return number + 13*(1 + suite) - 1

func _get_card_value() -> int:
	if number == 1:
		return 14;
	return number
