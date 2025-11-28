extends Node2D

class_name Building

# --- CONFIGURATION ---
@export var max_hp: int = 100
@export var build_cost: int = 50

# New: Faction Owner ("blue", "red", "neutral")
var faction: String = "neutral" 

var current_hp: int

func _ready() -> void:
	current_hp = max_hp
	add_to_group("building")

func take_damage(amount: int) -> void:
	current_hp -= amount
	queue_redraw()
	if current_hp <= 0:
		die()

func die() -> void:
	if SFXManager: SFXManager.play_building_destroy(global_position)
	queue_free()

func _draw() -> void:
	if current_hp < max_hp:
		var bar_width = 90.0
		var bar_height = 9.0
		var y_offset = -80.0 # Position above building
		
		# Background
		draw_rect(Rect2(-bar_width/2, y_offset, bar_width, bar_height), Color(0, 0, 0, 0.6))
		
		# Color
		var hp_col = Color.WHITE
		if faction == "blue": hp_col = Color(0.3, 0.6, 1.0)
		elif faction == "red": hp_col = Color(1.0, 0.4, 0.4)
		
		# Fill
		var fill_pct = float(current_hp) / float(max_hp)
		draw_rect(Rect2(-bar_width/2, y_offset, bar_width * fill_pct, bar_height), hp_col)
		
		# Border
		draw_rect(Rect2(-bar_width/2, y_offset, bar_width, bar_height), Color.BLACK, false, 1.0)
