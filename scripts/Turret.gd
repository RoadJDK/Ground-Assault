extends Building

# --- CONFIGURATION ---
@export_group("Machine Gun")
@export var mg_damage: int = 20
@export var mg_range: float = 2500.0
@export var mg_cooldown: float = 2.0
@export var mg_speed: float = 1500.0
@export var shots_per_burst: int = 12 
@export var burst_delay: float = 0.1

@export_group("Howitzer")
@export var how_damage: int = 10
@export var how_range: float = 6000.0
@export var how_cooldown: float = 6.0 
@export var how_speed: float = 625.0 
@export var how_explosion_radius: float = 200.0 # New Config for Howitzer AOE

const PROJ_MG_SCENE = preload("res://scenes/Projectiles/ProjectileMG.tscn")
const PROJ_HOW_SCENE = preload("res://scenes/Projectiles/ProjectileHowitzer.tscn")

var target_unit: Node2D = null
var target_building: Node2D = null
var timer_mg: float = 0.0
var timer_how: float = 0.0
var is_firing_burst: bool = false

@onready var head: Node2D = $Head
@onready var muzzle_mg: Marker2D = $Head/MuzzleMG
@onready var muzzle_how: Marker2D = $Head/MuzzleHowitzer

func _process(delta: float) -> void:
	if timer_mg > 0: timer_mg -= delta
	if timer_how > 0: timer_how -= delta
	
	_find_nearest_unit()
	_find_nearest_building()
	
	var aim_pos = Vector2.ZERO
	if is_instance_valid(target_unit):
		aim_pos = _get_predicted_position(target_unit, mg_speed)
	elif is_instance_valid(target_building):
		aim_pos = target_building.global_position
	
	if aim_pos != Vector2.ZERO:
		head.look_at(aim_pos)
	
	if is_instance_valid(target_unit) and timer_mg <= 0 and not is_firing_burst:
		_fire_mg_burst()
		
	if is_instance_valid(target_building) and timer_how <= 0:
		_fire_howitzer()

func _get_predicted_position(target: Node2D, bullet_speed: float) -> Vector2:
	# 1. Initial guess
	var dist = global_position.distance_to(target.global_position)
	var time_to_hit = dist / bullet_speed
	
	# 2. Iterative refinement (3 passes)
	for i in range(3):
		var predicted_pos = target.global_position
		if "velocity" in target:
			predicted_pos += target.velocity * time_to_hit
		
		dist = global_position.distance_to(predicted_pos)
		time_to_hit = dist / bullet_speed
	
	# 3. Final Calculation
	if "velocity" in target:
		return target.global_position + (target.velocity * time_to_hit)
	return target.global_position

func _find_nearest_unit() -> void:
	var units = get_tree().get_nodes_in_group("unit")
	var nearest: Node2D = null
	var min_dist = mg_range
	for unit in units:
		# Player targeting enabled again
		
		if "faction" in unit and unit.faction == self.faction:
			continue
		var dist = global_position.distance_to(unit.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = unit
	target_unit = nearest

func _find_nearest_building() -> void:
	var buildings = get_tree().get_nodes_in_group("building")
	var candidates = []
	
	# 1. Filter valid targets
	for b in buildings:
		if b == self: continue
		if "faction" in b and b.faction == self.faction: continue
		if b.faction == "neutral": continue
		
		var dist = global_position.distance_to(b.global_position)
		if dist <= how_range:
			candidates.append(b)
	
	if candidates.is_empty():
		target_building = null
		return
		
	# 2. Sort/Prioritize: Unshielded > Shielded, then by Distance
	var best_target: Node2D = null
	var best_dist: float = 999999.0
	var best_is_shielded: bool = true
	
	for b in candidates:
		var dist = global_position.distance_to(b.global_position)
		var is_shielded = _is_building_shielded(b)
		
		if best_target == null:
			best_target = b
			best_dist = dist
			best_is_shielded = is_shielded
			continue
		
		if not is_shielded and best_is_shielded:
			best_target = b
			best_dist = dist
			best_is_shielded = false
			continue
			
		if is_shielded == best_is_shielded:
			if dist < best_dist:
				best_target = b
				best_dist = dist
				best_is_shielded = is_shielded
	
	target_building = best_target

func _is_building_shielded(target: Node2D) -> bool:
	var shields = get_tree().get_nodes_in_group("shield")
	for s in shields:
		if s.faction == target.faction:
			var dist = s.global_position.distance_to(target.global_position)
			if dist < 1000.0:
				return true
	return false

func _fire_mg_burst() -> void:
	is_firing_burst = true
	for i in range(shots_per_burst):
		if not is_instance_valid(target_unit): break
		var spread_angle = randf_range(-0.05, 0.05)
		var fire_rot = head.rotation + spread_angle
		# MG Radius = 0
		_spawn_projectile(PROJ_MG_SCENE, muzzle_mg, mg_damage, mg_speed, "unit", fire_rot, 0.0)
		await get_tree().create_timer(burst_delay).timeout
	timer_mg = mg_cooldown
	is_firing_burst = false

func _fire_howitzer() -> void:
	timer_how = how_cooldown
	var fire_rot = head.rotation
	if is_instance_valid(target_building):
		fire_rot = (target_building.global_position - global_position).angle()
	# Howitzer Radius passed here
	_spawn_projectile(PROJ_HOW_SCENE, muzzle_how, how_damage, how_speed, "building", fire_rot, how_explosion_radius)

func _spawn_projectile(scene, muzzle, dmg, speed, group, rotation_override, radius) -> void:
	var proj = scene.instantiate()
	get_tree().root.add_child(proj)
	proj.global_position = muzzle.global_position
	proj.rotation = rotation_override
	# Self is passed as shooter, so Projectile.gd will read self.faction
	proj.setup(dmg, speed, group, self, radius)
