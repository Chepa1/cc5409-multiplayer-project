extends CharacterBody3D

@export var move_speed: float = 5
@export var jump_speed: float = 7
@export var acceleration: float = 20
@export var mouse_sensitivity: float = 0.005

@onready var head: Node3D = $Head
@onready var camera_3d: Camera3D = $Head/Camera3D
@onready var label_3d: Label3D = $Label3D
@onready var input_synchronizer: InputSynchronizer = $InputSynchronizer
@onready var sync_timer: Timer = $SyncTimer

func _ready() -> void:
	sync_timer.timeout.connect(on_sync_timeout)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("test"):
		test.rpc()
		
func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
		
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * mouse_sensitivity)
		camera_3d.rotate_x(-event.relative.y * mouse_sensitivity)
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
	if not is_on_floor(): #Agrega gravedad
		velocity += get_gravity() * delta
	
	if input_synchronizer.jump:	
		if is_on_floor(): #salto
			velocity.y = jump_speed
		input_synchronizer.jump = false
		
	var move_input: Vector2 = input_synchronizer.move_input
	
	var direction: Vector3 = Vector3(move_input.x, 0, move_input.y).rotated(Vector3.UP, input_synchronizer.head_rotation)
	direction = direction.normalized()
	var target: Vector2 = Vector2(direction.x, direction.z) * move_speed
	var current: Vector2 = Vector2(velocity.x, velocity.z)
	var result: Vector2 = current.move_toward(target, acceleration * delta)
	
	velocity.x = result.x
	velocity.z = result.y
	
	move_and_slide()
	#send_data.rpc(global_position)
	
#@rpc("authority", "call_remote", "unreliable_ordered")
#func send_data(pos: Vector3) -> void:
#	global_position = pos

func on_sync_timeout() -> void:
	_sync.rpc(global_position, velocity)

@rpc("authority","call_remote","reliable")
func _sync(pos: Vector3, vel: Vector3) -> void:
	global_position = global_position.lerp(pos, 0.5)
	velocity = velocity.lerp(vel, 0.5)

func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		head.rotation.y = input_synchronizer.head_rotation
