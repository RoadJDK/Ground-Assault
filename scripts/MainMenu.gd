extends Control

@onready var vbox = find_child("VBoxContainer", true, false)

func _ready() -> void:
	multiplayer.multiplayer_peer = null # Reset network state
	if vbox:
		# Clear existing editor-placed buttons to rebuild our structure
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
	ip_input.text = "127.0.0.1" # Default for convenience
	ip_input.custom_minimum_size.y = 50
	vbox.add_child(ip_input)
	
	_create_button("Join Game (Red)", func(): _on_join_pressed(ip_input.text))
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 20
	vbox.add_child(spacer)
	
	_create_button("Back", show_main_menu)

func _clear_menu():
	if not vbox: return
	for child in vbox.get_children():
		child.queue_free()

func _create_button(text: String, callable: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size.y = 60
	btn.pressed.connect(callable)
	vbox.add_child(btn)
	return btn

func _on_singleplayer_pressed():
	GameManager.reset()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_multiplayer_pressed():
	show_multi_menu()

func _on_options_pressed():
	print("Options Menu Not Implemented Yet")
	# Placeholder for options

func _on_quit_pressed():
	get_tree().quit()

func _on_host_pressed():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(GameManager.PORT)
	if error != OK:
		print("Failed to create server: ", error)
		return
		
	multiplayer.multiplayer_peer = peer
	print("Hosting on port ", GameManager.PORT)
	
	GameManager.is_multiplayer = true
	GameManager.my_faction = "blue"
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_join_pressed(ip: String):
	if ip.strip_edges() == "":
		ip = GameManager.DEFAULT_IP
		
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, GameManager.PORT)
	if error != OK:
		print("Failed to connect to ", ip, ": ", error)
		return
	
	multiplayer.multiplayer_peer = peer
	print("Joining ", ip, " on port ", GameManager.PORT)
	
	GameManager.is_multiplayer = true
	GameManager.my_faction = "red"
	get_tree().change_scene_to_file("res://scenes/Main.tscn")