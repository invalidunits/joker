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

var selected_card = 0


var max_offset:float = 0
var min_offset:float = 0

func smin(a:float, b:float, k:float) -> float:
	return log(exp(a*k) + exp(b*k))/k
	
func smax(a:float, b:float, k:float) -> float:
	return -log(exp(-a*k) + exp(-b*k))/k


func sclamp(x:float, a:float, b:float, k:float) -> float:
	return smin(smax(x, max(a, b), k), min(a, b), k);
	


func _process(delta: float) -> void:
	var nodes = []
	for n in get_children():
		if not n.is_played:
			nodes.append(n)
	
	max_offset = max(len(nodes)-16, 0)+2
	min_offset = -max(len(nodes)-16, 0)-2
	var real_offset = sclamp(offset, min_offset, max_offset, 1.0)
	
	var half = float(len(nodes))/2.0 - 0.5 - real_offset
	var local_mouse = get_local_mouse_position()
	var best_distance = INF
	for i in range(len(nodes)):
		var node = nodes[i]
		if node.is_played:
			continue
		
		# Base X position
		node.position.x = (float(i) - half) * card_distance
		node.position.y = (1.0 - cos(asin(min(node.position.x / radius, 1.0)))) * radius_distance
		
		var local_distance = local_mouse.distance_squared_to(node.position);
		if local_distance < best_distance:
			best_distance = local_distance
			selected_card = i
		node.rotation = asin(min(node.position.x / radius, 1.0))
	


	
	for i in range(len(nodes)):
		var node = nodes[i]
		if node.is_played:
			continue
		
		if i == selected_card:
			var is_hovered = local_mouse.distance_squared_to(node.position) < 10000
			node.selected = lerp(node.selected, float(is_hovered), delta * 8)
		else:
			node.selected = lerp(node.selected, 0.0, delta * 8)
		
		var hover_lift = -100 * node.selected  # negative = up
		node.position.y = (1.0 - cos(asin(min(node.position.x / radius, 1.0)))) * radius_distance + hover_lift
		node.rotation = asin(min(node.position.x / radius, 1.0))


#func _input(event: InputEvent) -> void:
	#if event.is_action("ui_accept"):
