extends Control

func _ready():
	# Hide initially
	visible = false
	
	var btn_continue = find_child("ContinueButton", true, false)
	var btn_home = find_child("HomeButton", true, false)
	
	if btn_continue:
		btn_continue.pressed.connect(continue_game)
	else:
		print("PauseUI: ContinueButton not found")
		
	if btn_home:
		btn_home.pressed.connect(go_home)
	else:
		print("PauseUI: HomeButton not found")

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if visible:
			continue_game()
		else:
			pause_game()
			# Mark input as handled so other things don't react to ESC
			get_viewport().set_input_as_handled()

func pause_game():
	visible = true
	get_tree().paused = true
	# Ensure this menu stays on top and is visible
	move_to_front()
	
	# Show the background dimming if it exists (it's usually a child ColorRect)
	var bg = find_child("ColorRect", true, false)
	if bg: bg.visible = true

func continue_game():
	visible = false
	get_tree().paused = false
	
	var bg = find_child("ColorRect", true, false)
	if bg: bg.visible = false

func go_home():
	get_tree().paused = false
	# Change to MainMenu
	get_tree().change_scene_to_file("res://scenes/UI/MainMenu.tscn")
