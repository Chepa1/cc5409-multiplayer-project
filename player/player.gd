extends CharacterBody3D

@onready var camera_3d: Camera3D = $Head/Camera3D
@onready var label_3d: Label3D = $Label3D

#const SPEED = 5.0
#const JUMP_VELOCITY = 4.5

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("test"):
		test.rpc()

func setup(player_data: Statics.PlayerData) -> void:
	label_3d.text = player_data.name
	set_multiplayer_authority(player_data.id)
	camera_3d.current = is_multiplayer_authority()

@rpc("authority", "call_local", "unreliable_ordered")
func test() -> void:
	Debug.log("meh")
#func _physics_process(delta: float) -> void:
	# Add the gravity.
	#if not is_on_floor():
		#velocity += get_gravity() * delta

	# Handle jump.
	#if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		#velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	#var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	#var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	#if direction:
		#velocity.x = direction.x * SPEED
		#velocity.z = direction.z * SPEED
	#else:
		#velocity.x = move_toward(velocity.x, 0, SPEED)
		#velocity.z = move_toward(velocity.z, 0, SPEED)

	#move_and_slide()
