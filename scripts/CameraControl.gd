extends Camera2D

# --- CONFIGURATION ---
@export_group("Settings")
@export var key_movement: bool = true
@export var drag_movement: bool = true
@export var edge_movement: bool = false
@export var wheel_zoom: bool = true

@export var camera_speed: int = 1000 
@export var max_zoom: float = 4.0
@export var min_zoom: float = 0.1
@export var camera_margin: int = 50
@export var zoom_step: float = 0.02

# --- MAP LIMITS ---
# Position: -6956.0, -4622.0
# Size: 13930.0 x 9321.0
const LIMIT_LEFT: float = -6956.0
const LIMIT_TOP: float = -4622.0
const LIMIT_RIGHT: float = 6974.0 
const LIMIT_BOTTOM: float = 4699.0 

var _camera_movement: Vector2 = Vector2.ZERO
var _prev_mouse_pos: Vector2 = Vector2.ZERO
var _right_mouse_pressed: bool = false

@onready var _target_zoom: Vector2 = zoom

func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 5.0
	_target_zoom = zoom
	_change_zoom(0.0) # Initial clamp

func _physics_process(delta: float) -> void:
	_camera_movement = Vector2.ZERO

	if key_movement:
		var input_dir = Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
		var zoom_factor = 1.0 / zoom.x
		_camera_movement += input_dir * camera_speed * zoom_factor

	if edge_movement:
		var viewport_rect = get_viewport_rect()
		var mouse_pos = get_viewport().get_mouse_position()
		var zoom_factor = 1.0 / zoom.x
		var edge_speed = camera_speed * zoom_factor

		if mouse_pos.x >= viewport_rect.size.x - camera_margin:
			_camera_movement.x += edge_speed
		if mouse_pos.x <= camera_margin:
			_camera_movement.x -= edge_speed
		if mouse_pos.y >= viewport_rect.size.y - camera_margin:
			_camera_movement.y += edge_speed
		if mouse_pos.y <= camera_margin:
			_camera_movement.y -= edge_speed

	if drag_movement and _right_mouse_pressed:
		var current_mouse_pos = get_local_mouse_position()
		var diff = _prev_mouse_pos - current_mouse_pos
		position += diff
		_prev_mouse_pos = get_local_mouse_position()
	
	position += _camera_movement * delta
	
	# CLAMP POSITION
	var view_size = get_viewport_rect().size / zoom
	var limit_l = LIMIT_LEFT + view_size.x / 2.0
	var limit_t = LIMIT_TOP + view_size.y / 2.0
	var limit_r = LIMIT_RIGHT - view_size.x / 2.0
	var limit_b = LIMIT_BOTTOM - view_size.y / 2.0
	
	if limit_l > limit_r: 
		position.x = (LIMIT_LEFT + LIMIT_RIGHT) / 2.0
	else:
		position.x = clamp(position.x, limit_l, limit_r)
		
	if limit_t > limit_b:
		position.y = (LIMIT_TOP + LIMIT_BOTTOM) / 2.0
	else:
		position.y = clamp(position.y, limit_t, limit_b)
	
	# SMOOTH ZOOM
	if not is_equal_approx(zoom.x, _target_zoom.x):
		var new_zoom = lerp(zoom.x, _target_zoom.x, 10.0 * delta)
		zoom = Vector2(new_zoom, new_zoom)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if drag_movement and event.button_index == MOUSE_BUTTON_RIGHT:
			_right_mouse_pressed = event.pressed
			if _right_mouse_pressed:
				_prev_mouse_pos = get_local_mouse_position()
		
		if wheel_zoom:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_change_zoom(zoom_step)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_change_zoom(-zoom_step)

func _change_zoom(amount: float) -> void:
	# 1. Calculate Dynamic Limit based on CURRENT map size
	var vp_size = get_viewport_rect().size
	var map_w = LIMIT_RIGHT - LIMIT_LEFT
	var map_h = LIMIT_BOTTOM - LIMIT_TOP
	
	# The zoom level where the viewport matches the map size
	var dynamic_min_zoom = max(vp_size.x / map_w, vp_size.y / map_h)
	
	# 2. Calculate Target
	var new_zoom_val = _target_zoom.x + amount
	
	# 3. CLAMP TARGET IMMEDIATELY
	# This prevents the smoothing target from ever being "out of bounds"
	new_zoom_val = clamp(new_zoom_val, dynamic_min_zoom, max_zoom)
	
	_target_zoom = Vector2(new_zoom_val, new_zoom_val)
