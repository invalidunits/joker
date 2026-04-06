@tool
extends Sprite2D


@export var card: Card
func _render():
	if is_instance_valid(card):
		frame = card._get_card_spr_index()

func _process(delta: float) -> void:
	_render()
		
