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
var attack_timer: float = 0.0
var scan_timer: float = 0.0
var projectile_scene: PackedScene = null

# Movement Variance
var engagement_variance: float = 0.6

# Recoil State
var recoil_velocity: Vector2 = Vector2.ZERO

# Visuals
var _color: Color = Color.WHITE

func _ready() -> void:
	current_hp = max_hp
	noise_seed = Vector2(randf(), randf()) * 10.0
	engagement_variance = randf_range(0.5, 0.9)
	
	top_level = true 
	add_to_group("unit")
	
	_setup_type_attributes()
	
	# Apply color once ready to ensure children exist
	_apply_faction_color()

func setup(leader: Node2D, offset: Vector2) -> void:
	squad_leader = leader
	assigned_offset = offset
	global_position = leader.global_position + offset

func _setup_type_attributes() -> void:
	match unit_type:
		UnitType.RANGED:
			damage = 1
			attack_range = 750.0      
			attack_cooldown = 0.8
			max_hp = 20
			base_speed = 325.0
			attack_speed = 2000.0
			explosion_radius = 20.0 # Small splash for MG
			projectile_scene = load("res://scenes/Projectiles/ProjectileMG.tscn")
		UnitType.MELEE:
			damage = 2
			attack_range = 125.0      
			attack_cooldown = 0.5
			max_hp = 40
			base_speed = 400.0
			explosion_radius = 0.0
		UnitType.ROCKET:
			damage = 4 
			attack_range = 1250.0     
			attack_cooldown = 6.0 
			max_hp = 30
			base_speed = 275.0
			attack_speed = 1000.0 
			explosion_radius = 200.0 # Large splash for Rockets
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
	if attack_timer > 0: attack_timer -= delta
	scan_timer -= delta
	
	if scan_timer <= 0:
		scan_timer = 0.5 
		_find_target()
	
	if is_instance_valid(target_enemy):
		# Adjust distance check for building size
		var dist = global_position.distance_to(target_enemy.global_position)
		var target_radius = 0.0
		if target_enemy.is_in_group("building"):
			target_radius = 250.0 
		
		var effective_dist = dist - target_radius
		
		# Movement logic decides when to stop, here we just check if we CAN fire
		# Check Shield Penetration
		var shield = _get_protecting_shield(target_enemy)
		var required_dist = attack_range * engagement_variance
		
		# If target is shielded, we MUST be inside the shield (e.g. < 600) to fire
		if shield:
			required_dist = 600.0
		
		# Allow small buffer
		var can_attack = (effective_dist <= required_dist + 10.0)
		
		if can_attack:
			if attack_timer <= 0:
				_attack_target()
		else:
			if effective_dist > attack_range * 1.5:
				target_enemy = null 

func _find_target() -> void:
	var enemy_units = get_tree().get_nodes_in_group("unit")
	var nearest: Node2D = null
	var min_dist = 3000.0
	
	for u in enemy_units:
		if "faction" in u and u.faction != faction and u.faction != "neutral":
			var dist = global_position.distance_to(u.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = u
	
	if nearest == null:
		var enemy_buildings = get_tree().get_nodes_in_group("building")
		for b in enemy_buildings:
			if "faction" in b and b.faction != faction and b.faction != "neutral":
				var dist = global_position.distance_to(b.global_position)
				if dist < min_dist:
					min_dist = dist
					nearest = b
	target_enemy = nearest

func _attack_target() -> void:
	attack_timer = attack_cooldown
	
	if unit_type == UnitType.MELEE:
		if target_enemy.has_method("take_damage"):
			target_enemy.take_damage(damage)
	else:
		if projectile_scene:
			var proj = projectile_scene.instantiate()
			get_tree().root.add_child(proj)
			proj.global_position = global_position
			
			# PREDICTION LOGIC
			var aim_pos = _get_predicted_position(target_enemy, attack_speed)
			var dir = (aim_pos - global_position).angle()
			proj.rotation = dir
			
			var target_group = "unit"
			if target_enemy.is_in_group("building"): target_group = "building"
			
			# PASS EXPLOSION RADIUS HERE
			proj.setup(damage, attack_speed, target_group, self, explosion_radius)
			
			# KNOCKBACK RECOIL
			if unit_type == UnitType.ROCKET:
				var recoil_dir = (global_position - target_enemy.global_position).normalized()
				recoil_velocity = recoil_dir * 900.0 

func _get_predicted_position(target: Node2D, bullet_speed: float) -> Vector2:
	var dist = global_position.distance_to(target.global_position)
	var time_to_hit = dist / bullet_speed
	if "velocity" in target:
		return target.global_position + (target.velocity * time_to_hit)
	return target.global_position

func _handle_movement(delta: float) -> void:
	var desired_velocity = Vector2.ZERO
	
	# 1. COMBAT MOVEMENT
	if is_instance_valid(target_enemy):
		var dist = global_position.distance_to(target_enemy.global_position)
		var target_radius = 0.0
		if target_enemy.is_in_group("building"): target_radius = 250.0
		var effective_dist = dist - target_radius
		
		if unit_type == UnitType.MELEE:
			var vec = target_enemy.global_position - global_position
			desired_velocity = vec.normalized() * base_speed
		else:
			var threshold = attack_range * engagement_variance
			
			# SHIELD PENETRATION LOGIC
			var shield = _get_protecting_shield(target_enemy)
			if shield:
				threshold = 600.0 
			
			if effective_dist <= threshold:
				# STOP.
				desired_velocity = Vector2.ZERO
			else:
				var vec = target_enemy.global_position - global_position
				desired_velocity = vec.normalized() * base_speed
	
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
		
		if distance > 2.0:
			var speed_mult = 1.0
			if distance > 60.0: speed_mult = 1.2
			desired_velocity = vector_to_target.normalized() * base_speed * speed_mult
	
	# 3. SEPARATION FORCE
	if recoil_velocity.length() < 10.0:
		var separation = _calculate_separation_force()
		desired_velocity += separation * 250.0 

	velocity = desired_velocity + recoil_velocity
	move_and_slide()

func _calculate_separation_force() -> Vector2:
	var force = Vector2.ZERO
	var neighbor_count = 0
	var separation_radius = 75.0 
	
	var units = get_tree().get_nodes_in_group("unit")
	
	for unit in units:
		if unit == self: continue
		if unit.faction != faction: continue 
		
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
	current_hp -= amount
	if current_hp <= 0:
		queue_free()
