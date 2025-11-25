extends Node2D

var building_instance: Node2D = null
var _visual_rect: ColorRect = null

# --- STATE ---
var is_buildable: bool = false
# Changed from single Vector2 to Array of Vector2 for spider web effect
var connection_targets: Array[Vector2] = []

const GENERATOR_SCENE = preload("res://scenes/Plot/Buildings/Generator.tscn")
const TURRET_SCENE = preload("res://scenes/Plot/Buildings/Turret.tscn")
const FACTORY_SCENE = preload("res://scenes/Plot/Buildings/Factory.tscn")
const SHIELD_SCENE = preload("res://scenes/Plot/Buildings/Shield.tscn")
const CORE_SCENE = preload("res://scenes/Plot/Buildings/Core.tscn")

signal plot_selected(plot_node)

func _ready() -> void:
	for child in get_children():
		if child is ColorRect:
			_visual_rect = child
			_visual_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# FIX: Darker color to contrast with Godot's grey background
			_visual_rect.color = Color(0.15, 0.15, 0.15)
			# FIX: Ensure the ColorRect stays behind the drawn lines/border
			_visual_rect.show_behind_parent = true
			break

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if _visual_rect and _visual_rect.get_global_rect().has_point(get_global_mouse_position()):
			if event.button_index == MOUSE_BUTTON_LEFT:
				get_viewport().set_input_as_handled()
				emit_signal("plot_selected", self)
				
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				get_viewport().set_input_as_handled()
				_sell_building()

# Updated to accept a generic Array to prevent type errors from Main.gd
func set_buildable_status(buildable: bool, targets: Array) -> void:
	# Robust check to avoid unnecessary redraws
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
		
		# Clear and re-assign
		connection_targets.clear()
		connection_targets.append_array(targets)
		
		_update_plot_color("neutral")
		queue_redraw()

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
	
	queue_redraw()

func _sell_building() -> void:
	if building_instance:
		if building_instance.is_in_group("core"):
			print("Cannot sell Core buildings!")
			return

		building_instance.queue_free()
		building_instance = null
		_update_plot_color("neutral")
		queue_redraw()

func _on_building_destroyed() -> void:
	call_deferred("_check_reset_color")

func _check_reset_color() -> void:
	if not is_instance_valid(building_instance) or building_instance.is_queued_for_deletion():
		building_instance = null
		_update_plot_color("neutral")

func _update_plot_color(faction: String) -> void:
	if not _visual_rect: return
	
	if building_instance != null:
		# Use the actual building's faction if occupied
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
			# Darker distinct color (Almost black) to show it's locked but visible
			_visual_rect.color = Color(0.15, 0.15, 0.15)

func _draw() -> void:
	# 1. Draw Border (So we can see the plot even if color matches BG)
	if _visual_rect:
		var r = Rect2(_visual_rect.position, _visual_rect.size)
		draw_rect(r, Color(0.3, 0.3, 0.3), false, 2.0) # Grey outline
	
	# 2. Draw lines to ALL targets in the array
	if not connection_targets.is_empty():
		var start = _visual_rect.position + _visual_rect.size / 2.0
		
		for target in connection_targets:
			var end = to_local(target)
			draw_line(start, end, Color.WHITE, 7.0, true)
