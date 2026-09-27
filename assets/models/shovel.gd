extends Node3D

@export var time_to_complete: float = 3.0 # Segundos necesarios manteniendo 'E'
@export_file("*.tscn") var victory_scene_path: String = "res://VictoryScene.tscn"

@onready var area_3d: Area3D = $Area3D
# Si usaste SubViewport + Sprite3D:
@export var progress_bar: ProgressBar

var current_progress: float = 0.0
var is_player_inside: bool = false
var local_player: Node3D = null

func _ready() -> void:
	area_3d.body_entered.connect(_on_body_entered)
	area_3d.body_exited.connect(_on_body_exited)
	progress_bar.value = 0

func _on_body_entered(body: Node3D) -> void:
	# Verificamos si el cuerpo es el jugador controlado localmente
	print("ALGO entró al área: ", body.name)
	if body.has_method("setup"): # O revisa si pertenece al grupo "players"
		if body.is_multiplayer_authority():
			print("1. Es un Jugador (tiene el método setup)")
			is_player_inside = true
			local_player = body
	else:
		print("2. Es el jugador de otra persona (no eres la autoridad).")
func _on_body_exited(body: Node3D) -> void:
	if body == local_player:
		is_player_inside = false
		local_player = null
		current_progress = 0.0
		progress_bar.value = 0

func _process(delta: float) -> void:
	if is_player_inside:
		# Mantiene presionada la tecla 'E'
		if Input.is_action_pressed("interact"):
			print("Cargando barra: ", current_progress)
			current_progress += delta
			progress_bar.value = (current_progress / time_to_complete) * 100.0
			
			if current_progress >= time_to_complete:
				# Desactivamos para evitar llamadas duplicadas
				is_player_inside = false 
				# Notifica a TODOS los jugadores vía red
				trigger_victory.rpc()
		else:
			# Si suelta la tecla 'E', la barra se reduce gradualmente
			current_progress = max(0.0, current_progress - delta * 2.0)
			progress_bar.value = (current_progress / time_to_complete) * 100.0

# @rpc con call_local asegura que la función se ejecute en todos los pares (clientes y servidor)
@rpc("any_peer", "call_local", "reliable")
func trigger_victory() -> void:
	get_tree().change_scene_to_file(victory_scene_path)
