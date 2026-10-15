class_name LobbyWaitingScreen
extends Control

@onready var player_texture: TextureRect = %PlayerTexture
@onready var player_name: Label = %PlayerName
@onready var role_button: Button = %RoleButton
@onready var ready_button: Button = %ReadyButton
@onready var player_list: VBoxContainer = %PlayerList
@onready var waiting_label: Label = %WaitingLabel
@onready var back_button: Button = %BackButton
@onready var role_container: PanelContainer = %RoleContainer
@onready var role_list: VBoxContainer = %RoleList
@onready var start_timer: Timer = $StartTimer
@onready var game_start_container: PanelContainer = %GameStartContainer
@onready var game_start_counter: Label = %GameStartCounter



var random_manager_checkbox: CheckBox
var manager_instruction: Label

var LOBBY_PLAYER_SCENE: PackedScene = preload("res://lobby/lobby_player.tscn")


func _ready() -> void:
	player_name.text = Game.instance.get_current_player().name
	ready_button.pressed.connect(_toggle_ready)
	Game.instance.players_updated.connect(_handle_players_updated)
	Game.instance.player_updated.connect(func(_id: int) -> void: _update_role_display())
	Game.instance.vote_updated.connect(func(_id: int) -> void: _handle_vote_updated())
	if multiplayer.is_server():
		start_timer.timeout.connect(_finish_countdown)
	_create_role_controls()
	Game.instance.role_settings_updated.connect(_update_role_display)
	_handle_players_updated()
	role_button.visible = Game.instance.use_roles
	back_button.pressed.connect(_handle_back_pressed)
	role_button.pressed.connect(_handle_role_pressed)
	role_container.hide()
	game_start_container.hide()
	
	_update_ready_button()
	
	_update_role_display()


func _process(_delta: float) -> void:
	game_start_counter.text = str(int(ceil(start_timer.time_left)))


func _toggle_ready() -> void:
	Game.instance.set_current_player_vote(not Game.instance.get_current_player().vote)
	_update_player()


func _update_player() -> void:
	var player_ready: bool = Game.instance.get_current_player().vote
	player_texture.modulate = Color.GREEN if player_ready else Color.WHITE
	role_container.hide()


func _handle_players_updated() -> void:
	for child: Node in player_list.get_children():
		child.queue_free()
	waiting_label.visible = Game.instance.players.size() == 1
	for player: Statics.PlayerData in Game.instance.players:
		if player.id != multiplayer.get_unique_id():
			var lobby_player_inst: LobbyPlayer = LOBBY_PLAYER_SCENE.instantiate()
			lobby_player_inst.set_player(player)
			player_list.add_child(lobby_player_inst)
	_update_ready_button()
	if multiplayer.is_server():
		Game.instance.reset_votes()
		Game.instance.refresh_role_settings()
	_fill_role_container()
	_update_role_display()


func _handle_back_pressed() -> void:
	if multiplayer.is_server():
		Lobby.instance.go_to_host()
	else:
		Lobby.instance.go_to_join()


func _handle_role_pressed() -> void:
	role_container.visible = not role_container.visible


func _create_role_controls() -> void:
	random_manager_checkbox = CheckBox.new()
	random_manager_checkbox.text = "Jefatura al azar"
	# Keep the outline visible in both states against the lobby background.
	for icon_name: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		var icon: Texture2D = load("res://lobby/icons/checkbox_%s.svg" % icon_name)
		random_manager_checkbox.add_theme_icon_override(icon_name, icon)
	random_manager_checkbox.tooltip_text = "El host sortea una única jefatura al comenzar la partida."
	random_manager_checkbox.visible = Game.instance.use_roles
	role_button.get_parent().add_child(random_manager_checkbox)
	role_button.get_parent().move_child(random_manager_checkbox, role_button.get_index())
	random_manager_checkbox.toggled.connect(_on_random_manager_toggled)
	manager_instruction = Label.new()
	manager_instruction.text = "Selecciona quién será\nla jefatura"
	manager_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	manager_instruction.add_theme_font_size_override("font_size", 18)
	manager_instruction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_button.get_parent().add_child(manager_instruction)
	role_button.get_parent().move_child(manager_instruction, role_button.get_index())


func _on_random_manager_toggled(enabled: bool) -> void:
	# Initially select the host when switching to manual selection.
	Game.instance.configure_roles(enabled, multiplayer.get_unique_id())


func _fill_role_container() -> void:
	for child: Node in role_list.get_children():
		role_list.remove_child(child)
		child.queue_free()
	if not multiplayer.is_server():
		return
	for player: Statics.PlayerData in Game.instance.players:
		var button: Button = Button.new()
		button.text = player.name
		button.pressed.connect(_select_manager.bind(player.id))
		role_list.add_child(button)


func _select_manager(id: int) -> void:
	Game.instance.configure_roles(false, id)
	role_container.hide()


func _update_role_display() -> void:
	if random_manager_checkbox == null:
		return
	var game: Game = Game.instance
	manager_instruction.visible = game.use_roles and multiplayer.is_server() and not game.random_manager
	random_manager_checkbox.set_pressed_no_signal(game.random_manager)
	random_manager_checkbox.disabled = not multiplayer.is_server() or not start_timer.is_stopped()
	role_button.disabled = not multiplayer.is_server() or game.random_manager or not start_timer.is_stopped()
	if game.random_manager:
		role_button.text = "Sin asignar"
	elif multiplayer.is_server():
		role_button.tooltip_text = "Haz clic para elegir quién será la jefatura."
		var manager: Statics.PlayerData = game.get_player(game.selected_manager_id)
		role_button.text = "Jefatura: " + manager.name + " ▾" if manager != null else "Elegir jefatura ▾"
	else:
		role_button.text = Statics.get_role_name(game.get_current_player().role)
	if role_button.disabled:
		role_container.hide()
	_update_ready_button()


func _handle_vote_updated() -> void:
	_update_player()
	if multiplayer and multiplayer.is_server():
		var all_voted: bool = true
		for player: Statics.PlayerData in Game.instance.players:
			all_voted = all_voted and player.vote
		if all_voted and _can_start_game():
			if start_timer.is_stopped():
				_start_timer.rpc()
		elif not start_timer.is_stopped():
			_stop_timer.rpc()

@rpc("reliable", "call_local")
func _start_timer() -> void:
	start_timer.start()
	game_start_container.show()
	_update_role_display()


@rpc("reliable", "call_local")
func _stop_timer() -> void:
	start_timer.stop()
	game_start_container.hide()
	_update_role_display()
	


func _finish_countdown() -> void:
	if not multiplayer.is_server() or not _can_start_game():
		_stop_timer.rpc()
		return
	for player: Statics.PlayerData in Game.instance.players:
		if not player.vote:
			_stop_timer.rpc()
			return
	var manager_id: int = Game.instance.choose_manager() if Game.instance.use_roles else 0
	_start_game.rpc(manager_id)


@rpc("authority", "reliable", "call_local")
func _start_game(manager_id: int) -> void:
	# Every peer applies the same host decision before loading the match.
	if Game.instance.use_roles and not Game.instance.apply_match_roles(manager_id):
		return
	start_timer.stop()
	for player: Statics.PlayerData in Game.instance.players:
		player.vote = false
	get_tree().change_scene_to_packed(Game.instance.main_scene)


func _can_start_game() -> bool:
	if Game.instance.players.size() < Game.instance.min_players:
		return false
	if not Game.instance.use_roles:
		return true
	return Game.instance.random_manager or Game.instance.get_player(Game.instance.selected_manager_id) != null


func _update_ready_button() -> void:
	ready_button.disabled = not _can_start_game()
