
extends Node3D

@export var player_scene: PackedScene

@onready var spawn_points: Node3D = $SpawnPoints
@onready var players: Node3D = $Players


func _ready() -> void:
	# Comprobar que exista una escena de jugador.
	if player_scene == null:
		push_error("ERROR: No se ha asignado player_scene en Office.")
		return

	# Obtener los jugadores registrados en la partida.
	var cantidad_jugadores: int = Game.instance.players.size()

	# Comprobar que existan suficientes puntos de aparición.
	if spawn_points.get_child_count() < cantidad_jugadores:
		push_error("ERROR: No hay suficientes SpawnPoints.")
		return

	# Crear todos los jugadores de la partida.
	for i: int in range(cantidad_jugadores):

		var player_data: Statics.PlayerData = Game.instance.players[i]

		# Crear una instancia de player.tscn.
		var player_inst: Player = player_scene.instantiate() as Player

		if player_inst == null:
			push_error("ERROR: player_scene no es una escena Player.")
			return

		# Asignar el ID como nombre del nodo.
		# Esto ayuda a mantener rutas consistentes para los RPC.
		player_inst.name = str(player_data.id)

		# Añadir el jugador al escenario.
		players.add_child(player_inst)

		# Asignar nombre, rol y autoridad multijugador.
		# Si el rol es MANAGER, player.gd configura la pistola.
		player_inst.setup(player_data)

		# Obtener el punto de aparición correspondiente.
		var punto_aparicion: Node3D = (
			spawn_points.get_child(i) as Node3D
		)

		if punto_aparicion == null:
			push_error("ERROR: SpawnPoint inválido.")
			return

		# Posicionar al jugador.
		player_inst.global_position = punto_aparicion.global_position

		# Información para depuración.
		print("--------------------------------")
		print("Jugador creado: ", player_data.name)
		print("ID: ", player_data.id)
		print("Rol: ", Statics.get_role_name(player_data.role))
		print("Posición: ", player_inst.global_position)

		if player_data.role == Statics.Role.MANAGER:
			print("Este jugador es JEFATURA.")
		elif player_data.role == Statics.Role.EMPLOYEE:
			print("Este jugador es EMPLEADO.")
		else:
			print("Este jugador no tiene rol asignado.")

	print("--------------------------------")
	print("Todos los jugadores han sido creados.")
