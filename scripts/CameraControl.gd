extends Camera2D

# --- CONFIGURATION ---
@export_group("Settings")
@export var key_movement: bool = true
@export var drag_movement: bool = true
@export var edge_movement: bool = false
@export var wheel_zoom: bool = true

@export var camera_speed: int = 2500 
@export var max_zoom: float = 20.0
@export var min_zoom: float = 0.35 # STRICT limit for Close View
@export var camera_margin: int = 50
@export var zoom_step: float = 0.1

# --- MAP LIMITS ---
# Updated to match Main.tscn Map ColorRect bounds
const LIMIT_LEFT: float = -12251.0
const LIMIT_TOP: float = -6666.0
const LIMIT_RIGHT: float = 12293.0 
const LIMIT_BOTTOM: float = 6650.0 

# --- STATE ---
var is_overview_mode: bool = false
var _saved_zoom: Vector2 = Vector2.ONE

# --- JUICE ---
var _shake_strength: float = 0.0
var _shake_decay: float = 3.0 # Reduced from 5.0 to make shake last longer
var _max_offset: Vector2 = Vector2(33, 23) # Decreased by another 2x (33, 23)
var _sway_offset: Vector2 = Vector2.ZERO # Smoothed sway component

var _prev_mouse_pos: Vector2 = Vector2.ZERO
var _right_mouse_pressed: bool = false

@onready var _target_zoom: Vector2 = zoom
# We assume the parent is the player to follow
@onready var _player_node: Node2D = get_parent() if get_parent() is Node2D else null

func _ready() -> void:
	position_smoothing_enabled = false # We handle smoothing manually for top_level transitions
	_target_zoom = zoom
	_saved_zoom = zoom
	_change_zoom(0.0) # Initial clamp
	randomize()

func add_trauma(amount: float) -> void:
	_shake_strength = min(_shake_strength + amount, 1.0)

func toggle_overview() -> void:
	if is_overview_mode:
		# --- EXIT TACTICAL VIEW (Return to Close View) ---
		is_overview_mode = false
		
		# Restore saved zoom, but ensure it obeys the Close View limit
		var restore_zoom = max(_saved_zoom.x, min_zoom)
		_target_zoom = Vector2(restore_zoom, restore_zoom)
		
		# We stay top_level = true until we physically reach the player to avoid snapping
	else:
		# --- ENTER TACTICAL VIEW ---
		is_overview_mode = true
		_saved_zoom = _target_zoom # Save current preference
		
		# STOP VIBRATIONS INSTANTLY
		_shake_strength = 0.0
		_sway_offset = Vector2.ZERO
		offset = Vector2.ZERO
		
		# Detach immediately to allow centering
		if not top_level:
			top_level = true
			global_position = get_parent().global_position # Start from player pos
			
		# Calculate best fit zoom to see entire map
		var vp_size = get_viewport_rect().size
		var map_w = LIMIT_RIGHT - LIMIT_LEFT
		var map_h = LIMIT_BOTTOM - LIMIT_TOP
		var required_zoom = max(vp_size.x / map_w, vp_size.y / map_h)
		
		# Reduce zoom out by 33% (Zoom in closer)
		required_zoom *= 1.33
		
		_target_zoom = Vector2(required_zoom, required_zoom)

func _process(delta: float) -> void:
	# --- 2. ZOOM SMOOTHING (Visual) ---
	# Moved to _process for smoother interpolation at high frame rates
	if not is_equal_approx(zoom.x, _target_zoom.x):
		var lerp_speed = 10.0 # Visual zoom speed
		var new_zoom = lerp(zoom.x, _target_zoom.x, lerp_speed * delta)
		zoom = Vector2(new_zoom, new_zoom)

	# --- 3. JUICE (Sway & Shake) ---
	_handle_juice(delta)

func _physics_process(delta: float) -> void:
	# --- 1. MOVEMENT & POSITIONING (Physics Sync) ---
	var lerp_speed = 5.0
	
	if is_overview_mode:
		# TACTICAL VIEW: Fixed Center Position
		var center_pos = Vector2(
			(LIMIT_LEFT + LIMIT_RIGHT) / 2.0,
			(LIMIT_TOP + LIMIT_BOTTOM) / 2.0
		)
		# Smoothly move to center
		global_position = global_position.lerp(center_pos, lerp_speed * delta)
		
	else:
		# CLOSE VIEW: Follow Player
		if top_level:
			# Transitioning back to player
			if is_instance_valid(_player_node):
				global_position = global_position.lerp(_player_node.global_position, lerp_speed * delta)
				
				# Re-attach check
				if global_position.distance_to(_player_node.global_position) < 5.0 and is_equal_approx(zoom.x, _target_zoom.x):
					top_level = false
					position = Vector2.ZERO
		else:
			# Attached. Stay at 0,0 (relative to player)
			position = Vector2.ZERO

func _handle_juice(delta: float) -> void:
	# NO Juice in Tactical View
	if is_overview_mode:
		_sway_offset = _sway_offset.lerp(Vector2.ZERO, 5.0 * delta)
		offset = _sway_offset
		return

	# --- SWAY (Smooth) ---
	var target_sway = Vector2.ZERO
	
	# Calculate Zoom Factor (Higher when zoomed out)
	# at zoom 0.35, factor is ~2.85
	var zoom_factor = 1.0 / max(zoom.x, 0.01)
	
	# Increase sway at lower zoom levels
	var sway_mult = 0.3 * zoom_factor * 1.4
	
	var mouse_center_offset = get_viewport().get_mouse_position() - get_viewport_rect().size / 2.0
	target_sway = mouse_center_offset * sway_mult
	
	# Scale max offset limit
	var current_max = _max_offset * zoom_factor * 1.4
	target_sway = target_sway.clamp(-current_max, current_max)
	
	# Smoothly interpolate sway
	_sway_offset = _sway_offset.lerp(target_sway, 5.0 * delta)
	
	# --- SHAKE (Instant/Jagged) ---
	var shake_offset = Vector2.ZERO
	
	if _shake_strength > 0:
		_shake_strength = max(_shake_strength - _shake_decay * delta, 0.0)
		var shake_base = _shake_strength * _shake_strength * 50.0
		
		# Scale shake by zoom_factor so it's visible when zoomed out
		var shake_val = shake_base * zoom_factor
		
		# Instant random offset
		shake_offset = Vector2(randf_range(-shake_val, shake_val), randf_range(-shake_val, shake_val))
		
	# Combine Smooth Sway + Instant Shake
	offset = _sway_offset + shake_offset

func _unhandled_input(event: InputEvent) -> void:
	if not enabled: return # Ignore if not current camera
	
	if event is InputEventMouseButton:
		# Drag logic (Close View Only)
		if not is_overview_mode and drag_movement and event.button_index == MOUSE_BUTTON_RIGHT:
			_right_mouse_pressed = event.pressed
			if _right_mouse_pressed:
				_prev_mouse_pos = get_local_mouse_position()
		
		# Zoom logic
		if wheel_zoom:
			if is_overview_mode:
				# In Tactical View: ONLY Zooming IN triggers exit
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					toggle_overview()
				# Zoom Out (Wheel Down) is IGNORED
			else:
				# Close View: Normal Zoom
				if event.button_index == MOUSE_BUTTON_WHEEL_UP:
					_change_zoom(zoom_step)
				elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					_change_zoom(-zoom_step)

func _change_zoom(amount: float) -> void:
	if is_overview_mode:
		# Should not be called manually in overview mode usually, 
		# but if it is, we treat it as a request to exit if zooming in?
		# Handled in _unhandled_input mostly.
		return

	var new_val = _target_zoom.x + amount
	# STRICT Clamp for Close View: Never go below min_zoom (0.35)
	new_val = clamp(new_val, min_zoom, max_zoom)
	
	_target_zoom = Vector2(new_val, new_val)
