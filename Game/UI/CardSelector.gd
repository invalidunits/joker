extends AspectRatioContainer

@export var mouse_margin:float = 0.2
@export var speed:float = 4.0
@export var acceleration:float = 1.0
var velocity:float = 0.0
func _process(delta: float) -> void:
	adjust_cards(delta);
	
func adjust_cards(delta: float):
	var rect := get_rect();
	var mouse := get_global_mouse_position();
	if not rect.has_point(mouse):
		return
	
	var mouse_relative = (mouse-rect.position)/rect.size;
	var target = 0;
	if abs(mouse_relative.x - 0.5) > mouse_margin:
		target = -speed*inverse_lerp(mouse_margin, 0.5, abs(mouse_relative.x - 0.5))*sign(mouse_relative.x - 0.5);
	
	velocity = move_toward(velocity, target, acceleration*delta);
	$CardList.offset += velocity;
	$CardList.offset = clamp($CardList.offset, $CardList.min_offset-1.0, $CardList.max_offset+1.0)
