@tool
class_name CardDisplayer
extends Sprite2D



@export var selected:float = 0.0;
@export var card: Card

var target_position: Vector2
var time_selected:float = 0.0;


func _render():
	if is_instance_valid(card):
		frame = card._get_card_spr_index()
	if is_instance_valid(card):
		$Label.text = "[font_size=16]" + card._describe_card() + "[/font_size]\n" + card._describe_ability()


func _process(delta: float) -> void:
	_render()
	if selected > 0.5:
		time_selected += delta
	else:
		time_selected -= delta
		time_selected = clamp(time_selected, 3.0, 0.0)
	
	$Label.modulate.a = lerp($Label.modulate.a, float(time_selected > 0.5), delta * 8)
