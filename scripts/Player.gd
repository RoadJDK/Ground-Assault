extends CharacterBody2D

@export var speed: float = 1200.0
@export var sprint_speed: float = 2400.0

# Zoom Settings
@export var min_zoom: float = 0.5
@export var max_zoom: float = 18.0
@export var zoom_step: float = 0.1

const PROJ_MG_SCENE = preload("res://scenes/Projectiles/ProjectileMG.tscn")

# Map Limits for Zoom Calculation
const LIMIT_LEFT: float = -6956.0
const LIMIT_TOP: float = -4622.0
const LIMIT_RIGHT: float = 6974.0 
const LIMIT_BOTTOM: float = 4699.0 

var is_active: bool = true
var camera: Camera2D = null
var visual_node: CanvasItem = null
var weapon_node = null # Untyped to support Node2D or Control (ColorRect)

# HP & Faction
var max_hp: int = 100
var current_hp: int = 100
var faction: String = "neutral"

# Weapon Stats
var mg_damage: int = 3
var mg_speed: float = 1500.0
var mg_cooldown: float = 0.066 # 1.5x faster (was 0.1)
var mg_timer: float = 0.0

# Camera State
var _target_zoom: Vector2 = Vector2.ONE
var _saved_zoom: Vector2 = Vector2.ONE
var _is_zoomed_out: bool = false

# Range Indicator
var _show_range_timer: float = 0.0
var _range_radius: float = 1000.0

func _ready() -> void:
	add_to_group("unit")
	current_hp = max_hp
	
	# --- NETWORKING ---
	if GameManager.is_multiplayer:
		var sync = MultiplayerSynchronizer.new()
		sync.name = "MultiplayerSynchronizer"
		sync.replication_interval = 0.016 # Roughly 60 times per second
		sync.delta_interval = 0.016
		add_child(sync)
		
		var config = SceneReplicationConfig.new()
		config.add_property("." + ":position")
		config.add_property("." + ":rotation")
		sync.replication_config = config
	
	# Find Camera
	camera = find_child("Camera2D", true, false)
	if camera:
		camera.position_smoothing_enabled = false # Disable built-in smoothing
		_target_zoom = camera.zoom
		_saved_zoom = camera.zoom
	
	# Find Visual (Sprite or ColorRect)
	for child in get_children():
		if child is Sprite2D or child is ColorRect or child is Polygon2D:
			visual_node = child
			break
			
	# Find Weapon
	weapon_node = find_child("Weapon", true, false)

func _physics_process(delta: float) -> void:
	if GameManager.is_multiplayer:
		if not is_multiplayer_authority():
			# We are a remote puppet. 
			# Position is synced automatically by MultiplayerSynchronizer.
			# We just ensure we don't override it with local physics or camera logic
			return 

	if _show_range_timer > 0:
		_show_range_timer -= delta
		queue_redraw()

	# Camera Smoothing
	if camera:
		var lerp_speed = 5.0
		
		# Zoom Smoothing
		if not is_equal_approx(camera.zoom.x, _target_zoom.x):
			var new_zoom = lerp(camera.zoom.x, _target_zoom.x, lerp_speed * delta)
			camera.zoom = Vector2(new_zoom, new_zoom)
			
		# Position Smoothing
		# If zoomed out, target is (0,0). If zoomed in, target is player (global_position).
		# We ALWAYS manage global_position when detached (top_level = true).
		if camera.top_level:
			var target_pos = Vector2.ZERO
			if not _is_zoomed_out:
				target_pos = global_position
			
			camera.global_position = camera.global_position.lerp(target_pos, lerp_speed * delta)
			
			# Re-attach when close to player
			if not _is_zoomed_out and camera.global_position.distance_to(target_pos) < 10.0 and is_equal_approx(camera.zoom.x, _target_zoom.x):
				camera.top_level = false
				camera.position = Vector2.ZERO

	if mg_timer > 0:
		mg_timer -= delta
		
	# Clamp Player Position (with margin)
	var margin = 100.0
	position.x = clamp(position.x, LIMIT_LEFT + margin, LIMIT_RIGHT - margin)
	position.y = clamp(position.y, LIMIT_TOP + margin, LIMIT_BOTTOM - margin)

	if not is_active:
		velocity = Vector2.ZERO
		move_and_slide()
		return
		
	# Rotate Weapon to Mouse
	if weapon_node:
		var mouse_pos = get_global_mouse_position()
		if weapon_node is Node2D:
			weapon_node.look_at(mouse_pos)
		elif weapon_node is Control:
			weapon_node.rotation = (mouse_pos - weapon_node.global_position).angle()

	# Shooting
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_shoot_mg()
		
	# Spacebar Zoom Toggle
	if Input.is_action_just_pressed("ui_select"): # Spacebar
		_toggle_zoom_out()

	var current_speed = speed
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed = sprint_speed
	
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction:
		velocity = direction * current_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	
func show_range_indicator() -> void:
	_show_range_timer = 0.05
	queue_redraw()

func _draw() -> void:
	if _show_range_timer > 0:
		# Static Red Outline (No fade, 0.05s duration)
		draw_arc(Vector2.ZERO, _range_radius, 0, TAU, 64, Color(1, 0, 0, 0.8), 3.0)

func _unhandled_input(event: InputEvent) -> void:
	if not is_active: return
	
	if GameManager.is_multiplayer and not is_multiplayer_authority():
		return # Ignore inputs if not mine

	if event is InputEventMouseButton:
		if _is_zoomed_out:
			# Only allow zooming IN (which exits overview)
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_toggle_zoom_out()
			return
			
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(-zoom_step)

func _change_zoom(amount: float) -> void:
	# If zoomed out, ignore manual zoom or reset?
	# Let's allow manual zoom only when NOT in overview mode, or switch back to player mode.
	if _is_zoomed_out:
		_toggle_zoom_out() # Switch back to player
		return
	
	var new_val = _saved_zoom.x + amount
	new_val = clamp(new_val, min_zoom, max_zoom)
	_saved_zoom = Vector2(new_val, new_val)
	_target_zoom = _saved_zoom

func _toggle_zoom_out() -> void:
	if not camera: return
	
	if _is_zoomed_out:
		# Zoom IN (Restore to Player)
		_is_zoomed_out = false
		_target_zoom = _saved_zoom
		# Keep top_level = true until it moves back to player (handled in process)
	else:
		# Zoom OUT (Battlefield Center)
		_is_zoomed_out = true
		_saved_zoom = camera.zoom # Save current before flying out
		
		# Important: Set top_level true AND update position to match player immediately
		# This prevents the "jump" from (0,0) if it wasn't detached
		if not camera.top_level:
			camera.top_level = true 
			camera.global_position = global_position
		
		# Calculate needed zoom to see map
		var vp_size = get_viewport_rect().size
		var map_w = LIMIT_RIGHT - LIMIT_LEFT
		var map_h = LIMIT_BOTTOM - LIMIT_TOP
		var required_zoom = max(vp_size.x / map_w, vp_size.y / map_h)
		
		# Ensure we don't zoom in if the map is smaller than screen (unlikely)
		# And apply some margin (0.9 factor)
		required_zoom = min(required_zoom, 1.0) * 0.9
		
		_target_zoom = Vector2(required_zoom, required_zoom)

func _shoot_mg() -> void:
	if GameManager.is_multiplayer:
		rpc("shoot_mg_action")
	else:
		shoot_mg_action()

@rpc("call_local")
func shoot_mg_action() -> void:
	if mg_timer > 0: return
	
	mg_timer = mg_cooldown
	
	var spawn_pos = global_position
	var spawn_rot = 0.0
	
	if weapon_node:
		spawn_rot = weapon_node.rotation
		var muzzle = weapon_node.find_child("Muzzle", true, false)
		if muzzle:
			spawn_pos = muzzle.global_position
		else:
			spawn_pos = weapon_node.global_position
	else:
		spawn_rot = (get_global_mouse_position() - global_position).angle()
	
	# Dynamic Spread
	var spread_amount = 0.05 # Base spread
	if velocity.length() > 10.0:
		spread_amount = 0.1 # Moving spread
		# Add position jitter when moving for "bullet stream" feel
		spawn_pos += Vector2(randf_range(-5, 5), randf_range(-5, 5))
		
	spawn_rot += randf_range(-spread_amount, spread_amount)
	
	var proj = PROJ_MG_SCENE.instantiate()
	
	var container = get_tree().root.find_child("ProjectileContainer", true, false)
	if container:
		container.add_child(proj)
	else:
		get_tree().root.add_child(proj) # Fallback

	proj.global_position = spawn_pos
	proj.rotation = spawn_rot
	
	# Target "all" to hit both units and buildings (handled by modified Projectile.gd)
	proj.setup(mg_damage, mg_speed, "all", self, 0.0)

func set_faction(new_faction: String) -> void:
	faction = new_faction
	if not visual_node: return
	
	match faction:
		"blue": visual_node.modulate = Color(0.4, 0.4, 1.0)
		"red": visual_node.modulate = Color(1.0, 0.4, 0.4)
		_: visual_node.modulate = Color.WHITE

func set_active(active: bool) -> void:
	# Local 'active' state for camera/input control
	# In multiplayer, we also check authority, but this handles the camera switching logic
	is_active = active
	if camera:
		camera.enabled = active
		if active:
			camera.make_current()
			# Reset zoom to saved user preference or default
			if not _is_zoomed_out:
				_target_zoom = _saved_zoom
				camera.zoom = _target_zoom

func take_damage(amount: int) -> void:
	if GameManager.is_multiplayer:
		rpc("rpc_take_damage", amount)
	else:
		rpc_take_damage(amount)

@rpc("any_peer", "call_local")
func rpc_take_damage(amount: int) -> void:
	current_hp -= amount
	print(name, " took damage: ", amount, " | HP: ", current_hp)
	
	if current_hp <= 0:
		print(name, " DIED! Respawning at Core...")
		_respawn_at_core()

func _respawn_at_core() -> void:
	current_hp = max_hp
	
	# Find Friendly Core
	var buildings = get_tree().get_nodes_in_group("building")
	var core_found = false
	
	for b in buildings:
		if "faction" in b and b.faction == faction:
			if b.is_in_group("core") or b.name.contains("Core"): # Assuming Core scene is named or grouped
				global_position = b.global_position + Vector2(0, 200)
				core_found = true
				break
	
	if not core_found:
		# Fallback if no core (shouldn't happen in normal gameplay)
		if faction == "blue":
			global_position = Vector2(LIMIT_LEFT + 1200.0, 0)
		elif faction == "red":
			global_position = Vector2(LIMIT_RIGHT - 1200.0, 0)
		else:
			global_position = Vector2.ZERO
			
	# Reset Camera if needed
	if _is_zoomed_out:
		_toggle_zoom_out() # Snap back to player view
