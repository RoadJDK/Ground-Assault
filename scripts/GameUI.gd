extends CanvasLayer

signal build_requested(building_type)

# Finds the label you created in the Editor named "GoldLabel"
@onready var gold_label = find_child("GoldLabel", true, false)

# Map names to button nodes
@onready var btn_generator = find_child("BtnGenerator", true, false)
@onready var btn_turret = find_child("BtnTurret", true, false)
@onready var btn_factory = find_child("BtnFactory", true, false)
@onready var btn_shield = find_child("BtnShield", true, false)

@onready var fps_label = find_child("FPSLabel", true, false)

func _process(_delta: float) -> void:
	if fps_label:
		fps_label.text = "FPS: " + str(Engine.get_frames_per_second())

func _ready() -> void:
	pass

func update_gold_display(amount: int) -> void:
	if gold_label:
		gold_label.text = "Gold: " + str(amount)
	else:
		print("ERROR: GoldLabel not found in GameUI!")

func update_factory_button_text(unit_name: String) -> void:
	if btn_factory:
		# Multi-line text: e.g. "Ranged\nFactory 150g"
		btn_factory.text = unit_name + "\nFactory 150g"
	else:
		print("ERROR: BtnFactory not found in GameUI!")

# Highlight buttons
# Returns TRUE if the tool was ALREADY selected (active)
func highlight_tool(type_name: String, highlight_color: Color) -> bool:
	var buttons = [btn_generator, btn_turret, btn_factory, btn_shield]
	
	var was_already_selected = false
	
	# Determine which button corresponds to the requested tool
	var target_btn = null
	match type_name:
		"Generator": target_btn = btn_generator
		"Turret": target_btn = btn_turret
		"Factory": target_btn = btn_factory
		"Shield": target_btn = btn_shield
	
	# Check if it's currently highlighted (using approx check for color match safety)
	if target_btn and target_btn.modulate.is_equal_approx(highlight_color):
		was_already_selected = true
	
	# Reset all
	for btn in buttons:
		if btn:
			btn.modulate = Color.WHITE 
			
	# Highlight new
	if target_btn:
		target_btn.modulate = highlight_color 
		
	return was_already_selected

func _on_btn_generator_pressed() -> void:
	emit_signal("build_requested", "Generator")

func _on_btn_turret_pressed() -> void:
	emit_signal("build_requested", "Turret")

func _on_btn_factory_pressed() -> void:
	# Special logic handled in Main via build_requested, 
	# but we can emit a generic request. 
	# If main sees it's already selected, it will cycle.
	emit_signal("build_requested", "Factory")

func _on_btn_shield_pressed() -> void:
	emit_signal("build_requested", "Shield")
