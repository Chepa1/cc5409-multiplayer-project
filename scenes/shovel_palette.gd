extends Node3D

@export_range(0.1, 60.0) var time_to_complete: float = 3.0
@export_file("*.tscn") var victory_scene_path: String = "res://VictoryScene.tscn"

@onready var interaction_area: InteractionArea = $InteractionArea
@onready var progress_bar: ProgressBar = $ProgressViewport/ProgressBar
@onready var progress_display: Sprite3D = $ProgressDisplay

var current_progress: float = 0.0
var completed: bool = false

func _ready() -> void:
	interaction_area.local_player_entered.connect(_on_local_player_entered)
	interaction_area.local_player_exited.connect(_on_local_player_exited)
	_reset_progress()
	progress_display.hide()

func _process(delta: float) -> void:
	if completed or not interaction_area.has_local_player():
		return
	if Input.is_action_pressed("interact"):
		current_progress = minf(time_to_complete, current_progress + delta)
	else:
		current_progress = maxf(0.0, current_progress - delta * 2.0)
	progress_bar.value = current_progress / time_to_complete * 100.0
	if current_progress >= time_to_complete:
		completed = true
		trigger_victory.rpc()

func _on_local_player_entered(_player: Player) -> void:
	progress_display.show()

func _on_local_player_exited(_player: Player) -> void:
	if not interaction_area.has_local_player():
		_reset_progress()
		progress_display.hide()

func _reset_progress() -> void:
	current_progress = 0.0
	progress_bar.value = 0.0

@rpc("any_peer", "call_local", "reliable")
func trigger_victory() -> void:
	completed = true
	get_tree().call_deferred("change_scene_to_file", victory_scene_path)
