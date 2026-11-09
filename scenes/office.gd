extends Node3D

@export var player_scene: PackedScene
@onready var spawn_points: Node3D = $SpawnPoints
@onready var players: Node3D = $Players
@onready var shovel: Node3D = $ShovelPalette
@onready var shovel_respawn_points: Node3D = $ShovelRespawnPoints
@onready var shovel_timer: Timer = $ShovelRespawnPoints/Timer

var _shovel_points: Array[Marker3D] = []
var _current_shovel_point: int = 0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for i: int in Game.instance.players.size():
		var player_data: Statics.PlayerData = Game.instance.players[i]
		var player_inst = player_scene.instantiate()
		player_inst.name = str(player_data.id)
		players.add_child(player_inst)
		player_inst.setup(player_data)
		player_inst.global_position = spawn_points.get_child(i).global_position
	_setup_shovel_respawn()


func _setup_shovel_respawn() -> void:
	for child: Node in shovel_respawn_points.get_children():
		if child is Marker3D:
			_shovel_points.append(child as Marker3D)
	if _shovel_points.is_empty():
		push_warning("ShovelRespawnPoints no tiene Marker3D hijos")
		return
	# La pala parte en el primer punto (Point1).
	_move_shovel_to(0)
	shovel_timer.timeout.connect(_on_shovel_timer_timeout)
	# Solo el servidor decide cuándo y adónde se mueve la pala.
	if multiplayer.is_server():
		if shovel_timer.is_stopped():
			shovel_timer.start()
	else:
		shovel_timer.stop()


func _on_shovel_timer_timeout() -> void:
	if not multiplayer.is_server() or _shovel_points.size() < 2:
		return
	# Siguiente punto en orden: Point1 -> Point2 -> ... -> Point1 (siempre distinto al actual).
	var next_index: int = (_current_shovel_point + 1) % _shovel_points.size()
	_move_shovel_to.rpc(next_index)


@rpc("authority", "call_local", "reliable")
func _move_shovel_to(index: int) -> void:
	if index < 0 or index >= _shovel_points.size():
		return
	_current_shovel_point = index
	shovel.global_position = _shovel_points[index].global_position


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
