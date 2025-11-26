extends Node2D

const PLOT_SCENE = preload("res://scenes/Plot/Plot.tscn")
const PLAYER_SCENE = preload("res://scenes/Player/Player.tscn")
const OBSTACLE_SCENE = preload("res://scenes/Obstacle.tscn")

# --- ECONOMY ---
var faction_gold = {
	"blue": 1000,
	"red": 1000,
	"neutral": 0
}

var building_costs = {
	"Generator": 50,
	"Turret": 100,
	"Factory": 150,
	"Shield": 80,
	"Core": 0 
}

# --- STATE ---
var selected_building_tool: String = "" 
var current_build_faction: String = "blue"
var current_unit_type: int = 0 
var game_ui: CanvasLayer = null

var player_blue: Node2D = null
var player_red: Node2D = null

# --- MAP LIMITS ---
const LIMIT_LEFT: float = -6956.0
const LIMIT_TOP: float = -4622.0
const LIMIT_RIGHT: float = 6974.0 
const LIMIT_BOTTOM: float = 4699.0 

# Spacing params
const MIN_PLOT_DIST: float = 600.0

var generated_plots: Array[Node2D] = []
var generated_obstacles: Array[Node2D] = []

func _ready() -> void:
	print("--- MAIN READY STARTED ---")
	
	if GameManager.is_multiplayer:
		seed(12345)
	
	_generate_all_plots()
	_generate_obstacles(10) # Generate obstacles
	
	print("Total Plots Generated: ", generated_plots.size())
	print("Total Obstacles Generated: ", generated_obstacles.size())
	
	# Rebake Navigation
	var nav_region = find_child("NavigationRegion2D", true, false)
	if nav_region:
		print("Baking Navigation Mesh...")
		nav_region.bake_navigation_polygon()
	else:
		print("WARNING: NavigationRegion2D not found!")
	
	game_ui = find_child("GameUI", true, false)
	if game_ui:
		print("GameUI Found.")
		game_ui.build_requested.connect(_on_ui_build_tool_selected)
		_update_gold_ui()
		_update_unit_ui()
	else:
		print("ERROR: GameUI NOT Found!")
	
	# --- PLAYER SETUP ---
	var y_center = (LIMIT_TOP + LIMIT_BOTTOM) / 2.0
	
	# Blue Player
	player_blue = find_child("PlayerBlue", true, false)
	if not player_blue:
		player_blue = PLAYER_SCENE.instantiate()
		player_blue.name = "PlayerBlue"
		player_blue.position = Vector2(LIMIT_LEFT + 1200.0, y_center + 200)
		add_child(player_blue)
	
	player_blue.set_faction("blue")
	
	# Red Player
	player_red = find_child("PlayerRed", true, false)
	if not player_red:
		player_red = PLAYER_SCENE.instantiate()
		player_red.name = "PlayerRed"
		player_red.position = Vector2(LIMIT_RIGHT - 1200.0, y_center + 200)
		add_child(player_red)
	
	player_red.set_faction("red")
	
	# Initial State
	if GameManager.is_multiplayer:
		# Set Authorities
		player_blue.set_multiplayer_authority(1) # Host is always Blue
		player_red.set_multiplayer_authority(GameManager.red_player_id) # Client is Red
		
		_set_active_player(GameManager.my_faction)
	else:
		_set_active_player("blue")

	await get_tree().physics_frame
	var plots = get_tree().get_nodes_in_group("build_pad")
	for plot in plots:
		if not plot.is_connected("plot_selected", _on_plot_clicked):
			plot.plot_selected.connect(_on_plot_clicked)
	
	print("--- MAIN READY FINISHED ---")

func _process(_delta: float) -> void:
	_update_plot_availability()

func _set_active_player(faction: String) -> void:
	current_build_faction = faction
	
	if faction == "blue":
		if player_blue: player_blue.set_active(true)
		if player_red: player_red.set_active(false)
		print("Faction Mode: BLUE (Player Active)")
	else:
		if player_blue: player_blue.set_active(false)
		if player_red: player_red.set_active(true)
		print("Faction Mode: RED (Player Active)")
	
	_update_gold_ui()

func _generate_all_plots() -> void:
	var y_min = LIMIT_TOP + 1000.0
	var y_max = LIMIT_BOTTOM - 1000.0
	var y_center = (LIMIT_TOP + LIMIT_BOTTOM) / 2.0
	
	_spawn_single_plot(Vector2(LIMIT_LEFT + 1200.0, y_center), "Core", "blue")
	_spawn_single_plot(Vector2(LIMIT_RIGHT - 1200.0, y_center), "Core", "red")
	
	_spawn_plots_in_zone(20, LIMIT_LEFT + 1000.0, -2500.0, y_min, y_max)
	_spawn_plots_in_zone(10, -1500.0, 1500.0, y_min, y_max)
	_spawn_plots_in_zone(20, 2500.0, LIMIT_RIGHT - 1000.0, y_min, y_max)

func _generate_obstacles(count: int) -> void:
	var nav_region = find_child("NavigationRegion2D", true, false)
	var parent_node = nav_region if nav_region else self
	
	var x_min = LIMIT_LEFT + 2000.0
	var x_max = LIMIT_RIGHT - 2000.0
	var y_min = LIMIT_TOP + 500.0
	var y_max = LIMIT_BOTTOM - 500.0
	
	for i in range(count):
		var safe_pos = Vector2.ZERO
		var valid = false
		for attempt in range(20):
			var rand_x = randf_range(x_min, x_max)
			var rand_y = randf_range(y_min, y_max)
			var candidate = Vector2(rand_x, rand_y)
			
			if _is_position_valid_for_obstacle(candidate):
				safe_pos = candidate
				valid = true
				break
		
		if valid:
			var obs = OBSTACLE_SCENE.instantiate()
			# Add to group for Navigation Source Geometry if configured that way
			obs.add_to_group("navigation_polygon_source_geometry_group")
			
			parent_node.add_child(obs)
			obs.global_position = safe_pos
			
			if obs.has_method("setup_random"):
				obs.setup_random()
			
			generated_obstacles.append(obs)

func _is_position_valid_for_obstacle(pos: Vector2) -> bool:
	# Check Plots
	for p in generated_plots:
		var min_dist = 1200.0
		# Give Cores extra breathing room
		if p.building_instance and p.building_instance.is_in_group("core"):
			min_dist = 1800.0
			
		if pos.distance_to(p.global_position) < min_dist:
			return false
			
	# Check other obstacles
	for o in generated_obstacles:
		if pos.distance_to(o.global_position) < 1500.0:
			return false
			
	return true

func _spawn_single_plot(pos: Vector2, building_type: String = "", faction: String = "neutral") -> void:
	var map_node = find_child("Map", true, false)
	var parent_node = map_node if map_node else self
	
	var p = PLOT_SCENE.instantiate()
	parent_node.add_child(p)
	p.global_position = pos
	p.add_to_group("build_pad")
	generated_plots.append(p)
	
	if building_type != "":
		p.call_deferred("build_specific_building", building_type, faction)

func _spawn_plots_in_zone(count: int, x_min: float, x_max: float, y_min: float, y_max: float) -> void:
	var attempts_per_plot = 50
	var map_node = find_child("Map", true, false)
	var parent_node = map_node if map_node else self
	
	for i in range(count):
		var safe_pos = Vector2.ZERO
		var valid = false
		for attempt in range(attempts_per_plot):
			var rand_x = randf_range(x_min, x_max)
			var rand_y = randf_range(y_min, y_max)
			var candidate = Vector2(rand_x, rand_y)
			if _is_position_valid(candidate):
				safe_pos = candidate
				valid = true
				break
		
		if valid:
			var p = PLOT_SCENE.instantiate()
			parent_node.add_child(p)
			p.global_position = safe_pos
			p.add_to_group("build_pad")
			generated_plots.append(p)

func _is_position_valid(pos: Vector2) -> bool:
	for existing in generated_plots:
		if pos.distance_to(existing.global_position) < MIN_PLOT_DIST:
			return false
	return true

func _update_plot_availability() -> void:
	# 1. Gather Data
	var friendly_buildings = [] # List of buildings
	var building_to_plot = {}   # Map building -> plot node
	var empty_plots = []
	var all_plots = [] 
	
	for plot in generated_plots:
		if not is_instance_valid(plot): continue
		all_plots.append(plot)
		
		if plot.building_instance != null:
			if "faction" in plot.building_instance and plot.building_instance.faction == current_build_faction:
				friendly_buildings.append(plot.building_instance)
				building_to_plot[plot.building_instance] = plot
		else:
			empty_plots.append(plot)
			
	var plot_states = {} # plot -> { buildable: bool, targets: Array }
	
	# Configuration
	var build_range = 2500.0    # Max distance to allow building (bridging gaps)
	var draw_range = 1400.0     # Max distance to draw lines (reduce visual clutter)
	var max_lines = 3           # Max lines per plot
	
	# 2. OCCUPIED PLOTS (Maintain the Web)
	for fb in friendly_buildings:
		var potential = []
		for other in friendly_buildings:
			if fb == other: continue
			var d = fb.global_position.distance_to(other.global_position)
			if d <= build_range: # Check full BUILD RANGE
				potential.append({ "pos": other.global_position, "dist": d })
		
		# Sort by distance
		potential.sort_custom(func(a, b): return a.dist < b.dist)
		
		var my_targets = []
		
		# Try to find targets within DRAW RANGE first
		var draw_candidates = []
		for p in potential:
			if p.dist <= draw_range:
				draw_candidates.append(p)
		
		if not draw_candidates.is_empty():
			# Standard behavior: connect to closest ones within draw range
			for i in range(min(draw_candidates.size(), max_lines)):
				my_targets.append(draw_candidates[i].pos)
		elif not potential.is_empty():
			# Fallback: connect to the single closest node within build range
			# (This preserves the line that allowed construction)
			my_targets.append(potential[0].pos)
		
		# Update occupied plots
		if building_to_plot.has(fb):
			var p = building_to_plot[fb]
			plot_states[p] = { "buildable": false, "targets": my_targets }

	# 3. EXPANSION FRONTIER (Empty Plots)
	var frontier_map = {} # Plot Node -> Array[Vector2] (Unique targets)

	for fb in friendly_buildings:
		# Find candidates for THIS specific building
		var candidates = []
		for p in empty_plots:
			var d = p.global_position.distance_to(fb.global_position)
			if d <= build_range: # Use BUILD RANGE for validity
				candidates.append({ "plot": p, "dist": d })
		
		# Sort by distance to THIS building
		candidates.sort_custom(func(a, b): return a.dist < b.dist)
		
		# Take Top 3 for THIS building (these are the empty plots this building "unlocks")
		var limit = min(3, candidates.size())
		for i in range(limit):
			var p = candidates[i].plot
			
			if not frontier_map.has(p):
				frontier_map[p] = []
			
			if not fb.global_position in frontier_map[p]:
				frontier_map[p].append(fb.global_position)

	# 4. Merge Frontier into Plot States with Filters
	for p in frontier_map:
		var raw_targets = frontier_map[p] # Positions of buildings connecting here
		var valid_draw_targets = []
		
		# Filter by Drawing Range
		for t_pos in raw_targets:
			var d = p.global_position.distance_to(t_pos)
			if d <= draw_range:
				valid_draw_targets.append({ "pos": t_pos, "dist": d })
		
		# Force at least one connection if none exist within draw_range
		if valid_draw_targets.is_empty() and not raw_targets.is_empty():
			var closest_pos = Vector2.ZERO
			var closest_dist = 100000.0 # Arbitrary large number
			
			for t_pos in raw_targets:
				var d = p.global_position.distance_to(t_pos)
				if d < closest_dist:
					closest_dist = d
					closest_pos = t_pos
			
			valid_draw_targets.append({ "pos": closest_pos, "dist": closest_dist })

		# Sort by Distance
		valid_draw_targets.sort_custom(func(a, b): return a.dist < b.dist)
		
		# Limit to SINGLE Line for empty plots (visual anchor only)
		var final_targets = []
		var limit_empty = 1
		for i in range(min(valid_draw_targets.size(), limit_empty)):
			final_targets.append(valid_draw_targets[i].pos)
			
		plot_states[p] = { "buildable": true, "targets": final_targets }

	# 5. Apply States to ALL plots
	for plot in all_plots:
		if plot_states.has(plot):
			plot.set_buildable_status(plot_states[plot].buildable, plot_states[plot].targets)
		else:
			# Not part of the web/frontier
			plot.set_buildable_status(false, [])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var unit_changed = false
		
		if not GameManager.is_multiplayer:
			if event.keycode == KEY_Q:
				_set_active_player("blue")
			elif event.keycode == KEY_E:
				_set_active_player("red")
			
		# UNIT TYPES (Y, X, C)
		elif event.keycode == KEY_Y:
			current_unit_type = 0 # Ranged
			print("Next Factory will build: RANGED")
			unit_changed = true
		elif event.keycode == KEY_X:
			current_unit_type = 1 # Melee
			print("Next Factory will build: MELEE")
			unit_changed = true
		elif event.keycode == KEY_C:
			current_unit_type = 2 # Rocket
			print("Next Factory will build: ROCKET")
			unit_changed = true
			
		elif event.keycode == KEY_1:
			_on_ui_build_tool_selected("Generator")
		elif event.keycode == KEY_2:
			_on_ui_build_tool_selected("Turret")
		elif event.keycode == KEY_3:
			_on_ui_build_tool_selected("Factory")
		elif event.keycode == KEY_4:
			_on_ui_build_tool_selected("Shield")
		
		if unit_changed:
			_update_unit_ui()

func _on_ui_build_tool_selected(type_name: String) -> void:
	selected_building_tool = type_name
	
	if game_ui and game_ui.has_method("highlight_tool"):
		game_ui.highlight_tool(type_name)
		
	print("Tool: ", type_name, " | Faction: ", current_build_faction)

func _on_plot_clicked(plot_node) -> void:
	var active_player = player_blue if current_build_faction == "blue" else player_red
	
	if selected_building_tool != "":
		if active_player:
			if active_player.global_position.distance_to(plot_node.global_position) > 1000.0:
				print("Too far away!")
				if active_player.has_method("show_range_indicator"):
					active_player.show_range_indicator()
				return
		
		if selected_building_tool == "Core": return

		var cost = building_costs.get(selected_building_tool, 0)
		var current_gold = faction_gold.get(current_build_faction, 0)
		
		if current_gold >= cost:
			if plot_node.can_build_here():
				faction_gold[current_build_faction] -= cost
				_update_gold_ui()
				plot_node.build_specific_building(selected_building_tool, current_build_faction, current_unit_type)
			else:
				print("Cannot build here!")
		else:
			print("Not enough gold!")

func add_gold(amount: int, faction: String = "neutral") -> void:
	if faction in faction_gold:
		faction_gold[faction] += amount
		if faction == current_build_faction:
			_update_gold_ui()

func _update_gold_ui() -> void:
	if game_ui and game_ui.has_method("update_gold_display"):
		var amount = faction_gold.get(current_build_faction, 0)
		game_ui.update_gold_display(amount)

func _update_unit_ui() -> void:
	if game_ui and game_ui.has_method("update_unit_display"):
		var type_name = "Ranged"
		match current_unit_type:
			0: type_name = "Ranged"
			1: type_name = "Melee"
			2: type_name = "Rocket"
		game_ui.update_unit_display(type_name)
