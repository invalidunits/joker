extends Node


const OnlineMatchSession = preload("res://Scenes/online_match_session.gd")
const CARD_DISPLAYER_SCENE = preload("res://GUI/gui/CardDisplayer.tscn")

@export var backend_base_url: String = ""
@export var match_id: String = ""
@export_file("*.tscn") var menu_scene_path: String = "res://GUI/Menus/MainMenu.tscn"

var _socket: WebSocketPeer
var _awaiting_turn: bool = false
var _closing_expected: bool = false
var _player_index: int = -1
var _current_turn: int = 0
var _current_hand: PackedByteArray = PackedByteArray()
var _round_start_unix: float = -1.0
var _choice_cards: Array[int] = []

@onready var _card_list: MarginContainer = $Game/UI/Container/CardList
@onready var _status_label: Label = $Overlay/MarginContainer/PanelContainer/VBoxContainer/StatusLabel
@onready var _detail_label: Label = $Overlay/MarginContainer/PanelContainer/VBoxContainer/DetailLabel
@onready var _back_button: Button = $Overlay/MarginContainer/PanelContainer/VBoxContainer/BackButton
@onready var _choice_panel: PanelContainer = $Overlay/ChoicePanel
@onready var _choice_label: Label = $Overlay/ChoicePanel/MarginContainer/VBoxContainer/ChoiceLabel
@onready var _choice_buttons: Array[Button] = [
	$Overlay/ChoicePanel/MarginContainer/VBoxContainer/ChoiceButtons/Choice0,
	$Overlay/ChoicePanel/MarginContainer/VBoxContainer/ChoiceButtons/Choice1,
	$Overlay/ChoicePanel/MarginContainer/VBoxContainer/ChoiceButtons/Choice2,
	$Overlay/ChoicePanel/MarginContainer/VBoxContainer/ChoiceButtons/Choice3,
	$Overlay/ChoicePanel/MarginContainer/VBoxContainer/ChoiceButtons/Choice4,
]
@onready var _my_table: Node3D = $Game/Tables/MyTable
@onready var _their_table: Node3D = $Game/Tables/TheirTable


func _ready() -> void:
	_back_button.pressed.connect(_return_to_menu)
	for index in range(_choice_buttons.size()):
		_choice_buttons[index].pressed.connect(_on_choice_button_pressed.bind(index))
	_choice_panel.visible = false
	_clear_sample_hand()
	_load_match_session()
	if backend_base_url.is_empty() or match_id.is_empty():
		_show_connection_error("Missing matchmaking session")
		return
	_connect_to_match()


func _process(_delta: float) -> void:
	_update_round_countdown()
	_poll_socket()


func _exit_tree() -> void:
	_close_socket(1000, "scene-exit")


func _load_match_session() -> void:
	if backend_base_url.is_empty():
		backend_base_url = OnlineMatchSession.backend_base_url
	if match_id.is_empty():
		match_id = OnlineMatchSession.match_id


func _connect_to_match() -> void:
	_close_socket(1000, "reconnecting")
	_closing_expected = false
	_socket = WebSocketPeer.new()
	var ws_url := _build_websocket_url(backend_base_url, "/match/%s?spectate=false" % match_id)
	var err := _socket.connect_to_url(ws_url)
	if err != OK:
		_show_connection_error("Failed to connect to match %s" % match_id)
		return

	_set_status("Connecting to match", match_id)


func _poll_socket() -> void:
	if _socket == null:
		return

	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _socket.get_available_packet_count() > 0:
			var payload := _socket.get_packet().get_string_from_utf8()
			_handle_payload(payload)
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
			_set_status("Joined match", "You are Player %s" % str(_player_index + 1))
		"startingRoundIn":
			_handle_round_start(message)
		"hand":
			_handle_hand(message)
		"requestTurn":
			_handle_turn_request(message)
		"opponentPlayed":
			_handle_opponent_played(message)
		"roundResult":
			_handle_round_result(message, false)
		"jokerBurn":
			_handle_round_result(message, true)
		"chooseTopFive":
			_handle_choose_top_five(message)
		"matchEnded":
			_handle_match_ended(message)


func _handle_round_start(message: Dictionary) -> void:
	var time_text := str(message.get("time", ""))
	_round_start_unix = Time.get_unix_time_from_datetime_string(time_text)
	_set_status("Round starting", _format_countdown_text())


func _handle_hand(message: Dictionary) -> void:
	_current_turn = int(message.get("turn", _current_turn))
	_player_index = int(message.get("player", _player_index))
	_current_hand = Marshalls.base64_to_raw(str(message.get("hand", "")))
	_render_hand()
	_set_status("Hand updated", "Deck remaining: %s" % str(int(message.get("decklen", 0))))


func _handle_turn_request(message: Dictionary) -> void:
	_current_turn = int(message.get("turn", _current_turn))
	_awaiting_turn = true
	_card_list.selecting = true
	_set_hand_interactable(true)
	var first_player = message.get("firstPlayer", null)
	if first_player == null:
		_set_status("Choose a card", "Turn %s" % str(_current_turn))
	elif int(first_player) == _player_index:
		_set_status("Play first", "Turn %s" % str(_current_turn))
	else:
		_set_status("Waiting for opponent", "Turn %s" % str(_current_turn))


func _handle_opponent_played(message: Dictionary) -> void:
	var player := int(message.get("player", -1))
	var card = message.get("card", null)
	if card == null:
		_set_status("Opponent played", "Waiting for reveal")
		return

	_set_played_card(player, int(card))
	_set_status("Opponent card revealed", _describe_card(int(card)))


func _handle_round_result(message: Dictionary, is_joker_burn: bool) -> void:
	_awaiting_turn = false
	_set_hand_interactable(false)
	_card_list.selecting = false
	_choice_panel.visible = false
	var round = message.get("round", {})
	if typeof(round) == TYPE_DICTIONARY:
		var played = round.get("Played", [])
		if typeof(played) == TYPE_ARRAY and played.size() >= 2:
			_set_played_card(0, int(played[0]))
			_set_played_card(1, int(played[1]))

	var remaining = message.get("remaining", [])
	if typeof(remaining) == TYPE_ARRAY and remaining.size() >= 2 and _player_index >= 0:
		var my_total := int(remaining[_player_index])
		var their_total := int(remaining[1 - _player_index])
		_set_deck_size(_my_table, my_total)
		_set_deck_size(_their_table, their_total)
		_detail_label.text = "Cards remaining - You: %s, Opponent: %s" % [my_total, their_total]

	if is_joker_burn:
		_set_status("Round burned", "A joker removed the pile")
		return

	var winner := int(message.get("winner", -1))
	if winner == _player_index:
		_set_status("Round won", _detail_label.text)
	elif winner >= 0:
		_set_status("Round lost", _detail_label.text)


func _handle_choose_top_five(message: Dictionary) -> void:
	_choice_cards.clear()
	var cards = message.get("cards", [])
	if typeof(cards) != TYPE_ARRAY:
		return

	for value in cards:
		_choice_cards.append(int(value))

	_choice_panel.visible = true
	_choice_label.text = "Choose which card moves to the top of your deck"
	for index in range(_choice_buttons.size()):
		var button := _choice_buttons[index]
		button.visible = index < _choice_cards.size()
		button.disabled = index >= _choice_cards.size()
		if index < _choice_cards.size():
			button.text = _describe_card(_choice_cards[index])

	_set_status("Card effect", "Choose from the top of your deck")


func _handle_match_ended(message: Dictionary) -> void:
	_awaiting_turn = false
	_set_hand_interactable(false)
	_choice_panel.visible = false
	var winner := int(message.get("winner", -1))
	var reason := str(message.get("reason", "unknown"))
	if winner < 0:
		_set_status("Match ended", "Result: tie (%s)" % reason)
	elif winner == _player_index:
		_set_status("Match ended", "You won (%s)" % reason)
	else:
		_set_status("Match ended", "You lost (%s)" % reason)
	_close_socket(1000, "match-ended")


func _render_hand() -> void:
	CardDisplayer.reset_play_lock()
	for child in _card_list.get_children():
		child.queue_free()

	for index in range(_current_hand.size()):
		var displayer := CARD_DISPLAYER_SCENE.instantiate() as CardDisplayer
		if displayer == null:
			continue

		displayer.card = _make_card_resource(_current_hand[index])
		displayer.auto_play_on_click = false
		displayer.input_enabled = _awaiting_turn
		displayer.card_clicked.connect(_on_card_clicked)
		displayer.set_meta("hand_index", index)
		_card_list.add_child(displayer)


func _on_card_clicked(displayer: CardDisplayer) -> void:
	if not _awaiting_turn:
		return

	var card_index = int(displayer.get_meta("hand_index", -1))
	if card_index < 0:
		return

	_send_json({
		"type": "turn",
		"cardIndex": card_index,
	})
	_awaiting_turn = false
	_set_hand_interactable(false)
	_card_list.selecting = false
	displayer.play_card()
	_set_status("Turn submitted", "Waiting for opponent")


func _on_choice_button_pressed(index: int) -> void:
	if index < 0 or index >= _choice_cards.size():
		return

	_send_json({
		"type": "effectChoice",
		"choice": index,
	})
	_choice_panel.visible = false
	_set_status("Choice sent", _describe_card(_choice_cards[index]))


func _set_hand_interactable(enabled: bool) -> void:
	for child in _card_list.get_children():
		if child is CardDisplayer:
			child.input_enabled = enabled


func _set_played_card(player: int, backend_card: int) -> void:
	if _player_index < 0:
		return

	var table := _my_table if player == _player_index else _their_table
	var place := table.get_node_or_null("MPlace")
	if place == null:
		return

	place.top_card = _make_card_resource(backend_card)
	place.middle_card = _make_card_resource(backend_card)
	place.pile_size = 1


func _set_deck_size(table: Node3D, total_cards: int) -> void:
	var deck := table.get_node_or_null("Deck")
	if deck == null:
		return

	deck.pile_size = mini(total_cards, 20)


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


func _set_status(title: String, detail: String) -> void:
	_status_label.text = title
	_detail_label.text = detail


func _show_connection_error(message: String) -> void:
	_set_status("Connection error", message)
	_set_hand_interactable(false)
	_card_list.selecting = false


func _clear_sample_hand() -> void:
	for child in _card_list.get_children():
		child.queue_free()
	_card_list.selecting = false


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


func _return_to_menu() -> void:
	OnlineMatchSession.clear_match()
	_close_socket(1000, "return-menu")
	get_tree().change_scene_to_file(menu_scene_path)
