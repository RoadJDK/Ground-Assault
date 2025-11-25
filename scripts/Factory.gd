extends Building

const SQUAD_SCENE = preload("res://scenes/Troops/Squad.tscn")

@onready var spawn_timer: Timer = $Timer

var unit_type: int = 0 
var current_squad: Node2D = null
var is_squad_active: bool = false # Explicit flag to prevent race conditions

func _ready() -> void:
	super._ready()
	if spawn_timer:
		spawn_timer.wait_time = 10.0
		spawn_timer.autostart = true
		if spawn_timer.is_stopped():
			spawn_timer.start()

func set_unit_type(type_val: int) -> void:
	unit_type = type_val

func _on_timer_timeout() -> void:
	spawn_squad()

func spawn_squad() -> void:
	# Check explicit flag AND instance validity for safety
	if is_squad_active and is_instance_valid(current_squad):
		return

	var map_node = get_tree().root.find_child("Map", true, false)
	
	if map_node:
		var squad = SQUAD_SCENE.instantiate()
		map_node.add_child(squad)
		squad.global_position = global_position
		
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
		print("Factory Error: Could not find Map.")

func _on_squad_destroyed() -> void:
	# Immediately mark as inactive so the next spawn attempt works
	is_squad_active = false
	current_squad = null
	
	# Try to spawn replacements immediately
	call_deferred("spawn_squad")
