extends Node

# --- CONFIGURATION ---
# Tracks
var stream_intro = preload("res://music/Intro.mp3")
var stream_base = preload("res://music/Base.mp3")
var stream_intensity1 = preload("res://music/Intensity1.mp3")
var stream_intensity2 = preload("res://music/Intensity2.mp3")
var stream_intensity3 = preload("res://music/Intensity3.mp3")

# Nodes
var player_intro: AudioStreamPlayer
var player_base: AudioStreamPlayer
var player_int1: AudioStreamPlayer
var player_int2: AudioStreamPlayer
var player_int3: AudioStreamPlayer

# State
enum Mode { MENU, GAME }
var current_mode = Mode.MENU
var heat_level: float = 0.0
var fade_speed: float = 3.0 # Volume changes per second

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Run even if game paused?
	
	# Create Players
	player_intro = _create_player(stream_intro, "Intro")
	player_base = _create_player(stream_base, "Base")
	player_int1 = _create_player(stream_intensity1, "Int1")
	player_int2 = _create_player(stream_intensity2, "Int2")
	player_int3 = _create_player(stream_intensity3, "Int3")
	
	# Connect Intro Finish
	player_intro.finished.connect(_on_intro_finished)
	
	# Determine Start Mode
	# If we are in MainMenu scene, start Intro. Else start Game loop.
	var current_scene = get_tree().current_scene
	if current_scene and current_scene.name == "MainMenu":
		_start_menu_music()
	else:
		_start_game_music()

func on_player_death() -> void:
	_stop_all()
	await get_tree().create_timer(1.0).timeout
	# Only restart if still in game mode (didn't quit to menu)
	if current_mode == Mode.GAME:
		_start_game_music()

func _create_player(stream: AudioStream, node_name: String) -> AudioStreamPlayer:
	var p = AudioStreamPlayer.new()
	p.name = node_name
	p.stream = stream
	p.bus = "Master" # Or "Music" if you have one
	add_child(p)
	return p

func _start_menu_music() -> void:
	current_mode = Mode.MENU
	_stop_all()
	player_intro.volume_db = 0.0
	player_intro.play()

func _on_intro_finished() -> void:
	if current_mode == Mode.MENU:
		# Transition to Base Loop
		if not player_base.playing:
			player_base.volume_db = 0.0
			player_base.play()

func _start_game_music() -> void:
	current_mode = Mode.GAME
	_stop_all()
	
	# Start Base + All Layers (synced)
	player_base.volume_db = 0.0
	player_base.play()
	
	# Start intensities silent
	player_int1.volume_db = -80.0
	player_int2.volume_db = -80.0
	player_int3.volume_db = -80.0
	
	player_int1.play()
	player_int2.play()
	player_int3.play()

func _stop_all() -> void:
	player_intro.stop()
	player_base.stop()
	player_int1.stop()
	player_int2.stop()
	player_int3.stop()

func _process(delta: float) -> void:
	if current_mode == Mode.GAME:
		_update_heat(delta)
		_update_volumes(delta)

func _update_heat(delta: float) -> void:
	var target_heat = 0.0
	
	# 1. Find Local Player (Center of action)
	var players = get_tree().get_nodes_in_group("unit")
	var my_hero = null
	
	for p in players:
		if p.get_script() and p.get_script().resource_path.contains("Player.gd"):
			if GameManager.is_multiplayer:
				if "faction" in p and p.faction == GameManager.my_faction:
					my_hero = p
					break
			else:
				# Singleplayer: Check active flag
				if "is_active" in p and p.is_active:
					my_hero = p
					break
	
	if my_hero:
		var hero_pos = my_hero.global_position
		var my_faction = my_hero.faction # Get actual faction from hero
		
		# 2. Count Enemies Nearby
		var enemy_count = 0
		var combat_range = 1600.0 # Decreased range (was 2400)
		
		# Check Units (Players & Squads)
		for u in get_tree().get_nodes_in_group("unit"):
			if u == my_hero: continue
			if "faction" in u and u.faction != my_faction and u.faction != "neutral":
				if u.global_position.distance_to(hero_pos) < combat_range:
					enemy_count += 1
		
		# Check Buildings (Turrets)
		for b in get_tree().get_nodes_in_group("building"):
			if "faction" in b and b.faction != my_faction and b.faction != "neutral":
				if b.global_position.distance_to(hero_pos) < combat_range:
					enemy_count += 1 
		
		# Heat Calculation
		target_heat = enemy_count * 2.0
		
		# 4. HP Stress
		# Increased threshold: < 60% HP adds heat
		if my_hero.current_hp < (my_hero.max_hp * 0.6):
			target_heat += 10.0
			
	# Smoothly interpolate heat
	heat_level = lerp(heat_level, target_heat, delta * 0.5) # Slow changing heat

func _update_volumes(delta: float) -> void:
	var target_db_1 = -80.0
	var target_db_2 = -80.0
	var target_db_3 = -80.0
	var target_db_base = 0.0
	
	# Check for Overview Mode
	var cam = get_viewport().get_camera_2d()
	var is_overview = false
	if cam and "is_overview_mode" in cam:
		is_overview = cam.is_overview_mode
	
	if is_overview:
		# Dampen Base Track in Overview
		target_db_base = -10.0
	else:
		# Detail Mode Logic
		if heat_level > 25.0:
			# Intensity 3 Full, 2 @ 66% (-3.5dB), 1 @ 33% (-10dB)
			target_db_3 = 0.0
			target_db_2 = -3.5
			target_db_1 = -10.0
		elif heat_level > 15.0:
			# Intensity 2 Full, 1 @ 50% (-6dB)
			target_db_3 = -80.0
			target_db_2 = 0.0
			target_db_1 = -6.0
		elif heat_level > 5.0:
			# Intensity 1 Full
			target_db_3 = -80.0
			target_db_2 = -80.0
			target_db_1 = 0.0
		
	# Apply smooth fade
	player_base.volume_db = move_toward(player_base.volume_db, target_db_base, fade_speed * 60.0 * delta)
	player_int1.volume_db = move_toward(player_int1.volume_db, target_db_1, fade_speed * 60.0 * delta)
	player_int2.volume_db = move_toward(player_int2.volume_db, target_db_2, fade_speed * 60.0 * delta)
	player_int3.volume_db = move_toward(player_int3.volume_db, target_db_3, fade_speed * 60.0 * delta)

# Public API to force states (if scene changes)
func enter_game():
	if current_mode != Mode.GAME:
		_start_game_music()

func enter_menu():
	if current_mode != Mode.MENU:
		_start_menu_music()
