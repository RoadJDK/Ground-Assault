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
	if current_hp <= 0:
		die()

func die() -> void:
	queue_free()
