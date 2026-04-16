@tool
class_name CardDisplayer
extends Sprite2D


signal card_clicked(card_displayer: CardDisplayer)

@export var selected:float = 0.0;
@export var card: Card
@export var play_speed: float = 6.0
@export var input_enabled: bool = true
@export var auto_play_on_click: bool = true

static var card_being_played: bool = false
var is_played: bool = false
var target_position: Vector2
var time_selected:float = 0.0;


static func reset_play_lock() -> void:
	card_being_played = false


func _render():
	if is_instance_valid(card):
		frame = card._get_card_spr_index()

func play_card():
	is_played = true
	card_being_played = true
	
	var viewport_rect = get_viewport_rect()
	target_position = Vector2(viewport_rect.size.x / 2, viewport_rect.size.y * 0.3)
	
func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if selected > 0.5 and input_enabled and not is_played and not card_being_played:
			card_clicked.emit(self)
			if auto_play_on_click:
				play_card()
			
func _process(delta: float) -> void:
	_render()
	if selected > 0.5:
		time_selected += delta
	else:
		time_selected -= delta
		time_selected = clamp(time_selected, 3.0, 0.0)
	
	if is_played:
		global_position = global_position.lerp(target_position, delta * play_speed)
		rotation = lerp(rotation, 0.0, delta * play_speed)
		return
	
	$Label.modulate.a = lerp($Label.modulate.a, float(time_selected > 0.5), delta * 8)
		
