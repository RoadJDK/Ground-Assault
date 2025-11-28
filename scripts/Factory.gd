extends Building

const SQUAD_SCENE = preload("res://scenes/Troops/Squad.tscn")

@onready var spawn_timer: Timer = $Timer

var unit_type: int = 0 
var current_squad: Node2D = null
var is_squad_active: bool = false 

func _ready() -> void:
	super._ready()
	add_to_group("factory")
	if spawn_timer:
		spawn_timer.wait_time = 10.0
		spawn_timer.autostart = true
		if spawn_timer.is_stopped():
			spawn_timer.start()

func set_unit_type(type_val: int) -> void:
	unit_type = type_val

func _on_timer_timeout() -> void:
	if GameManager.is_multiplayer and not multiplayer.is_server():
		return

	if _check_safe_spawn():
		spawn_squad()
	else:
		# Wait another cycle if enemies are nearby
		spawn_timer.start(10.0)

func _check_safe_spawn() -> bool:
	var check_radius = 1500.0
	
	# Check Enemy Units
	var units = get_tree().get_nodes_in_group("unit")
	for u in units:
		if "faction" in u and u.faction != faction and u.faction != "neutral":
			if global_position.distance_to(u.global_position) < check_radius:
				return false
				
	# Check Enemy Buildings (Turrets, etc.)
	var buildings = get_tree().get_nodes_in_group("building")
	for b in buildings:
		if "faction" in b and b.faction != faction and b.faction != "neutral":
			if global_position.distance_to(b.global_position) < check_radius:
				return false
				
	return true

func spawn_squad() -> void:
	if is_squad_active and is_instance_valid(current_squad):
		return

	# Find the container we created in Main.gd
	var unit_container = get_tree().root.find_child("UnitContainer", true, false)
	
	if unit_container:
		var squad = SQUAD_SCENE.instantiate()
		unit_container.add_child(squad, true)
		squad.global_position = global_position
		
		# Play Spawn Sound
		if SFXManager: SFXManager.play_factory_spawn(global_position)
		
		current_squad = squad
		is_squad_active = true
		
		if not current_squad.tree_exiting.is_connected(_on_squad_destroyed):
			current_squad.tree_exiting.connect(_on_squad_destroyed)
		
		if "faction" in squad:
			squad.faction = self.faction
		
		if "unit_type" in squad:
			squad.unit_type = self.unit_type
			
		squad.setup_squad_formation(4, 6) 
	else:
		print("Factory Error: Could not find UnitContainer.")

func _on_squad_destroyed() -> void:
	is_squad_active = false
	current_squad = null
	
	# Start timer to try respawn (checks safety on timeout)
	spawn_timer.start(1.0) # Short initial delay, then 10s loops if blocked
