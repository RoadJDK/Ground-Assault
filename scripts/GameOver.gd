extends Control

@onready var result_label = find_child("Label", true, false)

var winner_faction: String = ""

func _ready() -> void:
	var btn = find_child("RestartButton", true, false)
	if btn: btn.pressed.connect(_on_restart_pressed)
	
	var quit = find_child("QuitButton", true, false)
	if quit: quit.pressed.connect(_on_quit_pressed)
	
	# Apply winner if set before ready
	if winner_faction != "":
		_apply_winner_ui()

func set_winner(faction: String) -> void:
	winner_faction = faction
	if is_node_ready():
		_apply_winner_ui()

func _apply_winner_ui() -> void:
	if not result_label: return
	
	if winner_faction == "blue":
		result_label.text = "BLUE WINS!"
		result_label.modulate = Color(0.4, 0.4, 1.0)
	else:
		result_label.text = "RED WINS!"
		result_label.modulate = Color(1.0, 0.4, 0.4)

func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
