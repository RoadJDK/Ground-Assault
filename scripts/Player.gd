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
var camera: Camera2D = null
var visual_node: CanvasItem = null
var weapon_node = null # Untyped to support Node2D or Control (ColorRect)

# HP & Faction
var max_hp: int = 450
var current_hp: int = 450
var faction: String = "neutral"

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
		
		# Sync Weapon Rotation if it exists
		var w = find_child("Weapon", true, false)
		if w:
			# Use relative path from Player root
			var w_path = str(self.get_path_to(w))
			config.add_property(w_path + ":rotation")
			
		sync.replication_config = config
	
	# Find Camera
	camera = find_child("Camera2D", true, false)
	
	# Find Visual (Sprite or ColorRect)
	for child in get_children():
		if child is Sprite2D or child is ColorRect or child is Polygon2D:
			visual_node = child
			break
			
	# Find Weapon
	weapon_node = find_child("Weapon", true, false)

func _physics_process(delta: float) -> void:
	# Cooldown Management (Runs on all peers)
	if mg_timer > 0:
		mg_timer -= delta

	if GameManager.is_multiplayer:
		if not is_multiplayer_authority():
			# We are a remote puppet. 
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
		if camera and camera.has_method("toggle_overview"):
			camera.toggle_overview()
		
	# COMMANDING INPUTS
	if Input.is_action_just_pressed("command_squads"):
		_start_commanding()
	elif Input.is_action_just_pressed("release_squads"):
		_stop_commanding()

	var current_speed = speed
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed = sprint_speed
	
	# Movement (Allowed in both Close and Tactical views)
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction:
		velocity = direction * current_speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()

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

func set_faction(new_faction: String) -> void:
	faction = new_faction
	if not visual_node: return
	
	match faction:
		"blue": visual_node.modulate = Color(0.4, 0.4, 1.0)
		"red": visual_node.modulate = Color(1.0, 0.4, 0.4)
		_: visual_node.modulate = Color.WHITE

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
		print(name, " DIED! Respawning at Core...")
		
		# Stop music on death
		var mm = get_tree().root.find_child("MusicManager", true, false)
		if mm and mm.has_method("on_player_death"):
			mm.on_player_death()
			
		_respawn_at_core()

func _respawn_at_core() -> void:
	current_hp = max_hp
	
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
