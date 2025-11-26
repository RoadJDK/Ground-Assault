extends CanvasLayer

signal build_requested(building_type)

# Finds the label you created in the Editor named "GoldLabel"
@onready var gold_label = find_child("GoldLabel", true, false)

# Finds the label you created in the Editor named "UnitLabel"
@onready var unit_label = find_child("UnitLabel", true, false)

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
	# Initialize labels if they exist
	if unit_label:
		unit_label.text = "Selected Unit: Ranged"
		unit_label.modulate = Color(0.7, 1.0, 0.7) # Optional: Tint it Light Green

func update_gold_display(amount: int) -> void:
	if gold_label:
		gold_label.text = "Gold: " + str(amount)
	else:
		print("ERROR: GoldLabel not found in GameUI!")

func update_unit_display(unit_name: String) -> void:
	if unit_label:
		unit_label.text = "Selected Unit: " + unit_name
	else:
		print("ERROR: UnitLabel not found in GameUI!")

# Highlight buttons
func highlight_tool(type_name: String) -> void:
	var buttons = [btn_generator, btn_turret, btn_factory, btn_shield]
	
	for btn in buttons:
		if btn:
			btn.modulate = Color.WHITE # Reset
			
	var target_btn = null
	match type_name:
		"Generator": target_btn = btn_generator
		"Turret": target_btn = btn_turret
		"Factory": target_btn = btn_factory
		"Shield": target_btn = btn_shield
	
	if target_btn:
		target_btn.modulate = Color.YELLOW # Highlight Color

func _on_btn_generator_pressed() -> void:
	emit_signal("build_requested", "Generator")

func _on_btn_turret_pressed() -> void:
	emit_signal("build_requested", "Turret")

func _on_btn_factory_pressed() -> void:
	emit_signal("build_requested", "Factory")

func _on_btn_shield_pressed() -> void:
	emit_signal("build_requested", "Shield")
