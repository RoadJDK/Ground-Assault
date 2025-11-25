extends Control

@onready var result_label = $ResultLabel

func _ready() -> void:
	var btn = find_child("RestartButton", true, false)
	if btn: btn.pressed.connect(_on_restart_pressed)

func set_winner(winner_faction: String) -> void:
	if winner_faction == "blue":
		result_label.text = "BLUE WINS!"
		result_label.modulate = Color(0.4, 0.4, 1.0)
	else:
		result_label.text = "RED WINS!"
		result_label.modulate = Color(1.0, 0.4, 0.4)

func _on_restart_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
