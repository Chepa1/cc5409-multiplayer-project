extends Area3D


@export var label: Label3D

var players: Array[Player]

func _ready() -> void:
	if label:
		label.hide()
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	var player: Player = body as Player
	if player:
		players.push_back(player)
		
		if player.get_multiplayer_authority() == multiplayer.get_unique_id():
			label.show()
	
func _on_body_exited(body: Node3D) -> void:
	var player: Player = body as Player
	if player:
		players.erase(player)
		
		if player.get_multiplayer_authority() == multiplayer.get_unique_id():
			label.hide()
