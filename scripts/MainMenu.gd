extends Control

@onready var vbox = find_child("VBoxContainer", true, false)
var status_label: Label = null

func _ready() -> void:
	# Listen for Game Start
	GameManager.game_started.connect(_on_game_started)
	GameManager.player_connected_status.connect(_update_status)
	
	if vbox:
		for child in vbox.get_children():
			child.queue_free()
		show_main_menu()
	else:
		print("ERROR: VBoxContainer not found in MainMenu!")

func show_main_menu():
	_clear_menu()
	_create_button("Singleplayer", _on_singleplayer_pressed)
	_create_button("Multiplayer", _on_multiplayer_pressed)
	_create_button("Options", _on_options_pressed)
	_create_button("Quit", _on_quit_pressed)

func show_multi_menu():
	_clear_menu()
	_create_button("Host Game (Blue)", _on_host_pressed)
	
	var ip_input = LineEdit.new()
	ip_input.placeholder_text = "Enter IP (Default 127.0.0.1)"
	
	# Find local IPv4
	var local_ip = "127.0.0.1"
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.") or addr.begins_with("10."):
			local_ip = addr
			break
			
	ip_input.text = local_ip 
	ip_input.custom_minimum_size.y = 50
	vbox.add_child(ip_input)
	
	_create_button("Join Game (Red)", func(): _on_join_pressed(ip_input.text))
	
	status_label = Label.new()
	status_label.text = ""
	vbox.add_child(status_label)
	
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 20
	vbox.add_child(spacer)
	
	_create_button("Back", show_main_menu)

func _clear_menu():
	if not vbox: return
	for child in vbox.get_children():
		child.queue_free()
	status_label = null

func _create_button(text: String, callable: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size.y = 60
	btn.pressed.connect(callable)
	vbox.add_child(btn)
	return btn

func _update_status(msg: String):
	if status_label:
		status_label.text = msg

func _on_singleplayer_pressed():
	GameManager.reset()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_multiplayer_pressed():
	show_multi_menu()

func _on_options_pressed():
	print("Options Menu Not Implemented Yet")

func _on_quit_pressed():
	get_tree().quit()

func _on_host_pressed():
	var msg = GameManager.host_game()
	_update_status(msg)
	# Do NOT change scene yet. Wait for GameManager signal.

func _on_join_pressed(ip: String):
	var msg = GameManager.join_game(ip)
	_update_status(msg)
	# Do NOT change scene yet. Wait for GameManager signal.

func _on_game_started():
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
