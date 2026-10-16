extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _run() -> void:
	var game: Game = Game.instance
	game.players.clear()
	for id: int in [1, 2, 3]:
		game.add_player(Statics.PlayerData.new(id, "Player %d" % id, id - 1))
	check(game.random_manager, "Random selection is enabled by default")
	game.sync_role_settings(false, 2)
	check(game.get_player(2).role == Statics.Role.MANAGER, "Manual selection assigns the chosen manager")
	check(game.get_player(1).role == Statics.Role.EMPLOYEE, "Host can be an employee")
	check(game.get_player(3).role == Statics.Role.EMPLOYEE, "Multiple employees are allowed")
	game.add_player(Statics.PlayerData.new(4, "Late player", 3, Statics.Role.MANAGER))
	check(game.get_player(4).role == Statics.Role.EMPLOYEE, "Joining players cannot claim manager")
	check(game.choose_manager() == 2, "Manual selection survives new arrivals")
	check(not game.apply_match_roles(999), "Missing manager is rejected")
	game.sync_role_settings(true, 0)
	var selected: Dictionary = {}
	for iteration: int in 200:
		var manager_id: int = game.choose_manager()
		selected[manager_id] = true
		check(game.apply_match_roles(manager_id), "Random choice is a connected player")
		var managers: int = 0
		for player: Statics.PlayerData in game.players:
			if player.role == Statics.Role.MANAGER:
				managers += 1
			else:
				check(player.role == Statics.Role.EMPLOYEE, "Other players are employees")
		check(managers == 1, "Exactly one manager per match")
	check(selected.size() > 1, "Random choice is not fixed")
	game.sync_role_settings(false, 2)
	game.remove_player(2)
	game.refresh_role_settings()
	check(game.random_manager, "Missing manual manager restores random selection")
	var waiting: LobbyWaitingScreen = load("res://lobby/waiting_screen.tscn").instantiate()
	get_tree().root.add_child(waiting)
	get_tree().current_scene = waiting
	check(waiting.random_manager_checkbox.button_pressed, "Lobby checkbox defaults to random")
	check(waiting._can_start_game(), "Random mode allows ready without choosing roles")
	game.configure_roles(false, 3)
	check(game.selected_manager_id == 3, "Host selects a manager through lobby settings")
	check(not waiting.role_button.disabled, "Host can open manual selection")
	for player: Statics.PlayerData in game.players:
		game.set_player_vote(player.id, true)
	check(not waiting.start_timer.is_stopped(), "Ready players start the countdown")
	game.configure_roles(true)
	check(waiting.start_timer.is_stopped(), "Changing selection cancels the countdown")
	for player: Statics.PlayerData in game.players:
		check(not player.vote, "Changing selection resets ready votes")
	check(waiting.role_button.disabled, "Random mode disables manual selection")
	get_tree().current_scene = self
	get_tree().root.remove_child(waiting)
	waiting.free()
	game.players.clear()
	check(game.choose_manager() == 0, "Empty lobby has no manager")
	await _check_role_hud()
	print("Role tests: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _check_role_hud() -> void:
	var player_scene: PackedScene = load("res://player/player.tscn")
	var local_player: Player = player_scene.instantiate()
	var remote_player: Player = player_scene.instantiate()
	add_child(local_player)
	add_child(remote_player)
	check(not local_player.role_hud.visible, "HUD stays hidden until player setup")
	var local_data: Statics.PlayerData = Statics.PlayerData.new(multiplayer.get_unique_id(), "Local", 0, Statics.Role.EMPLOYEE)
	local_player.setup(local_data)
	check(local_player.role_hud.visible, "Local player sees their HUD")
	check(local_player.role_label.text == "Eres un empleado!", "Employee message is shown")
	local_data.role = Statics.Role.MANAGER
	local_player.setup(local_data)
	check(local_player.role_label.text == "Eres la jefatura!", "Manager message is shown")
	remote_player.setup(Statics.PlayerData.new(99, "Remote", 1, Statics.Role.MANAGER))
	check(not remote_player.role_hud.visible, "Remote players never show a HUD")
	Game.instance.use_roles = false
	local_player.setup(local_data)
	check(not local_player.role_hud.visible, "Disabled roles hide the HUD")
	Game.instance.use_roles = true
	local_data.role = Statics.Role.NONE
	local_player.setup(local_data)
	check(not local_player.role_hud.visible, "Unassigned players do not show a misleading role")
	local_data.role = Statics.Role.EMPLOYEE
	local_player.setup(local_data)
	check(local_player.role_notice_timer.wait_time == 12.0, "Role notice lasts 12 seconds")
	# Exercise the real timeout quickly, without running movement or network sync.
	local_player.set_physics_process(false)
	remote_player.set_physics_process(false)
	local_player.sync_timer.stop()
	local_player.role_notice_timer.start(0.05)
	await get_tree().create_timer(0.15).timeout
	check(not local_player.role_hud.visible, "Role notice hides automatically after timeout")
	check(local_player.role_notice_timer.is_stopped(), "Role notice does not repeat")
	local_player.free()
	remote_player.free()
