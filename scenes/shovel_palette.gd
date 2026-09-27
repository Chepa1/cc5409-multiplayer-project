extends Node3D

@onready var interaction_area: InteractionArea = $InteractionArea

func _ready() -> void:
	interaction_area.interact.connect(_on_interaction)

func _on_interaction() -> void:
	pass
