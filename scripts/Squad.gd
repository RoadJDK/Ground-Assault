extends Node2D

class_name Squad

@export var move_speed: float = 200.0
@export var turn_speed: float = 3.0
@export var spacing: float = 40.0

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

var is_wandering: bool = true
var faction: String = "neutral"
var unit_type: int = 0 

# COMMAND MODE
var is_commanded: bool = false
var command_target: Node2D = null

# VISUALS
var show_selection: bool = false

func _ready() -> void:
	# --- NETWORK SYNC ---
	if GameManager.is_multiplayer:
		var sync = MultiplayerSynchronizer.new()
		sync.name = "MultiplayerSynchronizer"
		sync.replication_interval = 0.016
		
		var config = SceneReplicationConfig.new()
		config.add_property("." + ":position")
		config.add_property("." + ":rotation")
		config.add_property("." + ":faction") # Sync Faction too
		sync.replication_config = config
		
		add_child(sync)
		
		# NESTED SPAWNER FOR TROOPS
		# Only add spawner; allow it to auto-detect children added by authority
		var troop_spawner = MultiplayerSpawner.new()
		troop_spawner.name = "TroopSpawner"
		troop_spawner.spawn_path = ".." # Spawn as direct children of the Squad (Parent of Spawner)
		troop_spawner.add_spawnable_scene("res://scenes/Troops/Types/Ranged.tscn")
		troop_spawner.add_spawnable_scene("res://scenes/Troops/Types/Melee.tscn")
		troop_spawner.add_spawnable_scene("res://scenes/Troops/Types/Rocket.tscn")
		add_child(troop_spawner)

	nav_agent.path_desired_distance = 50.0
	nav_agent.target_desired_distance = 50.0
	await get_tree().physics_frame
	_decide_next_target()

func _physics_process(delta: float) -> void:
	if GameManager.is_multiplayer and not is_multiplayer_authority():
		return # Client just interpolates Squad position

	# Check integrity first to handle instant death
	_check_integrity()
	
	if is_queued_for_deletion(): return

	if nav_agent.is_navigation_finished():
		_decide_next_target()
		return
	
	if is_commanded and is_instance_valid(command_target):
		nav_agent.target_position = command_target.global_position

	var next_path_position = nav_agent.get_next_path_position()
	var current_agent_position = global_position
	var new_velocity = (next_path_position - current_agent_position).normalized() * move_speed
	
	if new_velocity.length() > 0:
		var desired_angle = new_velocity.angle()
		rotation = rotate_toward(rotation, desired_angle, turn_speed * delta)
	
	global_position += new_velocity * delta

func _decide_next_target() -> void:
	if is_commanded and is_instance_valid(command_target):
		nav_agent.target_position = command_target.global_position
		return

	var enemy_buildings = get_tree().get_nodes_in_group("building")
	var nearest_building: Node2D = null
	var min_dist = 999999.0
	
	for b in enemy_buildings:
		if "faction" in b and b.faction != faction and b.faction != "neutral":
			var dist = global_position.distance_to(b.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest_building = b
	
	if nearest_building:
		nav_agent.target_position = nearest_building.global_position
	else:
		_pick_random_target()

func enter_command_mode(target: Node2D) -> void:
	is_commanded = true
	command_target = target
	show_selection = true
	queue_redraw()
	
	# Set all troops to passive
	for child in get_children():
		if child is Troop:
			child.is_passive = true
			child.target_enemy = null # Clear current target

func exit_command_mode() -> void:
	is_commanded = false
	command_target = null
	show_selection = false
	queue_redraw()
	
	# Reset troops
	for child in get_children():
		if child is Troop:
			child.is_passive = false
	_decide_next_target()

func _draw() -> void:
	if show_selection:
		# Draw a green ring around the Squad center
		# Since Squad is a Node2D and parent of troops, its position is the "center" of the squad (roughly)
		# Increased radius by 10px (120 -> 130) and enabled antialiasing
		draw_arc(Vector2.ZERO, 130.0, 0, TAU, 32, Color(0, 1, 0, 0.8), 4.0, true)

func command_fire_at(pos: Vector2) -> void:
	for child in get_children():
		if child is Troop:
			child.force_attack_at(pos)

func setup_squad_formation(cols: int, rows: int) -> void:
	var troop_scene_path = "res://scenes/Troops/Types/Ranged.tscn"
	match unit_type:
		0: troop_scene_path = "res://scenes/Troops/Types/Ranged.tscn"
		1: troop_scene_path = "res://scenes/Troops/Types/Melee.tscn"
		2: troop_scene_path = "res://scenes/Troops/Types/Rocket.tscn"
	
	var troop_scene = load(troop_scene_path)
	
	var total_width = (cols - 1) * spacing
	var total_height = (rows - 1) * spacing
	var offset_start = Vector2(-total_width / 2.0, -total_height / 2.0)
	
	for x in range(cols):
		for y in range(rows):
			var troop = troop_scene.instantiate()
			add_child(troop, true)
			var pos_x = offset_start.x + (x * spacing)
			var pos_y = offset_start.y + (y * spacing)
			
			if "faction" in troop:
				troop.faction = self.faction
			
			if "unit_type" in troop:
				troop.unit_type = unit_type
				
			troop.setup(self, Vector2(pos_x, pos_y))

func _pick_random_target() -> void:
	var random_offset = Vector2(randf_range(-2000, 2000), randf_range(-2000, 2000))
	var target = global_position + random_offset
	target.x = clamp(target.x, -6500, 6500)
	target.y = clamp(target.y, -4000, 4000)
	nav_agent.target_position = target

func _check_integrity() -> void:
	# FIX: Explicitly count Troops instead of checking child count (which includes NavigationAgent, etc)
	var troop_count = 0
	for child in get_children():
		if child is Troop:
			troop_count += 1
	
	if troop_count == 0:
		queue_free()
