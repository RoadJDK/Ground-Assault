extends Control

func _ready():
	# Ensure the menu is hidden on start
	visible = false
	
	# Ensure the background dimmer is visible when the menu is shown
	var bg = find_child("ColorRect", true, false)
	if bg:
		bg.visible = true

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if visible:
			_resume_game()
		else:
			_pause_game()
			# Handle input so it doesn't propagate
			get_viewport().set_input_as_handled()

func _pause_game():
	visible = true
	get_tree().paused = true
	
	# Optional: specific background handling if needed
	var bg = find_child("ColorRect", true, false)
	if bg: bg.visible = true

func _resume_game():
	visible = false
	get_tree().paused = false

func _on_continue_button_pressed() -> void:
	_resume_game()

func _on_home_button_pressed() -> void:
	_resume_game() # Unpause before changing scenes
	get_tree().change_scene_to_file("res://scenes/UI/MainMenu.tscn")
