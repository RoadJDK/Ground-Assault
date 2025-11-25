extends Node2D

class_name Squad

@export var move_speed: float = 200.0  # 5x (was 40)
@export var turn_speed: float = 3.0
@export var spacing: float = 40.0      # 5x (was 8)

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

var is_wandering: bool = true
var faction: String = "neutral"
var unit_type: int = 0 

func _ready() -> void:
	nav_agent.path_desired_distance = 50.0   # Scaled up
	nav_agent.target_desired_distance = 50.0
	await get_tree().physics_frame
	_decide_next_target()

func _physics_process(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		_decide_next_target()
		return

	var next_path_position = nav_agent.get_next_path_position()
	var current_agent_position = global_position
	var new_velocity = (next_path_position - current_agent_position).normalized() * move_speed
	
	if new_velocity.length() > 0:
		var desired_angle = new_velocity.angle()
		rotation = rotate_toward(rotation, desired_angle, turn_speed * delta)
	
	global_position += new_velocity * delta
	_check_integrity()

func _decide_next_target() -> void:
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
			# Instantiating safely
			var troop = troop_scene.instantiate()
			add_child(troop)
			
			var pos_x = offset_start.x + (x * spacing)
			var pos_y = offset_start.y + (y * spacing)
			
			if "faction" in troop:
				troop.faction = self.faction
			
			if "unit_type" in troop:
				troop.unit_type = unit_type
				
			troop.setup(self, Vector2(pos_x, pos_y))

func _pick_random_target() -> void:
	# 5x Range for random wander
	var random_offset = Vector2(randf_range(-2000, 2000), randf_range(-2000, 2000))
	var target = global_position + random_offset
	# Assuming map is ~5000x5000 now
	target.x = clamp(target.x, 500, 5500)
	target.y = clamp(target.y, 500, 3000)
	nav_agent.target_position = target

func _check_integrity() -> void:
	if get_child_count() == 1:
		queue_free()
