extends CharacterBody3D
class_name Player

signal player_captured

const MANAGER_GUN_SCENE: PackedScene = preload(
	"res://player/manager_gun.tscn"
)

var rol: Statics.Role = Statics.Role.NONE
var pistola: ManagerGun = null
var capturado: bool = false
var ultimo_disparo_ms: int = -100000

@export var alcance_pistola: float = 30.0
@export var tiempo_entre_disparos: float = 0.5

signal sit_state_changed

@export var move_speed: float = 5
@export var jump_speed: float = 7
@export var acceleration: float = 20
@export var mouse_sensitivity: float = 0.005
@export var sit_height_scale: float = 0.55
@export var sit_visual_offset: float = 0.45
@export var sit_head_offset: float = 0.45
@export var stand_offset: float = 1.2
@onready var role_notice_timer: Timer = $RoleNoticeTimer
@onready var role_hud: CanvasLayer = $RoleHUD
@onready var role_label: Label = $RoleHUD/RoleLabel
@onready var head: Node3D = $Head
@onready var camera_3d: Camera3D = $Head/Camera3D
@onready var label_3d: Label3D = $Label3D
@onready var input_synchronizer: InputSynchronizer = $InputSynchronizer
@onready var sync_timer: Timer = $SyncTimer
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var sentado: bool = false
var available_sit_points: Array[Marker3D] = []
var silla_actual: Marker3D = null
var posicion_salida_silla: Vector3 = Vector3.ZERO
var posicion_antes_sentarse: Vector3 = Vector3.ZERO
var posicion_silla_actual: Vector3 = Vector3.ZERO
var rotacion_silla_actual: float = 0.0
var mesh_scale_original: Vector3
var mesh_position_original: Vector3
var collision_scale_original: Vector3
var collision_position_original: Vector3
var head_position_original: Vector3
var label_position_original: Vector3

func _ready() -> void:
	sync_timer.timeout.connect(on_sync_timeout)
	role_notice_timer.timeout.connect(role_hud.hide)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mesh_scale_original = mesh.scale
	mesh_position_original = mesh.position
	collision_scale_original = collision.scale
	collision_position_original = collision.position
	head_position_original = head.position
	label_position_original = label_3d.position


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if capturado:
		return

	if event.is_action_pressed("test"):
		test.rpc()

	if event.is_action_pressed("sit"):
		if sentado:
			intentar_levantarse()
		else:
			buscar_silla()

	if event.is_action_pressed("shoot"):
		print("CLICK DE DISPARO DETECTADO")
		print("Rol: ", Statics.get_role_name(rol))
		print("Pistola existe: ", pistola != null)
		print("Mouse capturado: ",
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)

		if rol == Statics.Role.MANAGER and pistola != null:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				pistola.disparar()


func add_sit_point(point: Marker3D) -> void:
	if not available_sit_points.has(point):
		available_sit_points.append(point)

func remove_sit_point(point: Marker3D) -> void:
	available_sit_points.erase(point)

func silla_cercana() -> Marker3D:
	var silla_mas_cercana: Marker3D = null
	var menor_distancia: float = INF
	for punto: Marker3D in available_sit_points:
		if is_instance_valid(punto):
			var distancia: float = global_position.distance_to(punto.global_position)
			if distancia < menor_distancia:
				menor_distancia = distancia
				silla_mas_cercana = punto
	return silla_mas_cercana

func buscar_silla() -> void:
	var silla: Marker3D = silla_cercana()
	if silla != null:
		sentarse.rpc(silla.global_position, silla.global_rotation.y)

@rpc("authority", "call_local", "reliable")
func sentarse(posicion_silla: Vector3, rotacion_silla: float) -> void:
	posicion_antes_sentarse = global_position
	posicion_silla_actual = posicion_silla
	rotacion_silla_actual = rotacion_silla
	sentado = true
	sit_state_changed.emit()
	velocity = Vector3.ZERO
	global_position = posicion_silla
	# La salida queda detrás de la silla, aunque el jugador gire la cámara.
	posicion_salida_silla = posicion_silla + Vector3.BACK.rotated(
		Vector3.UP, rotacion_silla
	) * stand_offset
	head.rotation.y = rotacion_silla - global_rotation.y
	input_synchronizer.head_rotation = head.rotation.y
	mesh.scale = mesh_scale_original
	mesh.position = mesh_position_original
	collision.scale = collision_scale_original
	collision.position = collision_position_original
	head.position = head_position_original + Vector3(0, -0.4, 0)
	label_3d.position = label_position_original + Vector3(0, -0.4, 0)

func intentar_levantarse() -> void:
	if not sentado or not is_multiplayer_authority():
		return
	var destino: Variant = buscar_salida_segura()
	if destino != null:
		# Todos los pares reciben la misma posición elegida por el jugador local.
		levantarse.rpc(destino)

func buscar_salida_segura() -> Variant:
	# Primero detrás; si está bloqueado, probar diagonales y los lados.
	var angulos: Array[float] = [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, PI * 0.75, -PI * 0.75, PI]
	for distancia: float in [stand_offset, stand_offset + 0.3, stand_offset + 0.6]:
		for angulo: float in angulos:
			var candidato: Vector3 = posicion_silla_actual + Vector3.BACK.rotated(
				Vector3.UP, rotacion_silla_actual + angulo
			) * distancia
			var destino: Variant = validar_salida(candidato)
			if destino != null:
				return destino
	# La posición de aproximación suele ser útil en rincones estrechos.
	return validar_salida(posicion_antes_sentarse)

func validar_salida(candidato: Vector3) -> Variant:
	var espacio: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var suelo: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		candidato + Vector3.UP, candidato + Vector3.DOWN * 2.0, collision_mask, [get_rid()]
	)
	var impacto: Dictionary = espacio.intersect_ray(suelo)
	if impacto.is_empty():
		return null
	var punto_suelo: Vector3 = impacto.position
	var normal_suelo: Vector3 = impacto.normal
	# Evitar usar una mesa o el asiento como suelo de salida.
	if normal_suelo.y < 0.7 or punto_suelo.y > posicion_silla_actual.y - 0.25:
		return null
	var capsula: CapsuleShape3D = collision.shape as CapsuleShape3D
	if capsula == null:
		return null
	candidato.y = punto_suelo.y + capsula.height * 0.5 - collision.position.y + 0.02
	var trayecto: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		posicion_silla_actual, candidato, collision_mask, [get_rid()]
	)
	if not espacio.intersect_ray(trayecto).is_empty():
		return null
	var consulta: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	consulta.shape = capsula
	consulta.transform = collision.global_transform
	consulta.transform.origin = candidato + global_basis * collision.position
	consulta.collision_mask = collision_mask
	consulta.exclude = [get_rid()]
	consulta.margin = 0.01
	if not espacio.intersect_shape(consulta, 1).is_empty():
		return null
	return candidato

@rpc("authority", "call_local", "reliable")
func levantarse(posicion_segura: Vector3) -> void:
	if not sentado:
		return
	sentado = false
	sit_state_changed.emit()
	mesh.scale = mesh_scale_original
	mesh.position = mesh_position_original
	collision.scale = collision_scale_original
	collision.position = collision_position_original
	head.position = head_position_original
	label_3d.position = label_position_original
	velocity = Vector3.ZERO
	global_position = posicion_segura

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_event: InputEventMouseMotion = event as InputEventMouseMotion
		head.rotate_y(-mouse_event.relative.x * mouse_sensitivity)
		camera_3d.rotate_x(-mouse_event.relative.y * mouse_sensitivity)
		camera_3d.rotation.x = clamp(
			camera_3d.rotation.x,
			deg_to_rad(-80),
			deg_to_rad(80)
		)
		input_synchronizer.head_rotation = head.rotation.y

	if Input.is_action_just_pressed("escape"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventMouseButton and event.is_pressed():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return


func setup(player_data: Statics.PlayerData) -> void:
	label_3d.text = player_data.name
	rol = player_data.role

	set_multiplayer_authority(player_data.id, true)
	camera_3d.current = is_multiplayer_authority()

	print("Jugador: ", player_data.name)
	print("Rol: ", Statics.get_role_name(rol))
	print("Autoridad local: ", is_multiplayer_authority())

	if rol == Statics.Role.MANAGER:
		configurar_pistola()

	if is_multiplayer_authority():
		sync_timer.start()


@rpc("authority", "call_local", "unreliable_ordered")
func test() -> void:
	Debug.log("meh")

func _physics_process(delta: float) -> void:
	
	if capturado:
		velocity = Vector3.ZERO
		return
		
	if sentado:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	if input_synchronizer.jump:
		if is_on_floor():
			velocity.y = jump_speed

		input_synchronizer.jump = false

	var move_input: Vector2 = input_synchronizer.move_input

	var direction: Vector3 = Vector3(
		move_input.x,
		0,
		move_input.y
	).rotated(
		Vector3.UP,
		input_synchronizer.head_rotation
	)

	direction = direction.normalized()

	var target: Vector2 = Vector2(
		direction.x,
		direction.z
	) * move_speed

	var current: Vector2 = Vector2(
		velocity.x,
		velocity.z
	)

	var result: Vector2 = current.move_toward(
		target,
		acceleration * delta
	)
	
	velocity.x = result.x
	velocity.z = result.y
	move_and_slide()

func on_sync_timeout() -> void:
	if capturado:
		return
		
	_sync.rpc(
		global_position,
		velocity
	)

@rpc("authority", "call_remote", "reliable")
func _sync(pos: Vector3, vel: Vector3) -> void:
	if capturado:
		return
	global_position = global_position.lerp(
		pos,
		0.5
	)

	velocity = velocity.lerp(
		vel,
		0.5
	)

func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		head.rotation.y = input_synchronizer.head_rotation
		

func configurar_pistola() -> void:
	if rol != Statics.Role.MANAGER:
		return

	if not is_multiplayer_authority():
		return

	if pistola != null:
		return

	var instancia: Node = MANAGER_GUN_SCENE.instantiate()
	if not instancia is ManagerGun:
		push_error("manager_gun.tscn debe tener manager_gun.gd en su nodo raiz")
		instancia.free()
		return
	pistola = instancia as ManagerGun
	camera_3d.add_child(pistola)
	pistola.position = Vector3.ZERO
	pistola.configurar(self)


func pedir_disparo(origen: Vector3, direccion: Vector3) -> void:
	if not is_multiplayer_authority():
		return

	if rol != Statics.Role.MANAGER:
		return

	if multiplayer.is_server():
		validar_disparo(origen, direccion)
		print("Servidor recibió disparo de: ", name)
	else:
		solicitar_disparo.rpc_id(1, origen, direccion)


@rpc("any_peer", "call_remote", "reliable")
func solicitar_disparo(
	origen: Vector3,
	direccion: Vector3
) -> void:
	if not multiplayer.is_server():
		return

	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return

	validar_disparo(origen, direccion)


func validar_disparo(
	origen: Vector3,
	direccion: Vector3
) -> void:
	if not multiplayer.is_server():
		return

	if rol != Statics.Role.MANAGER or capturado:
		return

	var ahora: int = Time.get_ticks_msec()

	if ahora - ultimo_disparo_ms < int(tiempo_entre_disparos * 1000.0):
		return

	if not origen.is_finite() or not direccion.is_finite():
		return

	if direccion.length_squared() < 0.9:
		return

	if origen.distance_to(head.global_position) > 2.0:
		return

	ultimo_disparo_ms = ahora

	var consulta: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origen,
		origen + direccion.normalized() * alcance_pistola,
		0xFFFFFFFF,
		[get_rid()]
	)

	var impacto: Dictionary = get_world_3d().direct_space_state.intersect_ray(
		consulta
	)
	if not impacto.is_empty():
		print("Disparo impactó a: ", impacto["collider"])
		
	if impacto.is_empty():
		print("Disparo sin impacto")
		return

	var objetivo: Object = impacto["collider"]

	if objetivo is Player:
		var empleado: Player = objetivo as Player

		if empleado.rol == Statics.Role.EMPLOYEE:
			if not empleado.capturado:
				empleado.marcar_capturado.rpc()


@rpc("any_peer", "call_local", "reliable")
func marcar_capturado() -> void:
	# El servidor es quien autoriza las capturas.
	if multiplayer.is_server():
		if multiplayer.get_remote_sender_id() != 0:
			return
	else:
		if multiplayer.get_remote_sender_id() != 1:
			return

	if capturado:
		return

	capturado = true
	velocity = Vector3.ZERO

	player_captured.emit()

	print("Empleado capturado: ", name)
