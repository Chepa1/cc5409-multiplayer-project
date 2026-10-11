class_name InteractionArea
extends Area3D

signal local_player_entered(player: Player)
signal local_player_exited(player: Player)

@export var label: Label3D

var players: Array[Player] = []

func _ready() -> void:
	if label:
		label.hide()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func has_local_player() -> bool:
	for player: Player in players:
		if is_instance_valid(player) and player.is_multiplayer_authority():
			return true
	return false

func _on_body_entered(body: Node3D) -> void:
	var player: Player = body as Player
	if player == null or players.has(player):
		return
	players.append(player)
	if player.is_multiplayer_authority():
		if label:
			label.show()
		local_player_entered.emit(player)

func _on_body_exited(body: Node3D) -> void:
	var player: Player = body as Player
	if player == null:
		return
	players.erase(player)
	if player.is_multiplayer_authority():
		if label:
			label.visible = has_local_player()
		local_player_exited.emit(player)
