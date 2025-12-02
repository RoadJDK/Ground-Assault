extends Control

@onready var singleplayer_button: Button = $SingleplayerButton
@onready var multiplayer_button: Button = $MultiplayerButton
@onready var settings_button: Button = $SettingsButton
@onready var quit_button: Button = $QuitButton
@onready var host_button: Button = $HostButton
@onready var join_button: Button = $JoinButton
@onready var ip_text: LineEdit = $IPText
@onready var back_button: Button = $BackButton
@onready var status_label: Label = $StatusLabel
@onready var sandbox_button: Button = $SandboxButton
@onready var easy_button: Button = $EasyButton
@onready var hard_button: Button = $HardButton

func _ready() -> void:
	# Connect global signals
	GameManager.game_started.connect(_on_game_started)
	GameManager.player_connected_status.connect(_update_status)
	MusicManager.enter_menu()
	
	# Set initial view
	show_main_menu_view()

func _update_status(msg: String):
	status_label.text = msg

# --- View State Helpers ---
# These replace the old _clear_menu() and instantiation logic

func show_main_menu_view() -> void:
	# Show Main Menu items
	singleplayer_button.show()
	multiplayer_button.show()
	settings_button.show()
	quit_button.show()
	
	# Hide Multiplayer items
	host_button.hide()
	join_button.hide()
	ip_text.hide()
	back_button.hide()
	status_label.hide()
	
	# Hide Singleplayer items
	sandbox_button.hide()
	easy_button.hide()
	hard_button.hide()
	
	# Clear status when returning to menu
	status_label.text = ""

func show_multi_menu_view() -> void:
	# Hide Main Menu items
	singleplayer_button.hide()
	multiplayer_button.hide()
	settings_button.hide()
	quit_button.hide()
	
	# Show Multiplayer items
	host_button.show()
	join_button.show()
	ip_text.show()
	back_button.show()
	status_label.show()
	
	# --- Ported IP Detection Logic ---
	if ip_text.text.is_empty() or ip_text.text == "127.0.0.1":
		var local_ip = "127.0.0.1"
		for addr in IP.get_local_addresses():
			if addr.begins_with("192.") or addr.begins_with("10."):
				local_ip = addr
				break
		ip_text.text = local_ip

func show_singleplayer_menu_view() -> void:
	# Hide Main Menu items
	singleplayer_button.hide()
	multiplayer_button.hide()
	settings_button.hide()
	quit_button.hide()
	
	# Hide Multiplayer items
	host_button.hide()
	join_button.hide()
	ip_text.hide()
	status_label.hide()
	
	# Show Singleplayer items
	sandbox_button.show()
	easy_button.show()
	hard_button.show()
	back_button.show()

# --- Button Connections ---

func _on_singleplayer_button_pressed() -> void:
	# Ported from old: _on_singleplayer_pressed
	show_singleplayer_menu_view()

func _on_multiplayer_button_pressed() -> void:
	# Ported from old: _on_multiplayer_pressed
	show_multi_menu_view()

func _on_settings_button_pressed() -> void:
	# Ported from old: _on_options_pressed
	print("Options Menu Not Implemented Yet")

func _on_quit_button_pressed() -> void:
	# Ported from old: _on_quit_pressed
	get_tree().quit()

func _on_host_button_pressed() -> void:
	# Ported from old: _on_host_pressed
	var msg = GameManager.host_game()
	_update_status(msg)
	# Logic waits for signal to change scene

func _on_join_button_pressed() -> void:
	# Ported from old: _on_join_pressed
	var msg = GameManager.join_game(ip_text.text)
	_update_status(msg)
	# Logic waits for signal to change scene

func _on_back_button_pressed() -> void:
	# Returns to main menu view
	show_main_menu_view()

func _on_game_started():
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_sandbox_button_pressed() -> void:
	GameManager.reset()
	GameManager.difficulty = "sandbox"
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_easy_button_pressed() -> void:
	GameManager.reset()
	GameManager.difficulty = "easy"
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_hard_button_pressed() -> void:
	GameManager.reset()
	GameManager.difficulty = "hard"
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
