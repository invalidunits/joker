extends Node


const MatchSessionState = preload("res://Scenes/online_match_session.gd")
const CARD_DISPLAYER_SCENE = preload("res://GUI/gui/CardDisplayer.tscn")
const CARD_BACK_SCRIPT = preload("res://Game/Cards/card_back.gd")
const CARD_LIST_OFFSET_META_KEY := "cardListOffset"
const PRE_ROUND_REVEAL_SECONDS := 1.5
const PRE_ROUND_CAPTURE_TWEEN_SECONDS := 0.42
const JOKER_BURN_FIRE_GROW_SECONDS := 0.16
const JOKER_BURN_FIRE_SHRINK_SECONDS := 0.32
const JOKER_BURN_FIRE_MIN_SCALE := Vector3(0.001, 0.001, 0.001)
const JOKER_BURN_FIRE_MAX_SCALE := Vector3(1.0, 1.0, 1.0)

@export var backend_base_url: String = ""
@export var match_id: String = ""
@export_file("*.tscn") var menu_scene_path: String = "res://GUI/Menus/MainMenu.tscn"

var _socket: WebSocketPeer
var _awaiting_turn: bool = false
var _awaiting_war_turn: bool = false
var _war_selected_cards: Array[int] = []
var _war_needed_count: int = 4
var _closing_expected: bool = false
var _player_index: int = -1
var _current_turn: int = 0
var _current_hand: PackedByteArray = PackedByteArray()
var _round_start_unix: float = -1.0
var _choice_cards: Array[int] = []
var _last_sent_card_list_offset: float = 0
var _choose_top_five_rest_position: Vector2
var _choose_top_five_hidden_position: Vector2
var _choose_top_five_tween: Tween
var _event_label_rest_position: Vector2
var _event_label_hidden_position: Vector2
var _event_label_tween: Tween
var _event_label_hide_timer: SceneTreeTimer = null

const EVENT_LABEL_SLIDE_IN_SECONDS := 0.3
const EVENT_LABEL_SLIDE_OUT_SECONDS := 0.22
const EVENT_LABEL_HOLD_SECONDS := 2.0

@onready var _card_list: MarginContainer = $Game/UI/Container/CardList
@onready var _opponent_card_list: MarginContainer = $Game/OtherPlayer/OpponentCardGraphics/CardList
@onready var _event_label_container: MarginContainer = $Game/UI/MarginContainer
@onready var _status_label: Label = $Game/UI/MarginContainer/VBoxContainer/BigEventLabel
@onready var _detail_label: Label = $Game/UI/MarginContainer/VBoxContainer/SmallEventLabel
@onready var _choose_top_five: VBoxContainer = $Game/UI/ChooseTop5
@onready var _card_selector: MarginContainer = $Game/UI/ChooseTop5/CardSelector
@onready var _my_table: Node3D = $Game/Tables/MyTable
@onready var _their_table: Node3D = $Game/Tables/TheirTable
@onready var _camera_animator: AnimationPlayer = $Game/Node3D/AnimationPlayer


func _ready() -> void:
	_card_list.played_card.connect(_on_card_clicked)
	_card_selector.played_card.connect(_on_top_five_card_clicked)
	_choose_top_five_rest_position = _choose_top_five.position
	_choose_top_five_hidden_position = Vector2(
		_choose_top_five_rest_position.x,
		_choose_top_five_rest_position.y - get_viewport().get_visible_rect().size.y
	)
	_hide_choose_top_five(true)
	_event_label_rest_position = _event_label_container.position
	_event_label_hidden_position = Vector2(
		_event_label_rest_position.x,
		_event_label_rest_position.y - get_viewport().get_visible_rect().size.y
	)
	_event_label_container.position = _event_label_hidden_position
	_event_label_container.visible = false
	_card_selector.selecting = false
	_clear_sample_hand()
	_opponent_card_list.selecting = false
	_set_joker_fire_scale(JOKER_BURN_FIRE_MIN_SCALE)
	_load_match_session()
	if backend_base_url.is_empty() or match_id.is_empty():
		_show_connection_error("Missing matchmaking session")
		return
	_connect_to_match()
	_game_loop()

func _process(delta:float):
	_update_round_countdown()
	_sync_card_list_metadata()

func _game_loop():
	while true:
		if get_tree() == null: break
		await get_tree().process_frame
		await _poll_socket()


func _exit_tree() -> void:
	_close_socket(1000, "scene-exit")


func _load_match_session() -> void:
	MatchSessionState.apply_runtime_overrides(backend_base_url, match_id)
	if backend_base_url.is_empty():
		backend_base_url = MatchSessionState.backend_base_url
	if match_id.is_empty():
		match_id = MatchSessionState.match_id


func _connect_to_match() -> void:
	_close_socket(1000, "reconnecting")
	_closing_expected = false
	_socket = WebSocketPeer.new()
	var ws_url := _build_websocket_url(backend_base_url, "/match/%s?spectate=false" % match_id)
	var err := _socket.connect_to_url(ws_url)
	if err != OK:
		_show_connection_error("Failed to connect to match %s" % match_id)
		return

	_set_status("Connecting to match", match_id, true)


func _poll_socket() -> void:
	if _socket == null:
		return

	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _socket.get_available_packet_count() > 0:
			var payload := _socket.get_packet().get_string_from_utf8()
			await _handle_payload(payload)
			if _socket == null:
				return
	elif state == WebSocketPeer.STATE_CLOSED and not _closing_expected:
		var reason := _socket.get_close_reason()
		if reason.is_empty():
			reason = "Connection closed"
		_show_connection_error(reason)


func _handle_payload(payload: String) -> void:
	var parsed = JSON.parse_string(payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var message: Dictionary = parsed
	var message_type := str(message.get("type", ""))
	match message_type:
		"joinedMatch":
			var joined_player = message.get("player", null)
			if joined_player != null:
				_player_index = int(joined_player)
			_set_status("Joined match", "You are Player %s" % str(_player_index + 1), true)
		"startingRoundIn":
			_handle_round_start(message)
		"hand":
			_handle_hand(message)
		"requestWarTurn":
			_handle_war_turn_request(message)
		"warProgress":
			_handle_war_progress(message)
		"warReveal":
			_handle_war_reveal(message)
		"requestTurn":
			_handle_turn_request(message)
		"opponentPlayed":
			_handle_opponent_played(message)
		"preroundresult":
			_handle_preround_result(message)
		"roundResult":
			await _handle_round_result(message, false)
		"jokerBurn":
			await _handle_round_result(message, true)
		"chooseTopFive":
			_handle_choose_top_five(message)
		"meta":
			_handle_meta(message)
		"matchEnded":
			_handle_match_ended(message)


func _handle_meta(message: Dictionary) -> void:
	var sender = message.get("from", null)
	if typeof(sender) == TYPE_DICTIONARY:
		var sender_player = sender.get("player", null)
		if sender_player != null and int(sender_player) == _player_index:
			return

	var data = message.get("data", null)
	if typeof(data) != TYPE_DICTIONARY:
		return

	if not data.has(CARD_LIST_OFFSET_META_KEY):
		return

	_opponent_card_list.set("offset", float(data[CARD_LIST_OFFSET_META_KEY]))


func _handle_round_start(message: Dictionary) -> void:
	var time_text := str(message.get("time", ""))
	_round_start_unix = Time.get_unix_time_from_datetime_string(time_text)
	_set_status("Round starting", _format_countdown_text(), true)


func _handle_hand(message: Dictionary) -> void:
	_current_turn = int(message.get("turn", _current_turn))
	_player_index = int(message.get("player", _player_index))
	_current_hand = Marshalls.base64_to_raw(str(message.get("hand", "")))
	_render_hand()
	_render_opponent_hand(int(message.get("opponentHandLen", 0)))


func _handle_turn_request(message: Dictionary) -> void:
	_current_turn = int(message.get("turn", _current_turn))
	_awaiting_turn = true
	_clear_played_cards()
	_card_list.selecting = true
	_set_hand_interactable(true)
	var first_player = message.get("firstPlayer", null)
	if first_player == null:
		_set_status("Choose a card", "Turn %s" % str(_current_turn), true)
	elif int(first_player) == _player_index:
		_set_status("Play first", "Turn %s" % str(_current_turn), true)
	else:
		_set_status("Waiting for opponent", "Turn %s" % str(_current_turn), true)

func _handle_war_turn_request(_message: Dictionary) -> void:
	_war_selected_cards.clear()
	_war_needed_count = mini(_current_hand.size(), 4)
	if _war_needed_count == 0:
		# No hand cards — server draws all from deck, submit immediately
		_send_json({"type": "warTurn", "cards": []})
		_set_status("War!", "Drawing from deck...", true)
		return
	_awaiting_war_turn = true
	_card_list.selecting = true
	_set_hand_interactable(true)
	_update_war_status()


func _handle_war_progress(message: Dictionary) -> void:
	if _player_index < 0:
		return

	var player := int(message.get("player", -1))
	var slot := int(message.get("slot", -1))
	if player < 0 or player == _player_index:
		return

	var place_names := ["LPlace", "MPlace", "RPlace", "WarPlace"]
	if slot < 0 or slot >= place_names.size():
		return

	var table := _table_for_backend_player(player)
	if table == null:
		return

	var place := table.get_node_or_null(place_names[slot])
	if place == null:
		return

	var card_value = message.get("card", null)
	if card_value != null:
		place.top_card = _make_card_resource(int(card_value))
		place.middle_card = _make_card_resource(int(card_value))
	else:
		place.top_card = _make_card_back()
		place.middle_card = _make_card_back()
	place.pile_size += 1


func _handle_war_reveal(message: Dictionary) -> void:
	var cards = message.get("cards", [])
	if typeof(cards) != TYPE_ARRAY or cards.size() < 2:
		return
	for backend_player in [0, 1]:
		var table := _table_for_backend_player(backend_player)
		if table == null:
			continue
		var place: Node3D = table.get_node_or_null("WarPlace")
		if place == null:
			continue
		var card_value := int(cards[backend_player])
		place.top_card = _make_card_resource(card_value)
		place.middle_card = _make_card_resource(card_value)


func _handle_opponent_played(message: Dictionary) -> void:
	var player := int(message.get("player", -1))
	if _player_index >= 0 and player != _player_index:
		_render_opponent_hand(maxi(_opponent_card_list.get_child_count() - 1, 0))
	var card = message.get("card", null)
	if card == null:
		_set_played_card(player, 0, false)
		return

	_set_played_card(player, int(card), true)


func _handle_round_result(message: Dictionary, is_joker_burn: bool) -> void:
	_awaiting_turn = false
	_awaiting_war_turn = false
	_war_selected_cards.clear()
	_set_hand_interactable(false)
	_card_list.selecting = false
	_hide_choose_top_five()
	_card_selector.selecting = false
	
	var winner = message.get("winner", -1)
	if winner == null:
		winner = -1
	
	await _play_pre_round_capture_sequence(winner, not is_joker_burn)
	var round_data = message.get("round", {})
	if typeof(round_data) == TYPE_DICTIONARY:
		var played = round_data.get("Played", [])
		if typeof(played) == TYPE_ARRAY and played.size() >= 2:
			_set_played_card(0, int(played[0]), true)
			_set_played_card(1, int(played[1]), true)

	var remaining = message.get("remaining", [])
	if typeof(remaining) == TYPE_ARRAY and remaining.size() >= 2 and _player_index >= 0:
		var my_total := int(remaining[_player_index])
		var their_total := int(remaining[1 - _player_index])
		_set_deck_size(_my_table, my_total)
		_set_deck_size(_their_table, their_total)
		_detail_label.text = "Cards remaining - You: %s, Opponent: %s" % [my_total, their_total]


	if winner == _player_index:
		_set_status("Round won", _detail_label.text)
	elif winner >= 0:
		_set_status("Round lost", _detail_label.text)
	else:
		_hide_event_label()


func _handle_preround_result(message: Dictionary) -> void:
	if _player_index < 0:
		return

	var played = message.get("played", [])
	if typeof(played) != TYPE_ARRAY or played.size() < 2:
		return

	_set_played_card(0, int(played[0]), true)
	_set_played_card(1, int(played[1]), true)


func _handle_choose_top_five(message: Dictionary) -> void:
	_choice_cards.clear()
	var cards = message.get("cards", [])
	if typeof(cards) != TYPE_ARRAY:
		return

	for value in cards:
		_choice_cards.append(int(value))

	_clear_card_list(_card_selector)
	for index in range(_choice_cards.size()):
		var displayer := CARD_DISPLAYER_SCENE.instantiate()
		if displayer == null:
			continue

		displayer.card = _make_card_resource(_choice_cards[index])
		displayer.set_meta("choice_index", index)
		_card_selector.add_child(displayer)

	_show_choose_top_five()
	_card_selector.selecting = true


func _handle_match_ended(message: Dictionary) -> void:
	_awaiting_turn = false
	_set_hand_interactable(false)
	_hide_choose_top_five()
	_card_selector.selecting = false
	var winner := int(message.get("winner", -1))
	var reason := str(message.get("reason", "unknown"))
	if winner < 0:
		_set_status("Match ended", "Result: tie (%s)" % reason, true)
	elif winner == _player_index:
		_set_status("Match ended", "You won (%s)" % reason, true)
	else:
		_set_status("Match ended", "You lost (%s)" % reason, true)
	_close_socket(1000, "match-ended")


func _render_hand() -> void:
	_clear_card_list(_card_list)
		
	for index in range(_current_hand.size()):
		var displayer := CARD_DISPLAYER_SCENE.instantiate()
		if displayer == null:
			continue

		displayer.card = _make_card_resource(_current_hand[index])
		displayer.set_meta("hand_index", index)
		_card_list.add_child(displayer)


func _render_opponent_hand(card_count: int) -> void:
	_clear_card_list(_opponent_card_list)
	_opponent_card_list.selecting = false

	for _index in range(maxi(card_count, 0)):
		var displayer := CARD_DISPLAYER_SCENE.instantiate()
		if displayer == null:
			continue

		displayer.card = _make_card_back()
		displayer.selected = 0.0
		var label := displayer.get_node_or_null("Label")
		if label != null:
			label.visible = false
		_opponent_card_list.add_child(displayer)


func _on_card_clicked(_index:int, displayer: CardDisplayer) -> void:
	var card_index = int(displayer.get_meta("hand_index", -1))
	if card_index < 0 or card_index >= _current_hand.size():
		return

	if _awaiting_war_turn:
		var card_value := int(_current_hand[card_index])
		_war_selected_cards.append(card_value)
		_send_json({
			"type": "warTurn",
			"cards": [card_value],
		})
		displayer.queue_free()

		# Show on the appropriate place
		var place_names := ["LPlace", "MPlace", "RPlace", "WarPlace"]
		var slot := _war_selected_cards.size() - 1
		if slot < place_names.size():
			var place := _my_table.get_node_or_null(place_names[slot])
			if place != null:
				place.top_card = _make_card_resource(card_value)
				place.middle_card = _make_card_resource(card_value)
				place.pile_size += 1

		if _war_selected_cards.size() >= _war_needed_count:
			_awaiting_war_turn = false
			_set_hand_interactable(false)
			_card_list.selecting = false
			_set_status("Waiting for opponent...", "War cards submitted", true)
		else:
			_update_war_status()
		return

	if not _awaiting_turn:
		return

	_set_played_card(_player_index, int(_current_hand[card_index]), true)

	_send_json({
		"type": "turn",
		"cardIndex": card_index,
	})
	_awaiting_turn = false
	_set_hand_interactable(false)
	_card_list.selecting = false
	displayer.queue_free()
	_set_status("Waiting for opponent", "Turn submitted", true)


func _on_top_five_card_clicked(_index: int, displayer: CardDisplayer) -> void:
	var choice_index := int(displayer.get_meta("choice_index", -1))
	if choice_index < 0 or choice_index >= _choice_cards.size():
		return

	_send_json({
		"type": "effectChoice",
		"choice": choice_index,
	})
	_hide_choose_top_five()
	_card_selector.selecting = false


func _show_choose_top_five() -> void:
	if _choose_top_five_tween != null and _choose_top_five_tween.is_valid():
		_choose_top_five_tween.kill()

	_choose_top_five.visible = true
	_choose_top_five.position = _choose_top_five_hidden_position
	_choose_top_five_tween = create_tween()
	_choose_top_five_tween.set_trans(Tween.TRANS_CUBIC)
	_choose_top_five_tween.set_ease(Tween.EASE_OUT)
	_choose_top_five_tween.tween_property(_choose_top_five, "position", _choose_top_five_rest_position, 0.3)


func _hide_choose_top_five(immediate: bool = false) -> void:
	if _choose_top_five_tween != null and _choose_top_five_tween.is_valid():
		_choose_top_five_tween.kill()

	if immediate:
		_choose_top_five.position = _choose_top_five_hidden_position
		_choose_top_five.visible = false
		return

	_choose_top_five_tween = create_tween()
	_choose_top_five_tween.set_trans(Tween.TRANS_CUBIC)
	_choose_top_five_tween.set_ease(Tween.EASE_IN)
	_choose_top_five_tween.tween_property(_choose_top_five, "position", _choose_top_five_hidden_position, 0.22)
	_choose_top_five_tween.finished.connect(func() -> void:
		_choose_top_five.visible = false
	)


func _set_hand_interactable(enabled: bool) -> void:
	_card_list.selecting = enabled;


func _set_played_card(player: int, backend_card: int, revealed: bool = true) -> void:
	if _player_index < 0:
		return

	var table := _my_table if player == _player_index else _their_table
	var place := table.get_node_or_null("MPlace")
	if place == null:
		return

	if not revealed:
		place.top_card = _make_card_back()
		place.middle_card = _make_card_back()
		place.pile_size = 1
		return

	place.top_card = _make_card_resource(backend_card)
	place.middle_card = _make_card_resource(backend_card)
	place.pile_size = 1


func _clear_played_cards() -> void:
	for table in [_my_table, _their_table]:
		for place_name in ["MPlace", "LPlace", "RPlace", "WarPlace"]:
			var place: Node3D = table.get_node_or_null(place_name)
			if place == null:
				continue
			place.pile_size = 0


func _update_war_status() -> void:
	var selected := _war_selected_cards.size()
	var total := _war_needed_count
	var sacrifices_needed := mini(total - 1, 3)
	if selected < sacrifices_needed:
		var left := sacrifices_needed - selected
		_set_status("War! Select sacrifice %d/%d" % [selected + 1, sacrifices_needed], "Pick a card to sacrifice", true)
	else:
		_set_status("War! Select your war card", "This card battles the opponent", true)


func _set_looking_at_table(enabled: bool) -> void:
	if _camera_animator == null:
		return
	_camera_animator.set("looking_at_table", enabled)


func _table_for_backend_player(player: int) -> Node3D:
	if _player_index < 0:
		return null
	return _my_table if player == _player_index else _their_table


func _play_pre_round_capture_sequence(winner: int, capture_to_deck: bool) -> void:
	_camera_animator.looking_at_table.append(self)
	await get_tree().create_timer(PRE_ROUND_REVEAL_SECONDS).timeout
	
	if capture_to_deck and winner >= 0:
		await _tween_played_cards_to_winner_deck(winner)
	else:
		await _play_joker_burn_sequence()
	_camera_animator.looking_at_table.erase(self)


func _fire_node_for_table(table: Node3D) -> Node3D:
	if table == null:
		return null
	var fire := table.get_node_or_null("MPlaceFire") as Node3D
	if fire != null:
		return fire
	return table.get_node_or_null("BurnMPlace") as Node3D


func _set_joker_fire_scale(scale_value: Vector3) -> void:
	for table in [_my_table, _their_table]:
		var fire := _fire_node_for_table(table)
		if fire != null:
			fire.scale = scale_value


func _play_joker_burn_sequence() -> void:
	var fires: Array[Node3D] = []
	for table in [_my_table, _their_table]:
		var fire := _fire_node_for_table(table)
		if fire != null:
			fire.scale = JOKER_BURN_FIRE_MIN_SCALE
			fires.append(fire)

	if fires.is_empty():
		return

	var grow_tween := create_tween()
	grow_tween.set_parallel(true)
	grow_tween.set_trans(Tween.TRANS_BACK)
	grow_tween.set_ease(Tween.EASE_OUT)
	for fire in fires:
		grow_tween.tween_property(fire, "scale", JOKER_BURN_FIRE_MAX_SCALE, JOKER_BURN_FIRE_GROW_SECONDS)
	await grow_tween.finished

	var shrink_tween := create_tween()
	shrink_tween.set_parallel(true)
	shrink_tween.set_trans(Tween.TRANS_CUBIC)
	shrink_tween.set_ease(Tween.EASE_IN)
	for fire in fires:
		shrink_tween.tween_property(fire, "scale", JOKER_BURN_FIRE_MIN_SCALE, JOKER_BURN_FIRE_SHRINK_SECONDS)
	await shrink_tween.finished


func _tween_played_cards_to_winner_deck(winner: int) -> void:
	var winner_table := _table_for_backend_player(winner)
	if winner_table == null:
		return
	var winner_deck: Node3D = winner_table.get_node_or_null("Deck")
	if winner_deck == null:
		return
	var capture_root := winner_table.get_parent() as Node3D
	if capture_root == null:
		return

	var flying_cards: Array[Node3D] = []
	var source_places: Array[Node3D] = []
	for backend_player in [0, 1]:
		var table := _table_for_backend_player(backend_player)
		if table == null:
			continue
		for place_name in ["LPlace", "MPlace", "RPlace", "WarPlace"]:
			var place: Node3D = table.get_node_or_null(place_name)
			if place == null:
				continue
			if place.get_child_count() <= 0:
				continue

			source_places.append(place)
			while place.get_child_count() > 0:
				var displayer: Node3D = place.get_child(place.get_child_count() - 1)
				if displayer == null:
					break

				var original_transform := displayer.global_transform
				displayer.reparent(capture_root)
				displayer.top_level = true
				displayer.global_transform = original_transform
				flying_cards.append(displayer)

	if flying_cards.is_empty():
		return

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)

	for index in range(flying_cards.size()):
		var displayer := flying_cards[index]
		var target := winner_deck.global_position + Vector3(0.0, 0.12 + float(index) * 0.02, 0.0)
		tween.tween_property(displayer, "global_position", target, PRE_ROUND_CAPTURE_TWEEN_SECONDS)
		tween.tween_property(displayer, "scale", displayer.scale * 0.2, PRE_ROUND_CAPTURE_TWEEN_SECONDS)

	await tween.finished
	for displayer in flying_cards:
		displayer.queue_free()
	for place in source_places:
		place.pile_size = 0



func _set_deck_size(table: Node3D, total_cards: int) -> void:
	var deck := table.get_node_or_null("Deck")
	if deck == null:
		return

	deck.pile_size = mini(total_cards, 200)


func _make_card_resource(card_value: int) -> Card:
	var backend_suite := card_value & 0b111
	var backend_number := (card_value >> 3) & 0b11111
	var card := NumericCard.new()
	if backend_suite == 4:
		card.suite = Card.CardSuite.Special
		card.number = 2
		return card

	match backend_suite:
		0:
			card.suite = Card.CardSuite.Clubs
		1:
			card.suite = Card.CardSuite.Hearts
		2:
			card.suite = Card.CardSuite.Spades
		3:
			card.suite = Card.CardSuite.Diamonds
		_:
			card.suite = Card.CardSuite.Special

	card.number = 1 if backend_number == 14 else clampi(backend_number, 1, 13)
	return card


func _make_card_back() -> Card:
	return CARD_BACK_SCRIPT.new()


func _describe_card(card_value: int) -> String:
	var backend_suite := card_value & 0b111
	var backend_number := (card_value >> 3) & 0b11111
	if backend_suite == 4 and backend_number == 0:
		return "Joker"

	var names := {
		11: "Jack",
		12: "Queen",
		13: "King",
		14: "Ace",
	}
	var suite_names := {
		0: "Clubs",
		1: "Hearts",
		2: "Spades",
		3: "Diamonds",
	}
	var value_text := str(backend_number)
	if names.has(backend_number):
		value_text = names[backend_number]
	return "%s of %s" % [value_text, suite_names.get(backend_suite, "Unknown")]


func _send_json(payload: Dictionary) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_socket.send_text(JSON.stringify(payload))


func _send_meta(payload: Dictionary) -> void:
	_send_json({
		"type": "meta",
		"data": payload,
	})


func _sync_card_list_metadata() -> void:
	var current_offset := float(_card_list.get("offset"))
	if is_equal_approx(current_offset, _last_sent_card_list_offset):
		return

	_last_sent_card_list_offset = current_offset
	_send_meta({
		CARD_LIST_OFFSET_META_KEY: current_offset,
	})


func _set_status(title: String, detail: String, permanent: bool = false) -> void:
	_status_label.text = title
	_detail_label.text = detail
	_show_event_label(permanent)


func _show_event_label(permanent: bool = false) -> void:
	if _event_label_tween != null and _event_label_tween.is_valid():
		_event_label_tween.kill()

	_event_label_container.visible = true
	_event_label_tween = create_tween()
	_event_label_tween.set_trans(Tween.TRANS_CUBIC)
	_event_label_tween.set_ease(Tween.EASE_OUT)
	_event_label_tween.tween_property(_event_label_container, "position", _event_label_rest_position, EVENT_LABEL_SLIDE_IN_SECONDS)

	if not permanent:
		_event_label_hide_timer = get_tree().create_timer(EVENT_LABEL_HOLD_SECONDS)
		_event_label_hide_timer.timeout.connect(_hide_event_label, CONNECT_ONE_SHOT)


func _hide_event_label() -> void:
	if _event_label_tween != null and _event_label_tween.is_valid():
		_event_label_tween.kill()

	_event_label_tween = create_tween()
	_event_label_tween.set_trans(Tween.TRANS_CUBIC)
	_event_label_tween.set_ease(Tween.EASE_IN)
	_event_label_tween.tween_property(_event_label_container, "position", _event_label_hidden_position, EVENT_LABEL_SLIDE_OUT_SECONDS)
	_event_label_tween.finished.connect(func() -> void: _event_label_container.visible = false)


func _show_connection_error(message: String) -> void:
	_set_status("Connection error", message, true)
	_set_hand_interactable(false)
	_card_list.selecting = false


func _clear_sample_hand() -> void:
	_clear_card_list(_card_list)
	_clear_card_list(_opponent_card_list)
	_card_list.selecting = false
	_opponent_card_list.selecting = false


func _clear_card_list(card_list: MarginContainer) -> void:
	for child in card_list.get_children():
		child.queue_free()


func _close_socket(code: int, reason: String) -> void:
	if _socket == null:
		return

	_closing_expected = true
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN or state == WebSocketPeer.STATE_CONNECTING:
		_socket.close(code, reason)
	_socket = null


func _build_websocket_url(base_url: String, route: String) -> String:
	var normalized := base_url.strip_edges()
	if normalized.begins_with("https://"):
		normalized = "wss://" + normalized.trim_prefix("https://")
	elif normalized.begins_with("http://"):
		normalized = "ws://" + normalized.trim_prefix("http://")
	elif not normalized.begins_with("ws://") and not normalized.begins_with("wss://"):
		normalized = "ws://" + normalized

	if route.begins_with("/"):
		return normalized.trim_suffix("/") + route

	return normalized.trim_suffix("/") + "/" + route


func _update_round_countdown() -> void:
	if _round_start_unix <= 0.0:
		return

	_detail_label.text = _format_countdown_text()
	if Time.get_unix_time_from_system() >= _round_start_unix:
		_round_start_unix = -1.0


func _format_countdown_text() -> String:
	if _round_start_unix <= 0.0:
		return _detail_label.text
	var remaining := maxi(int(ceil(_round_start_unix - Time.get_unix_time_from_system())), 0)
	return "Round starts in %ss" % str(remaining)
