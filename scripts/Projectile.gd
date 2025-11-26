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
# ...
func _trigger_impact(direct_hit_target: Node) -> void:
	if explosion_radius > 0:
		_explode()
	else:
		# Only deal damage if we own the shooter (or it's singleplayer)
		if _should_deal_damage():
			if direct_hit_target:
				direct_hit_target.take_damage(damage)
			queue_free() # Only Authority deletes
		else:
			# Client visual hide
			hide()
			set_physics_process(false)
			set_deferred("monitoring", false)

func _should_deal_damage() -> bool:
	if not GameManager.is_multiplayer: return true
	return is_multiplayer_authority()

func _draw() -> void:
	if _exploded and explosion_radius > 0:
		# Transparent red circle (Alpha 0.25 is roughly 1.5x more transparent than 0.4)
		draw_circle(Vector2.ZERO, explosion_radius, Color(1, 0, 0, 0.25))
