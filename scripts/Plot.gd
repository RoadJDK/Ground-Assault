extends Node2D

var building_instance: Node2D = null
var _visual_rect: ColorRect = null
var _line_container: Node2D = null

# --- STATE ---
var is_buildable: bool = false
var connection_targets: Array[Vector2] = []

const GENERATOR_SCENE = preload("res://scenes/Plot/Buildings/Generator.tscn")
const TURRET_SCENE = preload("res://scenes/Plot/Buildings/Turret.tscn")
const FACTORY_SCENE = preload("res://scenes/Plot/Buildings/Factory.tscn")
const SHIELD_SCENE = preload("res://scenes/Plot/Buildings/Shield.tscn")
const CORE_SCENE = preload("res://scenes/Plot/Buildings/Core.tscn")

signal plot_selected(plot_node)

func _ready() -> void:
	# 1. Setup Visual Rect (Keep it visible this time)
	for child in get_children():
		if child is ColorRect:
			_visual_rect = child
			_visual_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_visual_rect.color = Color(0.2, 0.2, 0.2)
			break
	
	# 2. Setup Line Container (On top of everything)
	_line_container = Node2D.new()
	_line_container.name = "Lines"
	_line_container.z_index = 5 # Ensure lines are always on top
	add_child(_line_container)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if _visual_rect and _visual_rect.get_global_rect().has_point(get_global_mouse_position()):
			if event.button_index == MOUSE_BUTTON_LEFT:
				get_viewport().set_input_as_handled()
				emit_signal("plot_selected", self)
				
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				get_viewport().set_input_as_handled()
				_sell_building()

func set_buildable_status(buildable: bool, targets: Array) -> void:
	# Robust check to avoid unnecessary updates
	var needs_update = is_buildable != buildable
	if not needs_update:
		if connection_targets.size() != targets.size():
			needs_update = true
		else:
			for i in range(targets.size()):
				if connection_targets[i] != targets[i]:
					needs_update = true
					break
	
	if needs_update:
		is_buildable = buildable
		connection_targets.clear()
		connection_targets.append_array(targets)
		
		_update_plot_color("neutral")
		_update_lines() # Update the physical Line2D nodes

func _update_lines() -> void:
	# Clear old lines
	for child in _line_container.get_children():
		child.queue_free()
	
	if not _visual_rect: return
	
	# Create new lines if we have targets
	if not connection_targets.is_empty():
		var start = _visual_rect.position + _visual_rect.size / 2.0
		
		for target in connection_targets:
			var end = to_local(target)
			
			var line = Line2D.new()
			line.default_color = Color.WHITE
			line.width = 6.0
			line.antialiased = true
			line.add_point(start)
			line.add_point(end)
			_line_container.add_child(line)

func can_build_here() -> bool:
	return is_buildable and building_instance == null

func build_specific_building(type_name: String, faction: String, unit_type: int = 0) -> void:
	if building_instance != null:
		print("Plot occupied! Sell existing building first.")
		return
		
	# Core bypasses check
	if type_name != "Core" and not is_buildable:
		print("Plot is not valid (must be one of the 3 nearest)!")
		return

	var scene_to_build: PackedScene = null
	match type_name:
		"Generator": scene_to_build = GENERATOR_SCENE
		"Turret": scene_to_build = TURRET_SCENE
		"Factory": scene_to_build = FACTORY_SCENE
		"Shield": scene_to_build = SHIELD_SCENE
		"Core": scene_to_build = CORE_SCENE
	
	if scene_to_build:
		_replace_building(scene_to_build, faction, unit_type)

func _replace_building(scene: PackedScene, faction: String, unit_type: int) -> void:
	if building_instance:
		building_instance.queue_free()
	
	var new_building = scene.instantiate()
	new_building.z_index = 10 
	
	new_building.tree_exiting.connect(_on_building_destroyed)
	
	if "faction" in new_building:
		new_building.faction = faction
	
	if new_building.has_method("set_unit_type"):
		new_building.set_unit_type(unit_type)
	elif "unit_type" in new_building:
		new_building.unit_type = unit_type
		
	add_child(new_building)
	building_instance = new_building
	
	if _visual_rect:
		var center = _visual_rect.position + _visual_rect.size / 2.0
		new_building.position = center
		_update_plot_color(faction)
	else:
		new_building.position = Vector2(32, 32)
	
	# Clear lines when built
	connection_targets.clear()
	_update_lines()

func _sell_building() -> void:
	if building_instance:
		if building_instance.is_in_group("core"):
			print("Cannot sell Core buildings!")
			return

		building_instance.queue_free()
		building_instance = null
		_update_plot_color("neutral")
		_update_lines()

func _on_building_destroyed() -> void:
	call_deferred("_check_reset_color")

func _check_reset_color() -> void:
	if not is_instance_valid(building_instance) or building_instance.is_queued_for_deletion():
		building_instance = null
		_update_plot_color("neutral")

func _update_plot_color(faction: String) -> void:
	if not _visual_rect: return
	
	if building_instance != null:
		var f = "neutral"
		if "faction" in building_instance:
			f = building_instance.faction
			
		match f:
			"blue": _visual_rect.color = Color(0.4, 0.4, 1.0)
			"red": _visual_rect.color = Color(1.0, 0.4, 0.4)
			_: _visual_rect.color = Color.WHITE
	else:
		if is_buildable:
			_visual_rect.color = Color.WHITE
		else:
			_visual_rect.color = Color(0.2, 0.2, 0.2)
