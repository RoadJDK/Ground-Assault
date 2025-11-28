extends Area2D

var damage: int = 0
var speed: float = 0.0
var target_group: String = ""
var shooter: Node2D = null 
var life_timer: float = 20.0
var explosion_radius: float = 0.0

var _exploded: bool = false
var _faction_color: Color = Color(1.5, 1.5, 0.5) # Default Yellow (HDR)
var _visual_radius: float = 0.0

@export var collide_with_walls: bool = true 

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_mask = 1 + 2 + 4 + 8 + 16 
	z_index = 50 
	
func setup(dmg: int, spd: float, group: String, source_node: Node2D = null, radius: float = 0.0) -> void:
	damage = dmg
	speed = spd
	target_group = group
	shooter = source_node
	explosion_radius = radius
	add_to_group("projectile")
	
	# Colorize based on shooter faction
	if is_instance_valid(shooter) and "faction" in shooter:
		if shooter.faction == "blue": 
			_faction_color = Color(0.5, 0.5, 2.5) # Blue (HDR)
		elif shooter.faction == "red": 
			_faction_color = Color(2.5, 0.5, 0.5) # Red (HDR)
	
	modulate = _faction_color

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
	# Always explode visually on impact
	_explode(direct_hit_target)

func _explode(direct_hit_target: Node = null) -> void:
	if _exploded: return
	_exploded = true
	
	# Determine Visual Radius (Small for MG, Large for Explosives)
	if explosion_radius > 0:
		_visual_radius = explosion_radius
	else:
		_visual_radius = 15.0 # Small default for impact
		
	# Play SFX based on "Impact Size" not just existence of radius
	# Ranged Units have radius 15.0 -> Should be MG sound
	# Howitzer/Rocket have radius > 100.0 -> Should be Howitzer sound
	if SFXManager:
		if explosion_radius > 50.0:
			SFXManager.play_hit_howitzer(global_position)
		else:
			SFXManager.play_hit_mg(global_position)
	
	# 1. Stop Movement & Collision
	set_physics_process(false)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# 2. Hide Visuals (Sprites)
	for child in get_children():
		if child is Node2D:
			child.hide()
	
	# 3. Deal Damage
	if _should_deal_damage():
		# Determine Source Type
		var source_type = ""
		if is_instance_valid(shooter):
			if shooter.is_in_group("turret") or shooter.name.contains("Turret"):
				source_type = "turret"
			elif shooter.is_in_group("unit"):
				source_type = "unit"

		# Direct Hit Logic
		if direct_hit_target and direct_hit_target.has_method("take_damage"):
			var final_damage = damage
			# Pass source_type to take_damage
			# Check if function supports it (Player has it, others might not)
			# We use call() or check param count?
			# GDScript supports optional args, so passing it is safe IF defined.
			# BUT if target is Building or Troop, they might not have the updated signature.
			# To be safe, we should update Troop/Building signatures too OR use call mechanism?
			# No, simpler: just try calling with 2 args, if fail, call with 1?
			# Actually, simpler: Update Troop.gd/Building.gd to accept it (ignoring it).
			# Player.gd is updated.
			
			# Dynamic call attempt:
			_safe_deal_damage(direct_hit_target, final_damage, source_type)

		# Area Damage Logic (Only if actually explosive)
		if explosion_radius > 0:
			var potential_targets = get_tree().get_nodes_in_group(target_group)
			var shields = get_tree().get_nodes_in_group("shield")
			potential_targets.append_array(shields)
			
			for t in potential_targets:
				if not is_instance_valid(t): continue
				if t == direct_hit_target: continue # Don't double hit
				
				# Friendly fire check
				if shooter and "faction" in shooter and "faction" in t:
					if shooter.faction == t.faction:
						continue
						
				var dist = global_position.distance_to(t.global_position)
				if dist <= explosion_radius:
					var final_damage = damage
					if t.is_in_group("shield"): final_damage *= 3
					_safe_deal_damage(t, final_damage, source_type)
	
	# 4. Visual Feedback
	queue_redraw()
	
	# 5. Wait and Delete
	await get_tree().create_timer(0.2).timeout
	queue_free()

func _safe_deal_damage(target: Node, amount: int, source: String) -> void:
	if not target.has_method("take_damage"): return
	
	# Using call is risky if method signature doesn't match.
	# Safe bet: Most targets (Troop, Building) only accept 1 arg.
	# Player accepts 2.
	if target.has_method("take_damage") and target.get_script().source_code.contains("take_damage(amount: int, source_type"):
		target.take_damage(amount, source)
	else:
		target.take_damage(amount)


func _should_deal_damage() -> bool:
	if not GameManager.is_multiplayer: return true
	return is_multiplayer_authority()

func _draw() -> void:
	if _exploded and _visual_radius > 0:
		# Use Faction Color with transparency
		var draw_col = _faction_color
		draw_col.a = 0.25
		draw_circle(Vector2.ZERO, _visual_radius, draw_col)
