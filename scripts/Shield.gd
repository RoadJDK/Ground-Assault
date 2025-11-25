extends Building

const SHIELD_RADIUS = 2000.0

func _ready() -> void:
	super._ready()
	add_to_group("shield")
	
	# Ensure we have an Area to catch projectiles
	var dome = get_node_or_null("Dome")
	if dome:
		if not dome.area_entered.is_connected(_on_dome_area_entered):
			dome.area_entered.connect(_on_dome_area_entered)
		
		_update_shield_color(dome)

func _update_shield_color(dome_node: Node) -> void:
	var col = Color(1, 1, 1, 0.3) # Default white transparent
	
	match faction:
		"blue": col = Color(0.3, 0.6, 1.0, 0.3)
		"red": col = Color(1.0, 0.4, 0.4, 0.3)
	
	for child in dome_node.get_children():
		if child is ColorRect:
			child.color = col
		elif child is Sprite2D:
			child.modulate = col

func _on_dome_area_entered(area: Node) -> void:
	if area.is_in_group("projectile"):
		# Check projectile logic
		if "shooter" in area and is_instance_valid(area.shooter):
			# If projectile comes from an enemy, destroy it
			if "faction" in area.shooter and area.shooter.faction != self.faction:
				area.queue_free()
