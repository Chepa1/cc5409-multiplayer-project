extends Node3D
class_name ManagerGun

@export var alcance: float = 30.0
@onready var gun_ray_cast: RayCast3D = $GunRayCast

var propietario: Player = null


func configurar(jugador: Player) -> void:
	propietario = jugador
	gun_ray_cast.target_position = Vector3(0.0, 0.0, -alcance)
	gun_ray_cast.add_exception(jugador)


func disparar() -> void:
	print("Entró a disparar()")

	if propietario == null:
		print("ERROR: No tiene propietario")
		return

	if not propietario.is_multiplayer_authority():
		print("ERROR: No tiene autoridad")
		return

	if propietario.rol != Statics.Role.MANAGER:
		print("ERROR: El jugador no es Jefatura")
		return

	if propietario.capturado:
		print("ERROR: El jugador está capturado")
		return

	var origen: Vector3 = gun_ray_cast.global_position
	var direccion: Vector3 = -gun_ray_cast.global_basis.z

	print("DISPARO REALIZADO")
	propietario.pedir_disparo(origen, direccion)
