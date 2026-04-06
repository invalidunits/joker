@tool
class_name Card;
extends Resource

enum CardSuite {
	Hearts = 0,
	Diamonds = 1,
	Clubs = 2,
	Spades = 3,
	Special = -1
}

func _get_card_spr_index() -> int:
	assert(false, "_get_card_spr_index unimplemented");
	return 0

func _get_card_value() -> int:
	assert(false, "_get_card_spr_index unimplemented");
	return 0
		
	# TODO: CardEffects
