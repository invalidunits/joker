@tool
extends MarginContainer


@export
var offset:float = 0;


@export
var card_distance:float = 100;

@export
var radius:float = 100;

@export
var radius_distance:float = 100;


var max_offset:float = 0
var min_offset:float = 0

func smin(a:float, b:float, k:float) -> float:
	return log(exp(a*k) + exp(b*k))/k
	
func smax(a:float, b:float, k:float) -> float:
	return -log(exp(-a*k) + exp(-b*k))/k


func sclamp(x:float, a:float, b:float, k:float) -> float:
	return smin(smax(x, max(a, b), k), min(a, b), k);
	



func _process(delta: float) -> void:
	var nodes = get_children(false);
	
	max_offset = max(len(nodes)-9, 0)
	min_offset = -max(len(nodes)-9, 0)
	var real_offset = sclamp(offset, min_offset, max_offset, 1.0);
	
	var half = float(len(nodes))/2.0 - 0.5 - real_offset;
	var mouse = get_global_mouse_position()
	for i in range(len(nodes)):
		nodes[i].position.x = (float(i)-float(half))*card_distance;
		nodes[i].position.y = (1.0-cos(asin(min(nodes[i].position.x/radius, 1.0))))*radius_distance
		nodes[i].rotation = asin(min(nodes[i].position.x/radius, 1.0));
