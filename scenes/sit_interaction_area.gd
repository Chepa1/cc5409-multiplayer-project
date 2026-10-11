extends "res://scenes/interaction_area.gd"

@onready var sit_point: Marker3D = get_parent() as Marker3D

func _ready() -> void:
	super._ready()
	local_player_entered.connect(_on_local_player_entered)
	local_player_exited.connect(_on_local_player_exited)

func _on_local_player_entered(player: Player) -> void:
	player.add_sit_point(sit_point)
	if not player.sit_state_changed.is_connected(_update_label):
		player.sit_state_changed.connect(_update_label)
	_update_label()

func _on_local_player_exited(player: Player) -> void:
	player.remove_sit_point(sit_point)
	if player.sit_state_changed.is_connected(_update_label):
		player.sit_state_changed.disconnect(_update_label)
	_update_label()

func _update_label() -> void:
	if not label:
		return
	label.hide()
	for player: Player in players:
		if is_instance_valid(player) and player.is_multiplayer_authority() and not player.sentado:
			label.show()
			return
