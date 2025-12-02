extends Node
class_name AIHelper

# --- CONFIGURATION ---
var difficulty: String = "easy"
var faction: String = "red"
var tick_rate: float = 1.0
var timer: float = 0.0

# --- REFERENCES ---
var main_node: Node2D
var ai_player: CharacterBody2D
var my_core: Node2D
var enemy_core: Node2D

# --- STATE ---
var current_state: String = "IDLE" # IDLE, ATTACKING, DEFENDING, BUILDING, COLLECTING
var target_position: Vector2 = Vector2.ZERO
var target_plot: Node2D = null # The plot we want to build on
var squad_rally_point: Vector2 = Vector2.ZERO

# --- SETTINGS ---
var min_gold_reserve: int = 50
var expansion_desire: float = 0.5
var debug_mode: bool = true

func setup(_main: Node2D, _diff: String, _faction: String) -> void:
	main_node = _main
	difficulty = _diff
	faction = _faction
	
	# Find Players
	if faction == "red":
		ai_player = main_node.find_child("PlayerRed", true, false)
		# var blue_player = main_node.find_child("PlayerBlue", true, false) # Unused
	else:
		ai_player = main_node.find_child("PlayerBlue", true, false)
	
	if ai_player:
		ai_player.is_ai_controlled = true
		print("AI: Took control of ", ai_player.name)

	# Find Cores (Wait a frame for generation if needed, but Main ready is done)
	_find_cores()
	
	# Configure Difficulty
	if difficulty == "hard":
		tick_rate = 0.25 # Fast reaction
		min_gold_reserve = 10 # Spend everything
		expansion_desire = 0.9
	else:
		tick_rate = 1.5 # Slow reaction
		min_gold_reserve = 150 # Hoard gold
		expansion_desire = 0.4

func _find_cores() -> void:
	var buildings = get_tree().get_nodes_in_group("core")
	for b in buildings:
		if "faction" in b:
			if b.faction == faction:
				my_core = b
			else:
				enemy_core = b

func _process(delta: float) -> void:
	if not is_instance_valid(ai_player) or not is_instance_valid(main_node):
		return
		
	# --- CONTINUOUS ACTIONS (Movement/Combat) ---
	_handle_movement_and_combat(delta)
	
	# --- STRATEGIC TICK ---
	timer += delta
	if timer >= tick_rate:
		timer = 0.0
		_tick_strategy()

func _tick_strategy() -> void:
	# Refresh References
	if not is_instance_valid(my_core) or not is_instance_valid(enemy_core):
		_find_cores()
		if not is_instance_valid(my_core): return # We lost?

	# 1. Assess Threats (Defend?)
	if _should_defend():
		current_state = "DEFENDING"
		return

	# 2. Assess Economy (Build?)
	if _should_build():
		current_state = "BUILDING"
		return

	# 3. Assess Army (Collect Squads?)
	if _should_collect_squads():
		current_state = "COLLECTING"
		return

	# 4. Default: Attack
	current_state = "ATTACKING"

var defend_commit_timer: float = 0.0 # Hysteresis to prevent ping-ponging

func _should_defend() -> bool:
	# If already committed to defending, stick to it for at least 3 seconds
	if current_state == "DEFENDING" and defend_commit_timer > 0:
		defend_commit_timer -= tick_rate
		return true

	# Check enemies near ANY of my buildings (Base defense / Fallback)
	# Increased range 3x (1500 -> 4500)
	var danger_radius = 4500.0 
	var enemy_units = _get_enemy_units()
	
	# 1. Check Core (Highest Priority)
	if is_instance_valid(my_core):
		for u in enemy_units:
			if u.global_position.distance_to(my_core.global_position) < danger_radius:
				target_position = u.global_position
				defend_commit_timer = 3.0 # Commit
				return true
	
	# 2. Check other buildings (Smart Fallback)
	# If an enemy is attacking my generator/factory behind me, I should go there.
	var my_buildings = []
	for p in main_node.generated_plots:
		if is_instance_valid(p.building_instance) and "faction" in p.building_instance and p.building_instance.faction == faction:
			my_buildings.append(p.building_instance)
			
	for b in my_buildings:
		for u in enemy_units:
			if u.global_position.distance_to(b.global_position) < 1500.0: # Closer range for outlying buildings
				target_position = u.global_position
				defend_commit_timer = 3.0
				return true

	# 3. Self Preservation (Kiting handled in movement, but here we decide to FIGHT)
	# Low HP Logic: If HP < 40%, play safer. Don't aggressively chase unless cornered.
	var hp_percent = float(ai_player.current_hp) / float(ai_player.max_hp)
	var fight_range = 800.0
	if hp_percent < 0.4:
		fight_range = 400.0 # Only fight if VERY close (cornered)
		
		# If we are low HP and not cornered, maybe go to COLLECTING or BUILDING instead of Defending/Attacking
		# Returning false here allows other states to pick up.
		# But we should check if we are currently being chased?
		# For now, reducing fight range effectively makes AI ignore enemies further away when weak.
	
	for u in enemy_units:
		if u.global_position.distance_to(ai_player.global_position) < fight_range:
			# FIX: Don't chase into death traps (Turrets)
			if _is_position_dangerous(u.global_position):
				continue
				
			target_position = u.global_position
			defend_commit_timer = 3.0
			return true
			
	return false

func _is_position_dangerous(pos: Vector2) -> bool:
	# Check for Turrets
	var buildings = get_tree().get_nodes_in_group("building")
	for b in buildings:
		if "faction" in b and b.faction != faction and b.faction != "neutral":
			if "Turret" in b.name or b.is_in_group("turret"):
				if b.global_position.distance_to(pos) < 900.0: # Turret Range is ~800-1000
					return true
	return false

func _should_build() -> bool:
	# Check Gold
	var my_gold = main_node.faction_gold.get(faction, 0)
	# Strict check: Don't even plan if we are poor, unless we have NO buildings
	if my_gold < min_gold_reserve: return false
	
	# Determine what to build
	var build_plan = _get_build_plan()
	if build_plan.type == "": return false
	
	# CRITICAL FIX: Check affordability of the SPECIFIC building planned
	var cost = main_node.building_costs.get(build_plan.type, 0)
	if my_gold < cost:
		return false
	
	# Find a plot
	var plot = _find_best_plot(build_plan.type)
	if plot:
		target_plot = plot
		target_position = plot.global_position
		# Store the plan to execute when we get there
		target_plot.set_meta("planned_build", build_plan.type)
		target_plot.set_meta("planned_unit", build_plan.unit_type)
		return true
		
	return false

func _get_build_plan() -> Dictionary:
	var counts = _count_my_buildings()
	var gens = counts.get("Generator", 0)
	var facts = counts.get("Factory", 0)
	var turrets = counts.get("Turret", 0)
	
	# Priority Queue
	if gens < 2: return { "type": "Generator", "unit_type": 0 }
	if facts < 1: return { "type": "Factory", "unit_type": 0 } # Ranged
	if gens < 4: return { "type": "Generator", "unit_type": 0 }
	if facts < 2: return { "type": "Factory", "unit_type": 1 } # Melee
	
	# Dynamic choice based on difficulty
	if difficulty == "hard":
		# Counter Logic could go here
		if turrets < facts: return { "type": "Turret", "unit_type": 0 }
		return { "type": "Factory", "unit_type": 2 } # Rocket
	else:
		# Easy: Just more stuff
		if randf() < 0.5: return { "type": "Generator", "unit_type": 0 }
		return { "type": "Factory", "unit_type": 0 }

func _should_collect_squads() -> bool:
	# Check for uncommanded squads
	var uncommanded = []
	var units = get_tree().get_nodes_in_group("unit")
	for u in units:
		if u.has_method("enter_command_mode") and "faction" in u and u.faction == faction:
			if u not in ai_player.commanded_squads:
				# Only collect if they are relatively close to home/factories, don't chase stragglers
				if is_instance_valid(my_core) and u.global_position.distance_to(my_core.global_position) < 3000.0:
					uncommanded.append(u)
	
	if uncommanded.size() >= 2: # Wait for a couple
		# Target the center of mass of uncommanded squads
		var center = Vector2.ZERO
		for u in uncommanded:
			center += u.global_position
		target_position = center / uncommanded.size()
		return true
		
	return false

func _handle_movement_and_combat(_delta: float) -> void:
	# 1. Combat (Shooting)
	var target_enemy = _get_best_target()
	if target_enemy:
		ai_player.ai_look_at(target_enemy.global_position)
		
		# Shoot if aimed and in range
		var dist_to_enemy = ai_player.global_position.distance_to(target_enemy.global_position)
		if dist_to_enemy < 1800.0: # MG Range (Increased 2x)
			ai_player.ai_shoot_requested = true
			
		# Command Squads to fire
		if ai_player.is_commanding_squads:
			pass
	
	# 2. Movement
	var move_dest = target_position
	
	if current_state == "ATTACKING":
		# SMART ATTACK: If we have a target nearby, engage them first!
		# Don't just walk past them to the core.
		if target_enemy and ai_player.global_position.distance_to(target_enemy.global_position) < 2500.0:
			move_dest = target_enemy.global_position
		elif is_instance_valid(enemy_core):
			move_dest = enemy_core.global_position
		else:
			move_dest = Vector2.ZERO # Center map?
			
	elif current_state == "BUILDING":
		if is_instance_valid(target_plot):
			move_dest = target_plot.global_position
			# Check if arrived
			if ai_player.global_position.distance_to(move_dest) < 300.0:
				_execute_build_at_plot(target_plot)
				current_state = "IDLE" # Job done
		else:
			current_state = "IDLE"
			return
	
	elif current_state == "COLLECTING":
		# If we are close to the collection point, activate command
		if ai_player.global_position.distance_to(move_dest) < 500.0:
			ai_player.ai_command_squads(true)
			# Done collecting, switch to Attack
			current_state = "ATTACKING"

	# Execute Move
	var stop_distance = 100.0
	
	# Combat Maneuvers (Kiting & Strafing)
	if current_state == "ATTACKING" and target_enemy:
		if difficulty == "hard":
			var dist_to_target = ai_player.global_position.distance_to(target_enemy.global_position)
			
			if dist_to_target < 500.0:
				# KITE: Back away if too close
				var retreat_dir = (ai_player.global_position - target_enemy.global_position).normalized()
				move_dest = ai_player.global_position + retreat_dir * 400.0
				stop_distance = 10.0 # Force movement
			elif dist_to_target < 900.0:
				# STRAFE: Dodge bullets only when in shooting range
				var dir_to_enemy = (target_enemy.global_position - ai_player.global_position).normalized()
				var strafe_dir = Vector2(-dir_to_enemy.y, dir_to_enemy.x) # Perpendicular
				var strafe_offset = strafe_dir * sin(Time.get_ticks_msec() * 0.004) * 400.0
				
				move_dest = ai_player.global_position + strafe_offset
				stop_distance = 10.0
			else:
				# APPROACH: Straight line, no dodge until shooting
				move_dest = target_enemy.global_position
				stop_distance = 800.0
		else:
			# EASY MODE: Just walk up and shoot
			move_dest = target_enemy.global_position
			stop_distance = 800.0
	
	if current_state == "DEFENDING":
		# Apply Combat Maneuvers while defending too!
		if target_enemy:
			if difficulty == "hard":
				var dist_to_target = ai_player.global_position.distance_to(target_enemy.global_position)
				if dist_to_target < 500.0:
					# KITE
					var retreat_dir = (ai_player.global_position - target_enemy.global_position).normalized()
					move_dest = ai_player.global_position + retreat_dir * 400.0
					stop_distance = 10.0
				elif dist_to_target < 900.0:
					# STRAFE
					var dir_to_enemy = (target_enemy.global_position - ai_player.global_position).normalized()
					var strafe_dir = Vector2(-dir_to_enemy.y, dir_to_enemy.x)
					var strafe_offset = strafe_dir * sin(Time.get_ticks_msec() * 0.004) * 400.0
					move_dest = ai_player.global_position + strafe_offset
					stop_distance = 10.0
				else:
					# Approach
					move_dest = target_enemy.global_position
					stop_distance = 800.0
			else:
				# EASY MODE
				move_dest = target_enemy.global_position
				stop_distance = 800.0
		else:
			# Fallback if no specific target found but state is defending
			stop_distance = 600.0
			var hp_percent = float(ai_player.current_hp) / float(ai_player.max_hp)
			if hp_percent < 0.4:
				stop_distance = 1200.0 

	# --- EXECUTE MOVEMENT ---
	var dist_to_dest = ai_player.global_position.distance_to(move_dest)
	
	if dist_to_dest > stop_distance:
		# Set Navigation Target
		ai_player.ai_nav_target = move_dest
		ai_player.ai_input_vector = Vector2.ZERO
		
		# Sprint if far and safe
		if dist_to_dest > 1500.0 and not target_enemy:
			ai_player.ai_sprint = true
		else:
			ai_player.ai_sprint = false
	else:
		ai_player.ai_nav_target = Vector2.ZERO
		ai_player.ai_input_vector = Vector2.ZERO
		ai_player.velocity = Vector2.ZERO
		
	# --- DEBUG VISUALS ---
	if debug_mode:
		ai_player.ai_debug_target_pos = move_dest
		if Time.get_ticks_msec() % 60 == 0: # Print occasionally
			print("AI State: ", current_state, " | Target: ", move_dest, " | Enemy: ", target_enemy.name if target_enemy else "None")
	else:
		ai_player.ai_debug_target_pos = Vector2.ZERO

func _execute_build_at_plot(plot: Node2D) -> void:
	if not is_instance_valid(plot): 
		current_state = "IDLE"
		return
	
	var type = plot.get_meta("planned_build", "")
	var unit = plot.get_meta("planned_unit", 0)
	
	if type == "": 
		current_state = "IDLE"
		return
	
	var cost = main_node.building_costs.get(type, 0)
	var my_gold = main_node.faction_gold.get(faction, 0)
	
	if my_gold >= cost:
		# Force build, bypassing plot.can_build_here() which is UI-dependent
		if plot.building_instance == null:
			plot.build_specific_building(type, faction, unit)
			if SFXManager: SFXManager.play_building_build(plot.global_position)
			print("AI Built ", type, " at ", plot.global_position)
		else:
			print("AI Failed to build (Occupied)")
	else:
		print("AI Failed to build (Insufficient Gold)")
	
	target_plot = null
	current_state = "IDLE"

# --- HELPERS ---

func _get_enemy_units() -> Array:
	var enemies = []
	var units = get_tree().get_nodes_in_group("unit")
	for u in units:
		if "faction" in u and u.faction != faction and u.faction != "neutral":
			enemies.append(u)
	return enemies

func _get_best_target() -> Node2D:
	var enemies = _get_enemy_units()
	var buildings = get_tree().get_nodes_in_group("building")
	for b in buildings:
		if "faction" in b and b.faction != faction and b.faction != "neutral":
			enemies.append(b)
	
	if enemies.is_empty(): return null
	
	var player_pos = ai_player.global_position
	
	# Filter candidates within "Awareness Range" (e.g., 3000)
	# Unless the ONLY enemies are far away (fallback)
	var candidates = []
	for e in enemies:
		if player_pos.distance_to(e.global_position) < 3000.0:
			candidates.append(e)
			
	if candidates.is_empty():
		# Fallback: Just find closest regardless of type
		var closest = null
		var min_dist = 999999.0
		for e in enemies:
			var d = player_pos.distance_to(e.global_position)
			if d < min_dist:
				min_dist = d
				closest = e
		return closest
	
	# Sort by Priority Score (Lower is better)
	candidates.sort_custom(func(a, b):
		return _get_target_score(a, player_pos) < _get_target_score(b, player_pos)
	)
	
	return candidates[0]

func _get_target_score(node: Node2D, from: Vector2) -> float:
	var dist = from.distance_to(node.global_position)
	var penalty = 0.0
	
	if node.name.contains("Player"): penalty = 0.0
	elif node.is_in_group("turret") or node.name.contains("Turret"): penalty = 200.0
	elif node.is_in_group("unit"): penalty = 500.0
	elif node.name.contains("Factory"): penalty = 1000.0
	elif node.name.contains("Generator"): penalty = 1200.0
	elif node.name.contains("Shield"): penalty = 1500.0
	elif node.is_in_group("core") or node.name.contains("Core"): penalty = 5000.0
	
	return dist + penalty

func _count_my_buildings() -> Dictionary:
	var counts = {}
	var plots = main_node.generated_plots
	for p in plots:
		if is_instance_valid(p.building_instance) and "faction" in p.building_instance:
			if p.building_instance.faction == faction:
				# Determine type from name or group
				var type = "Unknown"
				var b_name = p.building_instance.name
				
				if p.building_instance.is_in_group("core") or "Core" in b_name: type = "Core"
				elif "Generator" in b_name: type = "Generator"
				elif "Factory" in b_name: type = "Factory"
				elif "Turret" in b_name: type = "Turret"
				elif "Shield" in b_name: type = "Shield"
				
				counts[type] = counts.get(type, 0) + 1
	return counts

func _find_best_plot(_building_type: String) -> Node2D:
	# Custom Connectivity Check (Main.gd only updates for Human Player)
	var my_buildings = []
	for p in main_node.generated_plots:
		if is_instance_valid(p.building_instance) and "faction" in p.building_instance:
			if p.building_instance.faction == faction:
				my_buildings.append(p.building_instance)
	
	var available = []
	var build_range = 2500.0
	
	for p in main_node.generated_plots:
		if p.building_instance != null: continue
		
		# Check connectivity
		var connected = false
		for b in my_buildings:
			if p.global_position.distance_to(b.global_position) <= build_range:
				connected = true
				break
		
		if connected:
			available.append(p)
			
	if available.is_empty(): return null
	
	# Sort based on Strategy
	# Always prioritize proximity to AI player to reduce walking time
	available.sort_custom(func(a, b): 
		return a.global_position.distance_to(ai_player.global_position) < b.global_position.distance_to(ai_player.global_position)
	)
	
	if difficulty == "hard":
		# In Hard mode, we still want efficiency, but we might want to prefer plots closer to enemy IF they are roughly same distance from player?
		# For now, simple efficiency (shortest walk) is better behavior than "running across the map".
		# The "Connected" check ensures we don't build random islands.
		pass
		
	return available[0]
