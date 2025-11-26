extends Building

class_name Core

func _ready() -> void:
	super._ready()
	add_to_group("core")
	# Core is tanky
	max_hp = 2000
	current_hp = max_hp

func die() -> void:
	print("Game Over! ", faction, " core destroyed.")
	
	# Determine winner (if Blue died, Red wins)
	var winner = "red" if faction == "blue" else "blue"
	
	# FIX: Updated path to the correct location inside "scenes/UI/"
	var game_over_res = load("res://scenes/UI/GameOver.tscn")
	
	if game_over_res:
		var game_over_scene = game_over_res.instantiate()
		
		if game_over_scene.has_method("set_winner"):
			game_over_scene.set_winner(winner)
		
		# Add to scene tree via a new CanvasLayer to ensure it sits on top
		var ui_layer = CanvasLayer.new()
		ui_layer.layer = 100 # Ensure high z-index
		ui_layer.add_child(game_over_scene)
		get_tree().root.add_child(ui_layer)
		
		# Pause game
		get_tree().paused = true
	else:
		print("CRITICAL ERROR: Could not load GameOver.tscn at 'res://scenes/UI/GameOver.tscn'")
	
	super.die()
