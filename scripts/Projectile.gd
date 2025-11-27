extends Area2D

var damage: int = 0
var speed: float = 0.0
var target_group: String = ""
var shooter: Node2D = null 
var life_timer: float = 20.0
var explosion_radius: float = 0.0

var _exploded: bool = false

@export var collide_with_walls: bool = true 

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_mask = 1 + 2 + 4 + 8 + 16 # Added layer 16 for obstacles? Or rely on physics mask.
	z_index = 50 
	
func setup(dmg: int, spd: float, group: String, source_node: Node2D = null, radius: float = 0.0) -> void:
	damage = dmg
	speed = spd
	target_group = group
	shooter = source_node
	explosion_radius = radius
	add_to_group("projectile")

func _physics_process(delta: float) -> void:
	if _exploded: return

	var direction = Vector2.RIGHT.rotated(rotation)
	position += direction * speed * delta
	
	# Bounds Check
	if global_position.x < -6500 or global_position.x > 6500 or global_position.y < -4000 or global_position.y > 4000:
		queue_free()
		return
	
	life_timer -= delta
	if life_timer <= 0:
		if GameManager.is_multiplayer:
			if is_multiplayer_authority():
				queue_free()
		else:
			queue_free()

func _on_body_entered(body: Node) -> void:
	if _exploded: return
	
	if _is_valid_target(body):
		_trigger_impact(body)
	elif collide_with_walls:
		if body is TileMap or body is StaticBody2D or body.is_in_group("obstacle"):
			_trigger_impact(null)

func _on_area_entered(area: Node) -> void:
	if _exploded: return

	var candidate = area
	var max_depth = 4
	
	while candidate and max_depth > 0:
		if _is_valid_target(candidate):
			_trigger_impact(candidate)
			return
		candidate = candidate.get_parent()
		max_depth -= 1

func _is_valid_target(node: Node) -> bool:
	if not node: return false
	if node == shooter: return false
	if node.is_in_group("projectile"): return false
	
	# Allow "all" to hit anything (that isn't excluded by other rules)
	if target_group != "all":
		if not node.is_in_group(target_group): return false
	
	# Friendly Fire Check
	if shooter and "faction" in shooter and "faction" in node:
		if shooter.faction == node.faction:
			return false
	
	if not node.has_method("take_damage"): return false
	
	return true

func _trigger_impact(direct_hit_target: Node) -> void:
	if explosion_radius > 0:
		_explode()
	else:
		# Only deal damage if we own the shooter (or it's singleplayer)
		if _should_deal_damage():
			if direct_hit_target:
				var final_damage = damage
				# Bonus vs Shield for Rockets (Explosive) is handled in _explode, 
				# but if we wanted direct hit bonuses for others, we'd do it here.
				direct_hit_target.take_damage(final_damage)
			queue_free() # Only Authority deletes
		else:
			# Client visual hide
			hide()
			set_physics_process(false)
			set_deferred("monitoring", false)

func _explode() -> void:
	if _exploded: return
	_exploded = true
	
	# 1. Stop Movement & Collision
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# 2. Hide Visuals (Sprites)
	for child in get_children():
		if child is Node2D:
			child.hide()
	
	# 3. Deal Area Damage
	if _should_deal_damage():
		var potential_targets = get_tree().get_nodes_in_group(target_group)
		# Also check for Shields if they aren't in target_group "unit" or "building"
		var shields = get_tree().get_nodes_in_group("shield")
		potential_targets.append_array(shields)
		
		for t in potential_targets:
			if not is_instance_valid(t): continue
			
			# Friendly fire check
			if shooter and "faction" in shooter and "faction" in t:
				if shooter.faction == t.faction:
					continue
					
			var dist = global_position.distance_to(t.global_position)
			if dist <= explosion_radius:
				if t.has_method("take_damage"):
					var final_damage = damage
					# Bonus: Rockets (Explosive) vs Shields
					if t.is_in_group("shield") and explosion_radius > 0:
						final_damage *= 3
					
					t.take_damage(final_damage)
	
	# 4. Visual Feedback
	queue_redraw()
	
	# 5. Wait and Delete
	await get_tree().create_timer(0.2).timeout
	queue_free()

func _should_deal_damage() -> bool:
	if not GameManager.is_multiplayer: return true
	return is_multiplayer_authority()

func _draw() -> void:
	if _exploded and explosion_radius > 0:
		# Transparent red circle (Alpha 0.25 is roughly 1.5x more transparent than 0.4)
		draw_circle(Vector2.ZERO, explosion_radius, Color(1, 0, 0, 0.25))
