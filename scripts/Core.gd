extends Building

class_name Core

func _ready() -> void:
	super._ready()
	add_to_group("core")
	max_hp = 2000
	current_hp = max_hp

func die() -> void:
	print("Game Over! ", faction, " core destroyed.")
	
	# Determine winner (if Blue died, Red wins)
	var winner = "red" if faction == "blue" else "blue"
	
	# Load Game Over screen
	var game_over_scene = load("res://scenes/GameOver.tscn").instantiate()
	game_over_scene.set_winner(winner)
	
	# Add to scene tree (CanvasLayer is best to float above everything)
	var ui_layer = CanvasLayer.new()
	ui_layer.add_child(game_over_scene)
	get_tree().root.add_child(ui_layer)
	
	# Pause game (Optional)
	get_tree().paused = true
	
	super.die()
