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

func _describe_suite() -> StringName:
	match suite:
		CardSuite.Hearts: return "Hearts"
		CardSuite.Diamonds: return "Diamonds"
		CardSuite.Clubs: return "Clubs"
		CardSuite.Spades: return "Spades"
	return ""
	

func _describe_card() -> String:
	if suite == CardSuite.Special and number == 2:
		return &"Joker"
	match number:
		1: return "Ace of " + _describe_suite()
		11: return "Jack of" + _describe_suite()
		12: return "Queen of" + _describe_suite()
		13: return "King of" + _describe_suite()
		_: return str(number) + " " + _describe_suite()

func _describe_ability() -> StringName:
	if suite == CardSuite.Special and number == 2:
		return &"Burns other card and self destructs"
	match number:
		2: return &"If captured, Force the other player to place first next turn."
		3: return &"If captured, Choose a card from the top 5 cards in your deck."
		4: return &"Shuffle the opponents deck."
		5: return &"If captured, swap any card in hand with one of your opponent's"
		6: return &"Always captures anything in it's suite."
		7: return &"Always captures 9."
		8: return &"No effect"
		9: return &"Can be played as a 6."
		10: return &"Disables any card effect."
		11: return &"If Jack is played in war, it always captures."
		12: return &"If captured grab a random King from your Deck if possible"
		13: return &"Both players play the top card in their deck"
		1: return &"You always capture (unless it's a joker)"
	return &""
