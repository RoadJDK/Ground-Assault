extends CharacterBody2D

@export var speed: float = 600.0
@export var sprint_speed: float = 1200.0

const PROJ_MG_SCENE = preload("res://scenes/Projectiles/ProjectileMG.tscn")

# Map Limits (Keep for Player clamping)
const LIMIT_LEFT: float = -12251.0
const LIMIT_TOP: float = -6666.0
const LIMIT_RIGHT: float = 12293.0 
const LIMIT_BOTTOM: float = 6650.0 

var is_active: bool = true
var is_ai_controlled: bool = false
var ai_input_vector: Vector2 = Vector2.ZERO
var ai_nav_target: Vector2 = Vector2.ZERO # New: For pathfinding
var ai_sprint: bool = false
var ai_shoot_requested: bool = false

var camera: Camera2D = null
var visual_node: CanvasItem = null # Deprecated
var weapon_node = null 
var muzzle_node: Node2D = null

# Visuals
var sprite_blue: Sprite2D = null
var sprite_red: Sprite2D = null
var particles_node: CPUParticles2D = null

# HP & Faction
var max_hp: int = 450
var current_hp: int = 450
var faction: String = "neutral":
	set(value):
		faction = value
		_update_faction_visuals()

# Weapon Stats
var mg_damage: int = 3
var mg_speed: float = 1500.0
var mg_cooldown: float = 0.066 # 1.5x faster (was 0.1)
var mg_timer: float = 0.0

# Range Indicator
var _show_range_timer: float = 0.0
var _range_radius: float = 1000.0

# INTERACTION STATE
var is_hovering_interactive: bool = false

# COMMANDING
var commanded_squads: Array = []
var is_commanding_squads: bool = false

var nav_agent: NavigationAgent2D = null

# DEBUG VISUALS
var ai_debug_target_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("unit")
	
	# Find Visuals
	sprite_blue = find_child("Blue", true, false)
	sprite_red = find_child("Red", true, false)
	particles_node = find_child("Particles", true, false)
			
	# Find Camera
	camera = find_child("Camera2D", true, false)
	
	# Find Weapon parts
	weapon_node = find_child("Weapon", true, false)
	muzzle_node = find_child("Muzzle", true, false)
	
	# Create NavigationAgent if not present (since it's not in the scene file yet)
	if not has_node("NavigationAgent2D"):
		nav_agent = NavigationAgent2D.new()
		nav_agent.name = "NavigationAgent2D"
		add_child(nav_agent)
		# Configure agent
		nav_agent.path_desired_distance = 20.0
		nav_agent.target_desired_distance = 20.0
		nav_agent.radius = 30.0
		nav_agent.max_speed = sprint_speed # Set max speed to sprint speed so it doesn't cap lower
		nav_agent.avoidance_enabled = true
		nav_agent.velocity_computed.connect(_on_velocity_computed)
	else:
		nav_agent = $NavigationAgent2D
		nav_agent.max_speed = sprint_speed # Ensure existing agent also has high max speed
		
	current_hp = max_hp
	
	# Initial Visual Update
	_update_faction_visuals()
	
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
		
		# Sync Weapon Rotation if it exists (Deprecated: We sync Player rotation now)
		# But keep for compatibility if needed
			
		sync.replication_config = config

func _update_faction_visuals() -> void:
	if not is_node_ready(): return
	
	if sprite_blue: sprite_blue.visible = (faction == "blue")
	if sprite_red: sprite_red.visible = (faction == "red")

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	if is_ai_controlled:
		velocity = safe_velocity
		move_and_slide()

func _physics_process(delta: float) -> void:
	# Dead check (Prevent Zombie AI)
	if current_hp <= 0:
		velocity = Vector2.ZERO
		_update_particles(false)
		return

	# Cooldown Management (Runs on all peers)
	if mg_timer > 0:
		mg_timer -= delta

	if GameManager.is_multiplayer:
		if not is_multiplayer_authority():
			# We are a remote puppet. 
			# Still update particles for visuals based on velocity?
			_update_particles(velocity.length() > 10.0)
			return 

	if _show_range_timer > 0:
		_show_range_timer -= delta
		queue_redraw()

	# Clamp Player Position (Dynamic from NavigationRegion if available)
	var limit_left = LIMIT_LEFT
	var limit_right = LIMIT_RIGHT
	var limit_top = LIMIT_TOP
	var limit_bottom = LIMIT_BOTTOM
	
	var nav_region = get_tree().root.find_child("NavigationRegion2D", true, false)
	if nav_region and nav_region.navigation_polygon:
		# FIX: Calculate bounds from outlines since get_polygon needs an index and returns indices
		var poly = nav_region.navigation_polygon
		var count = poly.get_outline_count()
		if count > 0:
			var outline = poly.get_outline(0) # Use the first outline (usually the main one)
			if not outline.is_empty():
				var r = Rect2(outline[0], Vector2.ZERO)
				for pt in outline:
					r = r.expand(pt)
				
				limit_left = r.position.x
				limit_top = r.position.y
				limit_right = r.end.x
				limit_bottom = r.end.y

	var margin = 50.0
	position.x = clamp(position.x, limit_left + margin, limit_right - margin)
	position.y = clamp(position.y, limit_top + margin, limit_bottom - margin)

	# Input Handling
	var direction = Vector2.ZERO
	var current_speed = speed
	
	# Inertia Settings
	var accel = 10000.0
	var friction = 1000.0
	
	if is_ai_controlled:
		if ai_sprint:
			current_speed = sprint_speed
		
		# AI Pathfinding Logic
		if ai_nav_target != Vector2.ZERO:
			nav_agent.target_position = ai_nav_target
			
			# Update Agent Speed
			nav_agent.max_speed = current_speed
			
			if not nav_agent.is_navigation_finished():
				var next_path_pos = nav_agent.get_next_path_position()
				var target_vel = global_position.direction_to(next_path_pos) * current_speed
				
				if nav_agent.avoidance_enabled:
					nav_agent.set_velocity(target_vel)
					# Movement happens in _on_velocity_computed
				else:
					# Apply Inertia to AI
					velocity = velocity.move_toward(target_vel, accel * delta)
					move_and_slide()
			else:
				# Stop with friction
				velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
				move_and_slide()
		else:
			# Fallback to direct vector if no nav target (or stopped)
			var target_vel = ai_input_vector * current_speed
			velocity = velocity.move_toward(target_vel, accel * delta)
			move_and_slide()

		if ai_shoot_requested:
			_shoot_mg()
			ai_shoot_requested = false 
			
	elif is_active:
		# Rotate Player to Mouse (Whole Ship)
		var mouse_pos = get_global_mouse_position()
		var target_angle = (mouse_pos - global_position).angle()
		# Smooth rotation? For now instant to match mouse feel
		rotation = target_angle

		# Shooting
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_shoot_mg()
			
		# Spacebar Zoom Toggle
		if Input.is_action_just_pressed("ui_select"): # Spacebar
			if camera and camera.has_method("toggle_overview"):
				camera.toggle_overview()
			
		# COMMANDING INPUTS
		if Input.is_action_just_pressed("command_squads"):
			_start_commanding()
		elif Input.is_action_just_pressed("release_squads"):
			_stop_commanding()

		if Input.is_key_pressed(KEY_SHIFT):
			current_speed = sprint_speed
		
		# Movement (Allowed in both Close and Tactical views)
		direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		
		if direction:
			var target_vel = direction * current_speed
			var apply_accel = accel
			# TURN BOOST: If turning against momentum, accelerate much faster
			if velocity.dot(direction) < 0:
				apply_accel = accel * 3.0
				
			velocity = velocity.move_toward(target_vel, apply_accel * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

		move_and_slide()
	else:
		# Not active and not AI -> Freeze (or drift to stop)
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		move_and_slide()
		_update_particles(0.0)
		return

	# Update Particles
	_update_particles(velocity.length())
	
	# Update Debug Visuals
	if ai_debug_target_pos != Vector2.ZERO:
		queue_redraw()

func _start_commanding() -> void:
	# Removed "if is_commanding_squads: return" to allow adding more squads
	
	# Safer: Find children of the main UnitContainer
	var unit_container = get_tree().root.find_child("UnitContainer", true, false)
	if not unit_container:
		print("UnitContainer not found!")
		return
		
	# Use the same radius as the visual indicator
	var collection_range = _range_radius
	var added_count = 0
	
	for child in unit_container.get_children():
		if child.has_method("enter_command_mode"):
			if "faction" in child and child.faction == faction:
				# Check if already commanded to avoid duplicates
				if child in commanded_squads:
					continue
					
				if global_position.distance_to(child.global_position) <= collection_range:
					child.enter_command_mode(self)
					commanded_squads.append(child)
					added_count += 1
	
	if added_count > 0:
		is_commanding_squads = true
		print("Commanded +", added_count, " new squads. Total: ", commanded_squads.size())
	elif commanded_squads.size() > 0:
		print("No new squads found. Maintaining command of ", commanded_squads.size())
	else:
		print("No squads in range.")
		
	# Always show indicator to provide feedback
	show_range_indicator()

func _stop_commanding() -> void:
	if not is_commanding_squads: return
	
	for squad in commanded_squads:
		if is_instance_valid(squad):
			squad.exit_command_mode()
	
	commanded_squads.clear()
	is_commanding_squads = false
	print("Released squads.")

func show_range_indicator() -> void:
	_show_range_timer = 0.05
	queue_redraw()

func _draw() -> void:
	# Range Indicator
	if _show_range_timer > 0:
		var col = Color(0, 1, 0, 0.8) if is_commanding_squads else Color(1, 0, 0, 0.8)
		draw_arc(Vector2.ZERO, _range_radius, 0, TAU, 64, col, 3.0, true)
	
	# HP Bar
	if current_hp < max_hp:
		var bar_width = 135.0
		var bar_height = 14.0
		var y_offset = -100.0
		
		# Background
		draw_rect(Rect2(-bar_width/2, y_offset, bar_width, bar_height), Color(0, 0, 0, 0.6))
		
		# Foreground Color
		var hp_col = Color(0.2, 0.8, 0.2) # Default Green
		if faction == "blue": hp_col = Color(0.3, 0.6, 1.0)
		elif faction == "red": hp_col = Color(1.0, 0.4, 0.4)
		
		# Fill
		var fill_pct = float(current_hp) / float(max_hp)
		draw_rect(Rect2(-bar_width/2, y_offset, bar_width * fill_pct, bar_height), hp_col)
		
		# Border
		draw_rect(Rect2(-bar_width/2, y_offset, bar_width, bar_height), Color.BLACK, false, 1.0)

	# AI Debug Path
	if ai_debug_target_pos != Vector2.ZERO:
		var target_local = to_local(ai_debug_target_pos)
		draw_line(Vector2.ZERO, target_local, Color.MAGENTA, 2.0)
		draw_circle(target_local, 10.0, Color.MAGENTA)

func _unhandled_input(_event: InputEvent) -> void:
	pass # Delegate all camera inputs to CameraControl

func _shoot_mg() -> void:
	# Prevent shooting if interacting with UI/Plots
	if is_hovering_interactive: return

	# Prevent RPC spam by checking locally first
	if mg_timer > 0: return

	if GameManager.is_multiplayer:
		rpc("shoot_mg_action")
	else:
		shoot_mg_action()

@rpc("call_local")
func shoot_mg_action() -> void:
	if mg_timer > 0: return
	
	var in_overview = false
	if camera and "is_overview_mode" in camera:
		in_overview = camera.is_overview_mode
	
	# Close View Benefit: Active unless in Spacebar-Overview mode
	var is_close_view = !in_overview
	
	# Close View Benefit: 1.5x Fire Rate (0.66 multiplier)
	mg_timer = mg_cooldown
	if is_close_view:
		mg_timer *= 0.66
	
	var spawn_pos = global_position
	var spawn_rot = rotation
	
	if muzzle_node:
		spawn_pos = muzzle_node.global_position
		spawn_rot = muzzle_node.global_rotation
	elif weapon_node:
		if weapon_node is Node2D:
			spawn_pos = weapon_node.global_position
			spawn_rot = weapon_node.global_rotation
		else:
			# Control Node fallback (e.g. ColorRect)
			spawn_pos = weapon_node.global_position
			# Use Player rotation for Controls attached to Player
			spawn_rot = rotation
	else:
		spawn_rot = (get_global_mouse_position() - global_position).angle()
	
	# Dynamic Spread
	if not is_close_view: # Close View Benefit: Reduced Spread (not zero)
		var spread_amount = 0.05 # Base spread
		if velocity.length() > 10.0:
			spread_amount = 0.1 # Moving spread
			spawn_pos += Vector2(randf_range(-5, 5), randf_range(-5, 5))
			
		spawn_rot += randf_range(-spread_amount, spread_amount)
	else:
		# Tiny spread for "alive" feel in Close View
		spawn_rot += randf_range(-0.02, 0.02)
		
		# Add Screenshake for feedback
		if camera and camera.has_method("add_trauma"):
			camera.add_trauma(0.03)
			
	# Play SFX
	if SFXManager:
		var extra_vol = 0.0
		# Dampen player shot if camera is zoomed out in Detail Mode
		if camera:
			# Map zoom 0.35 -> -6.0dB, Zoom 1.0 -> 0.0dB
			var t = inverse_lerp(0.35, 1.0, camera.zoom.x)
			t = clamp(t, 0.0, 1.0)
			extra_vol = lerp(-6.0, 0.0, t)
			
		SFXManager.play_player_shot(global_position, extra_vol)
	
	# COMMAND SQUADS FIRE
	if is_commanding_squads:
		var aim_target = get_global_mouse_position()
		var squad_index = 0
		for squad in commanded_squads:
			if is_instance_valid(squad):
				# Sequential Firing: 0.5s delay between each squad
				var delay = squad_index * 0.5
				get_tree().create_timer(delay).timeout.connect(
					func(): if is_instance_valid(squad): squad.command_fire_at(aim_target)
				)
				squad_index += 1

	if GameManager.is_multiplayer:
		# Only the Server (Host) owns the ProjectileSpawner and can spawn networked objects
		if multiplayer.is_server():
			var spawner = get_tree().root.find_child("ProjectileSpawner", true, false)
			if spawner:
				var data = {
					"scene_path": "res://scenes/Projectiles/ProjectileMG.tscn",
					"pos": spawn_pos,
					"rot": spawn_rot,
					"dmg": mg_damage,
					"spd": mg_speed,
					"group": "all",
					"shooter_path": get_path(),
					"radius": 0.0
				}
				spawner.spawn(data)
	else:
		var proj = PROJ_MG_SCENE.instantiate()
		get_tree().root.add_child(proj)
		proj.global_position = spawn_pos
		proj.rotation = spawn_rot
		proj.setup(mg_damage, mg_speed, "all", self, 0.0)

func _update_particles(current_vel_mag: float) -> void:
	if particles_node:
		particles_node.emitting = current_vel_mag > 10.0
		var ratio = clamp(current_vel_mag / sprint_speed, 0.0, 1.0)
		particles_node.speed_scale = lerp(0.5, 2.0, ratio)

func set_faction(new_faction: String) -> void:
	faction = new_faction
	# Visual update handled by setter

func set_active(active: bool) -> void:
	# Local 'active' state for camera/input control
	is_active = active
	if camera:
		camera.enabled = active
		if active:
			camera.make_current()
			# Reset zoom via CameraControl
			if camera.has_method("toggle_overview") and camera.is_overview_mode:
				camera.toggle_overview()

func take_damage(amount: int, source_type: String = "") -> void:
	if GameManager.is_multiplayer:
		rpc("rpc_take_damage", amount, source_type)
	else:
		rpc_take_damage(amount, source_type)

@rpc("any_peer", "call_local")
func rpc_take_damage(amount: int, source_type: String = "") -> void:
	var final_amount = amount
	if source_type == "turret":
		final_amount = int(amount / 1.5)
		if final_amount < 1: final_amount = 1
	elif source_type == "player":
		final_amount *= 4
	
	current_hp -= final_amount
	print(name, " took ", final_amount, " damage (Source: ", source_type, ") | HP: ", current_hp)
	queue_redraw() # Update HP Bar
	
	# Visual Feedback
	if camera and camera.has_method("add_trauma"):
		# Shake based on damage amount (reduced intensity)
		var trauma = clamp(float(final_amount) / 30.0, 0.1, 0.25)
		camera.add_trauma(trauma)
	
	if current_hp <= 0:
		print(name, " DIED! Starting Respawn Sequence...")
		
		# Hide player visual/disable collision temporarily
		# Keep position WHERE THEY DIED to avoid camera jumping
		is_active = false
		visible = false
		
		# Disable collision so they aren't targeted or blocking
		set_collision_layer_value(1, false) # Assuming layer 1 is units
		set_collision_mask_value(1, false)
		
		# Remove from "unit" group so AI/Turrets stop targeting them
		if is_in_group("unit"):
			remove_from_group("unit")
		
		# Stop music on death
		var mm = get_tree().root.find_child("MusicManager", true, false)
		if mm and mm.has_method("on_player_death"):
			mm.on_player_death()
			
		# Start Respawn Sequence (Local only for UI, but logic runs on client owner)
		# Only show UI if THIS player is the one controlled by the local human
		var is_local_human = false
		if GameManager.is_multiplayer:
			if is_multiplayer_authority() and not is_ai_controlled:
				is_local_human = true
		else:
			# Singleplayer: if active and not AI (or if we are the main player)
			if is_active and not is_ai_controlled:
				is_local_human = true
			# If we just died, is_active was set to false above. Check control flag?
			# In singleplayer, there is only one human.
			if not is_ai_controlled:
				is_local_human = true

		if is_local_human:
			_start_respawn_sequence_ui()
		else:
			# Just timer, no UI
			_start_respawn_timer()

func _start_respawn_sequence_ui() -> void:
	var game_ui = get_tree().root.find_child("GameUI", true, false)
	if game_ui:
		game_ui.show_respawn_screen(10)
		
	for i in range(10, 0, -1):
		if game_ui: game_ui.update_respawn_timer(i)
		await get_tree().create_timer(1.0).timeout
		
	if game_ui:
		game_ui.hide_respawn_screen()
		
	_respawn_at_core()

func _start_respawn_timer() -> void:
	# Background timer for AI or remote players
	await get_tree().create_timer(10.0).timeout
	_respawn_at_core()

func _respawn_at_core() -> void:
	current_hp = max_hp
	visible = true
	
	# Re-enable collision
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	
	# Re-add to group for targeting
	if not is_in_group("unit"):
		add_to_group("unit")
	
	# Find Friendly Core
	var buildings = get_tree().get_nodes_in_group("building")
	var core_found = false
	
	for b in buildings:
		if "faction" in b and b.faction == faction:
			if b.is_in_group("core") or b.name.contains("Core"):
				global_position = b.global_position + Vector2(0, 200)
				core_found = true
				break
	
	if not core_found:
		# Fallback
		if faction == "blue":
			global_position = Vector2(LIMIT_LEFT + 1200.0, 0)
		elif faction == "red":
			global_position = Vector2(LIMIT_RIGHT - 1200.0, 0)
		else:
			global_position = Vector2.ZERO
			
	# Reset Camera if needed
	if camera and camera.is_overview_mode:
		camera.toggle_overview()

	# Re-enable controls if this is the local player (or AI)
	if not GameManager.is_multiplayer or is_multiplayer_authority():
		is_active = true
		# For AI
		if is_ai_controlled:
			is_active = false # Keep as false if AI, but ensure visible above handled it

	# Music Resume handled by MusicManager waiting for signal or timer?
	# MusicManager.on_player_death waits 1s then pauses.
	# We need to tell it to resume now.
	var mm = get_tree().root.find_child("MusicManager", true, false)
	if mm and mm.has_method("_resume_game_music"):
		mm._resume_game_music()

# --- AI HELPER METHODS ---
func ai_look_at(target_pos: Vector2) -> void:
	var target_angle = (target_pos - global_position).angle()
	rotation = target_angle

func ai_command_squads(active: bool) -> void:
	if active and not is_commanding_squads:
		_start_commanding()
	elif not active and is_commanding_squads:
		_stop_commanding()
