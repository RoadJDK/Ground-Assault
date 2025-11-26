extends Node

signal game_started
signal player_connected_status(status_msg: String)

var is_multiplayer: bool = false
var my_faction: String = "blue"
var red_player_id: int = 1 # Default to 1 (Host) if not set, but will be set on connect

const PORT = 7777
const DEFAULT_IP = "127.0.0.1"

func reset():
	is_multiplayer = false
	my_faction = "blue"
	red_player_id = 1
	multiplayer.multiplayer_peer = null

func host_game():
	reset()
	is_multiplayer = true
	my_faction = "blue"
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	if error != OK:
		return "Failed to create server: " + str(error)
	
	multiplayer.multiplayer_peer = peer
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	return "Hosting on port " + str(PORT) + ". Waiting for player..."

func join_game(ip: String):
	reset()
	is_multiplayer = true
	my_faction = "red"
	
	if ip.strip_edges() == "":
		ip = DEFAULT_IP
		
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, PORT)
	if error != OK:
		return "Failed to create client: " + str(error)
		
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	return "Connecting to " + ip + "..."

# --- HOST EVENTS ---
func _on_peer_connected(id: int):
	# Only the Host runs this logic when a client connects
	if multiplayer.is_server():
		print("Player connected: ", id)
		red_player_id = id
		# Tell everyone to start
		rpc("rpc_start_game", red_player_id)

func _on_peer_disconnected(id: int):
	print("Player disconnected: ", id)

# --- CLIENT EVENTS ---
func _on_connected_ok():
	print("Connected to server!")
	player_connected_status.emit("Connected! Waiting for host...")

func _on_connected_fail():
	print("Connection failed.")
	player_connected_status.emit("Connection failed.")
	reset()

func _on_server_disconnected():
	print("Server disconnected.")
	player_connected_status.emit("Server disconnected.")
	reset()
	# Optionally return to menu?

# --- RPCs ---
@rpc("call_local", "reliable")
func rpc_start_game(assigned_red_id: int):
	red_player_id = assigned_red_id
	print("Game Starting! Red Player ID: ", red_player_id)
	game_started.emit()