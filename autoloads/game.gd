class_name Game
extends Node

signal players_updated
signal player_updated(id: int)
signal vote_updated(id: int)
signal role_settings_updated

static var instance: Game

@export var multiplayer_test: bool = false
@export var use_roles: bool = true
@export var min_players: int = 2 # won't start if there are at least these players
@export var fill_screen: bool = true
@export var test_players: Array[PlayerDataResource] = [] # first one is server
@export var main_scene: PackedScene

var players: Array[Statics.PlayerData] = []
var random_manager: bool = true
var selected_manager_id: int = 0
var change_window_scale : bool = true :
	set(value):
		var last_value: bool = change_window_scale
		change_window_scale = value
		if not change_window_scale:
			reset_window_scale()
		elif last_value != value:
			_update_window_scale()


var _is_window_small: bool = false
var _initial_window_scale_mode: Window.ContentScaleMode
var _initial_window_scale_aspect: Window.ContentScaleAspect

@onready var player_id: Label = %PlayerId

func _enter_tree() -> void:
	instance = self

func _ready() -> void:
	_initial_window_scale_mode = get_window().content_scale_mode
	_initial_window_scale_aspect = get_window().content_scale_aspect
	
	get_window().size_changed.connect(_handle_size_changed)
	_update_window_scale()
	get_tree().node_added.connect(_handle_node_added)
	
	if not OS.is_debug_build():
		multiplayer_test = false
		player_id.hide()


func sort_players() -> void:
	players.sort_custom(func(a: Statics.PlayerData, b: Statics.PlayerData) -> bool: return a.index < b.index)


func add_player(player: Statics.PlayerData) -> void:
	# Ignore roles in joining players' payloads; the host owns the selection.
	player.role = _lobby_role(player.id)
	var existing_player: Statics.PlayerData = null
	for data: Statics.PlayerData in players:
		if data.id == player.id:
			existing_player = data
			break
	if existing_player:
		existing_player.update(player)
	else:
		players.append(player)
	sort_players()
	players_updated.emit()


func remove_player(id: int) -> void:
	for i: int in players.size():
		if players[i].id == id:
			players.remove_at(i)
			break
	
	if multiplayer.is_server():
		var player_indices: Dictionary = {}
		for i: int in players.size():
			players[i].index = i
			player_indices[players[i].id] = i
		update_indices.rpc(player_indices)
	players_updated.emit()


func get_player(id: int) -> Statics.PlayerData:
	for player: Statics.PlayerData in players:
		if player.id == id:
			return player
	return null


func get_current_player() -> Statics.PlayerData:
	return get_player(multiplayer.get_unique_id())


@rpc("reliable")
func update_indices(player_indices: Dictionary) -> void:
	for player: Statics.PlayerData in Game.instance.players:
		if player.id in player_indices:
			player.index = player_indices[player.id]
			if player.id == multiplayer.get_unique_id():
				Debug.index = player.index
				Debug.add_to_window_title("Client %d" % player.index)
	sort_players()
	players_updated.emit()


func _lobby_role(id: int) -> Statics.Role:
	if random_manager:
		return Statics.Role.NONE
	return Statics.Role.MANAGER if id == selected_manager_id else Statics.Role.EMPLOYEE


func configure_roles(random_choice: bool, manager_id: int = 0) -> void:
	if not multiplayer.is_server() or not get_tree().current_scene is LobbyWaitingScreen:
		return
	if not random_choice and get_player(manager_id) == null:
		return
	reset_votes()
	sync_role_settings.rpc(random_choice, 0 if random_choice else manager_id)


@rpc("authority", "reliable", "call_local")
func sync_role_settings(random_choice: bool, manager_id: int) -> void:
	random_manager = random_choice
	selected_manager_id = manager_id
	for player: Statics.PlayerData in players:
		player.role = _lobby_role(player.id)
		player_updated.emit(player.id)
	role_settings_updated.emit()


func refresh_role_settings() -> void:
	if not multiplayer.is_server():
		return
	if not random_manager and get_player(selected_manager_id) == null:
		random_manager = true
		selected_manager_id = 0
	sync_role_settings.rpc(random_manager, selected_manager_id)


func choose_manager() -> int:
	if not multiplayer.is_server() or players.is_empty():
		return 0
	if not random_manager:
		return selected_manager_id if get_player(selected_manager_id) != null else 0
	var candidates: Array[int] = []
	for player: Statics.PlayerData in players:
		if player.id > 0:
			candidates.append(player.id)
	return candidates.pick_random() if not candidates.is_empty() else 0


func apply_match_roles(manager_id: int) -> bool:
	if get_player(manager_id) == null or manager_id <= 0:
		return false
	for player: Statics.PlayerData in players:
		player.role = Statics.Role.MANAGER if player.id == manager_id else Statics.Role.EMPLOYEE
	return true


@rpc("any_peer", "reliable", "call_local")
func set_player_vote(id: int, vote: bool) -> void:
	var player: Statics.PlayerData = get_player(id)
	if not player:
		return
	player.vote = vote
	player_updated.emit(id)
	vote_updated.emit(id)


func set_current_player_vote(vote: bool) -> void:
	set_player_vote.rpc(multiplayer.get_unique_id(), vote)


func reset_votes() -> void:
	for player: Statics.PlayerData in players:
		set_player_vote.rpc(player.id, false)


func is_online() -> bool:
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer and \
		multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func update_player_id() -> void:
	if not OS.is_debug_build():
		return
	if Debug.is_online():
		player_id.show()
		player_id.text = str(multiplayer.get_unique_id())
	else:
		player_id.hide()


func reset_window_scale() -> void:
	get_window().content_scale_mode = _initial_window_scale_mode
	get_window().content_scale_aspect = _initial_window_scale_aspect


func _handle_size_changed() -> void:
	if not change_window_scale:
		return
	
	var was_windows_small: bool = _is_window_small
	#get_window().min_size = Vector2i(1280, 720)
	_is_window_small =  get_window().size.x < 1280 or get_window().size.y < 720

	if was_windows_small == _is_window_small:
		return
	
	_update_window_scale()


func _update_window_scale() -> void:
	if _is_window_small:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	else:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP


func _handle_node_added(node: Node) -> void:
	if node.get_parent() == get_window():
		# Scene has been changed
		change_window_scale = node is MainMenu or node is LobbyHostScreen or \
			node is LobbyJoinScreen or node is LobbyWaitingScreen or node is Credits
