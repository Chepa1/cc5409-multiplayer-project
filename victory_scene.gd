extends Control # o CanvasLayer, dependiendo de tu nodo raíz

@onready var back_button: Button = $Button 

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	back_button.pressed.connect(_on_back_button_pressed)

func _on_back_button_pressed() -> void:
	Lobby.instance.go_to_menu()
