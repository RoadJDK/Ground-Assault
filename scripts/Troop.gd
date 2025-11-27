extends CharacterBody2D

class_name Troop

# --- CONFIGURATION ---
enum UnitType { RANGED, MELEE, ROCKET }
@export var unit_type: UnitType = UnitType.RANGED
@export var max_hp: int = 20

# Stats (Scaled for Large Map)
var damage: int = 1
var attack_range: float = 500.0
var attack_cooldown: float = 1.0
var attack_speed: float = 2000.0
var base_speed: float = 325.0
var explosion_radius: float = 0.0

# --- STATE ---
var current_hp: int
var faction: String = "neutral":
	set(value):
		faction = value
		if is_node_ready():
			_apply_faction_color()

var assigned_offset: Vector2 = Vector2.ZERO
var squad_leader: Node2D = null 
var noise_seed: Vector2 = Vector2.ZERO
var squeeze_weight: float = 0.0

# Combat State
var target_enemy: Node2D = null
var nearby_enemies: Array[Node2D] = [] 
var attack_timer: float = 0.0
var scan_timer: float = 0.0
var projectile_scene: PackedScene = null

# COMMAND MODE
var is_passive: bool = false

# Movement Variance
var engagement_variance: float = 0.6

# Recoil State
var recoil_velocity: Vector2 = Vector2.ZERO

# Visuals
var _color: Color = Color.WHITE

# DEBUG FLAG
var is_debug_unit: bool = false

var nav_agent: NavigationAgent2D = null
var _nav_path_timer: float = 0.0
var separation_area: Area2D = null

# Shield Cache
var cached_shield: Node2D = null
var _shield_check_timer: float = 0.0

func _ready() -> void:
	current_hp = max_hp
	noise_seed = Vector2(randf(), randf()) * 10.0
	engagement_variance = randf_range(0.5, 0.9)
	
	# Randomize scan timer to desync units
	scan_timer = randf_range(0.1, 0.5)
	_shield_check_timer = randf_range(0.0, 1.0)
	
	top_level = true 
	add_to_group("unit")
	
	# --- SEPARATION SENSOR ---
	separation_area = Area2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 75.0
	var col = CollisionShape2D.new()
	col.shape = shape
	separation_area.add_child(col)
	separation_area.collision_layer = 0
	# FIX: Units are on Layer 2. Default mask is 1 (Terrain). 
	# We must explicitly mask Layer 2 to detect other units.
	separation_area.collision_mask = 2 
	separation_area.monitorable = false
	separation_area.monitoring = true
	add_child(separation_area)
	
	# --- NETWORK SYNC ---
	if GameManager.is_multiplayer:
		var sync = MultiplayerSynchronizer.new()
		sync.name = "MultiplayerSynchronizer"
		sync.replication_interval = 0.016 # Roughly 60 times per second
		
		var config = SceneReplicationConfig.new()
		config.add_property("." + ":position")
		config.add_property("." + ":rotation")
		config.add_property("." + ":faction") # Sync Faction for colors
		sync.replication_config = config
		
		add_child(sync)
	
	# --- NAVIGATION ---
	nav_agent = NavigationAgent2D.new()
	nav_agent.avoidance_enabled = true # Enable RVO avoidance
	nav_agent.radius = 30.0
	nav_agent.neighbor_distance = 200.0
	nav_agent.time_horizon_agents = 1.0
	nav_agent.time_horizon_obstacles = 1.0
	
	# Avoidance? Maybe later. For now just pathfinding.
	nav_agent.path_desired_distance = 20.0
	nav_agent.target_desired_distance = 20.0
	add_child(nav_agent)
	
	_setup_type_attributes()
	
	# Speed up!
	base_speed *= 1.5 
	
	# Apply color once ready to ensure children exist
	_apply_faction_color()
	
	# SETUP DEBUG: Only track the FIRST child of a BLUE squad
	await get_tree().process_frame # Wait for parent assignment
	if faction == "blue" and get_parent().get_child_count() > 0 and get_parent().get_child(0) == self:
		is_debug_unit = true

func setup(leader: Node2D, offset: Vector2) -> void:
	squad_leader = leader
	assigned_offset = offset
	global_position = leader.global_position + offset

func _setup_type_attributes() -> void:
	match unit_type:
		UnitType.RANGED:
			damage = 1
			attack_range = 1200.0      
			attack_cooldown = 0.4 # Fast Fire Rate
			max_hp = 20
			base_speed = 350.0
			attack_speed = 2200.0
			explosion_radius = 15.0 
			projectile_scene = load("res://scenes/Projectiles/ProjectileMG.tscn")
		UnitType.MELEE:
			damage = 5 # High Base Damage
			attack_range = 200.0      
			attack_cooldown = 0.8
			max_hp = 60 # Tanky
			base_speed = 450.0 # Fast
			explosion_radius = 0.0
		UnitType.ROCKET:
			damage = 8 # High Splash Damage
			attack_range = 1800.0     
			attack_cooldown = 3.5 
			max_hp = 30
			base_speed = 275.0
			attack_speed = 1100.0 
			explosion_radius = 250.0 # Large AoE
			projectile_scene = load("res://scenes/Projectiles/ProjectileHowitzer.tscn")
	current_hp = max_hp

func _apply_faction_color() -> void:
	match faction:
		"blue": _color = Color(0.3, 0.6, 1.0)
		"red": _color = Color(1.0, 0.4, 0.4)
		_: _color = Color.WHITE
	_color_all_children(self, _color)

func _color_all_children(node: Node, col: Color) -> void:
	for child in node.get_children():
		if child is ColorRect:
			child.color = col
		if child.get_child_count() > 0:
			_color_all_children(child, col)

func _physics_process(delta: float) -> void:
	if GameManager.is_multiplayer and not is_multiplayer_authority():
		return # Client just interpolates (handled by Sync)

	if not is_instance_valid(squad_leader):
		queue_free()
		return

	_handle_combat(delta)
	_handle_movement(delta)
	
	# Damping Recoil
	if recoil_velocity.length() > 1.0:
		recoil_velocity = recoil_velocity.move_toward(Vector2.ZERO, 1000.0 * delta)
	else:
		recoil_velocity = Vector2.ZERO
	
	# ROTATION LOGIC
	if is_instance_valid(target_enemy) and velocity == Vector2.ZERO:
		var aim_pos = _get_predicted_position(target_enemy, attack_speed)
		var dir = (aim_pos - global_position).angle()
		rotation = rotate_toward(rotation, dir, 10.0 * delta)
	elif velocity.length() > 10.0:
		rotation = rotate_toward(rotation, velocity.angle(), 5.0 * delta)

func _handle_combat(delta: float) -> void:
	if is_passive: return # Do not scan or auto-attack in passive mode

	if attack_timer > 0: attack_timer -= delta
	scan_timer -= delta
	_shield_check_timer -= delta
	
	if target_enemy != null and not is_instance_valid(target_enemy):
		target_enemy = null
		# Don't immediately scan, wait for timer to spread load
	
	if scan_timer <= 0:
		scan_timer = randf_range(0.2, 0.4) # Randomize interval slightly
		if target_enemy == null:
			_scan_for_enemies()
	
	if is_instance_valid(target_enemy):
		var dist = global_position.distance_to(target_enemy.global_position)
		var target_radius = 0.0
		if target_enemy.is_in_group("building"):
			target_radius = 250.0 
		
		var effective_dist = dist - target_radius
		
		# Stop chasing if too far (De-aggro)
		if effective_dist > attack_range * 1.5:
			target_enemy = null
			return
		
		# Shield Check (Throttled)
		if _shield_check_timer <= 0:
			_shield_check_timer = 1.0
			cached_shield = _get_protecting_shield(target_enemy)
			
		var required_dist = attack_range * engagement_variance
		
		if cached_shield:
			required_dist = 600.0
		
		if effective_dist <= required_dist + 10.0:
			if attack_timer <= 0:
				_attack_target()

func _scan_for_enemies() -> void:
	# OPTIMIZATION: Removed list creation and sorting.
	# Now iterates to find nearest directly.
	
	# Detect enemies earlier (2x range or 1500 min) so we walk to them
	var scan_radius = max(1500.0, attack_range * 2.0)
	var nearest_dist = scan_radius
	var nearest_node = null
	
	# Check Units
	var enemy_units = get_tree().get_nodes_in_group("unit")
	for u in enemy_units:
		if "faction" in u and u.faction != faction and u.faction != "neutral":
			var dist = global_position.distance_to(u.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_node = u
	
	# Check Buildings (only if no unit found closer than current nearest)
	var enemy_buildings = get_tree().get_nodes_in_group("building")
	for b in enemy_buildings:
		if "faction" in b and b.faction != faction and b.faction != "neutral":
			var dist = global_position.distance_to(b.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_node = b
	
	target_enemy = nearest_node

func _select_next_target() -> void:
	# Fallback to scan
	_scan_for_enemies()

func force_attack_at(target_pos: Vector2) -> void:
	# Force rotation towards target
	var dir = (target_pos - global_position).angle()
	rotation = dir
	
	if attack_timer > 0: return
	
	attack_timer = attack_cooldown
	
	if unit_type == UnitType.MELEE:
		# Melee can only hit if actually close, so this might be ineffective at range
		# We check distance to target pos
		if global_position.distance_to(target_pos) <= attack_range + 20.0:
			# Try to find an enemy at that location to damage
			# Note: This is a simple approximation.
			pass
	else:
		if projectile_scene:
			var spawn_rot = dir
			
			var final_dmg = damage
			if GameManager.is_multiplayer:
				var spawner = get_tree().root.find_child("ProjectileSpawner", true, false)
				if spawner:
					var data = {
						"scene_path": projectile_scene.resource_path,
						"pos": global_position,
						"rot": spawn_rot,
						"dmg": final_dmg,
						"spd": attack_speed,
						"group": "all", # Hit anything
						"shooter_path": get_path(),
						"radius": explosion_radius
					}
					spawner.spawn(data)
			else:
				var proj = projectile_scene.instantiate()
				get_tree().root.add_child(proj)
				proj.global_position = global_position
				proj.rotation = spawn_rot
				proj.setup(final_dmg, attack_speed, "all", self, explosion_radius)
			
			if unit_type == UnitType.ROCKET:
				var recoil_dir = (global_position - target_pos).normalized()
				recoil_velocity = recoil_dir * 900.0

func _attack_target() -> void:
	attack_timer = attack_cooldown
	
	if unit_type == UnitType.MELEE:
		if target_enemy.has_method("take_damage"):
			var final_dmg = damage
			# Melee Bonus vs Buildings
			if target_enemy.is_in_group("building"):
				final_dmg *= 2
			target_enemy.take_damage(final_dmg)
	else:
		if projectile_scene:
			var aim_pos = _get_predicted_position(target_enemy, attack_speed)
			var dir = (aim_pos - global_position).angle()
			var spawn_rot = dir
			var target_group = "unit"
			if target_enemy.is_in_group("building"): target_group = "building"

			var final_dmg = damage
			# Ranged Bonus vs Units
			if unit_type == UnitType.RANGED and target_group == "unit":
				final_dmg = 2 # Double damage vs Squads

			if GameManager.is_multiplayer:
				var spawner = get_tree().root.find_child("ProjectileSpawner", true, false)
				if spawner:
					var data = {
						"scene_path": projectile_scene.resource_path,
						"pos": global_position,
						"rot": spawn_rot,
						"dmg": final_dmg,
						"spd": attack_speed,
						"group": target_group,
						"shooter_path": get_path(),
						"radius": explosion_radius
					}
					spawner.spawn(data)
			else:
				var proj = projectile_scene.instantiate()
				get_tree().root.add_child(proj)
				proj.global_position = global_position
				proj.rotation = spawn_rot
				proj.setup(final_dmg, attack_speed, target_group, self, explosion_radius)
			
			if unit_type == UnitType.ROCKET:
				var recoil_dir = (global_position - target_enemy.global_position).normalized()
				recoil_velocity = recoil_dir * 900.0 

func _get_predicted_position(target: Node2D, bullet_speed: float) -> Vector2:
	# 1. Initial guess
	var dist = global_position.distance_to(target.global_position)
	var time_to_hit = dist / bullet_speed
	
	# 2. Iterative refinement (Reduced to 1 pass for performance)
	var predicted_pos = target.global_position
	if "velocity" in target:
		predicted_pos += target.velocity * time_to_hit
	
	return predicted_pos

func _handle_movement(delta: float) -> void:
	var move_velocity = Vector2.ZERO
	var holding_ground = false
	var final_target_pos = Vector2.ZERO
	var use_nav = false
	
	# 1. COMBAT MOVEMENT
	if is_instance_valid(target_enemy):
		var dist = global_position.distance_to(target_enemy.global_position)
		var target_radius = 0.0
		if target_enemy.is_in_group("building"): target_radius = 250.0
		var effective_dist = dist - target_radius
		
		var threshold = attack_range * engagement_variance
		if cached_shield: # Use cached shield
			threshold = 600.0 
		
		# Combat Logic
		if effective_dist <= threshold:
			move_velocity = Vector2.ZERO
			holding_ground = true # STOP and HOLD
		else:
			final_target_pos = target_enemy.global_position
			use_nav = true
	
	# 2. FORMATION MOVEMENT
	else:
		var formation_pos = _get_formation_pos()
		var leader_pos = squad_leader.global_position
		
		if get_slide_collision_count() > 0:
			squeeze_weight = move_toward(squeeze_weight, 1.0, 5.0 * delta)
		else:
			squeeze_weight = move_toward(squeeze_weight, 0.0, 2.0 * delta)
			
		var move_target = formation_pos.lerp(leader_pos, squeeze_weight * 0.8)
		var time = Time.get_ticks_msec() / 1000.0
		var wobble = Vector2(sin(time * 2.0 + noise_seed.x), cos(time * 1.5 + noise_seed.y)) * 3.0
		move_target += wobble
		
		var vector_to_target = move_target - global_position
		var distance = vector_to_target.length()
		
		if distance > 5.0:
			final_target_pos = move_target
			use_nav = true # Always use pathfinding to avoid obstacles, even in formation
			
			# Speed mod
			var speed_mult = 1.0
			if distance > 60.0: speed_mult = 1.2
			base_speed = _get_base_speed_for_type() * speed_mult 
			
			move_velocity = vector_to_target.normalized() * base_speed
		else:
			move_velocity = Vector2.ZERO
	
	# APPLY NAVIGATION
	if use_nav and not holding_ground:
		if nav_agent:
			# Performance Optimization: Update path frequently but not every frame
			_nav_path_timer -= delta
			if _nav_path_timer <= 0:
				_nav_path_timer = 0.1 # Increased frequency to 10Hz
				nav_agent.target_position = final_target_pos
			
			if not nav_agent.is_navigation_finished():
				var next = nav_agent.get_next_path_position()
				move_velocity = (next - global_position).normalized() * base_speed
			
			# Fallback: If nav thinks we finished, but real target moved (e.g. formation), keep moving directly
			elif global_position.distance_to(final_target_pos) > 25.0: 
				move_velocity = (final_target_pos - global_position).normalized() * base_speed
				# Force path update next frame to sync up
				_nav_path_timer = 0.0
			else:
				move_velocity = Vector2.ZERO
		else:
			move_velocity = (final_target_pos - global_position).normalized() * base_speed
	
	# 3. SEPARATION FORCE
	var separation = Vector2.ZERO
	if recoil_velocity.length() < 10.0:
		# FIX: If holding ground (attacking), Disable separation completely (strength = 0)
		if holding_ground:
			separation = Vector2.ZERO
		else:
			# Only calculate separation if we are moving or stuck
			if move_velocity.length() > 0.1:
				separation = _calculate_separation_force()
				move_velocity += separation * 250.0

	velocity = move_velocity + recoil_velocity
	move_and_slide()

func _get_base_speed_for_type() -> float:
	# Helper to reset base speed which might be modified by Formation logic above
	match unit_type:
		UnitType.RANGED: return 350.0
		UnitType.MELEE: return 450.0
		UnitType.ROCKET: return 275.0
	return 300.0

func _calculate_separation_force() -> Vector2:
	var force = Vector2.ZERO
	var neighbor_count = 0
	var separation_radius = 75.0 
	
	# OPTIMIZATION: Use the local Area2D sensor
	var units = separation_area.get_overlapping_bodies()
	
	for unit in units:
		if unit == self: continue
		if not unit.is_in_group("unit"): continue
		if "faction" in unit and unit.faction != faction: continue 
		
		var dist = global_position.distance_to(unit.global_position)
		if dist < separation_radius and dist > 0.1:
			var push = (global_position - unit.global_position).normalized()
			force += push / dist 
			neighbor_count += 1
	
	if neighbor_count > 0:
		force = force / neighbor_count
		
	return force

func _get_formation_pos() -> Vector2:
	var rotated_offset = assigned_offset.rotated(squad_leader.rotation)
	return squad_leader.global_position + rotated_offset

func _get_protecting_shield(target: Node2D) -> Node2D:
	var shields = get_tree().get_nodes_in_group("shield")
	for s in shields:
		if s.faction == target.faction: 
			var dist = s.global_position.distance_to(target.global_position)
			if dist < 700.0: 
				return s
	return null

func take_damage(amount: int) -> void:
	if GameManager.is_multiplayer:
		rpc("rpc_take_damage", amount)
	else:
		rpc_take_damage(amount)

@rpc("any_peer", "call_local")
func rpc_take_damage(amount: int) -> void:
	current_hp -= amount
	if current_hp <= 0:
		queue_free()
