extends CharacterBody3D

@export var move_speed: float = 5
@export var jump_speed: float = 7
@export var acceleration: float = 20
@export var mouse_sensitivity: float = 0.005
@export var sit_distance: float = 2.0
@export var sit_height_scale: float = 0.55
@export var sit_visual_offset: float = 0.45
@export var sit_head_offset: float = 0.45
@export var stand_offset: float = 0.8
@onready var head: Node3D = $Head
@onready var camera_3d: Camera3D = $Head/Camera3D
@onready var label_3d: Label3D = $Label3D
@onready var input_synchronizer: InputSynchronizer = $InputSynchronizer
@onready var sync_timer: Timer = $SyncTimer
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var sentado: bool = false
var silla_actual: Marker3D = null
var mesh_scale_original: Vector3
var mesh_position_original: Vector3
var collision_scale_original: Vector3
var collision_position_original: Vector3
var head_position_original: Vector3
var label_position_original: Vector3

func _ready() -> void:
	sync_timer.timeout.connect(on_sync_timeout)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mesh_scale_original = mesh.scale
	mesh_position_original = mesh.position
	collision_scale_original = collision.scale
	collision_position_original = collision.position
	head_position_original = head.position
	label_position_original = label_3d.position

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("test"):
		test.rpc()
	if event.is_action_pressed("sit") and is_multiplayer_authority():
		if sentado:
			levantarse.rpc()
		else:
			buscar_silla()

func buscar_silla() -> void:
	var sit_points = get_tree().get_nodes_in_group("sit_points")
	var silla_mas_cercana: Marker3D = null
	var menor_distancia: float = sit_distance
	for punto in sit_points:
		if punto is Marker3D:
			var distancia = global_position.distance_to(punto.global_position)
			if distancia < menor_distancia:
				menor_distancia = distancia
				silla_mas_cercana = punto
	if silla_mas_cercana != null:
		sentarse.rpc(
			silla_mas_cercana.global_position,
			silla_mas_cercana.global_rotation.y
		)

@rpc("authority", "call_local", "reliable")
func sentarse(posicion_silla: Vector3, rotacion_silla: float) -> void:
	sentado = true
	velocity = Vector3.ZERO
	global_position = posicion_silla
	global_rotation.y = rotacion_silla
	mesh.scale = mesh_scale_original
	mesh.position = mesh_position_original
	collision.scale = collision_scale_original
	collision.position = collision_position_original
	head.position = head_position_original + Vector3(0, -0.4, 0)
	label_3d.position = label_position_original + Vector3(0, -0.4, 0)

@rpc("authority", "call_local", "reliable")
func levantarse() -> void:
	sentado = false
	mesh.scale = mesh_scale_original
	mesh.position = mesh_position_original
	collision.scale = collision_scale_original
	collision.position = collision_position_original
	head.position = head_position_original
	label_3d.position = label_position_original
	global_position += -global_transform.basis.z * stand_offset
	velocity = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * mouse_sensitivity)
		camera_3d.rotate_x(
			-event.relative.y * mouse_sensitivity
		)
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
	set_multiplayer_authority(player_data.id)
	camera_3d.current = is_multiplayer_authority()
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
	_sync.rpc(
		global_position,
		velocity
	)

@rpc("authority", "call_remote", "reliable")
func _sync(pos: Vector3, vel: Vector3) -> void:
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
