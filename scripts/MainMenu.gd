extends Control

func _ready() -> void:
	# Connect signals if not doing it via editor
	var play_btn = find_child("PlayButton", true, false)
	var quit_btn = find_child("QuitButton", true, false)
	
	if play_btn: play_btn.pressed.connect(_on_play_pressed)
	if quit_btn: quit_btn.pressed.connect(_on_quit_pressed)

func _on_play_pressed() -> void:
	# Load the actual game scene
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
