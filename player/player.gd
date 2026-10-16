extends CharacterBody3D
class_name Player

signal player_marked

const MANAGER_GUN_SCENE: PackedScene = preload(
	"res://scenes/gun.tscn"
)

var rol: Statics.Role = Statics.Role.NONE
var pistola: Node3D = null
var pistola_externa: Node3D = null
var nombre_rol: String = ""
var nombre_personaje: String = ""
var marcado: bool = false
@export var duracion_marca: float = 15.0
var tiempo_marca_local: float = 0.0
var temporizador_marca: Timer
var ultimo_disparo_ms: int = -100000
var ultimo_efecto_ms: int = -100000

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
	role_hud.hide()
	temporizador_marca = Timer.new()
	temporizador_marca.one_shot = true
	add_child(temporizador_marca)
	temporizador_marca.timeout.connect(_marca_vencida_servidor)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mesh_scale_original = mesh.scale
	mesh_position_original = mesh.position
	collision_scale_original = collision.scale
	collision_position_original = collision.position
	head_position_original = head.position
	label_position_original = label_3d.position
	configurar_boton_disparo()


func configurar_boton_disparo() -> void:
	# Permite disparar con clic izquierdo incluso si shoot aún no existe.
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
	for entrada: InputEvent in InputMap.action_get_events("shoot"):
		if entrada is InputEventMouseButton:
			var boton: InputEventMouseButton = entrada as InputEventMouseButton
			if boton.button_index == MOUSE_BUTTON_LEFT:
				return
	var clic: InputEventMouseButton = InputEventMouseButton.new()
	clic.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("shoot", clic)


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event.is_action_pressed("test"):
		test.rpc()

	if event.is_action_pressed("sit"):
		if sentado:
			intentar_levantarse()
		else:
			buscar_silla()

	if event.is_action_pressed("shoot"):
		# El primer clic captura el mouse; los siguientes disparan.
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if rol == Statics.Role.MANAGER and pistola != null:
			disparar_manager()


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
	rol = player_data.role
	nombre_rol = Statics.get_role_name(rol)
	nombre_personaje = nombre_rol
	label_3d.text = nombre_rol
	set_multiplayer_authority(player_data.id, true)
	camera_3d.current = is_multiplayer_authority()
	role_label.text = ""
	match player_data.role:
		Statics.Role.EMPLOYEE:
			role_label.text = "Eres un empleado!"
		Statics.Role.MANAGER:
			role_label.text = "Eres la jefatura!"
	role_notice_timer.stop()
	role_hud.visible = is_multiplayer_authority() and Game.instance.use_roles and not role_label.text.is_empty()
	if role_hud.visible:
		role_notice_timer.start()
	if rol == Statics.Role.MANAGER:
		configurar_pistola()
	if is_multiplayer_authority():
		sync_timer.start()

@rpc("authority", "call_local", "unreliable_ordered")
func test() -> void:
	Debug.log("meh")

func _physics_process(delta: float) -> void:
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
	var direction: Vector3 = Vector3(move_input.x, 0, move_input.y).rotated(
		Vector3.UP, input_synchronizer.head_rotation
	).normalized()
	var target: Vector2 = Vector2(direction.x, direction.z) * move_speed
	var current: Vector2 = Vector2(velocity.x, velocity.z)
	var result: Vector2 = current.move_toward(target, acceleration * delta)
	velocity.x = result.x
	velocity.z = result.y
	move_and_slide()

func on_sync_timeout() -> void:
	_sync.rpc(global_position, velocity)

@rpc("authority", "call_remote", "reliable")
func _sync(pos: Vector3, vel: Vector3) -> void:
	global_position = global_position.lerp(pos, 0.5)
	velocity = velocity.lerp(vel, 0.5)

func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		head.rotation.y = input_synchronizer.head_rotation
	if is_multiplayer_authority() and rol == Statics.Role.EMPLOYEE and marcado:
		tiempo_marca_local = maxf(0.0, tiempo_marca_local - delta)
		role_label.text = "¡MARCADO! %d s" % ceili(tiempo_marca_local)

func configurar_pistola() -> void:
	if rol != Statics.Role.MANAGER:
		return
	var instancia: Node = MANAGER_GUN_SCENE.instantiate()
	if not instancia is Node3D:
		push_error("gun.tscn necesita un nodo raíz Node3D")
		instancia.free()
		return
	if is_multiplayer_authority():
		pistola = instancia as Node3D
		camera_3d.add_child(pistola)
		pistola.position = Vector3(0.35, -0.25, -0.6)
	else:
		pistola_externa = instancia as Node3D
		head.add_child(pistola_externa)
		pistola_externa.position = Vector3(0.38, -0.30, -0.48)


func disparar_manager() -> void:
	if not is_multiplayer_authority():
		return
	if rol != Statics.Role.MANAGER or pistola == null:
		return
	var ahora: int = Time.get_ticks_msec()
	if ahora - ultimo_efecto_ms < int(tiempo_entre_disparos * 1000.0):
		return
	ultimo_efecto_ms = ahora

	var origen: Vector3 = camera_3d.global_position
	var direccion: Vector3 = -camera_3d.global_basis.z
	var destino: Vector3 = origen + direccion * alcance_pistola

	# Trayectoria visual local, con la primera colisión del escenario.
	var parametros: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origen, destino, 0xFFFFFFFF, [get_rid()]
	)
	var choque: Dictionary = get_world_3d().direct_space_state.intersect_ray(parametros)
	if not choque.is_empty():
		destino = choque["position"]

	# La autoridad distribuye la bala visual a todos los peers.
	mostrar_proyectil.rpc(origen, destino)
	# El servidor resuelve el impacto de forma independiente.
	pedir_disparo(origen, direccion)


@rpc("authority", "call_local", "reliable")
func mostrar_proyectil(origen: Vector3, destino: Vector3) -> void:
	if not origen.is_finite() or not destino.is_finite():
		return

	var mundo: Node = get_tree().current_scene
	if mundo == null:
		return
	var bala: MeshInstance3D = MeshInstance3D.new()
	var esfera: SphereMesh = SphereMesh.new()
	esfera.radius = 0.085
	esfera.height = 0.17
	bala.mesh = esfera

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.7, 0.1)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.6, 0.0)
	material.emission_energy_multiplier = 3.0
	bala.material_override = material

	mundo.add_child(bala)
	bala.global_position = origen
	var distancia: float = origen.distance_to(destino)
	var duracion: float = maxf(distancia / 35.0, 0.01)
	var animacion: Tween = bala.create_tween()
	animacion.tween_property(bala, "global_position", destino, duracion)
	animacion.tween_callback(bala.queue_free)


func pedir_disparo(origen: Vector3, direccion: Vector3) -> void:
	if not is_multiplayer_authority():
		return

	if rol != Statics.Role.MANAGER:
		return

	if multiplayer.is_server():
		validar_disparo(origen, direccion)
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

	if rol != Statics.Role.MANAGER:
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

	if impacto.is_empty():
		print("Disparo sin impacto")
		return

	var objetivo: Object = impacto["collider"]

	var empleado: Player = obtener_empleado_impactado(objetivo)
	if empleado == null or empleado.rol != Statics.Role.EMPLOYEE:
		return

	# Cada impacto renueva la marca durante 15 segundos.
	empleado.activar_marca_servidor()


# Permite encontrar el Player aunque el collider sea un nodo hijo.
func obtener_empleado_impactado(objeto: Object) -> Player:
	var nodo: Node = objeto as Node
	while nodo != null:
		if nodo is Player:
			return nodo as Player
		nodo = nodo.get_parent()
	return null


# El servidor es el único que decide cuándo empieza y termina la marca.
func activar_marca_servidor() -> void:
	if not multiplayer.is_server() or rol != Statics.Role.EMPLOYEE:
		return
	# Se reinicia la duración si Jefatura vuelve a acertar.
	temporizador_marca.start(duracion_marca)
	aplicar_marca_local(duracion_marca)
	recibir_marca.rpc(duracion_marca)


func aplicar_marca_local(segundos: float) -> void:
	if rol != Statics.Role.EMPLOYEE:
		return
	var primera_vez: bool = not marcado
	marcado = true
	tiempo_marca_local = segundos
	label_3d.text = nombre_rol + "\nMARCADO"
	label_3d.modulate = Color(1.0, 0.15, 0.15)
	if primera_vez:
		var resaltado: StandardMaterial3D = StandardMaterial3D.new()
		resaltado.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		resaltado.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		resaltado.albedo_color = Color(1.0, 0.05, 0.05, 0.55)
		mesh.material_overlay = resaltado
		player_marked.emit()
	if is_multiplayer_authority():
		role_notice_timer.stop()
		role_hud.show()
		role_label.text = "¡MARCADO! %d s" % ceili(segundos)
	print("MARCA | peer=", multiplayer.get_unique_id(), " jugador=", name)


@rpc("any_peer", "call_remote", "reliable")
func recibir_marca(segundos: float) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	aplicar_marca_local(segundos)


func _marca_vencida_servidor() -> void:
	if not multiplayer.is_server():
		return
	quitar_marca_local()
	recibir_fin_marca.rpc()


@rpc("any_peer", "call_remote", "reliable")
func recibir_fin_marca() -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	quitar_marca_local()


func quitar_marca_local() -> void:
	if not marcado:
		return
	marcado = false
	tiempo_marca_local = 0.0
	label_3d.text = nombre_rol
	label_3d.modulate = Color.WHITE
	mesh.material_overlay = null
	if is_multiplayer_authority():
		role_hud.hide()
	print("MARCA TERMINADA | peer=", multiplayer.get_unique_id(), " jugador=", name)
